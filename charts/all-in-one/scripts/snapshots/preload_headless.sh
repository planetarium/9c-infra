#!/usr/bin/env bash
set -ex

apt-get -y update
apt-get -y install curl zip
HOME="/app"

APP_PROTOCOL_VERSION=$1
SLACK_WEBHOOK=$2
STORE_PATH=$3
FORCE_CUTOFF_BLOCK=$4
VERSION_NUMBER="${APP_PROTOCOL_VERSION:0:6}"
GENESIS_BLOCK_PATH="{{ $.Values.global.genesisBlockPath }}"
TRUSTED_APP_PROTOCOL_VERSION_SIGNER="{{ $.Values.global.trustedAppProtocolVersionSigner }}"

{{- range $i, $s := $.Values.global.peerStrings }}
SEED{{ add $i 1 }}="{{ $s }}"
{{- end }}

ICE_SERVER="turn://0ed3e48007413e7c2e638f13ddd75ad272c6c507e081bd76a75e4b7adc86c9af:0apejou+ycZFfwtREeXFKdfLj2gCclKzz5ZJ49Cmy6I=@turn-us.planetarium.dev:3478"

HEADLESS="$HOME/NineChronicles.Headless.Executable"
HEADLESS_LOG_NAME="headless_$(date -u +"%Y%m%d%H%M").log"
HEADLESS_LOG_DIR=${4:-"/data/snapshot_logs"}
HEADLESS_LOG="$HEADLESS_LOG_DIR/$HEADLESS_LOG_NAME"
mkdir -p "$HEADLESS_LOG_DIR"

PID_FILE="$HOME/headless_pid"
function senderr() {
  echo "$1"
  curl -X POST -H 'Content-type: application/json' --data '{"text":"[K8S] '$1'. Check snapshot-partition-v'$VERSION_NUMBER' in {{ $.Values.clusterName }} cluster at preload_headless.sh."}' $SLACK_WEBHOOK
}

function preload_complete() {
  echo "$1"
}

function waitpid() {
  PID="$1"
  while [ -e "/proc/$PID" ]; do
    sleep 1
  done
}

function run_headless() {
  if [ ! -d "$STORE_PATH" ]; then
    mkdir -p "$STORE_PATH"
  fi

  chmod 777 -R "$STORE_PATH"

  "$HEADLESS" \
      --no-miner \
      --genesis-block-path="$GENESIS_BLOCK_PATH" \
      --store-type=rocksdb \
      --store-path="$STORE_PATH" \
      --app-protocol-version="$APP_PROTOCOL_VERSION" \
      --trusted-app-protocol-version-signer="$TRUSTED_APP_PROTOCOL_VERSION_SIGNER" \
      --ice-server="$ICE_SERVER" \
      {{- if $.Values.global.planet }}
      --planet={{ $.Values.global.planet }} \
      {{- end }}
      {{- if $.Values.global.headlessAppsettingsPath }}
      --config={{ $.Values.global.headlessAppsettingsPath }} \
      {{- end }}
      {{- range $i, $s := $.Values.global.peerStrings }}
      --peer "$SEED{{ add $i 1 }}" \
      {{- end }}
      > "$HEADLESS_LOG" 2>&1 &

  PID="$!"

  echo "$PID" | tee "$PID_FILE"

  if ! kill -0 "$PID"; then
    senderr "$PID doesn't exist. Failed to run headless" $1
    exit 1
  fi
}

function wait_preloading() {
  touch "$PID_FILE"
  PID="$(cat "$PID_FILE")"

  if ! kill -0 "$PID"; then
    senderr "$PID doesn't exist. Failed to run headless" $1
    exit 1
  fi

  CUTOFF_GREP=""
  if [ -n "$FORCE_CUTOFF_BLOCK" ]; then
    CUTOFF_GREP="-e \"Block #$FORCE_CUTOFF_BLOCK \""
  fi

  tail -f "$HEADLESS_LOG" | grep "Block #" &

  if timeout 144000 tail -f "$HEADLESS_LOG" | grep -m1 -e "preloading is no longer needed" -e "There are no appropriate peers for preloading" $CUTOFF_GREP; then
    sleep 5
  else
    senderr "grep failed. Failed to preload." $1
    kill "$PID"
    exit 1
  fi
}


function kill_headless() {
  touch "$PID_FILE"
  PID="$(cat "$PID_FILE")"
  if ! kill -0 "$PID"; then
    echo "$PID doesn't exist. Failed to kill headless"
  else
    kill "$PID"; sleep 60; kill -9 "$PID" || true
    waitpid "$PID" || true
    chmod 777 -R "$STORE_PATH"
  fi
}

function rotate_log() {
  cd "$HEADLESS_LOG_DIR"
  if ./*"$(date -d 'yesterday' -u +'%Y%m%d')"*.log; then
    zip "$(date -d 'yesterday' -u +'%Y%m%d')".zip ./*"$(date -d 'yesterday' -u +'%Y%m%d')"*.log
    rm ./*"$(date -d 'yesterday' -u +'%Y%m%d')"*.log
  fi
}

trap '' HUP

run_headless
wait_preloading
preload_complete "Preloading completed"
kill_headless
rotate_log
