#!/bin/bash

set -euo pipefail

PR="$1" # PR number passed as an argument
BASE="${2:-main}" # Base branch, default to 'main'

command git checkout "$BASE"
command git pull --ff-only origin "$BASE"

# Fetch the PR's head into temporary branch FETCH_HEAD
command git fetch origin "pull/$PR/head"

command git merge --no-ff -S -m "Merge pull request #$PR" FETCH_HEAD

# Push to protected branch (must be allowed by branch protection rule)
command git push origin "HEAD:$BASE"

# Optional: verify signature
command git log --show-signature -1

