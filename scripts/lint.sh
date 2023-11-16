#!/usr/bin/env bash

set -e
set -x

mypy app
black app tests --check  --line-length=89
isort app tests --check-only
