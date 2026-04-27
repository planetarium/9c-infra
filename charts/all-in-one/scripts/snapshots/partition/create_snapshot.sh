#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[ERROR] Script failed at line $LINENO with exit code $?" >&2' ERR

apt-get -y update
apt-get -y install curl

HOME="/app"
APP_PROTOCOL_VERSION=$1
SLACK_WEBHOOK=$2
OUTPUT_DIR="${3:-/data/snapshots}"
STORE_PATH="${4:-/data/headless}"
BYPASS_COPYSTATES="${5:-false}"
ZSTD="${6:-false}"
COMPRESSION_LEVEL="${7:-0}"

PARTITION_DIR="$OUTPUT_DIR/partition"
STATE_DIR="$OUTPUT_DIR/state"
METADATA_DIR="$OUTPUT_DIR/metadata"
SENTINEL="$OUTPUT_DIR/.snapshot-created"

function senderr() {
  echo "$1"
  curl -X POST -H 'Content-type: application/json' \
    --data '{"text":"[K8S] '"$1"'. Check snapshot in {{ $.Values.clusterName }} cluster at create_snapshot.sh."}' "$SLACK_WEBHOOK"
}

# Skip if recent snapshot already exists (restart safety for initContainer restarts).
# Require both sentinel freshness AND actual output files on disk — sentinel alone
# can lie when a prior upload ran with PRESERVE_PARTITIONS=false, which deletes the
# snapshot files but leaves the sentinel behind, causing the next run to skip
# create_snapshot and then fail in upload_snapshot with "No snapshot files found".
if [ -f "$SENTINEL" ]; then
  created_at=$(cat "$SENTINEL")
  now=$(date +%s)
  age=$(( now - created_at ))
  if [ "$age" -lt 43200 ] && ls "$PARTITION_DIR"/*.z* >/dev/null 2>&1 && ls "$STATE_DIR"/*.z* >/dev/null 2>&1; then
    echo "[INFO] Recent snapshot exists (${age}s ago) with files, skipping creation."
    exit 0
  elif [ "$age" -lt 43200 ]; then
    echo "[WARN] Sentinel is fresh (${age}s) but output files missing; running create_snapshot anyway."
    rm -f "$SENTINEL"
  fi
fi

SNAPSHOT="$HOME/NineChronicles.Snapshot"
URL="https://snapshots.nine-chronicles.com/{{ $.Values.snapshot.path }}/latest.json"

mkdir -p "$PARTITION_DIR" "$STATE_DIR" "$METADATA_DIR"

if curl --output /dev/null --silent --head --fail "$URL"; then
  curl "$URL" -o "$METADATA_DIR/latest.json"
else
  echo "[WARN] URL does not exist: $URL"
fi

if ! "$SNAPSHOT" --output-directory "$OUTPUT_DIR" --store-path "$STORE_PATH" --block-before 0 \
    --apv "$APP_PROTOCOL_VERSION" --snapshot-type "partition" --bypass-copystates="$BYPASS_COPYSTATES" \
    --zstd="$ZSTD" --compression-level="$COMPRESSION_LEVEL" --slack-webhook-url="$SLACK_WEBHOOK"; then
  senderr "Snapshot creation failed."
  exit 1
fi

date +%s > "$SENTINEL"
echo "[INFO] Snapshot creation complete."
