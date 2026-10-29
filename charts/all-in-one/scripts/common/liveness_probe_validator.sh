#!/usr/bin/env bash
set -eo pipefail

# Restarting a validator throws away any RocksDB compaction in flight. On 2026-10-29 odin's
# states DB hit the level-0 write stop behind a 90-minute compaction and every restart
# prolonged the halt, so a halted chain alone is not a liveness failure here.

STORE="{{ $.Values.validator.storePath | default "/data/headless" }}"
STALL_LIMIT_SECONDS=1800
COMPACTION_WINDOW_MINUTES=10

gql() {
  curl -sS -m 4 \
    -H 'Content-Type: application/json' \
    --data "$2" \
    "$1" 2>/dev/null
}

query_staged() {
  gql "$1" '{"query":"query{nodeStatus{stagedTxIds}}"}' \
    | jq -er '.data.nodeStatus.stagedTxIds | length' 2>/dev/null
}

# 1. The process must answer GraphQL. bootstrapEnded is in-memory, so a busy disk can't fail it.
gql http://localhost:80/graphql '{"query":"query{nodeStatus{bootstrapEnded}}"}' \
  | jq -e '.data.nodeStatus.bootstrapEnded != null' >/dev/null 2>&1 || exit 1

# 2. A long stall with no compaction running looks like a wedged consensus/transport,
#    which a restart does fix. Can't read the tip timestamp -> don't guess, pass.
last_block=$(
  gql http://localhost:80/graphql '{"query":"query{chainQuery{blockQuery{blocks(desc:true,limit:1){timestamp}}}}"}' \
    | jq -er '.data.chainQuery.blockQuery.blocks[0].timestamp' 2>/dev/null
) || exit 0
stall=$(( $(date +%s) - $(date +%s -u --date="$last_block") ))
if [[ "$stall" -gt "$STALL_LIMIT_SECONDS" ]]; then
  # Any RocksDB (states, txbindex, tx/*, ...) still writing compaction output: let it finish.
  cutoff=$(date -u -d "-${COMPACTION_WINDOW_MINUTES} min" +%Y/%m/%d-%H:%M:%S)
  if find "$STORE" -maxdepth 3 -name LOG -mmin "-${COMPACTION_WINDOW_MINUTES}" 2>/dev/null \
    | xargs -r grep -h -E 'Generated table|compaction_started' 2>/dev/null \
    | awk -v cutoff="$cutoff" '$1 >= cutoff { found = 1 } END { exit !found }'; then
    exit 0
  fi
  exit 1
fi

{{- if gt (int $.Values.remoteHeadless.count) 0 }}
# 3. Peers have txs this validator never received. Peer downtime must not restart the validator.
my_staged=$(query_staged http://localhost:80/graphql) || exit 0
peer_url="http://remote-headless-1.{{ $.Release.Name }}.svc.cluster.local:{{ $.Values.remoteHeadless.ports.graphql }}/graphql"
peer_staged=$(query_staged "$peer_url") || exit 0

if [[ "$my_staged" -eq 0 && "$peer_staged" -gt 0 ]]; then
  sleep 5
  my_staged=$(query_staged http://localhost:80/graphql) || exit 0
  [[ "$my_staged" -gt 0 ]]
  exit $?
fi
{{- end }}

exit 0
