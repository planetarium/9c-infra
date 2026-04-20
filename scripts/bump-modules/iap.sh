# iap (In-App Purchase) api / worker / backoffice
SERVICE_LABEL="iap"
COMMIT_SCOPE="iap"
BRANCH_PREFIX="iap"
STAGING_FILE="9c-internal/external-services/values.yaml"
PRODUCTION_FILE="9c-main/external-services/values.yaml"
TAG_KEYS=(
  ".iap.api.image.tag"
  ".iap.worker.image.tag"
  ".iap.backoffice.image.tag"
)
