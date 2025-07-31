#!/usr/bin/env bash
set -e

apt-get update && apt-get install -y jq default-mysql-client

HOME="/app"
NC_MySqlConnectionString="$1"
NC_MySqlConnectionString+="Allow User Variables=true"
MIGRATE_DB_OPTION=$2

if $MIGRATE_DB_OPTION
then
    /root/.dotnet/tools/dotnet-ef database update --project /app/NineChronicles.DataProvider/NineChronicles.DataProvider.Executable --connection "$NC_MySqlConnectionString"
fi
