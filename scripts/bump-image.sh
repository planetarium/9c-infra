#!/usr/bin/env bash
set -euo pipefail

# Bump a 9c-infra service's image tag in staging and/or production overlays
# and open a PR against planetarium/9c-infra.
#
# Usage: bump-image.sh <service> [<sub-service>] <hash> [--env staging|production|both] [--separate]
#
#   <service>      Service id. Discovered from scripts/bump-modules/<service>.sh.
#                  Use --help to list available services.
#   <sub-service>  Required only when the module declares SUB_SERVICES (e.g. `rb`).
#                  Picks which workload's image.tag to bump. Omit to bump every
#                  sub-service at once (requires the module to define
#                  resolve_all_sub_services).
#   <hash>         Image tag. Bare hash (e.g. abc123...) or git-<hash>; auto normalized.
#   --env          default: both. Pick dev/staging/production/both/all.
#                  `both` = staging + production (legacy alias).
#                  `all`  = dev + staging + production.
#   --separate     when --env both, open two PRs instead of one combined PR.
#
# Requires: git, gh (authenticated), yq (v4+).
#
# Adding a new flat service: create scripts/bump-modules/<id>.sh and set:
#   SERVICE_LABEL, COMMIT_SCOPE, BRANCH_PREFIX,
#   STAGING_FILE, PRODUCTION_FILE, TAG_KEYS=(".foo.image.tag" ...).
#
# Adding a service with multiple workloads: also set
#   SUB_SERVICES=(name1 name2 ...) and define `resolve_sub_service()` to set
#   TAG_KEYS / SERVICE_LABEL / BRANCH_PREFIX for the chosen sub-service.
#   Optionally define `resolve_all_sub_services()` to enable the
#   `bump-image.sh <service> <hash>` shortcut (no sub-service), which bumps
#   every workload in one PR.

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

# Source a module in a subshell and echo its SUB_SERVICES (one per line, empty
# if none). Used by usage() so we don't pollute the outer shell's vars.
sub_services_for() {
  (
    SUB_SERVICES=()
    # shellcheck disable=SC1090
    source "$MODULE_DIR/$1.sh" >/dev/null 2>&1 || exit 0
    if [[ "${#SUB_SERVICES[@]}" -gt 0 ]]; then
      printf '%s\n' "${SUB_SERVICES[@]}"
    fi
  )
}

supports_all() {
  (
    # shellcheck disable=SC1090
    source "$MODULE_DIR/$1.sh" >/dev/null 2>&1 || exit 1
    declare -F resolve_all_sub_services >/dev/null
  )
}

usage() {
  sed -n '4,30p' "$SCRIPT_PATH" | sed 's/^# \{0,1\}//'
  echo "Available services:"
  local s subs suffix
  for s in $(list_services); do
    subs="$(sub_services_for "$s" | paste -sd ' ' -)"
    if [[ -n "$subs" ]]; then
      suffix=""
      supports_all "$s" && suffix=", or omit for all"
      echo "  - $s (sub: $subs$suffix)"
    else
      echo "  - $s"
    fi
  done
}

ENV="both"
SEPARATE=0
POSITIONALS=()
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
      POSITIONALS+=("$1")
      shift
      ;;
  esac
done

SERVICE="${POSITIONALS[0]:-}"
if [[ -z "$SERVICE" ]]; then
  usage >&2
  exit 1
fi

MODULE_FILE="$MODULE_DIR/${SERVICE}.sh"
if [[ ! -f "$MODULE_FILE" ]]; then
  echo "error: unknown service '$SERVICE' (no $MODULE_FILE)" >&2
  echo "available: $(list_services | paste -sd ' ' -)" >&2
  exit 1
fi

# Load service module. May set SUB_SERVICES + resolve_sub_service(), or set
# SERVICE_LABEL / BRANCH_PREFIX / TAG_KEYS directly (flat module).
# COMMIT_SCOPE / STAGING_FILE / PRODUCTION_FILE are always required.
SERVICE_LABEL=""
COMMIT_SCOPE=""
BRANCH_PREFIX=""
STAGING_FILE=""
PRODUCTION_FILE=""
TAG_KEYS=()
SUB_SERVICES=()
# shellcheck disable=SC1090
source "$MODULE_FILE"

SUB=""
HASH=""
# A "hash-like" token: bare 7–40 hex chars or a git-<hash> form. Used to detect
# whether the user typed `bump-image.sh rb <hash>` (bulk) vs
# `bump-image.sh rb <sub> <hash>`.
is_hashlike() {
  [[ "$1" =~ ^(git-)?[0-9a-f]{7,40}$ ]]
}
if [[ "${#SUB_SERVICES[@]}" -gt 0 ]]; then
  SUB="${POSITIONALS[1]:-}"
  HASH="${POSITIONALS[2]:-}"
  # Bulk shortcut: only one trailing positional and it looks like a hash.
  # Treat as "all sub-services" if the module supports it.
  if [[ -z "$HASH" && -n "$SUB" ]] && is_hashlike "$SUB"; then
    if ! declare -F resolve_all_sub_services >/dev/null; then
      echo "error: service '$SERVICE' requires <sub-service> and <hash>" >&2
      echo "available sub-services: ${SUB_SERVICES[*]}" >&2
      exit 1
    fi
    HASH="$SUB"
    SUB=""
    resolve_all_sub_services || exit 1
  else
    if [[ -z "$SUB" || -z "$HASH" ]]; then
      echo "error: service '$SERVICE' requires <sub-service> and <hash>" >&2
      echo "available sub-services: ${SUB_SERVICES[*]}" >&2
      if declare -F resolve_all_sub_services >/dev/null; then
        echo "(omit <sub-service> to bump every sub-service at once)" >&2
      fi
      exit 1
    fi
    if [[ "${#POSITIONALS[@]}" -gt 3 ]]; then
      echo "error: unexpected positional arg: ${POSITIONALS[3]}" >&2
      exit 1
    fi
    if ! declare -F resolve_sub_service >/dev/null; then
      echo "error: module $MODULE_FILE declared SUB_SERVICES but no resolve_sub_service()" >&2
      exit 1
    fi
    resolve_sub_service "$SUB" || exit 1
  fi
else
  HASH="${POSITIONALS[1]:-}"
  if [[ -z "$HASH" ]]; then
    usage >&2
    exit 1
  fi
  if [[ "${#POSITIONALS[@]}" -gt 2 ]]; then
    echo "error: unexpected positional arg: ${POSITIONALS[2]}" >&2
    exit 1
  fi
fi

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
  # Modules may define *_FILES (bash array) when one env covers multiple
  # values files — e.g. legacy single-ns values plus per-tier overlays during
  # a cutover. Falls back to the single *_FILE variable for modules that only
  # touch one path per env.
  case "$1" in
    dev)
      if [[ "${#DEV_FILES[@]:-0}" -gt 0 ]]; then
        printf '%s\n' "${DEV_FILES[@]}"
      elif [[ -n "${DEV_FILE:-}" ]]; then
        echo "$DEV_FILE"
      else
        echo "error: module did not define DEV_FILES or DEV_FILE for --env dev" >&2
        return 1
      fi
      ;;
    staging)
      if [[ "${#STAGING_FILES[@]:-0}" -gt 0 ]]; then
        printf '%s\n' "${STAGING_FILES[@]}"
      else
        echo "$STAGING_FILE"
      fi
      ;;
    production)
      if [[ "${#PRODUCTION_FILES[@]:-0}" -gt 0 ]]; then
        printf '%s\n' "${PRODUCTION_FILES[@]}"
      else
        echo "$PRODUCTION_FILE"
      fi
      ;;
    *)
      echo "error: invalid env: $1" >&2
      return 1
      ;;
  esac
}

branch_for() {
  # $1: dev | staging | production | combined
  case "$1" in
    dev)        echo "${BRANCH_PREFIX}-dev-image-$SHORT8" ;;
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
  local branch title file body body_envs e workload_part
  workload_part=""
  if [[ -n "$SUB" ]]; then
    workload_part=" $SUB"
  fi

  if [[ "${#envs[@]}" -eq 1 ]]; then
    branch="$(branch_for "${envs[0]}")"
    title="chore(${COMMIT_SCOPE}): pin ${envs[0]}${workload_part} image to git-$SHORT7"
    body_envs="${envs[0]}"
  else
    branch="$(branch_for combined)"
    local envs_join
    printf -v envs_join '%s + ' "${envs[@]}"
    envs_join="${envs_join% + }"
    title="chore(${COMMIT_SCOPE}): bump ${envs_join}${workload_part} image to git-$SHORT7"
    body_envs="$envs_join"
  fi

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    echo "error: branch already exists: $branch" >&2
    exit 1
  fi

  git checkout -b "$branch" "$REMOTE/main" --quiet
  for e in "${envs[@]}"; do
    while IFS= read -r file; do
      [[ -z "$file" ]] && continue
      update_file_tags "$file"
      git add "$file"
    done < <(file_for_env "$e")
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
Pin ${SERVICE_LABEL} to \`$TAG\` for $body_envs.

## Test plan
- [ ] After sync, pods pull the pinned image successfully
EOF
)

  # Derive the PR head ref from origin's GitHub owner so this works whether
  # `origin` is the planetarium repo (same-repo PR) or a personal fork
  # (cross-fork PR). The branch was pushed to `origin` just above, so the head
  # owner must match origin's owner. Previously hardcoded to "Atralupus:".
  local origin_owner head_ref
  origin_owner="$(git remote get-url origin 2>/dev/null | sed -E 's#^.*github\.com[:/]([^/]+)/.*$#\1#')"
  if [[ -n "$origin_owner" && "$origin_owner" != "planetarium" ]]; then
    head_ref="${origin_owner}:${branch}"
  else
    head_ref="$branch"
  fi

  gh pr create \
    --repo planetarium/9c-infra \
    --base main \
    --head "$head_ref" \
    --title "$title" \
    --body "$body"
}

case "$ENV" in
  dev|staging|production)
    bump_and_pr "$ENV"
    ;;
  both)
    # Legacy alias for staging + production (predates the dev env). Kept so
    # existing automation keeps working; prefer `all` for full coverage.
    if [[ $SEPARATE -eq 1 ]]; then
      bump_and_pr staging
      git checkout "$ORIGINAL_BRANCH" --quiet
      bump_and_pr production
    else
      bump_and_pr staging production
    fi
    ;;
  all)
    if [[ $SEPARATE -eq 1 ]]; then
      bump_and_pr dev
      git checkout "$ORIGINAL_BRANCH" --quiet
      bump_and_pr staging
      git checkout "$ORIGINAL_BRANCH" --quiet
      bump_and_pr production
    else
      bump_and_pr dev staging production
    fi
    ;;
  *)
    echo "error: invalid --env: $ENV (expected dev|staging|production|both|all)" >&2
    exit 1
    ;;
esac
