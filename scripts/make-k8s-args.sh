#!/bin/bash
set -ex

BUMP_APV=$1
DIR=$2
HEADLESS=$3
DATAPROVIDER=$4
SEED=$5
WORLD_BOSS_SERVICE=$6
MARKET_SERVICE=$7
MANUAL_ARGS=$8

if [ "$DIR" == "9c-internal" ]; then
    file_path="9c-infra/$DIR/9c-network/values.yaml"
else
    file_path="9c-infra/$DIR/chart/values.yaml"
fi

sources=""
bump_apv=""

if [ "$MANUAL_ARGS" ]; then
    sources="$MANUAL_ARGS"
else
    if [ "$HEADLESS" ]; then
        sources="ninechronicles-headless/from $HEADLESS|$sources"
        sources="lib9c-stateservice/from $HEADLESS|$sources"
    fi

    if [ "$DATAPROVIDER" ]; then
        sources="ninechronicles-dataprovider/from $DATAPROVIDER|$sources"
    fi

    if [ "$SEED" ]; then
        sources="libplanet-seed/from $SEED|$sources"
    fi

    if [ "$WORLD_BOSS_SERVICE" ]; then
        sources="world-boss-service/from $WORLD_BOSS_SERVICE|$sources"
    fi

    if [ "$MARKET_SERVICE" ]; then
        sources="market-service/from $MARKET_SERVICE|$sources"
    fi

    if [ "$BUMP_APV" == "false" ]; then
        bump_apv="--no-bump-apv"
    fi
fi

K8S_CMD_ARGS="$file_path|$sources$bump_apv"
echo $K8S_CMD_ARGS
echo "K8S_CMD_ARGS=$K8S_CMD_ARGS" >> $GITHUB_OUTPUT
