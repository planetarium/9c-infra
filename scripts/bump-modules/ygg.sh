# ygg-gateway (lives inside the ragnarok-breaker chart; bumps only the
# .yggGateway.image.tag key, leaving the worker tag untouched).
SERVICE_LABEL="ygg-gateway"
COMMIT_SCOPE="ygg-gateway"
BRANCH_PREFIX="ygg-gateway"
STAGING_FILE="9c-internal/ragnarok-breaker-staging/values.yaml"
PRODUCTION_FILE="9c-main/ragnarok-breaker-production/values.yaml"
TAG_KEYS=(".yggGateway.image.tag")
