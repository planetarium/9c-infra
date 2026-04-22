#!/usr/bin/env bash
# Dump pt6 RKE2 OIDC documents and upload them to the public S3 bucket so
# AWS STS can verify service-account tokens during IRSA. Run this:
#   - once, right after pt6 RKE2 is first started
#   - whenever RKE2 rotates its service-account signing key (rare, check JWKS)
#
# Prereqs:
#   - Run on pt6 (or a host with kubectl context pointing at pt6)
#   - AWS CLI configured with write access to s3://9c-cluster-config/pt6-oidc/
#
# Usage: ./scripts/pt6-oidc-sync.sh

set -euo pipefail

BUCKET="9c-cluster-config"
PREFIX="pt6-oidc"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[1/3] Dumping OIDC documents from RKE2..."
kubectl get --raw /.well-known/openid-configuration > "$TMP/openid-configuration.json"
kubectl get --raw /openid/v1/jwks              > "$TMP/jwks.json"

# RKE2's discovery document points at the cluster's internal issuer URL.
# Rewrite it so fields resolve to the S3-hosted copy that AWS STS hits.
ISSUER="https://$BUCKET.s3.us-east-2.amazonaws.com/$PREFIX"
jq \
  --arg issuer "$ISSUER" \
  --arg jwks   "$ISSUER/openid/v1/jwks" \
  '.issuer = $issuer | .jwks_uri = $jwks' \
  "$TMP/openid-configuration.json" > "$TMP/openid-configuration.rewritten.json"

echo "[2/3] Uploading to s3://$BUCKET/$PREFIX/"
aws s3 cp "$TMP/openid-configuration.rewritten.json" \
  "s3://$BUCKET/$PREFIX/.well-known/openid-configuration" \
  --content-type application/json \
  --acl public-read
aws s3 cp "$TMP/jwks.json" \
  "s3://$BUCKET/$PREFIX/openid/v1/jwks" \
  --content-type application/json \
  --acl public-read

echo "[3/3] Verifying public access..."
curl -fsS "$ISSUER/.well-known/openid-configuration" > /dev/null
curl -fsS "$ISSUER/openid/v1/jwks"                   > /dev/null
echo "OK. OIDC issuer URL: $ISSUER"
