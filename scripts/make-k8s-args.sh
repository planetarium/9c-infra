#!/bin/bash
set -ex

BUMP_APV=$1
DIR=$2
HEADLESS=$3
LIB9C_STATESERVICE=$4
DATAPROVIDER=$5
SEED=$6
WORLD_BOSS_SERVICE=$7
MARKET_SERVICE=$8
MANUAL_ARGS=$9

if [ "$DIR" == "9c-internal" ]; then
    file_path="9c-infra/$DIR/9c-network/values.yaml"
else
    file_path="9c-infra/$DIR/chart/values.yaml"
fi
eda6ef63ae945cd15572fcf7d6635a8b3f8d86e85b57a353b482bc82c7fd2ad4
sources=""
bump_apv=""

if [ "$MANUAL_ARGS" ]; then
    sources="$MANUAL_ARGS"
else
    if [ "$HEADLESS" ]; then
        sources="ninechronicles-headless/from $HEADLESS|$sources"
    fi

    if [ "$LIB9C_STATESERVICE" ]; then
        sources="lib9c-stateservice/from $LIB9C_STATESERVICE|$sources"
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
