#!/usr/bin/env bash
set -ex

preloaded="$(
  curl \
    -H 'Content-Type: application/json' \
    --data '{"query":"query{nodeStatus{preloadEnded}}"}' \
    http://localhost:80/graphql \
  | jq .data.nodeStatus.preloadEnded
)"
[[ "$preloaded" = "true" ]]
