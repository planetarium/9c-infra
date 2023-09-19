#!/usr/bin/env bash
set -ex

apt-get -y update
apt-get -y install curl
apt-get -y install zip
apt-get -y install unzip
apt-get -y install sudo

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o
"awscliv2.zip"

unzip awscliv2.zip
sudo ./aws/install

HOME="/app"
STORE_PATH="/data/headless"
APP_PROTOCOL_VERSION=$1
VERSION_NUMBER="${APP_PROTOCOL_VERSION:0:6}"
SLACK_TOKEN=$2
CF_DISTRIBUTION_ID=$3

function senderr() {
  echo "$1"
  curl --data "[K8S] $1. Check snapshot-partition--$2 in {{ $.Values.clusterName }} cluster at upload_snapshot.sh." "https://planetariumhq.slack.com/services/hooks/slackbot?token=$SLACK_TOKEN&channel=%239c-mainnet"
}

function make_and_upload_snapshot() {
  SNAPSHOT="$HOME/NineChronicles.Snapshot"
  OUTPUT_DIR="/data/snapshots"
  PARTITION_DIR="/data/snapshots/partition"
  STATE_DIR="/data/snapshots/state"
  METADATA_DIR="/data/snapshots/metadata"
  FULL_DIR="/data/snapshots/full"
  URL="https://snapshots.nine-chronicles.com/main/partition/latest.json"

  mkdir -p "$OUTPUT_DIR" "$PARTITION_DIR" "$STATE_DIR" "$METADATA_DIR"
  if curl --output /dev/null --silent --head --fail "$URL"; then
    curl "$URL" -o "$METADATA_DIR/latest.json"
  else
    echo "URL does not exist: $URL"
  fi

  if ! "$SNAPSHOT" --output-directory "$OUTPUT_DIR" --store-path "$STORE_PATH"  --block-before 10 --apv "$1" --snapshot-type "full"; then
    senderr "Snapshot creation failed."
    exit 1
  fi

  # shellcheck disable=SC2012
  LATEST_FULL_SNAPSHOT=$(ls -t $FULL_DIR/*.zip | head -1)
  UPLOAD_FULL_SNAPSHOT_FILENAME="9c-main-snapshot"
  FULL_SNAPSHOT_FILENAME="$UPLOAD_FULL_SNAPSHOT_FILENAME.zip"

  S3_BUCKET_NAME="9c-snapshots-v2"

  AWS="/usr/local/bin/aws"
  AWS_ACCESS_KEY_ID="$(cat "/secret/aws_access_key_id" | base64)"
  AWS_SECRET_ACCESS_KEY="$(cat "/secret/aws_secret_access_key" | base64)"
  "$AWS" configure set aws_access_key_id $AWS_ACCESS_KEY_ID
  "$AWS" configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
  "$AWS" configure set default.region us-east-2
  "$AWS" configure set default.output json
  NOW=$(date '+%Y%m%d%H%M%S')

  "$AWS" s3 cp "$LATEST_FULL_SNAPSHOT" "s3://$S3_BUCKET_NAME/main/partition/full/$FULL_SNAPSHOT_FILENAME" --quiet --acl public-read
  "$AWS" s3 cp "s3://$S3_BUCKET_NAME/main/partition/full/$FULL_SNAPSHOT_FILENAME" "s3://$S3_BUCKET_NAME/main/partition/archive/full/${NOW}_$FULL_SNAPSHOT_FILENAME" --quiet --acl public-read
  invalidate_cf "/main/partition/full/$FULL_SNAPSHOT_FILENAME"
  
  rm "$LATEST_FULL_SNAPSHOT"
}

function invalidate_cf() {
  if "$AWS" cloudfront create-invalidation --distribution-id "$CF_DISTRIBUTION_ID" --paths "$1"; then
    echo "CF invalidation successful"
  else
    echo "CF invalidation failed. Trying again."
    invalidate_cf "$1"
  fi
}

trap '' HUP
make_and_upload_snapshot $1
