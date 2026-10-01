"""
IAP 지급 파이프라인 외부 감시 (dead-man's switch).

왜 따로 도는가 — 2026-09-28 에 iap-beat 이 Redis PubSub 재진입 데드락으로 4시간 20분
멈췄는데, **알람을 쏘는 status_monitor 자체가 그 beat 의 스케줄**이라 알람까지 같이
죽었다. 파드는 내내 Running 1/1 이었고 재시작도 0회였다. 즉 "조용함" 이 정상이 아니라
최악 신호였는데 그걸 구분할 방법이 없었다.

이 잡은 celery·beat·RabbitMQ·Redis 를 하나도 거치지 않는다. CronJob 으로 떠서 DB 만
직접 본다. 그래서 파이프라인이 통째로 죽어도 이건 살아서 말한다.

이상이 없어도 HEARTBEAT_HOUR 시각의 run 은 한 줄 남긴다. 비워 두면 하트비트가 꺼지고,
그러면 "조용함 = 정상" 으로 되돌아간다 — 이 사고가 정확히 그래서 길어졌다.

시간 비교는 전부 SQL 의 now() 로 한다. 파이썬에서 만든 naive datetime 을 넘기면
서버 TimeZone(Asia/Seoul)으로 해석돼 조건이 9시간 어긋난다.
"""

import datetime
import json
import os
import sys
import urllib.request

import psycopg2

DSN = os.environ["WORKER_PG_DSN"]
WEBHOOK = os.environ.get("IAP_ALERT_WEBHOOK_URL", "")
ENV_LABEL = os.environ.get("ENV_LABEL", "") or "Unknown"
# 문자열 "false" 는 truthy 다. bool(env) 로 두면 누가 DRY_RUN="false" 를 배선하는 순간
#   감시가 영구 무음이 된다 — 이 잡이 없애려는 실패 모드 그 자체다.
DRY_RUN = os.environ.get("DRY_RUN", "").strip().lower() not in ("", "0", "false", "no")
THRESHOLD_MIN = int(os.environ.get("THRESHOLD_MINUTES", "30"))
# 이 나이를 넘긴 건은 재시도로 풀릴 가능성이 사실상 없고 수동 개입 대상이라, 매 회차
#   다시 쏘는 대신 하루 한 번 하트비트에 실어 보고한다. IAP 의 status_monitor 도 같은
#   경계를 쓴다 — 여기서 갈라두지 않으면 24시간 내내 같은 메시지를 쏘고 채널이 뮤트된다.
#   (실데이터: tx_status IS NULL 12,062건 · FAILURE 13건이 전부 6시간 이상 묵은 잔류분이다.
#    나이로 안 가르면 배포 즉시 12,075건짜리 오탐이 뜬다.)
STALE_AFTER_HOURS = int(os.environ.get("STALE_AFTER_HOURS", "6"))
HEARTBEAT_HOUR = os.environ.get("HEARTBEAT_HOUR", "")

# 술어를 ix_receipt_stuck_monitor 의 부분 인덱스 조건과 **글자 그대로** 맞춘다.
#   그래야 인덱스를 탄다(메인넷 실측: 인덱스 스캔이면 0.7ms, seq scan 이면 15.5초).
#   INVALID/STAGED 만 보면 사각이 남는다 — tx_status IS NULL(발행 실패) 과 FAILURE
#   (온체인 실패)를 되살리는 게 전부 beat 의 retryer 라, 그것들이 멈춘 장애를 놓친다.
_STUCK_PREDICATE = """
  AND status = 'VALID'
  AND (tx_status IN ('INVALID', 'STAGED', 'FAILURE') OR tx_status IS NULL)
  -- ⚠️ 시즌패스는 tx_status 가 **영구 NULL 인 게 정상**이다. send_product 큐를 타지 않고
  --   시즌패스 서비스로 지급되기 때문이다(shared.models.product.is_season_pass_product 의
  --   docstring 이 그대로 그렇게 적고 있다). retryer 도 같은 이유로 제외한다 — 재전송하면
  --   패스(claim)와 온체인 아이템이 **이중 지급**된다(retryer.get_null_tx_status_receipts).
  --   빼지 않으면 시즌패스가 팔릴 때마다 30분 뒤 오탐이 뜬다(2026-10-01 실제 발생).
  --   판별 토큰 'pass' 는 SEASON_PASS_SKU_TOKEN 과 같은 값이다. SQL 이라 import 할 수
  --   없으니 바뀌면 여기도 같이 고쳐야 한다.
  --   NULL 버킷에만 적용한다 — 시즌패스는 tx 자체가 없어 STAGED/INVALID/FAILURE 가 될 수
  --   없고, 혹시라도 그 상태가 되면 그건 진짜 이상이라 가려선 안 된다.
  AND (
        tx_status IS NOT NULL
     OR NOT EXISTS (
          SELECT 1 FROM product p
           -- psycopg2 는 이 문자열 전체에서 파라미터 자리를 찾으므로 리터럴 퍼센트는
           --   두 번 적어야 한다. 주석도 예외가 아니다 — 주석 안에 파라미터 모양이
           --   들어가면 KeyError 로, 리터럴 퍼센트 하나면
           --   "argument formats can't be mixed" 로 터진다. 둘 다 실제로 겪었다.
           WHERE p.id = receipt.product_id AND p.google_sku LIKE '%%pass%%'
        )
  )
"""

# 경보에 필요한 건 **최근분뿐**이다. 잔류분까지 매 회차 세면 12,075행을 훑느라 7.7초가
#   걸린다(메인넷 실측). 나이 상한을 걸면 0.5ms 로 떨어진다 — 잔류분은 하트비트 때만 센다.
RECENT_SQL = (
    """
SELECT coalesce(tx_status::text, 'NULL') AS st,
       count(*)::int,
       EXTRACT(EPOCH FROM (now() - min(created_at)))::int
FROM receipt
WHERE created_at <= now() - make_interval(mins => %(threshold)s)
  AND created_at > now() - make_interval(hours => %(stale)s)
"""
    + _STUCK_PREDICATE
    + "GROUP BY 1"
)

# 하트비트에서만 부른다(위 주석의 7.7초가 여기 있다).
STALE_SQL = (
    """
SELECT coalesce(tx_status::text, 'NULL') AS st, count(*)::int
FROM receipt
WHERE created_at <= now() - make_interval(hours => %(stale)s)
"""
    + _STUCK_PREDICATE
    + "GROUP BY 1"
)

# CREATED 는 위 부분 인덱스의 조건에 없다. 같이 OR 로 묶으면 인덱스를 못 타고 1.4GB
#   seq scan 이 되므로, ix_receipt_retry_pending(CREATED/INVALID + tx IS NOT NULL)을
#   타는 별도 쿼리로 센다.
CREATED_SQL = """
SELECT count(*)::int,
       EXTRACT(EPOCH FROM (now() - min(created_at)))::int
FROM receipt
WHERE tx_status IN ('CREATED', 'INVALID')
  AND tx IS NOT NULL
  AND created_at <= now() - make_interval(mins => %(threshold)s)
  AND created_at > now() - make_interval(hours => %(stale)s)
"""

# 하트비트 문맥용. max(created_at) 은 무조건부라 인덱스가 없어 seq scan 이 되므로
#   PK 역순 1건으로 대신한다.
LAST_RECEIPT_SQL = """
SELECT EXTRACT(EPOCH FROM (now() - created_at))::int
FROM receipt ORDER BY id DESC LIMIT 1
"""


def fmt_age(seconds) -> str:
    if seconds is None:
        return "?"
    minutes = int(seconds) // 60
    if minutes < 60:
        return f"{minutes}분"
    hours, rest = divmod(minutes, 60)
    if hours < 24:
        return f"{hours}시간" if rest == 0 else f"{hours}시간 {rest}분"
    days, rest_h = divmod(hours, 24)
    return f"{days}일" if rest_h == 0 else f"{days}일 {rest_h}시간"


def post_slack(text: str) -> None:
    if DRY_RUN:
        print("--- DRY_RUN, 실제 발송 안 함 ---")
        print(text)
        return
    req = urllib.request.Request(
        WEBHOOK,
        data=json.dumps({"text": text}).encode("utf-8"),
        headers={"Content-Type": "application/json; charset=utf-8"},
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        body = resp.read().decode("utf-8", "replace")
        if resp.status != 200:
            raise RuntimeError(f"slack {resp.status}: {body}")
    print("posted")


def collect(conn, want_stale: bool):
    """(최근 {상태: (건수, 최고령초)}, 잔류 {상태: 건수}, 마지막 영수증 경과초)."""
    params = {"threshold": THRESHOLD_MIN, "stale": STALE_AFTER_HOURS}
    with conn.cursor() as cur:
        cur.execute(RECENT_SQL, params)
        recent = {st: (cnt, age) for st, cnt, age in cur.fetchall()}
        cur.execute(CREATED_SQL, params)
        created_cnt, created_age = cur.fetchone()
        if created_cnt:
            # CREATED 만 더한다 — INVALID 는 RECENT_SQL 에 이미 있어 중복이 된다.
            recent["CREATED"] = (created_cnt, created_age)
        cur.execute(LAST_RECEIPT_SQL)
        row = cur.fetchone()
        last_receipt_age = row[0] if row else None
        stale = {}
        if want_stale:
            cur.execute(STALE_SQL, params)
            stale = {st: cnt for st, cnt in cur.fetchall()}
    return recent, stale, last_receipt_age


def main() -> None:
    heartbeat = (
        HEARTBEAT_HOUR != ""
        and datetime.datetime.now(datetime.timezone.utc).hour == int(HEARTBEAT_HOUR)
    )

    conn = psycopg2.connect(DSN, connect_timeout=15)
    try:
        # 잔류분 집계는 하트비트 때만 — 매 회차 돌리면 7.7초짜리가 된다.
        recent, stale, last_receipt_age = collect(conn, want_stale=heartbeat)
    finally:
        conn.close()

    recent_total = sum(cnt for cnt, _ in recent.values())
    stale_total = sum(stale.values())
    oldest_recent = max(
        (age for _, age in recent.values() if age is not None), default=None
    )
    print(
        f"recent={recent_total} stale={stale_total} oldest_recent_s={oldest_recent} "
        f"last_receipt_s={last_receipt_age} recent_by_status={recent} "
        f"threshold_min={THRESHOLD_MIN} heartbeat={heartbeat}"
    )

    if not recent_total and not heartbeat:
        return

    lines = []
    if recent_total:
        breakdown = ", ".join(
            f"{st} {cnt}건" for st, (cnt, _) in sorted(recent.items()) if cnt
        )
        lines.append(f":rotating_light: *[{ENV_LABEL}] IAP 지급 파이프라인 정체*")
        lines.append(
            f"• 멈춘 영수증 *{recent_total}건* ({breakdown}) — 최고령 "
            f"{fmt_age(oldest_recent)}, 임계 {THRESHOLD_MIN}분"
        )
        lines.append(
            "• 이 알람은 celery 를 거치지 않는다 — *beat 이 죽어 있어도 뜬다.* "
            "평소 10분 주기 `Tx. Invalid Receipt Report` 가 같이 안 보이면 beat 부터 의심할 것."
        )
        lines.append(
            "• 확인: `kubectl -n 9c-external-services logs deploy/iap-beat --tail=1` "
            "— 로그가 과거에서 멈춰 있으면 데드락이다(`/proc/7/wchan` 이 `futex_wait_queue_me`)."
        )
        lines.append(
            "• 복구: `kubectl -n 9c-external-services rollout restart deploy/iap-beat`"
        )
    else:
        lines.append(
            f":white_check_mark: *[{ENV_LABEL}] IAP 지급 파이프라인 정상* (감시 동작 확인)"
        )
        lines.append(f"• 정체 0건 / 마지막 영수증 {fmt_age(last_receipt_age)} 전")

    if stale_total:
        stale_breakdown = ", ".join(
            f"{st} {cnt}건" for st, cnt in sorted(stale.items()) if cnt
        )
        lines.append(
            f"• (참고) {STALE_AFTER_HOURS}시간 이상 묵은 잔류 {stale_total}건 — "
            f"{stale_breakdown}. 수동 개입 대상이라 매 회차 쏘지 않는다."
        )

    post_slack("\n".join(lines))


if __name__ == "__main__":
    # 웹훅이 비어 있으면 **시작하기 전에** 시끄럽게 죽는다. 조용히 넘어가면 정체를
    #   탐지해 놓고도 exit 0 으로 끝나 "감시가 붙었으니 조용한 것" 으로 읽힌다 —
    #   이 잡이 없애려는 실패 모드 그 자체다(자매 구현도 같은 이유로 여기서 throw 한다).
    if not WEBHOOK and not DRY_RUN:
        print("IAP_ALERT_WEBHOOK_URL 이 비어 있다. 감시가 무음이 되므로 기동을 거부한다.", file=sys.stderr)
        sys.exit(1)
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        # 감시 잡이 조용히 실패하면 감시가 없는 것과 같다. 슬랙에 먼저 알리고
        #   (웹훅 경로는 DB 와 독립이라 DB 장애 때 특히 유효하다) 비정상 종료로 남긴다.
        print(f"watchdog failed: {exc!r}", file=sys.stderr)
        try:
            post_slack(
                f":warning: *[{ENV_LABEL}] IAP 감시 잡 실패* — `{type(exc).__name__}: {exc}`\n"
                "• 이 잡이 죽어 있는 동안은 지급 정체를 아무도 안 본다."
            )
        except Exception as notify_exc:  # noqa: BLE001
            print(f"slack notify also failed: {notify_exc!r}", file=sys.stderr)
        sys.exit(1)
