#!/usr/bin/env bash
set -ex

preloaded="$(
  curl \
    -H 'Content-Type: application/json' \
    --data '{"query":"query{nodeStatus{preloadEnded}}"}' \
    http://localhost:80/graphql \
  | jq .data.nodeStatus.preloadEnded
)"

echo $preloaded
{{- if eq .Values.global.networkType "Main"  }}
if [[ "$preloaded" = "true" ]]; then
  echo "Preload finished. Check chain tip."
  local_tip="$(
    curl \
      -H 'Content-Type: application/json' \
      --data '{"query":"query{chainQuery{blockQuery{blocks(desc:true,limit:1){index}}}}"}' \
      http://localhost:80/graphql \
    | jq -r '.data.chainQuery.blockQuery.blocks[0].index'
  )"
  echo $local_tip
  miner_tip="$(
    curl \
      -H 'Content-Type: application/json' \
      --data '{"query":"query{chainQuery{blockQuery{blocks(desc:true,limit:1){index}}}}"}' \
      http://9c-main-validator-1.nine-chronicles.com/graphql \
    | jq -r '.data.chainQuery.blockQuery.blocks[0].index'
  )"
  echo $miner_tip
  echo [[ $(( miner_tip - local_tip)) -lt 5 ]]
  [[ $(( miner_tip - local_tip)) -lt 5 ]]
fi
{{- else }}
if [[ "$preloaded" = "true" ]]; then
  echo "Preload finished. Check chain tip."
  last_block="$(
    curl \
      -H 'Content-Type: application/json' \
      --data '{"query":"query{chainQuery{blockQuery{blocks(desc:true,limit:1){timestamp}}}}"}' \
      http://localhost:80/graphql \
      | jq -r '.data.chainQuery.blockQuery.blocks[0].timestamp'
  )"
  last_timestamp="$(date +%s -u --date="$last_block")"
  now="$(date +%s -u)"	
  [[ $(( now - last_timestamp )) -lt 400 ]]
fi
{{- end }}
