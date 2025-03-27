#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[ERROR] Script failed at line $LINENO with exit code $?" >&2' ERR
set -x

apt-get -y update
apt-get -y install curl zip unzip sudo p7zip-full

# Install rclone
curl https://rclone.org/install.sh | bash

HOME="/app"
STORE_PATH="/data/headless"
APP_PROTOCOL_VERSION=$1
VERSION_NUMBER="${APP_PROTOCOL_VERSION:0:6}"
SLACK_WEBHOOK=$2
CF_DISTRIBUTION_ID=$3
SNAPSHOT_PATH=$4

function setup_rclone() {
  RCLONE_CONFIG_DIR="/root/.config/rclone"
  mkdir -p "$RCLONE_CONFIG_DIR"

  export AWS_ACCESS_KEY_ID="$(cat /secret/aws_access_key_id)"
  export AWS_SECRET_ACCESS_KEY="$(cat /secret/aws_secret_access_key)"

  cat <<EOF > "$RCLONE_CONFIG_DIR/rclone.conf"
[r2]
type = s3
provider = Cloudflare
access_key_id = $AWS_ACCESS_KEY_ID
secret_access_key = $AWS_SECRET_ACCESS_KEY
endpoint = https://1cd1f38b21c0bfdde9501f7d8e43b663.r2.cloudflarestorage.com
region = auto
no_check_bucket = true
EOF

  export RCLONE_CONFIG="$RCLONE_CONFIG_DIR/rclone.conf"
}

function senderr() {
  echo "$1"
  curl -X POST -H 'Content-type: application/json' \
    --data '{"text":"[K8S] '"$1"'. Check snapshot in {{ $.Values.clusterName }} cluster at upload_snapshot.sh."}' "$SLACK_WEBHOOK"
}

function retry_until_success() {
  local max_attempts=100
  local delay=60
  local count=1

  until "$@"; do
    echo "[WARN] Attempt $count failed. Retrying in $delay seconds..."
    sleep $delay
    count=$((count + 1))
    if [ $count -gt $max_attempts ]; then
      echo "[ERROR] Command failed after $max_attempts attempts."
      return 1
    fi
  done
  echo "[INFO] Command succeeded after $count attempt(s)."
}

function make_and_upload_snapshot() {
  SNAPSHOT="$HOME/NineChronicles.Snapshot"
  OUTPUT_DIR="/data/snapshots"
  PARTITION_DIR="$OUTPUT_DIR/partition"
  STATE_DIR="$OUTPUT_DIR/state"
  METADATA_DIR="$OUTPUT_DIR/metadata"
  FULL_DIR="$OUTPUT_DIR/full"
  URL="https://snapshots.nine-chronicles.com/{{ $.Values.snapshot.path }}/latest.json"

  mkdir -p "$PARTITION_DIR" "$STATE_DIR" "$METADATA_DIR"

  if curl --output /dev/null --silent --head --fail "$URL"; then
    curl "$URL" -o "$METADATA_DIR/latest.json"
  else
    echo "URL does not exist: $URL"
  fi

  if ! "$SNAPSHOT" --output-directory "$OUTPUT_DIR" --store-path "$STORE_PATH" --block-before 0 --apv "$APP_PROTOCOL_VERSION" --snapshot-type "partition"; then
    senderr "Snapshot creation failed."
    exit 1
  fi

  LATEST_SNAPSHOT=$(ls -t "$PARTITION_DIR"/*.zip | head -1)
  LATEST_METADATA=$(ls -t "$METADATA_DIR"/*.json 2>/dev/null | head -1 || true)
  LATEST_STATE=$(ls -t "$STATE_DIR"/*.zip | head -1)

  SNAPSHOT_FILENAME=$(basename "$LATEST_SNAPSHOT")
  METADATA_FILENAME=$(basename "$LATEST_METADATA" || echo "")
  STATE_FILENAME=$(basename "$LATEST_STATE")

  NOW=$(date '+%Y%m%d%H%M%S')

  DEST_PATH="r2:9c-snapshots/{{ $.Values.snapshot.path }}"
  ARCHIVE_PATH="r2:9c-snapshots/{{ $.Values.snapshot.path }}/archive"

  echo "[INFO] Archiving snapshot..."
  ARCHIVED_SNAPSHOT_PATH="$ARCHIVE_PATH/snapshots/${NOW}_$SNAPSHOT_FILENAME"
  rclone copyto "$LATEST_SNAPSHOT" "$ARCHIVED_SNAPSHOT_PATH" \
    --s3-upload-cutoff 512M \
    --s3-chunk-size 512M \
    --s3-disable-checksum \
    --multi-thread-streams 4 \
    --no-traverse \
    --retries 5 \
    --low-level-retries 10

  echo "[INFO] Copying snapshot to latest path..."
  rclone copyto "$ARCHIVED_SNAPSHOT_PATH" "$DEST_PATH/$SNAPSHOT_FILENAME" \
    --no-traverse --retries 5 --low-level-retries 10

  if [ -n "$LATEST_METADATA" ]; then
    echo "[INFO] Archiving metadata..."
    ARCHIVED_METADATA_PATH="$ARCHIVE_PATH/metadata/${NOW}_$METADATA_FILENAME"
    rclone copyto "$LATEST_METADATA" "$ARCHIVED_METADATA_PATH" --no-traverse --retries 5 --low-level-retries 10

    echo "[INFO] Copying metadata to latest path..."
    rclone copyto "$ARCHIVED_METADATA_PATH" "$DEST_PATH/$METADATA_FILENAME" --no-traverse --retries 5 --low-level-retries 10
  fi

  echo "[INFO] Archiving state..."
  ARCHIVED_STATE_PATH="$ARCHIVE_PATH/states/${NOW}_$STATE_FILENAME"
  rclone copyto "$LATEST_STATE" "$ARCHIVED_STATE_PATH" \
    --s3-upload-cutoff 512M \
    --s3-chunk-size 512M \
    --s3-disable-checksum \
    --multi-thread-streams 4 \
    --no-traverse \
    --retries 5 \
    --low-level-retries 10

  echo "[INFO] Copying state to latest path (with retry)..."
  retry_until_success rclone copyto "$ARCHIVED_STATE_PATH" "$DEST_PATH/$STATE_FILENAME" \
    --no-traverse \
    --s3-disable-checksum \
    --s3-copy-cutoff 1G \
    --retries 5 \
    --low-level-retries 10

  rm "$LATEST_SNAPSHOT" "$LATEST_STATE"
  rm -rf "$METADATA_DIR"
}

trap '' HUP

echo "[INFO] Setting up rclone..."
setup_rclone

echo "[INFO] Starting snapshot process..."
make_and_upload_snapshot
