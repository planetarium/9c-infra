#!/bin/bash
set -ex

NETWORK="$1"
HEADLESS_TAG="$2"
DATAPROVIDER_TAG="$3"
SEED_BRANCH="$4"
MANUAL_CMD="$5"

file_path="'9c-infra/$NETWORK/chart/values.yaml'"
sources=""

if [[ $MANUAL_CMD ]]; then
    sources=$MANUAL_CMD
else
    if [[ $HEADLESS_TAG ]]; then
        sources="'ninechronicles-headless/from tag $HEADLESS_TAG' $sources"
    fi

    if [[ $DATAPROVIDER_TAG ]]; then
        sources="'ninechronicles-dataprovider/from tag $DATAPROVIDER_TAG' $sources"
    fi

    if [[ $SEED_BRANCH ]]; then
        sources="'libplanet-seed/from branch $SEED_BRANCH' $sources"
    fi
fi

K8S_CMD="$file_path $sources"
echo "K8S_CMD=$K8S_CMD" >> $GITHUB_OUTPUT
