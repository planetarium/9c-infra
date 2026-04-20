#!/usr/bin/env bash
set -euo pipefail

# Bump ragnarok-breaker-worker image tag in staging and/or production overlays
# and open a PR against planetarium/9c-infra.
#
# Usage: bump-rb-worker.sh <hash> [--env staging|production|both] [--separate]
#
#   <hash>         image tag. Bare hash (e.g. abc123...) or git-<hash>; auto normalized.
#   --env          default: both. Pick staging/production/both.
#   --separate     when --env both, open two PRs instead of one combined PR.
#
# Requires: git, gh (authenticated), yq (v4+).

usage() {
  sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'
}

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
      usage
      exit 1
      ;;
    *)
      if [[ -n "$HASH" ]]; then
        echo "error: multiple positional args: '$HASH' and '$1'" >&2
        exit 1
      fi
      HASH="$1"
      shift
      ;;
  esac
done

if [[ -z "$HASH" ]]; then
  usage
  exit 1
fi

# Normalize hash: strip leading "git-" if present.
HASH="${HASH#git-}"
if [[ ! "$HASH" =~ ^[0-9a-f]{7,40}$ ]]; then
  echo "error: hash must be 7-40 hex chars, got: $HASH" >&2
  exit 1
fi
TAG="git-${HASH}"
SHORT7="${HASH:0:7}"
SHORT8="${HASH:0:8}"

# Resolve repo root from the script's real path so symlinked invocations work.
resolve_self() {
  local src="${BASH_SOURCE[0]}"
  while [[ -L "$src" ]]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" && pwd
}
SCRIPT_DIR="$(resolve_self)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Prereq checks.
for bin in git gh yq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: missing binary: $bin" >&2; exit 1; }
done
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree not clean; commit or stash first" >&2
  exit 1
fi
gh auth status >/dev/null 2>&1 || { echo "error: gh not authenticated; run 'gh auth login'" >&2; exit 1; }

# Pick the remote that tracks planetarium/9c-infra.
if git remote | grep -qx upstream; then
  REMOTE=upstream
else
  REMOTE=origin
fi
git fetch "$REMOTE" main --quiet

STAGING_FILE="9c-internal/ragnarok-breaker-staging/values.yaml"
PRODUCTION_FILE="9c-main/ragnarok-breaker-production/values.yaml"

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
    staging)    echo "ragnarok-breaker-staging-image-$SHORT8" ;;
    production) echo "ragnarok-breaker-main-image-$SHORT8" ;;
    combined)   echo "ragnarok-breaker-image-$SHORT8" ;;
  esac
}

ORIGINAL_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
restore_branch() {
  local cur
  cur="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "$cur" != "$ORIGINAL_BRANCH" ]]; then
    git checkout "$ORIGINAL_BRANCH" --quiet
  fi
}
trap restore_branch EXIT

bump_and_pr() {
  local envs=("$@")
  local branch title file
  if [[ "${#envs[@]}" -eq 1 ]]; then
    branch="$(branch_for "${envs[0]}")"
    title="chore(ragnarok-breaker): pin ${envs[0]} image to git-$SHORT7"
  else
    branch="$(branch_for combined)"
    title="chore(ragnarok-breaker): bump staging + production image to git-$SHORT7"
  fi

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    echo "error: branch already exists: $branch" >&2
    exit 1
  fi

  git checkout -b "$branch" "$REMOTE/main" --quiet
  for e in "${envs[@]}"; do
    file="$(file_for_env "$e")"
    TAG="$TAG" yq -i '.image.tag = strenv(TAG)' "$file"
    git add "$file"
  done

  if git diff --cached --quiet; then
    echo "error: nothing to commit (tag already $TAG?)" >&2
    git checkout "$ORIGINAL_BRANCH" --quiet
    git branch -D "$branch" --quiet
    exit 1
  fi

  git commit --quiet -m "$title" -m "Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
  git push --quiet -u origin "$branch"

  local body_envs
  if [[ "${#envs[@]}" -eq 1 ]]; then
    body_envs="${envs[0]}"
  else
    body_envs="staging + production"
  fi

  local body
  body=$(cat <<EOF
Pin ragnarok-breaker-worker image to \`$TAG\` for $body_envs.

## Test plan
- [ ] After sync, workers pull the pinned image successfully
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
