#!/usr/bin/env bash
set -ex

apt-get -y update
apt-get -y install curl
apt-get -y install zip
apt-get -y install unzip
apt-get -y install sudo
apt-get -y install p7zip

uname=$(uname -r)
arch=${uname##*.}
if [ "$arch" = "aarch64" ]; then
  curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64-2.22.35.zip" -o "awscliv2.zip"
else
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-2.22.35.zip" -o "awscliv2.zip"
fi
unzip awscliv2.zip
sudo ./aws/install

HOME="/app"
STORE_PATH="/data/headless"
APP_PROTOCOL_VERSION=$1
VERSION_NUMBER="${APP_PROTOCOL_VERSION:0:6}"
SLACK_WEBHOOK=$2
CF_DISTRIBUTION_ID=$3
SNAPSHOT_PATH=$4

export AWS_ENDPOINT_URL_S3="https://1cd1f38b21c0bfdde9501f7d8e43b663.r2.cloudflarestorage.com"
export AWS_DEFAULT_REGION=auto

function senderr() {
  echo "$1"
  curl -X POST -H 'Content-type: application/json' --data '{"text":"[K8S] '$1'. Check snapshot in {{ $.Values.clusterName }} cluster at upload_snapshot.sh."}' $SLACK_WEBHOOK
}

function make_and_upload_snapshot() {
  SNAPSHOT="$HOME/NineChronicles.Snapshot"
  OUTPUT_DIR="/data/snapshots"
  PARTITION_DIR="/data/snapshots/partition"
  STATE_DIR="/data/snapshots/state"
  METADATA_DIR="/data/snapshots/metadata"
  FULL_DIR="/data/snapshots/full"
  URL="https://snapshots.nine-chronicles.com/{{ $.Values.snapshot.path }}/latest.json"

  mkdir -p "$OUTPUT_DIR" "$PARTITION_DIR" "$STATE_DIR" "$METADATA_DIR"
  if curl --output /dev/null --silent --head --fail "$URL"; then
    curl "$URL" -o "$METADATA_DIR/latest.json"
  else
    echo "URL does not exist: $URL"
  fi

  if ! "$SNAPSHOT" --output-directory "$OUTPUT_DIR" --store-path "$STORE_PATH"  --block-before 0 --apv "$1" --snapshot-type "partition"; then
    senderr "Snapshot creation failed." "$SLACK_WEBHOOK"
    exit 1
  fi

  # shellcheck disable=SC2012
  LATEST_SNAPSHOT=$(ls -t $PARTITION_DIR/*.zip | head -1)
  # shellcheck disable=SC2012
  LATEST_METADATA=$(ls -t $METADATA_DIR/*.json | head -1)
  LATEST_SNAPSHOT_FILENAME=$(basename "$LATEST_SNAPSHOT")
  LATEST_METADATA_FILENAME=$(basename "$LATEST_METADATA")
  UPLOAD_FILENAME="latest"
  UPLOAD_SNAPSHOT_FILENAME="$UPLOAD_FILENAME.zip"
  UPLOAD_METADATA_FILENAME="$UPLOAD_FILENAME.json"
  SNAPSHOT_FILENAME=$(echo $LATEST_SNAPSHOT_FILENAME | cut -d'.' -f 1)
  # shellcheck disable=SC2012
  LATEST_STATE=$(ls -t $STATE_DIR/*.zip | head -1)
  LATEST_STATE_FILENAME=$(basename "$LATEST_STATE")
  STATE_FILENAME=$(echo $LATEST_STATE_FILENAME | cut -d'.' -f 1)

  S3_BUCKET_NAME="9c-snapshots"
  S3_LATEST_SNAPSHOT_PATH="{{ $.Values.snapshot.path }}/$UPLOAD_SNAPSHOT_FILENAME"
  S3_LATEST_METADATA_PATH="{{ $.Values.snapshot.path }}/$UPLOAD_METADATA_FILENAME"
  {{- if eq $.Values.global.networkType "Main" }}
  S3_LATEST_INTERNAL_SNAPSHOT_PATH="{{ $.Values.snapshot.path }}/internal/$UPLOAD_SNAPSHOT_FILENAME"
  S3_LATEST_INTERNAL_METADATA_PATH="{{ $.Values.snapshot.path }}/internal/$UPLOAD_METADATA_FILENAME"
  {{- end }}

  AWS="/usr/local/bin/aws"
  AWS_ACCESS_KEY_ID="$(cat "/secret/aws_access_key_id")"
  AWS_SECRET_ACCESS_KEY="$(cat "/secret/aws_secret_access_key")"
  "$AWS" configure set aws_access_key_id $AWS_ACCESS_KEY_ID
  "$AWS" configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
  "$AWS" configure set default.region us-east-2
  "$AWS" configure set default.output json
  NOW=$(date '+%Y%m%d%H%M%S')

  safe_cp "$LATEST_SNAPSHOT" "s3://$S3_BUCKET_NAME/{{ $.Values.snapshot.path }}/$LATEST_SNAPSHOT_FILENAME" --acl public-read
  safe_cp "$LATEST_METADATA" "s3://$S3_BUCKET_NAME/{{ $.Values.snapshot.path }}/$LATEST_METADATA_FILENAME" --acl public-read
  safe_cp "$LATEST_STATE" "s3://$S3_BUCKET_NAME/{{ $.Values.snapshot.path }}/$LATEST_STATE_FILENAME" --acl public-read

  {{- if eq $.Values.global.networkType "Main" }}
  safe_cp "s3://$S3_BUCKET_NAME/{{ $.Values.snapshot.path }}/$LATEST_SNAPSHOT_FILENAME" "s3://$S3_BUCKET_NAME/{{ $.Values.snapshot.path }}/archive/snapshots/${NOW}_$LATEST_SNAPSHOT_FILENAME" --acl public-read --copy-props none --metadata-directive COPY
  safe_cp "s3://$S3_BUCKET_NAME/{{ $.Values.snapshot.path }}/$LATEST_METADATA_FILENAME" "s3://$S3_BUCKET_NAME/{{ $.Values.snapshot.path }}/archive/metadata/${NOW}_$LATEST_METADATA_FILENAME" --acl public-read --copy-props none --metadata-directive COPY
  safe_cp "s3://$S3_BUCKET_NAME/{{ $.Values.snapshot.path }}/$LATEST_STATE_FILENAME" "s3://$S3_BUCKET_NAME/{{ $.Values.snapshot.path }}/archive/states/${NOW}_$LATEST_STATE_FILENAME" --acl public-read --copy-props none --metadata-directive COPY

  safe_cp "s3://$S3_BUCKET_NAME/{{ $.Values.snapshot.path }}/$LATEST_SNAPSHOT_FILENAME" "s3://$S3_BUCKET_NAME/$S3_LATEST_SNAPSHOT_PATH" --acl public-read --copy-props none --metadata-directive COPY
  safe_cp "s3://$S3_BUCKET_NAME/{{ $.Values.snapshot.path }}/$LATEST_METADATA_FILENAME" "s3://$S3_BUCKET_NAME/$S3_LATEST_METADATA_PATH" --acl public-read --copy-props none --metadata-directive COPY
  {{- end }}

  invalidate_cf "/{{ $.Values.snapshot.path }}/$SNAPSHOT_FILENAME.*"
  invalidate_cf "/{{ $.Values.snapshot.path }}/$UPLOAD_FILENAME.*"
  invalidate_cf "/{{ $.Values.snapshot.path }}/$STATE_FILENAME.*"

  {{- if eq $.Values.global.networkType "Main" }}
  safe_cp "s3://$S3_BUCKET_NAME/{{ $.Values.snapshot.path }}/$LATEST_SNAPSHOT_FILENAME" "s3://$S3_BUCKET_NAME/{{ $.Values.snapshot.path }}/internal/$LATEST_SNAPSHOT_FILENAME" --acl public-read --copy-props none --metadata-directive COPY
  safe_cp "s3://$S3_BUCKET_NAME/{{ $.Values.snapshot.path }}/$LATEST_METADATA_FILENAME" "s3://$S3_BUCKET_NAME/{{ $.Values.snapshot.path }}/internal/$LATEST_METADATA_FILENAME" --acl public-read --copy-props none --metadata-directive COPY
  safe_cp "s3://$S3_BUCKET_NAME/{{ $.Values.snapshot.path }}/$LATEST_STATE_FILENAME" "s3://$S3_BUCKET_NAME/{{ $.Values.snapshot.path }}/internal/$LATEST_STATE_FILENAME" --acl public-read --copy-props none --metadata-directive COPY
  safe_cp "s3://$S3_BUCKET_NAME/{{ $.Values.snapshot.path }}/internal/$LATEST_SNAPSHOT_FILENAME" "s3://$S3_BUCKET_NAME/$S3_LATEST_INTERNAL_SNAPSHOT_PATH" --acl public-read --copy-props none --metadata-directive COPY
  safe_cp "s3://$S3_BUCKET_NAME/{{ $.Values.snapshot.path }}/internal/$LATEST_METADATA_FILENAME" "s3://$S3_BUCKET_NAME/$S3_LATEST_INTERNAL_METADATA_PATH" --acl public-read --copy-props none --metadata-directive COPY

  invalidate_cf "/{{ $.Values.snapshot.path }}/internal/$SNAPSHOT_FILENAME.*"
  invalidate_cf "/{{ $.Values.snapshot.path }}/internal/$UPLOAD_FILENAME.*"
  invalidate_cf "/{{ $.Values.snapshot.path }}/internal/$STATE_FILENAME.*"

  mkdir -p "$PARTITION_DIR/partition-snapshot" "$STATE_DIR/state-snapshot"
  unzip -o "$LATEST_SNAPSHOT" -d "$PARTITION_DIR/partition-snapshot"
  unzip -o "$LATEST_STATE" -d "$STATE_DIR/state-snapshot"

  invalidate_cf "/{{ $.Values.snapshot.path }}/$SNAPSHOT_FILENAME.*"
  invalidate_cf "/{{ $.Values.snapshot.path }}/$UPLOAD_FILENAME.*"
  invalidate_cf "/{{ $.Values.snapshot.path }}/$STATE_FILENAME.*"

  rm -r "$PARTITION_DIR/partition-snapshot"
  rm -r "$STATE_DIR/state-snapshot"
  {{- end }}

  rm "$LATEST_SNAPSHOT"
  rm "$LATEST_STATE"
  rm -r "$METADATA_DIR"
}

function invalidate_cf() {
  if [[ $AWS_ENDPOINT_URL_S3 == *.r2.cloudflarestorage.com ]]; then
    return
  fi

  if "$AWS" cloudfront create-invalidation --distribution-id "$CF_DISTRIBUTION_ID" --paths "$1"; then
    echo "CF invalidation successful"
  else
    echo "CF invalidation failed. Trying again."
    invalidate_cf "$1"
  fi
}

function safe_cp() {
  local src=$1
  local dst=$2
  shift 2  # Shift off src and dst to get the rest of the arguments (like --acl etc.)
  local extra_args=("$@")
  local retries=3
  local count=0
  local delay=5

  echo "Uploading: $src → $dst"
  until "$AWS" s3 cp "$src" "$dst" "${extra_args[@]}"; do
    exit_code=$?
    count=$((count + 1))
    if [ $count -lt $retries ]; then
      echo "Retry $count/$retries failed with exit code $exit_code. Retrying in $delay seconds..."
      sleep $delay
    else
      echo "Failed after $retries attempts. Source: $src → $dst"
      senderr "S3 upload failed: $src → $dst"
      return $exit_code
    fi
  done
}

trap '' HUP

make_and_upload_snapshot "$APP_PROTOCOL_VERSION" "$SNAPSHOT_PATH"
