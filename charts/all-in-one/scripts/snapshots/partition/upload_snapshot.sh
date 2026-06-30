#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[ERROR] Script failed at line $LINENO with exit code $?" >&2' ERR

apt-get -y update
apt-get -y install curl rclone

HOME="/app"
APP_PROTOCOL_VERSION=$1
VERSION_NUMBER="${APP_PROTOCOL_VERSION:0:6}"
SLACK_WEBHOOK=$2
SOURCE_PREFIX="${SNAPSHOT_SOURCE_LABEL:+[$SNAPSHOT_SOURCE_LABEL] }"
CF_DISTRIBUTION_ID=$3
SNAPSHOT_PATH=$4
STORE_PATH="$6"
BYPASS_COPYSTATES="${7:-false}"
ZSTD="${8:-false}"
COMPRESSION_LEVEL="${9:-0}"
PRESERVE_PARTITIONS="${10:-false}"
PART_LENGTH="${11:-3}"

# --- Publish tuning (Helm values; bash :- defaults keep legacy behavior) ---
# archiveToS3=false skips the AWS S3 GLACIER archive and uploads to R2 directly
# from the local files. Needed on pt6 where large multipart PUTs to AWS S3 hang
# (on-prem -> AWS network path) while Cloudflare R2 uploads work fine.
ARCHIVE_TO_S3="{{ $.Values.snapshot.archiveToS3 }}"; ARCHIVE_TO_S3="${ARCHIVE_TO_S3:-true}"
# Parallel chunk streams per rclone upload. pt6's uplink is single-stream
# window-limited (~0.6MB/s at the default 4); 16 streams reach ~3.4MB/s.
RCLONE_CONCURRENCY="{{ $.Values.snapshot.rcloneUploadConcurrency }}"; RCLONE_CONCURRENCY="${RCLONE_CONCURRENCY:-4}"
# uploadSplitParts=false skips re-uploading >4G files as .partNNN chunks.
# download_snapshot.sh's test_ext_path tries .part001 then falls back to the
# whole file, so parts are an optimisation, not a requirement; skipping roughly
# halves the state upload (no second 64G pass) on slow uplinks like pt6.
UPLOAD_SPLIT_PARTS="{{ $.Values.snapshot.uploadSplitParts }}"; UPLOAD_SPLIT_PARTS="${UPLOAD_SPLIT_PARTS:-true}"

function setup_rclone() {
  RCLONE_CONFIG_DIR="/root/.config/rclone"
  mkdir -p "$RCLONE_CONFIG_DIR"

  export AWS_ACCESS_KEY_ID="$(cat /secret/aws_access_key_id)"
  export AWS_SECRET_ACCESS_KEY="$(cat /secret/aws_secret_access_key)"
  ORIG_AWS_ACCESS_KEY_ID="$(cat /secret/orig__aws_access_key_id)"
  ORIG_AWS_SECRET_ACCESS_KEY="$(cat /secret/orig__aws_secret_access_key)"

  cat <<EOF > "$RCLONE_CONFIG_DIR/rclone.conf"
[r2]
type = s3
provider = Cloudflare
access_key_id = $AWS_ACCESS_KEY_ID
secret_access_key = $AWS_SECRET_ACCESS_KEY
endpoint = https://1cd1f38b21c0bfdde9501f7d8e43b663.r2.cloudflarestorage.com
region = auto
no_check_bucket = true

[s3]
type = s3
provider = AWS
access_key_id = $ORIG_AWS_ACCESS_KEY_ID
secret_access_key = $ORIG_AWS_SECRET_ACCESS_KEY
region = us-east-2
storage_class = GLACIER_IR
no_check_bucket = true
EOF

  export RCLONE_CONFIG="$RCLONE_CONFIG_DIR/rclone.conf"
}

function senderr() {
  echo "$1"
  curl -X POST -H 'Content-type: application/json' \
    --data '{"text":"'"$SOURCE_PREFIX"'[K8S] '"$1"'. Check snapshot in {{ $.Values.clusterName }} cluster at upload_snapshot.sh."}' "$SLACK_WEBHOOK"
}

# Success/info notification. Non-fatal (|| true): a failed Slack post must not
# fail an otherwise-successful snapshot upload.
function sendinfo() {
  echo "$1"
  curl -X POST -H 'Content-type: application/json' \
    --data '{"text":"'"$SOURCE_PREFIX"'[K8S] '"$1"'"}' "$SLACK_WEBHOOK" || true
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

# Wait on every background PID passed as args and return non-zero if ANY failed.
# A bare `wait` (no args) always returns 0, so it silently swallowed background
# upload failures (e.g. an R2 403): the Job would exit 0 and report success
# while the public latest.json stayed weeks stale. Collect PIDs and fail loudly.
function wait_all() {
  local pid rc=0
  for pid in "$@"; do
    if ! wait "$pid"; then rc=1; fi
  done
  return "$rc"
}

# Publish one artifact (snapshot zip / state / metadata) to its R2 destinations,
# crossing the WAN with the local file only ONCE regardless of dest count:
#   ARCHIVE_TO_S3=true : upload local -> S3 GLACIER archive, then server-side
#                        copy S3 -> each R2 destination.
#   ARCHIVE_TO_S3=false: upload local -> first R2 destination, then server-side
#                        copy R2 -> the remaining R2 destinations.
# Usage: publish_artifact <local_file> <s3_archive_path> <r2_dest> [r2_dest ...]
function publish_artifact() {
  local local_file="$1" s3_path="$2"
  shift 2
  local up_flags="--no-traverse --s3-disable-checksum --s3-upload-cutoff=64M --s3-chunk-size=64M --s3-upload-concurrency=$RCLONE_CONCURRENCY --retries 5 --low-level-retries 10"
  local copy_flags="--no-traverse --s3-disable-checksum --s3-copy-cutoff 1G --retries 5 --low-level-retries 10"
  local source
  if [ "$ARCHIVE_TO_S3" = "true" ]; then
    echo "[INFO] Archiving to S3: $s3_path"
    # Explicit check: set -e is suppressed inside a function called from `if !`,
    # so a bare failing command would not abort — fail loudly here instead.
    if ! rclone copyto "$local_file" "$s3_path" $up_flags; then
      echo "[ERROR] S3 archive failed: $s3_path"
      return 1
    fi
    source="$s3_path"
  else
    source="$1"
    shift
    echo "[INFO] Uploading to R2 (S3 archive skipped): $source"
    retry_until_success rclone copyto "$local_file" "$source" $up_flags
  fi
  local pids=() dest
  for dest in "$@"; do
    echo "[INFO] Copying to $dest"
    retry_until_success rclone copyto "$source" "$dest" $copy_flags &
    pids+=($!)
  done
  if [ "${#pids[@]}" -gt 0 ] && ! wait_all "${pids[@]}"; then
    return 1
  fi
}

function make_and_upload_snapshot() {
  echo "[DEBUG] Args: $1"
  OUTPUT_DIR="${1:-/data/snapshots}"
  PARTITION_DIR="$OUTPUT_DIR/partition"
  STATE_DIR="$OUTPUT_DIR/state"
  METADATA_DIR="$OUTPUT_DIR/metadata"

  # Clean up leftover split part files from any previous interrupted run
  find "$OUTPUT_DIR" -name "*.part*" -delete 2>/dev/null || true

  if ! ls "$PARTITION_DIR"/*.z* > /dev/null 2>&1; then
    senderr "No snapshot files found in $PARTITION_DIR. Was create_snapshot step completed?"
    exit 1
  fi

  LATEST_SNAPSHOT=$(ls -t "$PARTITION_DIR"/*.z* | grep -v '\.part' | head -1)
  LATEST_METADATA=$(ls -t "$METADATA_DIR"/*.json 2>/dev/null | head -1 || true)
  LATEST_STATE=$(ls -t "$STATE_DIR"/*.z* | grep -v '\.part' | head -1)

  METADATA_FILENAME=$(basename "$LATEST_METADATA" || echo "")
  SNAPSHOT_FILENAME=$(basename "$LATEST_SNAPSHOT")
  STATE_FILENAME=$(basename "$LATEST_STATE")
  SNAPSHOT_EXTENSION="${LATEST_SNAPSHOT#*.}"
  STATE_EXTENSION="${LATEST_STATE#*.}"
  SNAPSHOT_LATEST_FILENAME="latest.$SNAPSHOT_EXTENSION"
  STATE_LATEST_FILENAME="latest.$STATE_EXTENSION"

  NOW=$(date '+%Y%m%d%H%M%S')

  DEST_PATH="r2:9c-snapshots/$SNAPSHOT_PATH"
  ARCHIVE_PATH="s3:9c-snapshots-archive/$SNAPSHOT_PATH/archive"

  # Upload order: data first (partition zip, then state + split parts), and the
  # metadata/latest.json pointer LAST (see below) so the public latest.json never
  # points at a snapshot whose state_latest.zip is not yet fully uploaded — this
  # window is ~hours on a slow uplink like pt6.

  # The legacy "$DEST_PATH/internal/..." mirror copies were dropped: nothing
  # consumes them (every node's snapshot.path points at the public path, never
  # <network>/partition/internal), they doubled R2 storage, and R2 has no
  # lifecycle so they accumulated unbounded. Publish only the public serving set.

  # 1) partition snapshot zip
  ARCHIVED_SNAPSHOT_PATH="$ARCHIVE_PATH/snapshots/${NOW}_$SNAPSHOT_FILENAME"
  if ! publish_artifact "$LATEST_SNAPSHOT" "$ARCHIVED_SNAPSHOT_PATH" \
      "$DEST_PATH/$SNAPSHOT_FILENAME" \
      "$DEST_PATH/$SNAPSHOT_LATEST_FILENAME"; then
    senderr "Failed to upload partition snapshot to R2 ($DEST_PATH)."
    exit 1
  fi

  # 2) state
  ARCHIVED_STATE_PATH="$ARCHIVE_PATH/states/${NOW}_$STATE_FILENAME"
  if ! publish_artifact "$LATEST_STATE" "$ARCHIVED_STATE_PATH" \
      "$DEST_PATH/$STATE_FILENAME"; then
    senderr "Failed to upload state snapshot to R2 ($DEST_PATH)."
    exit 1
  fi

  # 3) split parts of any >4G file (state). Optional: download_snapshot.sh falls
  #    back to the whole file when parts are absent, so this is skippable on slow
  #    uplinks to avoid a second full-size pass.
  if [ "$UPLOAD_SPLIT_PARTS" = "true" ]; then
    part_pids=()
    _parallel_count=0
    for file in $( find "$OUTPUT_DIR" -size +4G ); do
      split -b 4GB "$file" "$file.part" --numeric-suffixes=1 -a $PART_LENGTH
      for part in "$file.part"*; do
        retry_until_success rclone copyto "$part" "$DEST_PATH/${part##*/}" \
          --s3-upload-cutoff 64M \
          --s3-chunk-size 64M \
          --s3-disable-checksum \
          --s3-upload-concurrency=$RCLONE_CONCURRENCY \
          --retries 5 \
          --low-level-retries 10 \
          --no-traverse && echo "[INFO] Copied $DEST_PATH/${part##*/}" && rm "$part" &
        part_pids+=($!)
        _parallel_count=$(( _parallel_count + 1 ))
        if [ $(( _parallel_count % 5 )) -eq 0 ]; then
          if ! wait_all "${part_pids[@]}"; then
            senderr "Failed to upload split part to R2 ($DEST_PATH)."
            exit 1
          fi
          part_pids=()
        fi
      done
    done

    if [ "${#part_pids[@]}" -gt 0 ] && ! wait_all "${part_pids[@]}"; then
      senderr "Failed to upload split part to R2 ($DEST_PATH)."
      exit 1
    fi
  fi

  # 4) metadata + latest.json LAST — the public pointer flips to this snapshot
  #    only now, after the zip/state/parts above are all in place.
  if [ -n "$LATEST_METADATA" ]; then
    ARCHIVED_METADATA_PATH="$ARCHIVE_PATH/metadata/${NOW}_$METADATA_FILENAME"
    if ! publish_artifact "$LATEST_METADATA" "$ARCHIVED_METADATA_PATH" \
        "$DEST_PATH/$METADATA_FILENAME" \
        "$DEST_PATH/latest.json"; then
      senderr "Failed to upload metadata/latest.json to R2 ($DEST_PATH)."
      exit 1
    fi
  fi

  SNAPSHOT_INDEX=""
  if [ -n "$LATEST_METADATA" ] && [ -f "$LATEST_METADATA" ]; then
    SNAPSHOT_INDEX=$(grep -oE '"Index":[0-9]+' "$LATEST_METADATA" 2>/dev/null | head -1 | grep -oE '[0-9]+' || true)
  fi
  sendinfo "Partition snapshot uploaded OK: $SNAPSHOT_PATH block ${SNAPSHOT_INDEX:-?} ($SNAPSHOT_FILENAME); latest.json updated."

  if [ "$PRESERVE_PARTITIONS" = "false" ]; then
    rm "$LATEST_SNAPSHOT" "$LATEST_STATE" "$LATEST_METADATA"
    # Sentinel tracks whether output files are present; clear it alongside files
    # so a subsequent create_snapshot run does not incorrectly skip as "recent".
    rm -f "$OUTPUT_DIR/.snapshot-created"
  fi
  rm -rf "$METADATA_DIR"
}

trap '' HUP

echo "[INFO] Setting up rclone..."
setup_rclone

echo "[INFO] Starting snapshot process..."
make_and_upload_snapshot $5
