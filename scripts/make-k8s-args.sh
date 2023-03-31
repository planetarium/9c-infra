#!/bin/bash
set -ex

BUMP_APV=$1
DIR=$2
HEADLESS_TAG=$3
DATAPROVIDER_TAG=$4
SEED_BRANCH=$5
MANUAL_ARGS=$6

file_path="9c-infra/$DIR/chart/values.yaml"
sources=""
bump_apv=""

if [ "$MANUAL_ARGS" ]; then
    sources="$MANUAL_ARGS"
else
    if [ "$HEADLESS_TAG" ]; then
        sources="ninechronicles-headless/from tag $HEADLESS_TAG|$sources"
    fi

    if [ "$DATAPROVIDER_TAG" ]; then
        sources="ninechronicles-dataprovider/from tag $DATAPROVIDER_TAG|$sources"
    fi

    if [ "$SEED_BRANCH" ]; then
        sources="libplanet-seed/from branch $SEED_BRANCH|$sources"
    fi

    if [ "$BUMP_APV" == "false" ]; then
        bump_apv="--no-bump-apv"
    fi
fi

K8S_CMD_ARGS="$file_path|$sources$bump_apv"
echo $K8S_CMD_ARGS
echo "K8S_CMD_ARGS=$K8S_CMD_ARGS" >> $GITHUB_OUTPUT
