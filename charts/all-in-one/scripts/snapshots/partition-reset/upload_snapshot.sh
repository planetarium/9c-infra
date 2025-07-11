#!/usr/bin/env bash
set -ex

apt-get -y update
apt-get -y install curl sudo unzip

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
APP_PROTOCOL_VERSION=$2
VERSION_NUMBER="${APP_PROTOCOL_VERSION:0:6}"
SLACK_WEBHOOK=$3
CF_DISTRIBUTION_ID=$4
SNAPSHOT_PATH="$5/$1"

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
  URL="https://snapshots.nine-chronicles.com/$2/latest.json"

  mkdir -p "$OUTPUT_DIR" "$PARTITION_DIR" "$STATE_DIR" "$METADATA_DIR"
  if curl --output /dev/null --silent --head --fail "$URL"; then
    curl "$URL" -o "$METADATA_DIR/latest.json"
  else
    echo "URL does not exist: $URL"
  fi

  if ! "$SNAPSHOT" --output-directory "$OUTPUT_DIR" --store-path "$STORE_PATH"  --block-before 0 --apv "$1" --snapshot-type "partition"; then
    senderr "Snapshot creation failed." $1
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

  S3_BUCKET_NAME="9c-snapshots"
  S3_LATEST_SNAPSHOT_PATH="$2/$UPLOAD_SNAPSHOT_FILENAME"
  S3_LATEST_METADATA_PATH="$2/$UPLOAD_METADATA_FILENAME"

  AWS="/usr/local/bin/aws"
  AWS_ACCESS_KEY_ID="$(cat "/secret/aws_access_key_id")"
  AWS_SECRET_ACCESS_KEY="$(cat "/secret/aws_secret_access_key")"
  "$AWS" configure set aws_access_key_id $AWS_ACCESS_KEY_ID
  "$AWS" configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
  "$AWS" configure set default.region us-east-2
  "$AWS" configure set default.output json

  "$AWS" s3 cp "$LATEST_SNAPSHOT" "s3://$S3_BUCKET_NAME/$2/$LATEST_SNAPSHOT_FILENAME" --quiet --acl public-read
  "$AWS" s3 cp "$LATEST_METADATA" "s3://$S3_BUCKET_NAME/$2/$LATEST_METADATA_FILENAME" --quiet --acl public-read
  "$AWS" s3 cp "$LATEST_STATE" "s3://$S3_BUCKET_NAME/$2/$LATEST_STATE_FILENAME" --quiet --acl public-read
  "$AWS" s3 cp "s3://$S3_BUCKET_NAME/$2/$LATEST_SNAPSHOT_FILENAME" "s3://$S3_BUCKET_NAME/$S3_LATEST_SNAPSHOT_PATH" --quiet --acl public-read --copy-props none --metadata-directive COPY
  "$AWS" s3 cp "s3://$S3_BUCKET_NAME/$2/$LATEST_METADATA_FILENAME" "s3://$S3_BUCKET_NAME/$S3_LATEST_METADATA_PATH" --quiet --acl public-read --copy-props none --metadata-directive COPY

  rm "$LATEST_SNAPSHOT"
  rm "$LATEST_STATE"
  rm -r "$PARTITION_DIR/partition-snapshot"
  rm -r "$STATE_DIR/state-snapshot"
  rm -r "$METADATA_DIR"
}

trap '' HUP

make_and_upload_snapshot "$APP_PROTOCOL_VERSION" "$SNAPSHOT_PATH"
