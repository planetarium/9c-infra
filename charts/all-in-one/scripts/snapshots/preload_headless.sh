#!/usr/bin/env bash
set -ex

apt-get -y update
apt-get -y install curl
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
HEADLESS_LOG_DIR=${4:-"/data/snapshot_logs"}
mkdir -p "$HEADLESS_LOG_DIR"

# Overall preload budget (40h) shared by every attempt below.
PRELOAD_DEADLINE=$(( $(date +%s) + 144000 ))

# "There are no appropriate peers for preloading" is also what a short network
# outage looks like: on 2026-11-17 19:00 UTC the office switch dropped link on
# pt2/pt4/pt6 for ~2.5 min, every GetChainStatus in the next preload round timed
# out, and the job alerted although it was syncing fine before and after.
# A persistent cause (APV mismatch, unreachable seed) fails every attempt, so we
# restart headless a few times after a pause and only alert when all of them fail.
NO_PEER_RETRIES=3
NO_PEER_RETRY_WAIT=300

# Each attempt writes its own log: the watcher in wait_preloading() reads the log
# from the first line, so reusing the file would re-match the previous attempt's
# "no appropriate peers" line immediately.
#
# Create the log file up front. run_headless() backgrounds headless with the
# redirect applied in the forked child, so the file's open() races against the
# `tail -f "$HEADLESS_LOG"` that wait_preloading() starts immediately after. If
# tail loses, it exits with "cannot open ... No such file or directory", grep
# sees EOF, MATCH comes back empty and the job falsely reports a preload
# timeout seconds into the run. (Observed 2026-08-11 on pt6: alerted 6s in,
# while the timeout is 144000s.)
function new_headless_log() {
  HEADLESS_LOG="$HEADLESS_LOG_DIR/headless_$(date -u +"%Y%m%d%H%M").log"
  if [ -s "$HEADLESS_LOG" ]; then  # same minute as the previous attempt or pod (Job retry)
    HEADLESS_LOG="${HEADLESS_LOG%.log}_$(date -u +"%S").log"
  fi
  : > "$HEADLESS_LOG"
}

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

  # --pid: stop following once this attempt's headless exits (a retry starts a new log).
  tail --pid="$PID" -f "$HEADLESS_LOG" | grep "Block #" &

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
  REMAINING=$(( PRELOAD_DEADLINE - $(date +%s) ))
  if [ "$REMAINING" -le 0 ]; then REMAINING=1; fi
  MATCH_FILE="$(mktemp)"
  (timeout "$REMAINING" tail -n +1 -f "$HEADLESS_LOG" | grep -m1 -e "preloading is no longer needed" -e "There are no appropriate peers for preloading" $(echo "$CUTOFF_GREP") > "$MATCH_FILE" || true) &
  WATCHER="$!"
  set +x  # the loop below would flood the log with trace lines
  while kill -0 "$WATCHER" 2>/dev/null; do
    if ! kill -0 "$PID" 2>/dev/null; then
      sleep 5  # let the watcher read the last lines headless wrote before exiting
      if [ ! -s "$MATCH_FILE" ]; then
        set -x
        rc=0; wait "$PID" || rc=$?  # headless is our child: its exit code tells OOM (137) from an exception
        senderr "Headless exited (code $rc) before preload completed (see $HEADLESS_LOG)"
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
    # The caller decides whether to retry or alert.
    PRELOAD_RESULT="no_peers"
    return 0
  fi

  PRELOAD_RESULT="done"
  echo "[INFO] Preload completed: $MATCH"
  sleep 5
}


function kill_headless() {
  touch "$PID_FILE"
  PID="$(cat "$PID_FILE")"
  if ! kill -0 "$PID"; then
    echo "$PID doesn't exist. Failed to kill headless"
  else
    kill "$PID" || true; sleep 60; kill -9 "$PID" || true
    waitpid "$PID" || true
    chmod 777 -R "$STORE_PATH"
  fi
}

# Compress finished headless logs. The old version ran `if ./*<yesterday>*.log`,
# which tried to EXECUTE the log (Permission denied -> false), so nothing was ever
# compressed: pt6 had 218 raw logs / 38G by 2026-11-18. It also only looked at
# "yesterday", which misses runs longer than a day.
# Logs untouched for 24h are done (a running headless writes every few seconds),
# which also skips a log another snapshot job is still writing in the same dir.
# Never fail here: this runs in an initContainer and the upload comes after it.
function rotate_log() {
  find "$HEADLESS_LOG_DIR" -maxdepth 1 -type f -name 'headless_*.log' -mmin +1440 \
    -exec gzip -f {} + || echo "[WARN] rotate_log: gzip failed (ignored)"
}

trap '' HUP

attempt=0
while true; do
  new_headless_log
  run_headless
  PRELOAD_RESULT=""
  wait_preloading
  if [ "$PRELOAD_RESULT" = "done" ]; then
    break
  fi

  # no appropriate peers: stop headless cleanly (releases the RocksDB lock) first.
  kill_headless
  attempt=$((attempt + 1))
  if [ "$attempt" -gt "$NO_PEER_RETRIES" ] || [ $(( $(date +%s) + NO_PEER_RETRY_WAIT )) -ge "$PRELOAD_DEADLINE" ]; then
    senderr "Preload found NO appropriate peers in $attempt attempts (likely APV mismatch or unreachable seed); store may be stale. Aborting."
    exit 1
  fi
  echo "[WARN] No appropriate peers (attempt $attempt/$((NO_PEER_RETRIES + 1))); retrying in ${NO_PEER_RETRY_WAIT}s (see $HEADLESS_LOG)"
  sleep "$NO_PEER_RETRY_WAIT"
done
preload_complete "Preloading completed"
kill_headless
rotate_log
