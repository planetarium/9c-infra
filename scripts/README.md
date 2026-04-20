## Prerequisite

**.env**
- GITHUB_TOKEN: 1password k8s-github-token or your github token(required org:read permission)
- SLACK_TOKEN: 1password Slack Token
- KEY_PASSPHRASE: used for apv signing
- KEY_ADDRESS: used for apv signing

**boto3**
- aws_access_key_id, aws_secret_access_key: $aws configure (~/.aws/credentials)

**Installation**
- required [planet](https://www.npmjs.com/package/@planetarium/cli)
- python 3.9.10

**Python**
```python
# cd ./py-scripts
$ python -m venv .venv
$ . .venv/bin/activate
$ pip install -r requirements-dev.txt
$ flit install --extras all
```

## Usage

**Run cli**

```bash
python cli.py --help
```

## Image bump scripts

### bump-image.sh

Bump a service's image tag in staging and/or production overlays and open a
PR against `planetarium/9c-infra`.

```bash
./scripts/bump-image.sh <service> <hash> [--env staging|production|both] [--separate]
```

- `<service>`: one of the ids discovered from `scripts/bump-modules/<id>.sh`. Run
  `./scripts/bump-image.sh --help` for the current list. Currently supported:
  `rb` (ragnarok-breaker-worker), `iap`, `seasonpass`, `arena`
- `<hash>`: bare commit hash or `git-<hash>` (auto-normalized, 7–40 hex chars)
- `--env`: default `both`. Pick `staging`, `production`, or `both`
- `--separate`: when `--env both`, open two PRs instead of one combined PR

Requires `git`, `gh` (authenticated via `gh auth login`), and `yq` v4+. Works
from any directory if symlinked into `PATH`:

```bash
ln -s "$PWD/scripts/bump-image.sh" ~/bin/bump-image
bump-image rb b3cf4800925e0ebb1dd422c5d46928d2e0934000
bump-image iap 1f5add5c11506199b4a6dc7f7128f395400f632a --env production
```

The script refuses to run with a dirty working tree. It branches off the
remote that tracks `planetarium/9c-infra` (`upstream` if present, else
`origin`), edits only the specific `tag:` line(s) via `yq`-sourced line
numbers + `sed` (so blank lines and comments are preserved), commits, pushes
to `origin`, and opens the PR. On exit (success or failure) it returns to the
branch you started from.

#### Adding a new service

Create `scripts/bump-modules/<id>.sh` and set the module variables. Example
(`rb.sh`):

```bash
SERVICE_LABEL="ragnarok-breaker-worker"
COMMIT_SCOPE="ragnarok-breaker"          # appears in commit/PR subject
BRANCH_PREFIX="ragnarok-breaker"         # used in branch names
STAGING_FILE="9c-internal/ragnarok-breaker-staging/values.yaml"
PRODUCTION_FILE="9c-main/ragnarok-breaker-production/values.yaml"
TAG_KEYS=(".image.tag")                  # yq paths to every tag to update
```

`TAG_KEYS` can list multiple paths when a single service version covers
several subcomponents (api, worker, backoffice, ...).
