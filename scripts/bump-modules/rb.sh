# ragnarok-breaker chart — independent images, one per workload.
# Usage:
#   bump-image.sh rb <worker|v8-gateway|log-stream|anticheat-alert-worker> <hash>
#   bump-image.sh rb <hash>   # bump every workload at once
#
# anticheat-alert-worker is prod-only, so it's excluded from the bulk all-bump's
# REQUIRED keys and included as an OPTIONAL key instead: `bump-image.sh rb <hash>`
# bumps it where it exists and skips overlays that lack the key (no error).
# Its per-service bump targets the prod overlays only:
#   - anticheat-alert-worker : per-env Slack alert consumer, all three prod overlays.
#       bump-image.sh rb anticheat-alert-worker <hash>
#
# Environments after the env×tier split (dev/staging/prod × web2/web3):
# each env keyword resolves to multiple values files (legacy single-ns values
# + the two new tier overlays) so a single bump keeps the cutover-period
# namespaces in sync. The legacy entries should be dropped from this list
# once those Applications are deleted.

COMMIT_SCOPE="ragnarok-breaker"
DEV_FILES=(
  9c-internal/ragnarok-breaker-dev-web2/values.yaml
  9c-internal/ragnarok-breaker-dev-web3/values.yaml
)
STAGING_FILES=(
  9c-internal/ragnarok-breaker-staging/values.yaml
  9c-internal/ragnarok-breaker-staging-web2/values.yaml
  9c-internal/ragnarok-breaker-staging-web3/values.yaml
)
PRODUCTION_FILES=(
  9c-main/ragnarok-breaker-production/values.yaml
  9c-main/ragnarok-breaker-prod-web2/values.yaml
  9c-main/ragnarok-breaker-prod-web3/values.yaml
)
# Single-path fallbacks expected by bump-image.sh's mandatory-vars check.
DEV_FILE="${DEV_FILES[0]}"
STAGING_FILE="${STAGING_FILES[0]}"
PRODUCTION_FILE="${PRODUCTION_FILES[0]}"
SUB_SERVICES=(worker v8-gateway log-stream anticheat-alert-worker)

resolve_sub_service() {
  case "$1" in
    worker)
      TAG_KEYS=(".worker.image.tag")
      SERVICE_LABEL="ragnarok-breaker-worker"
      BRANCH_PREFIX="ragnarok-breaker-worker"
      ;;
    v8-gateway)
      TAG_KEYS=(".v8Gateway.image.tag")
      SERVICE_LABEL="ragnarok-breaker-v8-gateway"
      BRANCH_PREFIX="ragnarok-breaker-v8-gateway"
      ;;
    log-stream)
      TAG_KEYS=(".logStream.image.tag")
      SERVICE_LABEL="ragnarok-breaker-log-stream"
      BRANCH_PREFIX="ragnarok-breaker-log-stream"
      ;;
    anticheat-alert-worker)
      TAG_KEYS=(".anticheatAlertWorker.image.tag")
      SERVICE_LABEL="ragnarok-breaker-anticheat-alert-worker"
      BRANCH_PREFIX="ragnarok-breaker-anticheat-alert-worker"
      # prod-only workload (enabled in the three prod overlays). Scope every env
      # keyword to the prod files so any --env (including the default `both`)
      # only touches prod and never errors on dev/staging files that lack the key.
      DEV_FILES=("${PRODUCTION_FILES[@]}")
      STAGING_FILES=("${PRODUCTION_FILES[@]}")
      DEV_FILE="${PRODUCTION_FILES[0]}"
      STAGING_FILE="${PRODUCTION_FILES[0]}"
      ;;
    *)
      echo "error: unknown rb sub-service '$1' (available: ${SUB_SERVICES[*]})" >&2
      return 1
      ;;
  esac
}

resolve_all_sub_services() {
  TAG_KEYS=(
    ".worker.image.tag"
    ".v8Gateway.image.tag"
    ".logStream.image.tag"
  )
  # Prod-only workloads are OPTIONAL keys: the bulk bump spans every env file but
  # bumps these only where they exist (the prod overlays) and skips the overlays
  # that lack them, instead of erroring on the missing key.
  #   - anticheatAlertWorker : all three prod overlays.
  OPTIONAL_TAG_KEYS=(
    ".anticheatAlertWorker.image.tag"
  )
  SERVICE_LABEL="all ragnarok-breaker images"
  BRANCH_PREFIX="ragnarok-breaker-all"
}
