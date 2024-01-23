#!/bin/bash

NAMESPACE="heimdall"
GITHUB_TOKEN=${GITHUB_TOKEN}
REPO="planetarium/9c-infra"
FILE_PATH="9c-internal/multiplanetary/network/heimdall.yaml"
BRANCH="test-script"

scale_down() {
    kubectl scale --replicas=0 statefulset/$1 --namespace=$NAMESPACE
}

delete_pvc() {
    kubectl delete pvc/$1 --namespace=$NAMESPACE
}

scale_down "bridge-service-db"
scale_down "bridge-service"

echo "scale_down db, service"

delete_pvc "bridge-service-db-data-bridge-service-db-0"

echo "delete pvc"

GQL_ENDPOINT="https://9c-internal-rpc-1.nine-chronicles.com/graphql"
GQL_QUERY='{"query":"{ nodeStatus { tip { index } } }"}'

TIP_INDEX=$(curl -s -X POST -H "Content-Type: application/json" -d "$GQL_QUERY" $GQL_ENDPOINT | jq -r '.data.nodeStatus.tip.index')

echo "tip " $TIP_INDEX

sed -i'.bak' "/defaultStartBlockIndex:/,/upstream:/s/upstream: \".*\"/upstream: \"$TIP_INDEX\"/" $FILE_PATH
rm '9c-internal/multiplanetary/network/heimdall.yaml.bak'

echo "update tip"

git config --global user.email "engineering+9cinfra@planetariumhq.com"
git config --global user.name "9c-infra-bot"

git add .
git commit -m "Update RDB upstream index to $TIP_INDEX"
git push origin $BRANCH

echo "commit"
