#!/usr/bin/env bash
set -ex

BASEDIR=$(dirname "$0")
echo "$BASEDIR"

# AWS configuration must be already set on your environment
reset_snapshot() {
  if [[ Previous_Mainnet_BlockEpoch=$(curl --silent "snapshots.nine-chronicles.com/internal/mainnet_latest.json" | jq ".BlockEpoch") -gt 0 ]]; then
    base_url="snapshots.nine-chronicles.com/main/partition/internal"

    get_snapshot_value() {
        snapshot_json_url="$1"
        snapshot_param="$2"

        snapshot_param_return_value=$(curl --silent "$snapshot_json_url" | jq ".$snapshot_param")
        echo "$snapshot_param_return_value"
    }

    copy_snapshot() {
        snapshot_json_filename="latest.json"
        snapshot_zip_filename="state_latest.zip"
        snapshot_zip_filename_array=("$snapshot_zip_filename")
        snapshot_zip_filename_array+=("latest.zip")
        snapshot_zip_filename_array+=("latest.json")
        aws s3 cp "$2/state_latest.zip" "$1/state_latest.zip"
        aws s3 cp "$2/latest.zip" "$1/latest.zip"
        aws s3 cp "$2/latest.json" "$1/latest.json"
        aws s3 cp "$2/latest.json" "$1/mainnet_latest.json"

        while :
        do
            snapshot_json_url="$base_url/$snapshot_json_filename"

            BlockEpoch=$(get_snapshot_value "$snapshot_json_url" "BlockEpoch")
            TxEpoch=$(get_snapshot_value "$snapshot_json_url" "TxEpoch")
            PreviousBlockEpoch=$(get_snapshot_value "$snapshot_json_url" "PreviousBlockEpoch")
            PreviousTxEpoch=$(get_snapshot_value "$snapshot_json_url" "PreviousTxEpoch")

            snapshot_zip_filename="snapshot-$BlockEpoch-$TxEpoch.zip"
            snapshot_json_filename="snapshot-$BlockEpoch-$TxEpoch.json"
            aws s3 cp "$2/$snapshot_zip_filename" "$1/$snapshot_zip_filename"
            aws s3 cp "$2/$snapshot_json_filename" "$1/$snapshot_json_filename"
            snapshot_zip_filename_array+=("$snapshot_zip_filename")
            snapshot_zip_filename_array+=("$snapshot_json_filename")

            if [ "$PreviousBlockEpoch" -lt $Previous_Mainnet_BlockEpoch ]
            then
                break
            fi

            snapshot_json_filename="snapshot-$PreviousBlockEpoch-$PreviousTxEpoch.json"
        done

        for ((i=${#snapshot_zip_filename_array[@]}-1; i>=0; i--))
        do
            snapshot_zip_filename="${snapshot_zip_filename_array[$i]}"
        done
    }

    curl -X POST -H 'Content-type: application/json' --data '{"text":"[K8S] Copying 9c-main snapshots to 9c-internal."}' $3
    copy_snapshot $1 $2
  else
    curl -X POST -H 'Content-type: application/json' --data '{"text":"[K8S] Copying 9c-main snapshots to 9c-internal."}' $3
    ARCHIVE="archive_"$(date '+%Y%m%d%H')
    INTERNAL_PREFIX=$(echo $1/ | awk '{gsub(/\//,"\\/");print}')
    ARCHIVE_PATH=$1/$ARCHIVE/
    ARCHIVE_PREFIX=$(echo $ARCHIVE_PATH | awk '{gsub(/\//,"\\/");print}')
    MAIN_PREFIX=$(echo $2/ | awk '{gsub(/\//,"\\/");print}')

    # archive internal cluster chain
    for f in $(aws s3 ls $1/ | awk 'NF>1{print $4}' | grep "zip\|json"); do
      echo $f
      aws s3 mv $(echo $f | sed "s/.*/$INTERNAL_PREFIX&/") $(echo $f | sed "s/.*/$ARCHIVE_PREFIX&/")
    done

    # copy main cluster chain to internal (copy state_latest.zip first)
    aws s3 cp "$2/state_latest.zip" "$1/state_latest.zip"
    for f in $(aws s3 ls $2/ | sort -k1,2 | sort -r | awk 'NF>1{print $4}' | grep "zip\|json" | grep -v "state_latest.zip"); do
      echo $f
      aws s3 cp $(echo $f | sed "s/.*/$MAIN_PREFIX&/") $(echo $f | sed "s/.*/$INTERNAL_PREFIX&/")
    done

    aws s3 cp "$1/latest.json" "$1/mainnet_latest.json"

  fi

  BUCKET="s3://9c-snapshots"
  BUCKET_PREFIX=$(echo $BUCKET | awk '{gsub(/\//,"\\/");print}')
  CF_PATH=$(echo $1/ | sed -e "s/^$BUCKET_PREFIX//" | sed "s/.*/&*/")

  # reset cf path
  CF_DISTRIBUTION_ID="EAU4XRUZSBUD5"
  aws cloudfront create-invalidation --distribution-id "$CF_DISTRIBUTION_ID" --paths "$CF_PATH"
}

# Type "y" to reset the cluster with a new snapshot and "n" to just deploy the cluster.
echo "Do you want to reset the cluster with a new snapshot(y/n)?"
read response

echo $SLACK_WEBHOOK_URL

if [ $response = y ]
then
    echo "Reset cluster with a new snapshot"
    curl -X POST -H 'Content-type: application/json' --data '{"text":"[K8S] Reset cluster with a new snapshot"}' $SLACK_WEBHOOK_URL
    reset_snapshot "s3://9c-snapshots/internal-v2-pbft" "s3://9c-snapshots/main/partition/internal" $SLACK_WEBHOOK_URL || true
else
    echo "Reset cluster without resetting snapshot."
    curl -X POST -H 'Content-type: application/json' --data '{"text":"[K8S] Reset cluster without resetting snapshot."}' $SLACK_WEBHOOK_URL
fi

