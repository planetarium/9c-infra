#!/usr/bin/env bash

set -o pipefail

apt-get update
apt-get -y install curl jq aria2 libarchive-tools

cd /data

base_url=${1:-https://snapshots.nine-chronicles.com/{{ $.Values.snapshot.path }}}
save_dir=${2:-"9c-main-snapshot_$(date +%Y%m%d_%H)"}
download_option=$3
service_name=$4
SLACK_WEBHOOK=$5
rollback_snapshot=${6:-"false"}
complete_snapshot_reset=${7:-"false"}
part_length="${8:-3}"
mainnet_snapshot_json_filename={{- if eq $.Values.global.networkType "Main" }}"latest.json"{{- else }}"mainnet_latest.json"{{- end }}

function download_with_retry() {
  local url=$1
  local save_dir=$2
  local output_file=$3

  aria2c "$url" -d "$2" -o "$3" -s1 --force-sequential=true --continue=true \
    --show-console-readout=false --summary-interval=30 --max-tries=10
}

function download_partition() {
  EXTENSIONS=("zip" "tar.zst")

  function test_ext_path() {
    local base_url=$1
    local filename=$2

    while true; do
      for ext in "${EXTENSIONS[@]}"; do
        ARCHIVE_PATH=$(printf "$base_url/$filename.$ext.part%0${part_length}d" 1)
        curl -I --fail "$ARCHIVE_PATH" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
          echo "$ARCHIVE_PATH"
          return 0
        fi

        ARCHIVE_PATH=$base_url/$filename.$ext
        curl -I --fail "$ARCHIVE_PATH" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
          echo "$ARCHIVE_PATH"
          return 0
        fi
      done

      base_url=${base_url%/*}
      if [[ ! "$base_url" =~ '/' ]]; then
        return 1
      fi
    done
  }

  function test_ext() {
    local url=$1
    for ext in "${EXTENSIONS[@]}"; do
      if [[ "$url" = *".$ext" ]]; then
        echo "$ext"
        return 0
      fi
    done
    return 1
  }

  local base_url=$1
  local filename=$2
  local save_dir=$3

  local archive_path=$(test_ext_path "$base_url" "$filename")
  if [ -z "$archive_path" ]; then
    return 1
  fi

  if [[ "$archive_path" = *.part* ]]; then
    archive_path=${archive_path%".part"*}
    local extension=$(test_ext "$archive_path")
    local idx=1
    while true; do
      local part_extension=$(printf "part%0${part_length}d" $idx)
      local url=$archive_path.$part_extension
      curl -I --fail "$url" > /dev/null 2>&1
      if [ $? -eq 0 ]; then
        echo "$url"
        if [ ! -f "$save_dir/$filename.$extension.$part_extension" ] || [ -f "$save_dir/$filename.$extension.$part_extension.aria2" ]; then
          download_with_retry "$url" "$save_dir" "$filename.$extension.$part_extension" &
        fi
      else
        break
      fi
      idx=$((idx + 1))
    done
    wait

    cat "$save_dir/$filename.$extension.part"* > "$save_dir/$filename.$extension"
    rm "$save_dir/$filename.$extension.part"*
  else
    local extension=$(test_ext "$archive_path")
    download_with_retry "$archive_path" "$save_dir" "$filename.$extension"
  fi

  echo "$save_dir/$filename.$extension"
}

if [ $download_option = "true" ]; then
  echo "Start download snapshot from $service_name"

  # strip tailing slash
  base_url=${base_url%/}

  function get_snapshot_value() {
    snapshot_json_url="$1"
    snapshot_param="$2"

    snapshot_param_return_value=$(curl --silent "$snapshot_json_url" | jq ".$snapshot_param")
    echo "$snapshot_param_return_value"
  }

  function download_unzip_snapshot() {
    snapshot_dir=$(realpath "$save_dir/../snapshots")
    snapshot_partition_dir="$snapshot_dir/partition"
    snapshot_state_dir="$snapshot_dir/state"
    snapshot_json_filename="latest.json"
    snapshot_zip_filename="state_latest"
    snapshot_zip_filename_array=("$snapshot_zip_filename")

    if [ $rollback_snapshot = "false" ] && [ ! -z "$1" ] && [ ! -z "$2" ]; then
      mainnet_snapshot_json_url="$base_url/$mainnet_snapshot_json_filename"
      mainnet_snapshot_blockIndex=$(get_snapshot_value "$mainnet_snapshot_json_url" "Index")
      mainnet_snapshot_blockEpoch=$(get_snapshot_value "$mainnet_snapshot_json_url" "BlockEpoch")
      if [ "$mainnet_snapshot_blockEpoch" -le $1 ] && [ "$mainnet_snapshot_blockIndex" -le $2 ]; then
        echo "Skip snapshot download because the local chain tip is greater than the snapshot tip."
        return
      fi
    fi

    if [[ ! -d "$save_dir" ]]; then
      echo "[Info] The directory $save_dir does not exist and is created."
      mkdir -p "$save_dir/block" "$save_dir/tx"
    fi

    rm -rf $save_dir/block/blockindex
    rm -rf $save_dir/tx/txindex
    rm -rf $save_dir/txbindex
    rm -rf $save_dir/blockcommit
    rm -rf $save_dir/txexec
    rm -rf $save_dir/states

    while true; do
      local traverse_base_url=$base_url
      while true; do
        if curl --silent -f "$traverse_base_url/$snapshot_json_filename" > /dev/null; then
          break
        fi
        traverse_base_url=${traverse_base_url%/*}
      done

      snapshot_json_url="$traverse_base_url/$snapshot_json_filename"
      echo "$snapshot_json_url"

      curl --silent --location "$snapshot_json_url" -o "$save_dir/$snapshot_json_filename"
      BlockEpoch=$(cat "$save_dir/$snapshot_json_filename" | jq ".BlockEpoch")
      TxEpoch=$(cat "$save_dir/$snapshot_json_filename" | jq ".TxEpoch")
      PreviousBlockEpoch=$(cat "$save_dir/$snapshot_json_filename" | jq ".PreviousBlockEpoch")
      PreviousTxEpoch=$(cat "$save_dir/$snapshot_json_filename" | jq ".PreviousTxEpoch")
      rm "$save_dir/$snapshot_json_filename"

      snapshot_zip_filename="snapshot-$BlockEpoch-$TxEpoch"
      snapshot_zip_filename_array+=("$snapshot_zip_filename")

      rm -rf $save_dir/block/epoch$BlockEpoch
      rm -rf $save_dir/tx/epoch$BlockEpoch

      if [[ "$PreviousBlockEpoch" -le "$1" ]]; then break; fi

      snapshot_json_filename="snapshot-$PreviousBlockEpoch-$PreviousTxEpoch.json"
    done

    for ((i=${#snapshot_zip_filename_array[@]}-1; i>=0; i--)); do
      snapshot_zip_filename="${snapshot_zip_filename_array[$i]}"

      local has_archive="false"
      local has_archive_part="false"

      for archive_file in "$snapshot_partition_dir/$snapshot_zip_filename."*z*; do
        if [ -f "$archive_file" ]; then
          has_archive="true"
          break
        fi
      done
      for archive_part_file in "$snapshot_partition_dir/$snapshot_zip_filename."*z*.part*; do
        if [ -f "$archive_part_file" ]; then
          has_archive_part="true"
          break
        fi
      done

      if [[ "$rollback_snapshot" = "true" ]] || [[ "$has_archive" = "false" ]] || [[ "$has_archive_part" = "true" ]]; then
        echo "Downloading $base_url/$snapshot_zip_filename"
        download_partition "$base_url" "$snapshot_zip_filename" "$snapshot_partition_dir"
      fi

      echo "Extracting $snapshot_zip_filename"
      bsdtar -C "$save_dir" -xf "$snapshot_partition_dir/$snapshot_zip_filename."*z*
    done

    mkdir -p "$snapshot_state_dir"
    mv "$snapshot_partition_dir/state_latest."*z* "$snapshot_state_dir/"

    rm -f "$save_dir/$mainnet_snapshot_json_filename"
    download_with_retry "$base_url/$mainnet_snapshot_json_filename" "$save_dir" "$mainnet_snapshot_json_filename"

    rm -rf "$snapshot_dir"
  }

  if [ -f $save_dir/$mainnet_snapshot_json_filename ] && [ ! $complete_snapshot_reset = "true" ]; then
    local_previous_mainnet_blockEpoch=$(cat "$save_dir/$mainnet_snapshot_json_filename" | jq ".BlockEpoch")
    local_chain_tip_index="$((/app/NineChronicles.Headless.Executable chain tip "RocksDb" "$save_dir") | jq -r '.Index')"
    download_unzip_snapshot $local_previous_mainnet_blockEpoch $local_chain_tip_index
  else
    if [ $complete_snapshot_reset = "true" ]; then
      echo "Completely delete the existing store and download a new snapshot"
      rm -rf "$save_dir"
      mkdir -p "$save_dir"
    fi
    download_unzip_snapshot
  fi

  # The return value for the program that calls this script
  echo "$save_dir"
else
  echo "Skip download snapshot"
fi

if [ $service_name != "snapshot" ]; then
  echo $service_name
fi
