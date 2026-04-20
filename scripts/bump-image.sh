#!/usr/bin/env bash
set -euo pipefail

# Bump a 9c-infra service's image tag in staging and/or production overlays
# and open a PR against planetarium/9c-infra.
#
# Usage: bump-image.sh <service> <hash> [--env staging|production|both] [--separate]
#
#   <service>      Service id. Discovered from scripts/bump-modules/<service>.sh.
#                  Use --help to list available services.
#   <hash>         Image tag. Bare hash (e.g. abc123...) or git-<hash>; auto normalized.
#   --env          default: both. Pick staging/production/both.
#   --separate     when --env both, open two PRs instead of one combined PR.
#
# Requires: git, gh (authenticated), yq (v4+).
#
# Adding a new service: create scripts/bump-modules/<id>.sh and set:
#   SERVICE_LABEL, COMMIT_SCOPE, BRANCH_PREFIX,
#   STAGING_FILE, PRODUCTION_FILE, TAG_KEYS=(".foo.image.tag" ...).

SCRIPT_PATH="${BASH_SOURCE[0]}"
resolve_self() {
  local src="$1"
  while [[ -L "$src" ]]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" && pwd
}
SCRIPT_DIR="$(resolve_self "$SCRIPT_PATH")"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODULE_DIR="$SCRIPT_DIR/bump-modules"

list_services() {
  local f
  for f in "$MODULE_DIR"/*.sh; do
    [[ -f "$f" ]] && basename "$f" .sh
  done | sort
}

usage() {
  sed -n '4,15p' "$SCRIPT_PATH" | sed 's/^# \{0,1\}//'
  echo "Available services:"
  local s
  for s in $(list_services); do
    echo "  - $s"
  done
}

SERVICE=""
HASH=""
ENV="both"
SEPARATE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      [[ $# -ge 2 ]] || { echo "error: --env requires a value" >&2; exit 1; }
      ENV="$2"
      shift 2
      ;;
    --separate)
      SEPARATE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "error: unknown flag: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -z "$SERVICE" ]]; then
        SERVICE="$1"
      elif [[ -z "$HASH" ]]; then
        HASH="$1"
      else
        echo "error: unexpected positional arg: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$SERVICE" || -z "$HASH" ]]; then
  usage >&2
  exit 1
fi

MODULE_FILE="$MODULE_DIR/${SERVICE}.sh"
if [[ ! -f "$MODULE_FILE" ]]; then
  echo "error: unknown service '$SERVICE' (no $MODULE_FILE)" >&2
  echo "available: $(list_services | paste -sd ' ' -)" >&2
  exit 1
fi

# Load service module. Expected to set SERVICE_LABEL, COMMIT_SCOPE,
# BRANCH_PREFIX, STAGING_FILE, PRODUCTION_FILE, TAG_KEYS=(...).
SERVICE_LABEL=""
COMMIT_SCOPE=""
BRANCH_PREFIX=""
STAGING_FILE=""
PRODUCTION_FILE=""
TAG_KEYS=()
# shellcheck disable=SC1090
source "$MODULE_FILE"

for var in SERVICE_LABEL COMMIT_SCOPE BRANCH_PREFIX STAGING_FILE PRODUCTION_FILE; do
  if [[ -z "${!var}" ]]; then
    echo "error: module $MODULE_FILE missing $var" >&2
    exit 1
  fi
done
if [[ "${#TAG_KEYS[@]}" -eq 0 ]]; then
  echo "error: module $MODULE_FILE set empty TAG_KEYS" >&2
  exit 1
fi

HASH="${HASH#git-}"
if [[ ! "$HASH" =~ ^[0-9a-f]{7,40}$ ]]; then
  echo "error: hash must be 7-40 hex chars, got: $HASH" >&2
  exit 1
fi
TAG="git-${HASH}"
SHORT7="${HASH:0:7}"
SHORT8="${HASH:0:8}"

cd "$REPO_ROOT"

for bin in git gh yq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: missing binary: $bin" >&2; exit 1; }
done
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree not clean; commit or stash first" >&2
  exit 1
fi
gh auth status >/dev/null 2>&1 || { echo "error: gh not authenticated; run 'gh auth login'" >&2; exit 1; }

if git remote | grep -qx upstream; then
  REMOTE=upstream
else
  REMOTE=origin
fi
git fetch "$REMOTE" main --quiet

file_for_env() {
  case "$1" in
    staging)    echo "$STAGING_FILE" ;;
    production) echo "$PRODUCTION_FILE" ;;
    *)          echo "error: invalid env: $1" >&2; return 1 ;;
  esac
}

branch_for() {
  # $1: staging | production | combined
  case "$1" in
    staging)    echo "${BRANCH_PREFIX}-staging-image-$SHORT8" ;;
    production) echo "${BRANCH_PREFIX}-main-image-$SHORT8" ;;
    combined)   echo "${BRANCH_PREFIX}-image-$SHORT8" ;;
  esac
}

update_file_tags() {
  # Rewrite only the `tag:` line of each TAG_KEYS entry in the file,
  # preserving every other line (blank lines, comments, other keys) and the
  # original quote style (`tag: git-x` vs `tag: "git-x"`).
  local file="$1"
  local key line_num original replacement
  for key in "${TAG_KEYS[@]}"; do
    line_num="$(yq "$key | line" "$file")"
    if [[ -z "$line_num" || "$line_num" == "null" || "$line_num" == "0" ]]; then
      echo "error: key '$key' not found in $file" >&2
      return 1
    fi
    original="$(sed -n "${line_num}p" "$file")"
    if [[ "$original" == *'tag: "'* ]]; then
      replacement="\\1 \"${TAG}\""
    else
      replacement="\\1 ${TAG}"
    fi
    sed -i.bak -E "${line_num}s|(^[[:space:]]*tag:)[[:space:]]*.*|${replacement}|" "$file"
    rm -f "${file}.bak"
  done
}

ORIGINAL_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
restore_branch() {
  local cur
  cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo)"
  if [[ -n "$cur" && "$cur" != "$ORIGINAL_BRANCH" ]]; then
    git checkout "$ORIGINAL_BRANCH" --quiet 2>/dev/null || true
  fi
}
trap restore_branch EXIT

bump_and_pr() {
  local envs=("$@")
  local branch title file body body_envs e

  if [[ "${#envs[@]}" -eq 1 ]]; then
    branch="$(branch_for "${envs[0]}")"
    title="chore(${COMMIT_SCOPE}): pin ${envs[0]} image to git-$SHORT7"
    body_envs="${envs[0]}"
  else
    branch="$(branch_for combined)"
    title="chore(${COMMIT_SCOPE}): bump staging + production image to git-$SHORT7"
    body_envs="staging + production"
  fi

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    echo "error: branch already exists: $branch" >&2
    exit 1
  fi

  git checkout -b "$branch" "$REMOTE/main" --quiet
  for e in "${envs[@]}"; do
    file="$(file_for_env "$e")"
    update_file_tags "$file"
    git add "$file"
  done

  if git diff --cached --quiet; then
    echo "info: tag already pinned to $TAG for $body_envs; nothing to do"
    git checkout "$ORIGINAL_BRANCH" --quiet
    git branch -D "$branch" --quiet
    return 0
  fi

  git commit --quiet \
    -m "$title" \
    -m "Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
  git push --quiet -u origin "$branch"

  body=$(cat <<EOF
Pin ${SERVICE_LABEL} image to \`$TAG\` for $body_envs.

## Test plan
- [ ] After sync, pods pull the pinned image successfully
EOF
)

  gh pr create \
    --repo planetarium/9c-infra \
    --base main \
    --head "Atralupus:$branch" \
    --title "$title" \
    --body "$body"
}

case "$ENV" in
  staging|production)
    bump_and_pr "$ENV"
    ;;
  both)
    if [[ $SEPARATE -eq 1 ]]; then
      bump_and_pr staging
      git checkout "$ORIGINAL_BRANCH" --quiet
      bump_and_pr production
    else
      bump_and_pr staging production
    fi
    ;;
  *)
    echo "error: invalid --env: $ENV (expected staging|production|both)" >&2
    exit 1
    ;;
esac
