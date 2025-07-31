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
  [[ "$preloaded" = "true" ]]
fi
