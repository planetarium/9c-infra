#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[ERROR] Script failed at line $LINENO with exit code $?" >&2' ERR

apt-get -y update
apt-get -y install curl rclone

HOME="/app"
APP_PROTOCOL_VERSION=$1
VERSION_NUMBER="${APP_PROTOCOL_VERSION:0:6}"
SLACK_WEBHOOK=$2
CF_DISTRIBUTION_ID=$3
SNAPSHOT_PATH=$4
STORE_PATH="$6"
BYPASS_COPYSTATES="${7:-false}"
ZSTD="${8:-false}"
COMPRESSION_LEVEL="${9:-0}"
PRESERVE_PARTITIONS="${10:-false}"
PART_LENGTH="${11:-3}"

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
  echo "[DEBUG] Args: $1"
  OUTPUT_DIR="${1:-/data/snapshots}"
  PARTITION_DIR="$OUTPUT_DIR/partition"
  STATE_DIR="$OUTPUT_DIR/state"
  METADATA_DIR="$OUTPUT_DIR/metadata"
  URL="https://snapshots.nine-chronicles.com/{{ $.Values.snapshot.path }}/latest.json"

  mkdir -p "$OUTPUT_DIR"
  mkdir -p "$PARTITION_DIR" "$STATE_DIR" "$METADATA_DIR"

  if curl --output /dev/null --silent --head --fail "$URL"; then
    curl "$URL" -o "$METADATA_DIR/latest.json"
  else
    echo "URL does not exist: $URL"
  fi

  if ! "$SNAPSHOT" --output-directory "$OUTPUT_DIR" --store-path "$STORE_PATH" --block-before 0 \
      --apv "$APP_PROTOCOL_VERSION" --snapshot-type "partition" --bypass-copystates="$BYPASS_COPYSTATES" \
      --zstd="$ZSTD" --compression-level="$COMPRESSION_LEVEL"; then
    senderr "Snapshot creation failed."
    exit 1
  fi

  LATEST_SNAPSHOT=$(ls -t "$PARTITION_DIR"/*.z* | head -1)
  LATEST_METADATA=$(ls -t "$METADATA_DIR"/*.json 2>/dev/null | head -1 || true)
  LATEST_STATE=$(ls -t "$STATE_DIR"/*.z* | head -1)

  METADATA_FILENAME=$(basename "$LATEST_METADATA" || echo "")
  SNAPSHOT_FILENAME=$(basename "$LATEST_SNAPSHOT")
  STATE_FILENAME=$(basename "$LATEST_STATE")
  SNAPSHOT_EXTENSION="${LATEST_SNAPSHOT#*.}"
  STATE_EXTENSION="${LATEST_STATE#*.}"
  SNAPSHOT_LATEST_FILENAME="latest.$SNAPSHOT_EXTENSION"
  STATE_LATEST_FILENAME="latest.$STATE_EXTENSION"

  NOW=$(date '+%Y%m%d%H%M%S')

  DEST_PATH="r2:9c-snapshots/$SNAPSHOT_PATH"
  ARCHIVE_PATH="$DEST_PATH/archive"

  ARCHIVED_SNAPSHOT_PATH="$ARCHIVE_PATH/snapshots/${NOW}_$SNAPSHOT_FILENAME"
  echo "[INFO] Archiving snapshot: $ARCHIVED_SNAPSHOT_PATH"
  rclone copyto "$LATEST_SNAPSHOT" "$ARCHIVED_SNAPSHOT_PATH" \
    --s3-upload-cutoff 512M \
    --s3-chunk-size 512M \
    --s3-disable-checksum \
    --multi-thread-streams 4 \
    --no-traverse \
    --retries 5 \
    --low-level-retries 10

  echo "[INFO] Copying snapshot to latest path: $DEST_PATH/$SNAPSHOT_FILENAME"
  retry_until_success rclone copyto "$ARCHIVED_SNAPSHOT_PATH" "$DEST_PATH/$SNAPSHOT_FILENAME" \
    --no-traverse \
    --s3-disable-checksum \
    --s3-copy-cutoff 1G \
    --retries 5 \
    --low-level-retries 10 &
  retry_until_success rclone copyto "$ARCHIVED_SNAPSHOT_PATH" "$DEST_PATH/$SNAPSHOT_LATEST_FILENAME" \
    --no-traverse \
    --s3-disable-checksum \
    --s3-copy-cutoff 1G \
    --retries 5 \
    --low-level-retries 10 &
  retry_until_success rclone copyto "$ARCHIVED_SNAPSHOT_PATH" "$DEST_PATH/internal/$SNAPSHOT_FILENAME" \
    --no-traverse \
    --s3-disable-checksum \
    --s3-copy-cutoff 1G \
    --retries 5 \
    --low-level-retries 10 &
  retry_until_success rclone copyto "$ARCHIVED_SNAPSHOT_PATH" "$DEST_PATH/internal/$SNAPSHOT_LATEST_FILENAME" \
    --no-traverse \
    --s3-disable-checksum \
    --s3-copy-cutoff 1G \
    --retries 5 \
    --low-level-retries 10 &

  wait

  if [ -n "$LATEST_METADATA" ]; then
    ARCHIVED_METADATA_PATH="$ARCHIVE_PATH/metadata/${NOW}_$METADATA_FILENAME"
    echo "[INFO] Archiving metadata: $ARCHIVED_METADATA_PATH"
    rclone copyto "$LATEST_METADATA" "$ARCHIVED_METADATA_PATH" --no-traverse --retries 5 --low-level-retries 10

    echo "[INFO] Copying metadata to latest path: $DEST_PATH/$METADATA_FILENAME"
    rclone copyto "$ARCHIVED_METADATA_PATH" "$DEST_PATH/$METADATA_FILENAME" --no-traverse --retries 5 --low-level-retries 10 &
    rclone copyto "$ARCHIVED_METADATA_PATH" "$DEST_PATH/latest.json" --no-traverse --retries 5 --low-level-retries 10 &
    rclone copyto "$ARCHIVED_METADATA_PATH" "$DEST_PATH/internal/$METADATA_FILENAME" --no-traverse --retries 5 --low-level-retries 10 &
    rclone copyto "$ARCHIVED_METADATA_PATH" "$DEST_PATH/internal/latest.json" --no-traverse --retries 5 --low-level-retries 10 &
    rclone copyto "$ARCHIVED_METADATA_PATH" "$DEST_PATH/internal/mainnet_latest.json" --no-traverse --retries 5 --low-level-retries 10 &

    wait
  fi

  ARCHIVED_STATE_PATH="$ARCHIVE_PATH/states/${NOW}_$STATE_FILENAME"
  echo "[INFO] Archiving state: $ARCHIVED_STATE_PATH"
  rclone copyto "$LATEST_STATE" "$ARCHIVED_STATE_PATH" \
    --s3-upload-cutoff 512M \
    --s3-chunk-size 512M \
    --s3-disable-checksum \
    --multi-thread-streams 4 \
    --no-traverse \
    --retries 5 \
    --low-level-retries 10

  echo "[INFO] Copying state to latest path (with retry): $DEST_PATH/$STATE_FILENAME"
  retry_until_success rclone copyto "$ARCHIVED_STATE_PATH" "$DEST_PATH/$STATE_FILENAME" \
    --no-traverse \
    --s3-disable-checksum \
    --s3-copy-cutoff 1G \
    --retries 5 \
    --low-level-retries 10 &

  retry_until_success rclone copyto "$ARCHIVED_STATE_PATH" "$DEST_PATH/internal/$STATE_FILENAME" \
    --no-traverse \
    --s3-disable-checksum \
    --s3-copy-cutoff 1G \
    --retries 5 \
    --low-level-retries 10 &

  wait

  for file in $( find "$OUTPUT_DIR" -size +4G ); do
    split -b 4GB "$file" "$file.part" --numeric-suffixes=1 -a $PART_LENGTH
    for part in "$file.part"*; do
      retry_until_success rclone copyto "$part" "$DEST_PATH/${part##*/}" \
        --s3-upload-cutoff 512M \
        --s3-chunk-size 512M \
        --s3-disable-checksum \
        --multi-thread-streams 4 \
        --retries 5 \
        --low-level-retries 10 \
        --no-traverse && echo "[INFO] Copied $DEST_PATH/${part##*/}" && rm "$part" &
    done
  done

  wait

  if [ "$PRESERVE_PARTITIONS" = "false" ]; then
    rm "$LATEST_SNAPSHOT" "$LATEST_STATE" "$LATEST_METADATA"
  fi
  rm -rf "$METADATA_DIR"
}

trap '' HUP

echo "[INFO] Setting up rclone..."
setup_rclone

echo "[INFO] Starting snapshot process..."
make_and_upload_snapshot $5
