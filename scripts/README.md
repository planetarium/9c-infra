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

### bump-rb-worker.sh

Bump the `planetariumhq/ragnarok-breaker-worker` image tag in staging and/or
production overlays and open a PR against `planetarium/9c-infra`.

```bash
./scripts/bump-rb-worker.sh <hash> [--env staging|production|both] [--separate]
```

- `<hash>`: bare commit hash or `git-<hash>` (auto-normalized, 7–40 hex chars)
- `--env`: default `both`. Pick `staging`, `production`, or `both`
- `--separate`: when `--env both`, open two PRs instead of one combined PR

Requires `git` and `gh` (authenticated via `gh auth login`). Works from any
directory if symlinked into `PATH`:

```bash
ln -s "$PWD/scripts/bump-rb-worker.sh" ~/bin/bump-rb-worker
bump-rb-worker b3cf4800925e0ebb1dd422c5d46928d2e0934000
```

The script refuses to run with a dirty working tree. It branches off the
remote that tracks `planetarium/9c-infra` (`upstream` if present, else
`origin`), commits the tag update, pushes to `origin`, and opens the PR. On
exit (success or failure) it returns to the branch you started from.
