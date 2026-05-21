# ragnarok-breaker chart — 6 independent images, one per workload.
# Usage:
#   bump-image.sh rb <worker|v8-gateway|ygg-redeem|log-stream|ygg-quest-worker|bq-analytics-worker> <hash>
#   bump-image.sh rb <hash>   # bump every workload at once
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
SUB_SERVICES=(worker v8-gateway ygg-redeem log-stream ygg-quest-worker bq-analytics-worker)

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
    ygg-redeem)
      TAG_KEYS=(".yggRedeem.image.tag")
      SERVICE_LABEL="ragnarok-breaker-ygg-redeem"
      BRANCH_PREFIX="ragnarok-breaker-ygg-redeem"
      ;;
    log-stream)
      TAG_KEYS=(".logStream.image.tag")
      SERVICE_LABEL="ragnarok-breaker-log-stream"
      BRANCH_PREFIX="ragnarok-breaker-log-stream"
      ;;
    ygg-quest-worker)
      TAG_KEYS=(".yggQuestWorker.image.tag")
      SERVICE_LABEL="ragnarok-breaker-ygg-quest-worker"
      BRANCH_PREFIX="ragnarok-breaker-ygg-quest-worker"
      ;;
    bq-analytics-worker)
      TAG_KEYS=(".bqAnalyticsWorker.image.tag")
      SERVICE_LABEL="ragnarok-breaker-bq-analytics-worker"
      BRANCH_PREFIX="ragnarok-breaker-bq-analytics-worker"
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
    ".yggRedeem.image.tag"
    ".logStream.image.tag"
    ".yggQuestWorker.image.tag"
    ".bqAnalyticsWorker.image.tag"
  )
  SERVICE_LABEL="all ragnarok-breaker images"
  BRANCH_PREFIX="ragnarok-breaker-all"
}
