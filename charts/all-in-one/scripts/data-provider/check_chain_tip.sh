#!/usr/bin/env bash
set -ex

apt-get -y update
apt-get -y install jq
apt-get -y install default-mysql-client

HOME="/app"
DP_HOST=$1
DP_USER=$2
DP_TOKEN=$3
DP_PORT=$4
DP_DATABASE=$5
RESET_SNAPSHOT_OPTION=$6

if ! $RESET_SNAPSHOT_OPTION
then
  FILE="/data/blockIndex.txt"
  CHAIN_TIP_INDEX="$(($HOME/NineChronicles.Headless.Executable/NineChronicles.Headless.Executable chain tip "RocksDb" "/data/data-provider") | jq -r '.Index')"

  RENDERED_BLOCK_INDEX=$CHAIN_TIP_INDEX
  if [ -f "$FILE" ]; then
      RENDERED_BLOCK_INDEX="$(cat "/data/blockIndex.txt")"
  else
      echo $FILE does not exist. Get the latest block index from the database.
      MYSQL_BLOCK_INDEX=$(mysql --host=$DP_HOST --user=$DP_USER --password=$DP_TOKEN --port=$DP_PORT --database=$DP_DATABASE --skip-column-names -e "SELECT \`Index\` FROM $DP_DATABASE.Blocks order by \`Index\` desc limit 1;")
      RENDERED_BLOCK_INDEX=$MYSQL_BLOCK_INDEX
  fi

  TIP_DIFF=$(( $CHAIN_TIP_INDEX - $RENDERED_BLOCK_INDEX ))
  if (( $TIP_DIFF > 0 ))
  then
    echo Truncate chain tip by $TIP_DIFF.
    $HOME/NineChronicles.Headless.Executable/NineChronicles.Headless.Executable chain truncate "RocksDb" "/data/data-provider" $TIP_DIFF
  else
    echo No need to truncate chain tip.
  fi
fi