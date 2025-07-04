#!/usr/bin/env bash
set -ex

apt-get -y update
apt-get -y install curl unzip sudo

uname=$(uname -r)
arch=${uname##*.}
if [ "$arch" = "aarch64" ]; then
  curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64-2.22.35.zip" -o "awscliv2.zip"
else
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-2.22.35.zip" -o "awscliv2.zip"
fi
unzip awscliv2.zip
sudo ./aws/install

AWS="/usr/local/bin/aws"
AWS_ACCESS_KEY_ID="$(cat "/secret/aws_access_key_id")"
AWS_SECRET_ACCESS_KEY="$(cat "/secret/aws_secret_access_key")"
"$AWS" configure set aws_access_key_id $AWS_ACCESS_KEY_ID
"$AWS" configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
"$AWS" configure set default.region us-east-2
"$AWS" configure set default.output json
APP_PROTOCOL_VERSION=$2
VERSION_NUMBER="${APP_PROTOCOL_VERSION:0:6}"
SLACK_TOKEN=$3
CF_DISTRIBUTION_ID=$4

export AWS_ENDPOINT_URL_S3="https://1cd1f38b21c0bfdde9501f7d8e43b663.r2.cloudflarestorage.com"
export AWS_DEFAULT_REGION=auto

function senderr() {
  echo "$1"
  curl --data "[K8S] $1. Check snapshot-partition-reset-v$VERSION_NUMBER in {{ $.Values.clusterName }} cluster at upload_snapshot.sh." "https://planetariumhq.slack.com/services/hooks/slackbot?token=$SLACK_TOKEN&channel=%23{{ $.Values.snapshot.slackChannel }}"
}

function replace_snapshot() {
  ARCHIVE="archive_"$(date '+%Y%m%d')
  SNAPSHOT_PREFIX=$(echo $1 | awk '{gsub(/\//,"\\/");print}')
  ARCHIVE_PATH=$1$ARCHIVE/
  ARCHIVE_PREFIX=$(echo $ARCHIVE_PATH | awk '{gsub(/\//,"\\/");print}')
  TEMP_PREFIX=$(echo $2 | awk '{gsub(/\//,"\\/");print}')

  for f in $(aws s3 ls $1 | awk 'NF>1{print $4}' | grep "zip\|json\|7z"); do
    aws s3 mv $(echo $f | sed "s/.*/$SNAPSHOT_PREFIX&/") $(echo $f | sed "s/.*/$ARCHIVE_PREFIX&/")
  done

  for f in $(aws s3 ls $2 | awk 'NF>1{print $4}' | grep "zip\|json\|7z"); do
    aws s3 mv $(echo $f | sed "s/.*/$TEMP_PREFIX&/") $(echo $f | sed "s/.*/$SNAPSHOT_PREFIX/")
  done

  if [[ $AWS_ENDPOINT_URL_S3 == *.r2.cloudflarestorage.com ]]; then
    return
  fi

  BUCKET="s3://9c-snapshots"
  BUCKET_PREFIX=$(echo $BUCKET | awk '{gsub(/\//,"\\/");print}')
  CF_PATH=$(echo $1 | sed -e "s/^$BUCKET_PREFIX//" | sed "s/.*/&*/")

  "$AWS" cloudfront create-invalidation --distribution-id "$CF_DISTRIBUTION_ID" --paths "$CF_PATH"
  "$AWS" cloudfront create-invalidation --distribution-id "$CF_DISTRIBUTION_ID" --paths "/main/temp/partition/*"
}

trap '' HUP

replace_snapshot $1 $2
