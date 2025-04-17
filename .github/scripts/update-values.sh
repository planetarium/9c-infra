#!/bin/bash
set -ex

DIR=$1
FILE_NAME=$2
HEADLESS=$3
SEED=$4
BRIDGE_SERVICE=$5
DATA_PROVIDER=$6
WORLD_BOSS=$7
MARKET_SERVICE=$8
RUDOLF_SERVICE=$9
PORTAL_SERVICE=$10
PORTAL_BACKOFFICE_SERVICE=$11

file_path="$DIR/network/$FILE_NAME.yaml"

sources=""

if [ "$MANUAL_ARGS" ]; then
    sources="$MANUAL_ARGS"
else
    if [ "$HEADLESS" ]; then
        sources="global|planetariumhq/ninechronicles-headless:$HEADLESS $sources"
    fi

    if [ "$SEED" ]; then
        sources="seed|planetariumhq/libplanet-seed:$SEED $sources"
    fi

    if [ "$BRIDGE_SERVICE" ]; then
        sources="bridgeService|planetariumhq/9c-bridge:$BRIDGE_SERVICE $sources"
    fi

    if [ "$DATA_PROVIDER" ]; then
        sources="dataProvider|planetariumhq/ninechronicles-dataprovider:$DATA_PROVIDER $sources"
    fi

    if [ "$WORLD_BOSS" ]; then
        sources="worldBoss|planetariumhq/world-boss-service:$WORLD_BOSS $sources"
    fi

    if [ "$MARKET_SERVICE" ]; then
        sources="marketService|planetariumhq/market-service:$MARKET_SERVICE $sources"
    fi

    if [ "$RUDOLF_SERVICE" ]; then
        sources="rudolfService|planetariumhq/9c-rudolf:$RUDOLF_SERVICE $sources"
    fi

    if [ "$PORTAL_SERVICE" ]; then
        sources="portalService|planetariumhq/9c-portal:main-$PORTAL_SERVICE $sources"
    else
        sources="portalService|planetariumhq/9c-portal:internal-$PORTAL_SERVICE $sources"
    fi

    if [ "$PORTAL_BACKOFFICE_SERVICE" ]; then
        sources="backofficeService|planetariumhq/9c-portal-backoffice:main-$PORTAL_BACKOFFICE_SERVICE $sources"
    else
        sources="backofficeService|planetariumhq/9c-portal-backoffice:internal-$PORTAL_BACKOFFICE_SERVICE $sources"
    fi
fi

echo $sources

cd scripts
python cli.py update-values $file_path $sources
