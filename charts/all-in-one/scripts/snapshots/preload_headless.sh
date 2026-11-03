#!/usr/bin/env bash
set -ex

apt-get -y update
apt-get -y install curl zip
HOME="/app"

APP_PROTOCOL_VERSION=$1
# The webhook URL is a secret: keep it out of the `set -x` trace (it used to land
# in plain text in every job log).
{ set +x; } 2>/dev/null
SLACK_WEBHOOK=$2
set -x
STORE_PATH=$3
FORCE_CUTOFF_BLOCK=$5
VERSION_NUMBER="${APP_PROTOCOL_VERSION:0:6}"
SOURCE_PREFIX="${SNAPSHOT_SOURCE_LABEL:+[$SNAPSHOT_SOURCE_LABEL] }"
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

# Create the log file up front. run_headless() backgrounds headless with the
# redirect applied in the forked child, so the file's open() races against the
# `tail -f "$HEADLESS_LOG"` that wait_preloading() starts immediately after. If
# tail loses, it exits with "cannot open ... No such file or directory", grep
# sees EOF, MATCH comes back empty and the job falsely reports a preload
# timeout seconds into the run. (Observed 2026-08-11 on pt6: alerted 6s in,
# while the timeout is 144000s.)
: > "$HEADLESS_LOG"

PID_FILE="$HOME/headless_pid"
function senderr() {
  echo "$1"
  { set +x; } 2>/dev/null
  curl -X POST -H 'Content-type: application/json' --data '{"text":"'"$SOURCE_PREFIX"'[K8S] '"$1"'. Check snapshot-partition-v'$VERSION_NUMBER' in {{ $.Values.clusterName }} cluster at preload_headless.sh."}' "$SLACK_WEBHOOK" || true
  set -x
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
      >> "$HEADLESS_LOG" 2>&1 &

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
    CUTOFF_GREP="-e #$FORCE_CUTOFF_BLOCK"
  fi

  tail -f "$HEADLESS_LOG" | grep "Block #" &

  # Capture WHICH terminal line appeared instead of treating them all as success.
  # "There are no appropriate peers for preloading" means the node could NOT find
  # peers to sync from (e.g. APV mismatch or unreachable seed) -> it is NOT caught
  # up. Previously this matched the same grep as the real success message, so the
  # job silently "completed" on a stale store (odin snapshot froze ~24 days at the
  # 2026-05-26 APV bump). Now it alerts and aborts.
  #
  # The watcher runs in the background so this loop can also check that headless is
  # still alive. Without that, a headless that dies right after start (2026-11-01 on
  # pt6: plugin download hit "Connection reset by peer" 58s in) left tail/grep
  # waiting for the full 40h timeout before the job failed and retried.
  MATCH_FILE="$(mktemp)"
  (timeout 144000 tail -n +1 -f "$HEADLESS_LOG" | grep -m1 -e "preloading is no longer needed" -e "There are no appropriate peers for preloading" $(echo "$CUTOFF_GREP") > "$MATCH_FILE" || true) &
  WATCHER="$!"
  set +x  # the loop below would flood the log with trace lines
  while kill -0 "$WATCHER" 2>/dev/null; do
    if ! kill -0 "$PID" 2>/dev/null; then
      sleep 5  # let the watcher read the last lines headless wrote before exiting
      if [ ! -s "$MATCH_FILE" ]; then
        set -x
        senderr "Headless exited before preload completed (see $HEADLESS_LOG)"
        exit 1
      fi
      break
    fi
    sleep 30
  done
  set -x
  MATCH="$(cat "$MATCH_FILE")"

  if [ -z "$MATCH" ]; then
    senderr "Preload timed out with no completion log."
    kill "$PID" || true
    exit 1
  fi

  if echo "$MATCH" | grep -q "There are no appropriate peers for preloading"; then
    senderr "Preload found NO appropriate peers (likely APV mismatch or unreachable seed); store may be stale. Aborting."
    kill "$PID" || true
    exit 1
  fi

  echo "[INFO] Preload completed: $MATCH"
  sleep 5
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
