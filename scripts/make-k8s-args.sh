#!/bin/bash
set -ex

NETWORK=$1
HEADLESS_TAG=$2
DATAPROVIDER_TAG=$3
SEED_BRANCH=$4
MANUAL_ARGS=$5

file_path="\"9c-infra/$NETWORK/chart/values.yaml\""
sources=""

if [[ ! -z "$MANUAL_ARGS" ]]; then
    sources="$MANUAL_ARGS"
else
    if [[ ! -z "$HEADLESS_TAG" ]]; then
        sources="\"ninechronicles-headless/from tag $HEADLESS_TAG\" $sources"
    fi

    if [[ ! -z "$DATAPROVIDER_TAG" ]]; then
        sources="\"ninechronicles-dataprovider/from tag $DATAPROVIDER_TAG\" $sources"
    fi

    if [[ ! -z "$SEED_BRANCH" ]]; then
        sources="\"libplanet-seed/from branch $SEED_BRANCH\" $sources"
    fi
fi

K8S_CMD_ARGS="$file_path $sources"
echo $K8S_CMD_ARGS
# echo "K8S_CMD_ARGS=$K8S_CMD_ARGS" >> $GITHUB_OUTPUT
