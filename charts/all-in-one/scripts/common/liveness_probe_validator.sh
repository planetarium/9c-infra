#!/usr/bin/env bash
set -ex

stagedTxIdsCount="$(
  curl \
  -H 'Content-Type: application/json' \
  --data '{"query":"query{nodeStatus{stagedTxIds}}"}' \
  http://localhost:80/graphql | jq .data.nodeStatus | jq '.stagedTxIds | length'
)"

if [[ $(( stagedTxIdsCount )) -gt 0 ]]; then
  last_block="$(
    curl \
    -H 'Content-Type: application/json' \
    --data '{"query":"query{chainQuery{blockQuery{blocks(desc:true,limit:1){timestamp}}}}"}' \
    http://localhost:80/graphql | jq -r '.data.chainQuery.blockQuery.blocks[0].timestamp')"
  last_timestamp="$(date +%s -u --date="$last_block")"
  now="$(date +%s)"
  [[ $(( now - last_timestamp )) -lt 300 ]]
else
  [[ $(( stagedTxIdsCount )) -gt 0 ]]
fi
