#!/usr/bin/env bash
set -ex

apt-get -y update
apt-get -y install jq
apt-get -y install default-mysql-client

HOME="/app"
NC_MySqlConnectionString="$1"
NC_MySqlConnectionString+="Allow User Variables=true"
MIGRATE_DB_OPTION=$2

if $MIGRATE_DB_OPTION
then
    /root/.dotnet/tools/dotnet-ef database update --project /app/NineChronicles.DataProvider/NineChronicles.DataProvider.Executable --connection "$NC_MySqlConnectionString"
fi
