# ragnarok-breaker chart — 7 independent images, one per workload.
# Usage:
#   bump-image.sh rb <worker|v8-gateway|ygg-redeem|log-stream|ygg-quest-worker|bq-analytics-worker|bq-ingest-gateway> <hash>
#   bump-image.sh rb <hash>   # bump every workload at once (except bq-ingest-gateway)
#
# bq-ingest-gateway is a single shared instance living only in prod-web3, so it
# is NOT part of the bulk all-bump and its per-service bump targets prod-web3
# only. Bump it explicitly: bump-image.sh rb bq-ingest-gateway <hash>
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
SUB_SERVICES=(worker v8-gateway ygg-redeem log-stream ygg-quest-worker bq-analytics-worker bq-ingest-gateway)

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
    bq-ingest-gateway)
      TAG_KEYS=(".bqIngestGateway.image.tag")
      SERVICE_LABEL="ragnarok-breaker-bq-ingest-gateway"
      BRANCH_PREFIX="ragnarok-breaker-bq-ingest-gateway"
      # Single shared instance, prod-web3 only — scope every env keyword to that
      # one file so any --env (including the default `both`) only touches
      # prod-web3 and never errors on files that lack the key.
      DEV_FILES=(9c-main/ragnarok-breaker-prod-web3/values.yaml)
      STAGING_FILES=(9c-main/ragnarok-breaker-prod-web3/values.yaml)
      PRODUCTION_FILES=(9c-main/ragnarok-breaker-prod-web3/values.yaml)
      DEV_FILE="${DEV_FILES[0]}"
      STAGING_FILE="${STAGING_FILES[0]}"
      PRODUCTION_FILE="${PRODUCTION_FILES[0]}"
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
  # bqIngestGateway is intentionally excluded — it lives only in prod-web3 and
  # the bulk bump spans every env file, most of which lack the key.
  SERVICE_LABEL="all ragnarok-breaker images"
  BRANCH_PREFIX="ragnarok-breaker-all"
}
