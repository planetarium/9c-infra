#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[ERROR] Script failed at line $LINENO with exit code $?" >&2' ERR

apt-get -y update
apt-get -y install curl rclone

HOME="/app"
STORE_PATH="/data/headless"
APP_PROTOCOL_VERSION=$1
VERSION_NUMBER="${APP_PROTOCOL_VERSION:0:6}"
SLACK_WEBHOOK=$2
CF_DISTRIBUTION_ID=$3
SNAPSHOT_PATH=$4
PART_LENGTH="${5:-3}"

# Define directories
OUTPUT_DIR="/data/snapshots"
PARTITION_DIR="$OUTPUT_DIR/partition"
STATE_DIR="$OUTPUT_DIR/state"
METADATA_DIR="$OUTPUT_DIR/metadata"
FULL_DIR="$OUTPUT_DIR/full"
mkdir -p "$OUTPUT_DIR" "$PARTITION_DIR" "$STATE_DIR" "$METADATA_DIR" "$FULL_DIR"

function senderr() {
  echo "$1"
  curl -X POST -H 'Content-type: application/json' \
       --data '{"text":"[K8S] '$1'. Check snapshot in {{ $.Values.clusterName }} cluster at upload_snapshot.sh."}' \
       "$SLACK_WEBHOOK"
}

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
  echo "[INFO] Starting make_and_upload_snapshot..."
  SNAPSHOT="$HOME/NineChronicles.Snapshot"
  URL="https://snapshots.nine-chronicles.com/$SNAPSHOT_PATH/latest.json"

  if curl --output /dev/null --silent --head --fail "$URL"; then
    curl "$URL" -o "$METADATA_DIR/latest.json"
  else
    echo "URL does not exist: $URL"
  fi

  rm -rf "$FULL_DIR"/* || true

  if ! "$SNAPSHOT" --output-directory "$OUTPUT_DIR" --store-path "$STORE_PATH" --block-before 0 --apv "$APP_PROTOCOL_VERSION" --snapshot-type "full"; then
    senderr "Snapshot creation failed."
    exit 1
  fi

  LATEST_FULL_SNAPSHOT=$(ls -t "$FULL_DIR"/*.zip | head -1)
  NOW=$(date '+%Y%m%d%H%M%S')

  DEST_PATH="r2:9c-snapshots/$SNAPSHOT_PATH/full"
  ARCHIVE_PATH="r2:9c-snapshots/$SNAPSHOT_PATH/archive/full"

  echo "[INFO] Uploading snapshot to $ARCHIVE_PATH..."
  BASENAME=$(basename "$LATEST_FULL_SNAPSHOT")
  ARCHIVED_NAME="${NOW}_$BASENAME"
  ARCHIVED_PATH="$ARCHIVE_PATH/$ARCHIVED_NAME"

  rclone copyto "$LATEST_FULL_SNAPSHOT" "$ARCHIVED_PATH" \
    --s3-upload-cutoff 512M \
    --s3-chunk-size 512M \
    --s3-disable-checksum \
    --multi-thread-streams 4 \
    --retries 5 \
    --low-level-retries 10 \
    --no-traverse

  # Copy within R2 using server-side copy (no re-upload)
  FINAL_NAME="9c-main-snapshot.zip"
  FINAL_DEST="$DEST_PATH/$FINAL_NAME"

  split -b 4GB "$LATEST_FULL_SNAPSHOT" "$FINAL_NAME.part" --numeric-suffixes=1 -a $PART_LENGTH
  for part in "$FINAL_NAME.part"*; do
    retry_until_success rclone copyto "$part" "$DEST_PATH/$part" \
      --s3-upload-cutoff 512M \
      --s3-chunk-size 512M \
      --s3-disable-checksum \
      --multi-thread-streams 4 \
      --retries 5 \
      --low-level-retries 10 \
      --no-traverse
    rm "$part"
  done

  echo "[INFO] Copying archive snapshot to $FINAL_DEST without re-upload..."
  retry_until_success rclone copyto "$ARCHIVED_PATH" "$FINAL_DEST" \
    --no-traverse \
    --s3-disable-checksum \
    --retries 5 \
    --s3-copy-cutoff 1G \
    --low-level-retries 10

  LATEST_METADATA=$(ls -t "$METADATA_DIR"/*.json 2>/dev/null | head -1 || true)
  if [ -n "$LATEST_METADATA" ]; then
    echo "[INFO] Uploading metadata $LATEST_METADATA..."
    rclone copyto "$LATEST_METADATA" "$DEST_PATH/latest.json" --no-traverse --retries 5 --low-level-retries 10
  else
    echo "[INFO] No metadata file found to upload."
  fi

  echo "[INFO] Snapshot upload complete."
  rm "$LATEST_FULL_SNAPSHOT"
  rm -rf "$METADATA_DIR"
}

trap '' HUP

setup_rclone
make_and_upload_snapshot
