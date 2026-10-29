#!/usr/bin/env bash
set -eo pipefail

# Liveness fails only when the node is unresponsive or has stopped receiving txs.
# A halted chain is deliberately NOT a liveness failure: on 2026-10-29 odin's states DB
# hit RocksDB's level-0 write stop behind a 90-minute compaction, and every restart threw
# that compaction away and prolonged the halt. Tip stalls are alerted by tip monitors.

query_staged() {
  curl -sS -m 6 \
    -H 'Content-Type: application/json' \
    --data '{"query":"query{nodeStatus{stagedTxIds}}"}' \
    "$1" 2>/dev/null \
    | jq -er '.data.nodeStatus.stagedTxIds | length' 2>/dev/null
}

# No GraphQL answer from this process = genuinely unhealthy.
my_staged=$(query_staged http://localhost:80/graphql) || exit 1

{{- if gt (int $.Values.remoteHeadless.count) 0 }}
peer_url="http://remote-headless-1.{{ $.Release.Name }}.svc.cluster.local:{{ $.Values.remoteHeadless.ports.graphql }}/graphql"
# Peer downtime must never cascade into validator restarts.
peer_staged=$(query_staged "$peer_url") || exit 0

if [[ "$my_staged" -eq 0 && "$peer_staged" -gt 0 ]]; then
  sleep 10
  my_staged=$(query_staged http://localhost:80/graphql) || exit 1
  [[ "$my_staged" -gt 0 ]]
  exit $?
fi
{{- end }}

exit 0
