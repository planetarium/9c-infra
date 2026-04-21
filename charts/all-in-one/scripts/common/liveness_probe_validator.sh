#!/usr/bin/env bash
set -eo pipefail

query_staged() {
  curl -sS -m 5 \
    -H 'Content-Type: application/json' \
    --data '{"query":"query{nodeStatus{stagedTxIds}}"}' \
    "$1" 2>/dev/null \
    | jq -r '.data.nodeStatus.stagedTxIds | length' 2>/dev/null \
    || echo 0
}

my_staged=$(query_staged http://localhost:80/graphql)

if [[ "$my_staged" -gt 0 ]]; then
  last_block=$(
    curl -sS -m 5 \
      -H 'Content-Type: application/json' \
      --data '{"query":"query{chainQuery{blockQuery{blocks(desc:true,limit:1){timestamp}}}}"}' \
      http://localhost:80/graphql \
      | jq -r '.data.chainQuery.blockQuery.blocks[0].timestamp'
  )
  last_ts=$(date +%s -u --date="$last_block")
  now=$(date +%s)
  [[ $(( now - last_ts )) -lt 60 ]]
  exit $?
fi

{{- if gt (int $.Values.remoteHeadless.count) 0 }}
peer_url="http://remote-headless-1.{{ $.Release.Name }}.svc.cluster.local:{{ $.Values.remoteHeadless.ports.graphql }}/graphql"
peer_staged=$(query_staged "$peer_url")

if [[ "$peer_staged" -gt 0 ]]; then
  sleep 10
  my_staged=$(query_staged http://localhost:80/graphql)
  [[ "$my_staged" -gt 0 ]]
  exit $?
fi
{{- end }}

exit 0
