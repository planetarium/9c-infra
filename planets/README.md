# ⚠️ 이 디렉터리는 더 이상 배포 원본이 아닙니다

2026-09-26 부터 플래닛 레지스트리는 **백오피스에서 S3 에 직접** 반영합니다.

- 화면: <https://backoffice.nine-chronicles.com/planet-registry>
- API: `POST /api/tools/planet-registry` (헤더 `X-API-Key`)
- 운영 지식: 9c-backoffice 저장소의 `planets-registry-ops` 스킬

**클라이언트가 실제로 읽는 것은 아래이고, 이 저장소의 JSON 이 아닙니다.**

| 레지스트리 | 라이브 URL |
|---|---|
| mainnet | <https://planets.nine-chronicles.com/planets/index.json> |
| internal | <https://planets-internal.nine-chronicles.com/planets/index.json> |
| preview | <https://planets-internal.nine-chronicles.com/planets-preview/index.json> |

## 왜 바꿨나

장애 중 죽은 RPC 엔드포인트를 빼는 게 이 파일의 주 용도인데(4개월에 12번 변경,
대부분 `Maintenance ...` / `Revert ...`), PR 왕복이 느렸습니다.

그리고 **두 경로가 모두 살아 있으면 서로를 덮어씁니다.** 백오피스로 뺀 엔드포인트가
몇 주 뒤 무관한 planets PR 머지로 조용히 되살아납니다. 그래서 자동 배포 트리거
(`pull_request_target`)를 끊었습니다.

## 이 파일들은 왜 남겨두나

이력 참조용입니다. **최신이라는 보장이 없습니다** — 라이브와 다를 수 있으니
현재 상태를 알고 싶으면 위 라이브 URL 을 보세요.

## 비상구

백오피스가 죽었거나 S3 를 직접 못 고칠 때만:

1. `planets/<registry>.json` 을 고쳐 머지
2. Actions → **Update planets config** → Run workflow → registry 선택

⚠️ 이건 **git 내용으로 라이브를 통째로 덮어씁니다.** 백오피스로 바꾼 내용이 있으면
사라지므로, 실행 전 반드시 라이브와 대조하세요:

```
curl -s https://planets.nine-chronicles.com/planets/index.json | jq .
```

## 되돌리기

백오피스 화면의 백업 목록에서 복원합니다. 저장할 때마다
`planets/backups/index-<UTC>-<8자리>.json` 으로 직전 내용이 보관되고,
버킷 버저닝도 켜져 있습니다. (예전처럼 `git revert` 로는 되돌아가지 않습니다.)
