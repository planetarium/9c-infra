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
ENV_LABEL = os.environ.get("ENV_LABEL", "Mainnet")
DRY_RUN = bool(os.environ.get("DRY_RUN"))
THRESHOLD_MIN = int(os.environ.get("THRESHOLD_MINUTES", "30"))
HEARTBEAT_HOUR = os.environ.get("HEARTBEAT_HOUR", "")

# status_monitor.check_halt_tx 와 같은 술어다. 같은 것을 보되 **다른 프로세스에서** 본다.
#   술어가 같아야 기존 부분 인덱스 ix_receipt_stuck_monitor 를 그대로 탄다.
STUCK_SQL = """
SELECT count(*)::int AS stuck,
       COALESCE(EXTRACT(EPOCH FROM (now() - min(created_at))) / 60, 0)::int AS oldest_min
FROM receipt
WHERE status = 'VALID'
  AND tx_status IN ('INVALID', 'STAGED')
  AND created_at <= now() - make_interval(mins => %(threshold)s)
"""

# 트래픽이 없으면 위 숫자는 정상적으로 0 이다. 하트비트에 이 값을 같이 실어
#   "0 건인데 결제가 있었나" 를 사람이 바로 판단할 수 있게 한다.
TRAFFIC_SQL = """
SELECT count(*)::int AS recent,
       COALESCE(EXTRACT(EPOCH FROM (now() - max(created_at))) / 60, -1)::int AS last_min
FROM receipt
WHERE created_at > now() - interval '1 hour'
"""


def fmt_age(minutes: int) -> str:
    if minutes < 60:
        return f"{minutes}분"
    hours, rest = divmod(minutes, 60)
    if hours < 24:
        return f"{hours}시간" if rest == 0 else f"{hours}시간 {rest}분"
    days, rest_h = divmod(hours, 24)
    return f"{days}일" if rest_h == 0 else f"{days}일 {rest_h}시간"


def post_slack(text: str) -> None:
    if DRY_RUN or not WEBHOOK:
        print("--- DRY_RUN / webhook 미설정, 실제 발송 안 함 ---")
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


def main() -> None:
    with psycopg2.connect(DSN) as conn, conn.cursor() as cur:
        cur.execute(STUCK_SQL, {"threshold": THRESHOLD_MIN})
        stuck, oldest_min = cur.fetchone()
        cur.execute(TRAFFIC_SQL)
        recent, last_min = cur.fetchone()

    print(
        f"stuck={stuck} oldest_min={oldest_min} recent_1h={recent} "
        f"last_receipt_min={last_min} threshold={THRESHOLD_MIN}"
    )

    heartbeat = (
        HEARTBEAT_HOUR != ""
        and datetime.datetime.utcnow().hour == int(HEARTBEAT_HOUR)
    )
    if not stuck and not heartbeat:
        return

    lines = []
    if stuck:
        lines.append(f":rotating_light: *[{ENV_LABEL}] IAP 지급 파이프라인 정체*")
        lines.append(
            f"• tx 가 STAGED/INVALID 로 멈춘 영수증 *{stuck}건* "
            f"(최고령 {fmt_age(oldest_min)}, 임계 {fmt_age(THRESHOLD_MIN)})"
        )
        lines.append(
            "• 이 알람은 celery 를 거치지 않는다 — *beat 이 죽어 있어도 뜬다.* "
            "평소 10분 주기 `Tx. Invalid Receipt Report` 가 같이 안 보이면 beat 부터 의심할 것."
        )
        lines.append(
            "• 확인: `kubectl -n 9c-external-services logs deploy/iap-beat --tail=1` "
            "— 로그가 과거에서 멈춰 있으면 데드락이다(`/proc/7/wchan` 이 `futex_wait_queue_me`)."
        )
        lines.append("• 복구: `kubectl -n 9c-external-services rollout restart deploy/iap-beat`")
    else:
        lines.append(f":white_check_mark: *[{ENV_LABEL}] IAP 지급 파이프라인 정상* (감시 동작 확인)")
        lines.append(
            f"• 정체 0건 / 최근 1시간 영수증 {recent}건"
            + (f", 마지막 결제 {fmt_age(last_min)} 전" if last_min >= 0 else ", 최근 1시간 결제 없음")
        )

    post_slack("\n".join(lines))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        # 감시 잡이 조용히 실패하면 감시가 없는 것과 같다. 반드시 비정상 종료로 남긴다.
        print(f"watchdog failed: {exc!r}", file=sys.stderr)
        sys.exit(1)
