#!/usr/bin/env bash
set -ex

BASEDIR=$(dirname "$0")
echo "$BASEDIR"

BUCKET="s3://9c-snapshots-v2"

# AWS configuration must be already set on your environment
reset_snapshot() {
  CHAIN=$3
  PREFIX="$BUCKET/"
  PREVIOUS_MAINNET_EPOCH_PATH="${1#$PREFIX}"
  BASE_URL_PATH="${2#$PREFIX}"
  NEW_SNAPSHOT_TIP=0
  if [[ Previous_Mainnet_BlockEpoch=$(curl --silent "snapshots.nine-chronicles.com/$PREVIOUS_MAINNET_EPOCH_PATH/mainnet_latest.json" | jq ".BlockEpoch") -gt 0 ]]; then
    base_url="snapshots.nine-chronicles.com/$BASE_URL_PATH"

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
        NEW_SNAPSHOT_TIP=$(curl --silent "snapshots.nine-chronicles.com/$BASE_URL_PATH/latest.json" | jq ".Index")

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

    copy_snapshot $1 $2
  else
    ARCHIVE="archive_"$(date '+%Y%m%d%H')
    INTERNAL_PREFIX=$(echo $1/ | awk '{gsub(/\//,"\\/");print}')
    ARCHIVE_PATH=$1/$ARCHIVE/
    ARCHIVE_PREFIX=$(echo $ARCHIVE_PATH | awk '{gsub(/\//,"\\/");print}')
    MAIN_PREFIX=$(echo $2/ | awk '{gsub(/\//,"\\/");print}')
    NEW_SNAPSHOT_TIP=$(curl --silent "snapshots.nine-chronicles.com/$BASE_URL_PATH/latest.json" | jq ".Index")

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

  BUCKET_PREFIX=$(echo $BUCKET | awk '{gsub(/\//,"\\/");print}')
  CF_PATH=$(echo $1/ | sed -e "s/^$BUCKET_PREFIX//" | sed "s/.*/&*/")

  # reset cf path
  CF_DISTRIBUTION_ID="EAU4XRUZSBUD5"
  aws cloudfront create-invalidation --distribution-id "$CF_DISTRIBUTION_ID" --paths "$CF_PATH"
  if [[ $CHAIN != *-preview ]]; then
    curl --data "[9C-INFRA] Internal $CHAIN snapshot file reset complete. New tip: \`#$NEW_SNAPSHOT_TIP\`." "https://planetariumhq.slack.com/services/hooks/slackbot?token=$SLACK_TOKEN&channel=%239c-internal"
  else
    curl --data "[9C-INFRA] Preview $CHAIN snapshot file reset complete. New tip: \`#$NEW_SNAPSHOT_TIP\`." "https://planetariumhq.slack.com/services/hooks/slackbot?token=$SLACK_TOKEN&channel=%239c-previewnet"
  fi
}

# Type "y" to reset the cluster with a new snapshot and "n" to just deploy the cluster.
echo "Do you want to reset the cluster with a new snapshot(y/n)?"
read response
CHAIN=$1

if [ "$response" = "y" ]; then
    echo "Reset cluster with a new snapshot"

    INTERNAL_OR_PREVIEW=$([[ $CHAIN != *-preview ]] && echo "internal" || echo "preview")
    CHAIN_NAME=${CHAIN%-preview}
    CHAIN_PATH=$([[ $CHAIN_NAME = odin ]] && echo "" || echo "/$CHAIN_NAME")

    reset_snapshot "$BUCKET/$INTERNAL_OR_PREVIEW$CHAIN_PATH" "$BUCKET/main$CHAIN_PATH/partition/internal" "$CHAIN_NAME" || true

else
    echo "Reset cluster without resetting snapshot."
fi

