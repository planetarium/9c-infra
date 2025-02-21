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
  URL="https://snapshots.nine-chronicles.com/$2/latest.json"

  mkdir -p "$OUTPUT_DIR" "$PARTITION_DIR" "$STATE_DIR" "$METADATA_DIR"
  if curl --output /dev/null --silent --head --fail "$URL"; then
    curl "$URL" -o "$METADATA_DIR/latest.json"
  else
    echo "URL does not exist: $URL"
  fi

  rm -r "$FULL_DIR/*" || true

  if ! "$SNAPSHOT" --output-directory "$OUTPUT_DIR" --store-path "$STORE_PATH" --block-before 0 --apv "$1" --snapshot-type "full"; then
    senderr "Snapshot creation failed." "$SLACK_WEBHOOK"
    exit 1
  fi

  # shellcheck disable=SC2012
  LATEST_FULL_SNAPSHOT=$(ls -t $FULL_DIR/*.zip | head -1)
  UPLOAD_FULL_SNAPSHOT_FILENAME="9c-main-snapshot"
  FULL_SNAPSHOT_FILENAME="$UPLOAD_FULL_SNAPSHOT_FILENAME.zip"
  FULL_SNAPSHOT_FILENAME_7Z="$UPLOAD_FULL_SNAPSHOT_FILENAME.7z"

  LATEST_METADATA=$(ls -t $METADATA_DIR/*.json | head -1)
  LATEST_METADATA_FILENAME=$(basename "$LATEST_METADATA")
  UPLOAD_METADATA_FILENAME="$UPLOAD_FULL_SNAPSHOT_FILENAME.json"

  S3_BUCKET_NAME="9c-snapshots-v2"

  AWS="/usr/local/bin/aws"
  AWS_ACCESS_KEY_ID="$(cat "/secret/aws_access_key_id")"
  AWS_SECRET_ACCESS_KEY="$(cat "/secret/aws_secret_access_key")"
  "$AWS" configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
  "$AWS" configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
  "$AWS" configure set default.region us-east-2
  "$AWS" configure set default.output json
  NOW=$(date '+%Y%m%d%H%M%S')

  "$AWS" s3 cp "$LATEST_FULL_SNAPSHOT" "s3://$S3_BUCKET_NAME/$2/full/$FULL_SNAPSHOT_FILENAME" --quiet --acl public-read
  "$AWS" s3 cp "$LATEST_METADATA" "s3://$S3_BUCKET_NAME/$2/full/$UPLOAD_METADATA_FILENAME" --quiet --acl public-read
  "$AWS" s3 cp "s3://$S3_BUCKET_NAME/$2/full/$FULL_SNAPSHOT_FILENAME" "s3://$S3_BUCKET_NAME/$2/archive/full/${NOW}_$FULL_SNAPSHOT_FILENAME" --quiet --acl public-read --copy-props none --metadata-directive COPY
  invalidate_cf "/$2/full/$FULL_SNAPSHOT_FILENAME"

  # Disable 7z snapshot
  # 7zr a -r /data/snapshots/full/7z/9c-main-snapshot-"$NOW".7z /data/headless/*
  # "$AWS" s3 cp /data/snapshots/full/7z/9c-main-snapshot-"$NOW".7z "s3://$S3_BUCKET_NAME/$2/full/$FULL_SNAPSHOT_FILENAME_7Z" --quiet --acl public-read
  # invalidate_cf "/$2/full/$FULL_SNAPSHOT_FILENAME_7Z"
  # rm /data/snapshots/full/7z/9c-main-snapshot-"$NOW".7z
  rm "$LATEST_FULL_SNAPSHOT"
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

trap '' HUP

make_and_upload_snapshot "$APP_PROTOCOL_VERSION" "$SNAPSHOT_PATH"
