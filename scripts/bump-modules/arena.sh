# arena service + backoffice
SERVICE_LABEL="arena-service"
COMMIT_SCOPE="arena"
BRANCH_PREFIX="arena"
STAGING_FILE="9c-internal/network/general.yaml"
PRODUCTION_FILE="9c-main/network/general.yaml"
TAG_KEYS=(
  ".arenaService.image.tag"
  ".arenaService.backoffice.image.tag"
)
