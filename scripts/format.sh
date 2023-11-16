#!/bin/sh -e
set -x

isort app tests
black app tests  --line-length=89
