#!/bin/bash

set -ex

apt-get update && apt-get install -y libc6-dev libsnappy-dev jq
dotnet tool install -g Libplanet.Tools

BLOCK_INDEX=${1:-"0"}
GRAPHQL_ENDPOINT=${2:-"http://odin-validator-5.nine-chronicles.com/graphql"}
STORE_PATH=${3:-"/headless/headless"}

if [ "$BLOCK_INDEX" = "0" ]; then
  BLOCK_INDEX=$(~/.dotnet/tools/planet stats -p "rocksdb+file://$STORE_PATH" -o -1 | cut -d, -f1 2>/dev/null)
fi

QUERY='{ "query": "query { blockStartingTxNoncesQuery(index: '$BLOCK_INDEX') { signer nonce } }" }'
RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" --data "$QUERY" "$GRAPHQL_ENDPOINT")

echo "$RESPONSE" | jq -c '.data.blockStartingTxNoncesQuery[]' | while read -r entry; do
  SIGNER=$(echo "$entry" | jq -r '.signer')
  NONCE=$(echo "$entry" | jq -r '.nonce')

  CURRENT_NONCE=$(~/.dotnet/tools/planet store get-tx-nonce "rocksdb+file://$STORE_PATH" "$SIGNER" 2>/dev/null)

  if [[ "$CURRENT_NONCE" != "$NONCE" ]]; then
    echo "Updating nonce for $SIGNER: $CURRENT_NONCE → $NONCE"
    ~/.dotnet/tools/planet store set-tx-nonce "rocksdb+file://$STORE_PATH" "$SIGNER" "$NONCE"
  else
    echo "Nonce is already up to date for $SIGNER"
  fi
done
