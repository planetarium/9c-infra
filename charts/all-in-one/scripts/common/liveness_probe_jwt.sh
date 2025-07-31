#!/usr/bin/env bash
set -e

if [ -z "$JWT_TOKEN" ]; then
  echo "Token not provided"
  exit 1
else
  preloaded="$(
    curl \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $JWT_TOKEN" \
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
        -H "Authorization: Bearer $JWT_TOKEN" \
        http://localhost:80/graphql \
      | jq -r '.data.chainQuery.blockQuery.blocks[0].index'
    )"
    echo $local_tip
    miner_tip="$(
      curl \
        -H 'Content-Type: application/json' \
        --data '{"query":"query{chainQuery{blockQuery{blocks(desc:true,limit:1){index}}}}"}' \
        {{ $.Values.global.validatorPath }}/graphql \
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
        -H "Authorization: Bearer $JWT_TOKEN" \
        http://localhost:80/graphql \
        | jq -r '.data.chainQuery.blockQuery.blocks[0].timestamp'
    )"
    last_timestamp="$(date +%s -u --date="$last_block")"
    now="$(date +%s -u)"	
    [[ $(( now - last_timestamp )) -lt 400 ]]
  fi
  {{- end }}
fi
