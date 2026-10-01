"""
IAP DB 정비 — VACUUM (ANALYZE) 를 우리 손으로 돌린다.

## 왜 autovacuum 에 맡기지 않는가

2026-10-01 에 `GET /api/purchase/invalid-receipt-count` 가 15~23초까지 느려져 Assertible
외부 감시가 PagerDuty 를 울렸다. 값(22)은 정상이었고 **쿼리가 느린 게 원인**이었다.
파보니 `receipt`(832k행 / 2.2GB)가 **한 번도 vacuum·analyze 된 적이 없었다** —
dead 82,479, 플래너가 본 행수는 15,533(실제의 1.9%). VACUUM (ANALYZE) 후 응답이
22.9초 → 0.01초가 됐다.

문제는 autovacuum 이 꺼져 있어서가 아니다. 켜져 있고(`autovacuum=on`), 막는 것도 없다
(장기 트랜잭션·prepared xact·replication slot 전부 0). **따라오지 못하는 것**이다:

    autovacuum_vacuum_cost_delay = 20ms   ← PG10 기본값
    vacuum_cost_limit            = 200
    autovacuum_max_workers       = 3
    인스턴스 총량                 = 84.6 GB / 15개 DB (portal 16GB, seasonpass 26GB, petpop 16GB)

이 조합은 autovacuum 처리량을 수 MB/s 로 묶는다. PostgreSQL 이 12 버전에서 이 기본값을
20ms → 2ms 로 바꾼 이유가 정확히 이것이다. 실제로 iap_db 22개 테이블 중 autovacuum 이
돈 건 `price` 하나뿐이었다.

그 설정은 `sighup`/`postmaster` 컨텍스트라 **superuser 가 있어야** 바꾼다. 우리 롤(`iap`)은
일반 롤이고 이 인스턴스의 superuser 는 `postgres` 하나뿐이라, 인스턴스 레벨 조정은
iwinv 에 요청해야 한다. 그게 되기 전까지 우리 권한으로 결과를 보장하는 방법이 이 잡이다.

## 왜 이게 통하는가

`vacuum_cost_delay` 는 context=`user` 다 — **세션에서 0으로 끌 수 있다.** autovacuum 의
20ms throttle 과 무관하게 전속력으로 돈다. 실측: receipt 62초, 나머지 21개 합쳐 3.2초.

## 무엇을 안 하는가

- `VACUUM FULL` 은 쓰지 않는다. ACCESS EXCLUSIVE 로 테이블을 잠그고 2.2GB 를 재작성한다.
  일반 VACUUM 은 잠그지 않아 라이브 결제와 같이 돌 수 있다.
- 다른 DB(portal·seasonpass·petpop)는 건드리지 않는다. 우리 롤로 접근 권한도 없고,
  각 팀의 소관이다.
"""

import datetime
import json
import os
import sys
import time
import urllib.request

import psycopg2

DSN = os.environ["WORKER_PG_DSN"]
WEBHOOK = os.environ.get("IAP_ALERT_WEBHOOK_URL", "")
ENV_LABEL = os.environ.get("ENV_LABEL", "") or "Unknown"
DRY_RUN = os.environ.get("DRY_RUN", "").strip().lower() not in ("", "0", "false", "no")
# 이상이 없어도 이 UTC 시각의 run 은 한 줄 남긴다. 비우면 "조용함 = 정상" 으로 되돌아간다.
HEARTBEAT_HOUR = os.environ.get("HEARTBEAT_HOUR", "")
# 이보다 오래 걸리면 보고에 싣는다(디스크가 느려지고 있다는 신호).
SLOW_SECONDS = float(os.environ.get("SLOW_SECONDS", "300"))

TABLES_SQL = """
SELECT relname, n_dead_tup, pg_total_relation_size(relid)
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC
"""


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
        if resp.status != 200:
            raise RuntimeError(f"slack {resp.status}: {resp.read()[:200]!r}")
    print("posted")


def main() -> None:
    conn = psycopg2.connect(DSN, connect_timeout=15)
    conn.autocommit = True  # VACUUM 은 트랜잭션 블록 안에서 못 돈다
    try:
        with conn.cursor() as cur:
            cur.execute(TABLES_SQL)
            tables = cur.fetchall()
            dead_before = sum(t[1] for t in tables)

            # autovacuum 의 20ms throttle 을 이 세션에서만 끈다. context=user 라 가능하다.
            cur.execute("SET vacuum_cost_delay = 0")

            started = time.time()
            slow = []
            for name, _dead, _size in tables:
                t0 = time.time()
                # 식별자는 서버에서 따옴표 처리한다(테이블명은 pg_stat_user_tables 에서 온 값).
                cur.execute(f'VACUUM (ANALYZE) "{name}"')
                took = time.time() - t0
                if took >= SLOW_SECONDS:
                    slow.append((name, took))
            elapsed = time.time() - started

            cur.execute("SELECT coalesce(sum(n_dead_tup), 0) FROM pg_stat_user_tables")
            dead_after = cur.fetchone()[0]
    finally:
        conn.close()

    print(
        f"tables={len(tables)} dead_before={dead_before} dead_after={dead_after} "
        f"elapsed={elapsed:.1f}s slow={slow}"
    )

    heartbeat = (
        HEARTBEAT_HOUR != ""
        and datetime.datetime.now(datetime.timezone.utc).hour == int(HEARTBEAT_HOUR)
    )
    if not slow and not heartbeat:
        return

    lines = []
    if slow:
        lines.append(f":warning: *[{ENV_LABEL}] IAP DB 정비가 느려지고 있다*")
        for name, took in slow:
            lines.append(f"• `{name}` {took:.0f}초 (임계 {SLOW_SECONDS:.0f}초)")
        lines.append(
            "• 디스크가 느려졌거나 테이블이 커진 것이다. 커졌다면 이 잡의 주기를 줄이거나 "
            "인스턴스 autovacuum 설정(`cost_delay` 20ms)을 iwinv 에 요청할 때가 됐다는 신호다."
        )
    else:
        lines.append(f":broom: *[{ENV_LABEL}] IAP DB 정비 완료*")
        lines.append(
            f"• {len(tables)}개 테이블 / {elapsed:.0f}초 · dead {dead_before:,} → {dead_after:,}"
        )

    post_slack("\n".join(lines))


if __name__ == "__main__":
    # 웹훅이 비면 실패를 아무도 모른다. 기동 전에 시끄럽게 죽는다(워치독과 같은 이유).
    if not WEBHOOK and not DRY_RUN:
        print("IAP_ALERT_WEBHOOK_URL 이 비어 있다. 기동을 거부한다.", file=sys.stderr)
        sys.exit(1)
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print(f"db maintenance failed: {exc!r}", file=sys.stderr)
        try:
            post_slack(
                f":warning: *[{ENV_LABEL}] IAP DB 정비 실패* — `{type(exc).__name__}: {exc}`\n"
                "• 방치하면 플래너 통계가 다시 틀어지고 invalid-receipt-count 가 느려진다."
            )
        except Exception as notify_exc:  # noqa: BLE001
            print(f"slack notify also failed: {notify_exc!r}", file=sys.stderr)
        sys.exit(1)
