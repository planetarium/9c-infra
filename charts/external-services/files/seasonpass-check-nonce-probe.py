"""seasonpass /api/check-nonce 를 주기적으로 불러 판정 기록을 남긴다(시험 기간용).

check-nonce 의 지속 시간 판정(hole_stuck·nonce_unavailable)은 api 프로세스가 호출을 받을 때만
잰다. 부르는 쪽이 없는 환경에서는 판정이 한 번도 쓰이지 않으므로 이 잡이 부른다.

- 플래닛마다 한 줄 JSON 을 stdout 에 찍는다(시각·플래닛·상태 코드·check 의 판정 필드).
- api 는 reason 이 ok·no_claims 가 아니면 WARNING 줄을 남긴다 — 이상 기록은 api 로그에도 남는다.
- 하나라도 200 이 아니면 exit 1: 실패한 Job 은 failedJobsHistoryLimit 만큼 남아 로그를 볼 수 있다.

앱 코드·비밀값을 쓰지 않는다. 표준 라이브러리만 쓴다.
"""
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

BASE = os.environ.get("PROBE_BASE_URL", "http://seasonpass-api-service")
PLANETS = [p for p in os.environ.get("PROBE_PLANETS", "odin,heimdall").split(",") if p]
TIMEOUT = float(os.environ.get("PROBE_TIMEOUT_SECONDS", "30"))
FIELDS = (
    "reason",
    "gap",
    "stuck_seconds",
    "unavailable_seconds",
    "highest_nonce",
    "next_nonce",
    "error",
    "stuck_minutes",
    "unavailable_minutes",
)


def probe(planet: str) -> dict:
    url = f"{BASE}/api/check-nonce?planet={planet}"
    line = {"planet": planet}
    try:
        with urllib.request.urlopen(url, timeout=TIMEOUT) as resp:
            status, raw = resp.status, resp.read()
    except urllib.error.HTTPError as e:
        status, raw = e.code, e.read()
    except Exception as e:  # noqa: BLE001 — 연결 실패도 한 줄로 남긴다
        line.update(status=None, probe_error=type(e).__name__)
        return line
    line["status"] = status
    try:
        check = json.loads(raw or b"{}").get("check") or {}
    except (ValueError, AttributeError):
        check = {}
    line.update({k: check[k] for k in FIELDS if k in check})
    return line


def main() -> int:
    ok = True
    for planet in PLANETS:
        line = {"ts": datetime.now(timezone.utc).isoformat(timespec="seconds")}
        line.update(probe(planet))
        print("check-nonce-probe " + json.dumps(line, sort_keys=True), flush=True)
        ok = ok and line.get("status") == 200
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
