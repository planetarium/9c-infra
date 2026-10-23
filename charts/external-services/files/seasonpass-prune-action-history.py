"""
seasonpass action_history 일일 정리 — 끝난 시즌의 행을 조금씩 지운다.

## 왜 CronJob 인가 (celery 태스크가 아니라)

seasonpass claim 워커는 `-Q claim_queue --concurrency=1` 로 돈다(실제 돈이 나가는 클레임).
거기에 긴 정리 태스크를 얹으면 그동안 클레임이 막힌다. 그래서 워커 이미지만 빌려 별도
Job 으로 돌린다.

## 무엇을 남기는가 (pass_type 별)

- 진행 중 시즌: start <= now 이고 (end 가 NULL 이거나 now <= end). end 는 모델상 inclusive.
- 가장 이른 진행 중 시즌의 바로 앞 시즌(start_timestamp 기준) — 막 끝난 시즌의 클레임·문의 대응용.
- 미래 시즌(start > now)과 start 가 NULL 인 시즌.
- 진행 중 시즌이 하나도 없는 pass_type 은 통째로 건너뛴다(판단 근거가 없으니 안 지운다).
- 어느 pass_type 에도 진행 중 시즌이 없으면 아무것도 안 하고 실패로 끝난다(시계·데이터 이상).

## 부하

공유 PG10 인스턴스라 조심한다. id 커서로 배치 삭제(죽은 튜플 재스캔 방지), 문장마다
statement_timeout 30s, 배치마다 autocommit + 쉬기, 1회 실행당 PRUNE_MAX_ROWS 상한
(유입 ~45k행/일 — 며칠에 걸쳐 따라잡는다).

PRUNE_ENABLED=true 가 아니면 지울 시즌 목록과 추정 행수만 찍는다(dry run).
"""

import datetime
import json
import os
import sys
import time

LOCK_KEY = "seasonpass-prune-action-history"
REPORT_PREFIX = "SEASON_AUTOMATION_REPORT "


def compute_keep_set(seasons, now):
    """seasons: iterable of (id, pass_type, start, end). datetimes are tz-aware or None.

    Returns (keep_ids, delete_ids, skipped_pass_types), each a sorted list.
    Raises RuntimeError if no pass_type has a current season.
    """
    by_type = {}
    for s in seasons:
        by_type.setdefault(s[1], []).append(s)

    keep, delete, skipped = set(), set(), []
    any_current = False
    for pass_type in sorted(by_type, key=str):
        rows = by_type[pass_type]
        current = [
            r for r in rows
            if r[2] is not None and r[2] <= now and (r[3] is None or now <= r[3])
        ]
        if not current:
            skipped.append(pass_type)
            keep.update(r[0] for r in rows)
            continue
        any_current = True
        type_keep = {r[0] for r in current}
        type_keep.update(r[0] for r in rows if r[2] is None or r[2] > now)
        earliest = min(r[2] for r in current)
        before = [r for r in rows if r[2] is not None and r[2] < earliest]
        if before:
            prev_start = max(r[2] for r in before)
            # 같은 start 가 여럿이면 id 가 큰 것 하나(가장 나중에 만든 것).
            type_keep.add(max(r[0] for r in before if r[2] == prev_start))
        keep.update(type_keep)
        delete.update(r[0] for r in rows if r[0] not in type_keep)

    if not any_current:
        raise RuntimeError("no current season for any pass_type — refusing to prune")
    return sorted(keep), sorted(delete), skipped


def _self_test():
    utc = datetime.timezone.utc
    D = lambda m, d: datetime.datetime(2026, m, d, tzinfo=utc)  # noqa: E731
    now = D(10, 23)

    # 1) current + prev: 8월(삭제), 9월(직전, 유지), 10월(진행 중), 11월(미래), NULL start
    s = [
        (1, "C", D(8, 1), D(8, 31)),
        (2, "C", D(9, 1), D(9, 30)),
        (3, "C", D(10, 1), D(10, 31)),
        (4, "C", D(11, 1), D(11, 30)),
        (5, "C", None, None),
    ]
    k, d, sk = compute_keep_set(s, now)
    assert k == [2, 3, 4, 5] and d == [1] and sk == [], (k, d, sk)

    # 2) overlapping currents: 직전은 가장 이른 진행 중 시즌 기준
    s = [
        (1, "A", D(7, 1), D(7, 31)),
        (2, "A", D(8, 1), D(8, 31)),
        (3, "A", D(9, 15), D(10, 30)),
        (4, "A", D(10, 10), D(11, 10)),
    ]
    k, d, sk = compute_keep_set(s, now)
    assert k == [2, 3, 4] and d == [1], (k, d)

    # 3) NULL end 는 start <= now 면 진행 중; end inclusive
    s = [
        (1, "W", D(6, 1), D(6, 30)),
        (2, "W", D(7, 1), D(7, 31)),
        (3, "W", D(8, 1), None),
        (4, "X", D(9, 1), D(9, 30)),
        (5, "X", D(10, 1), now),
    ]
    k, d, sk = compute_keep_set(s, now)
    assert k == [2, 3, 4, 5] and d == [1], (k, d)

    # 4) 진행 중 시즌 없는 pass_type 은 건드리지 않는다
    s = [
        (1, "C", D(8, 1), D(8, 31)),
        (2, "C", D(9, 1), D(9, 30)),
        (3, "C", D(10, 1), D(10, 31)),
        (10, "B", D(1, 1), D(1, 31)),
        (11, "B", D(2, 1), D(2, 28)),
    ]
    k, d, sk = compute_keep_set(s, now)
    assert d == [1] and sk == ["B"] and 10 in k and 11 in k, (k, d, sk)

    # 5) 어디에도 진행 중 시즌이 없으면 거부
    s = [(1, "C", D(8, 1), D(8, 31)), (2, "B", D(11, 1), None)]
    try:
        compute_keep_set(s, now)
    except RuntimeError:
        pass
    else:
        raise AssertionError("expected RuntimeError when nothing is current")
    try:
        compute_keep_set([], now)
    except RuntimeError:
        pass
    else:
        raise AssertionError("expected RuntimeError on empty season list")

    print("self-test OK")


def main(state):
    import psycopg2
    from psycopg2 import errors as pg_errors

    dsn = os.environ["WORKER_PG_DSN"]
    batch = int(os.environ.get("PRUNE_BATCH", "") or 5000)
    max_rows = int(os.environ.get("PRUNE_MAX_ROWS", "") or 300000)

    conn = psycopg2.connect(dsn, connect_timeout=15)
    conn.autocommit = True
    try:
        with conn.cursor() as cur:
            cur.execute("SET statement_timeout = '30s'")
            cur.execute("SELECT pg_try_advisory_lock(hashtext(%s))", (LOCK_KEY,))
            if not cur.fetchone()[0]:
                state["text"] = "another run holds the advisory lock — skipped"
                print(state["text"])
                return

            cur.execute(
                "SELECT id, pass_type::text, start_timestamp, end_timestamp FROM season_pass"
            )
            seasons = cur.fetchall()
            cur.execute("SELECT now()")
            now = cur.fetchone()[0]

            keep, delete, skipped = compute_keep_set(seasons, now)
            print(f"now={now.isoformat()} keep={keep} delete={delete} skipped_pass_types={skipped}")
            for pt in skipped:
                print(f"pass_type {pt}: no current season — not pruning it")
            skip_note = f" skipped(no current)={skipped}" if skipped else ""

            if not delete:
                state["text"] = f"nothing to prune (keep={len(keep)} seasons){skip_note}"
                return

            if state["dryRun"]:
                try:
                    cur.execute(
                        "SELECT count(*) FROM (SELECT 1 FROM action_history"
                        " WHERE season_id = ANY(%s) LIMIT 1000000) t",
                        (delete,),
                    )
                    n = cur.fetchone()[0]
                    est = f">={n}" if n >= 1000000 else str(n)
                except pg_errors.QueryCanceled:
                    est = "count timeout"
                state["text"] = (
                    f"dry run — would delete seasons {delete}, est rows {est}{skip_note}"
                )
                return

            last, total, batches = 0, 0, 0
            started = time.time()
            while total < max_rows:
                n = min(batch, max_rows - total)
                t0 = time.time()
                cur.execute(
                    "DELETE FROM action_history WHERE id IN ("
                    " SELECT id FROM action_history"
                    " WHERE id > %(last)s AND season_id = ANY(%(del)s)"
                    " ORDER BY id LIMIT %(n)s) RETURNING id",
                    {"last": last, "del": delete, "n": n},
                )
                ids = [r[0] for r in cur.fetchall()]
                took = time.time() - t0
                if not ids:
                    break
                last = max(ids)
                total += len(ids)
                batches += 1
                state["deleted"] = total
                time.sleep(5 if took > 5 else 0.2)
            elapsed = time.time() - started
            capped = " (hit PRUNE_MAX_ROWS, continues next run)" if total >= max_rows else ""
            state["text"] = (
                f"deleted {total} rows from seasons {delete} in {batches} batches,"
                f" {elapsed:.0f}s{capped}{skip_note}"
            )
    finally:
        conn.close()  # 세션 종료가 advisory lock 도 푼다


def run():
    env_label = os.environ.get("ENV_LABEL", "") or "Unknown"
    state = {
        "dryRun": os.environ.get("PRUNE_ENABLED", "").strip().lower() != "true",
        "text": "",
        "deleted": 0,
    }
    error = None
    try:
        main(state)
    except Exception as exc:  # noqa: BLE001
        error = exc
        print(f"prune failed: {exc!r}", file=sys.stderr)
    finally:
        if error is not None:
            done = f" (deleted {state['deleted']} rows before failing)" if state["deleted"] else ""
            body = f"FAILED: {type(error).__name__}: {error}{done}"
        else:
            body = state["text"] or "finished"
        report = {
            "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "stage": env_label,
            "dryRun": state["dryRun"],
            "text": f"[seasonpass prune][{env_label}] {body}",
            "mention": error is not None,
            "onceKey": None,
        }
        print(REPORT_PREFIX + json.dumps(report, ensure_ascii=False), flush=True)
    if error is not None:
        sys.exit(1)


if __name__ == "__main__":
    if "--self-test" in sys.argv[1:]:
        _self_test()
    else:
        run()
