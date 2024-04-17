#!/usr/bin/env bash
set -ex

if [ -z "$1" ]; then
  echo "Token not provided"
  exit 1
else
  preloaded="$(
    curl \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $1" \
      --data '{"query":"query{nodeStatus{preloadEnded}}"}' \
      http://localhost:80/graphql \
    | jq .data.nodeStatus.preloadEnded
  )"
  [[ "$preloaded" = "true" ]]
fi
