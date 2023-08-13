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
