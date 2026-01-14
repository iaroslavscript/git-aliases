#!/bin/bash

set -e
set -o pipefail


check_upstream_exists() {
    command git rev-parse --abbrev-ref "HEAD@{u}" >/dev/null 2>&1
}


find_branch() {
    local name="$1"

    command git branch --list --no-color | grep -qE "^\*?\s+${name}$" && echo "${name}"
}


find_remote_branch() {
    command git symbolic-ref refs/remote/origin/HEAD | sed 's@^refs/remotes/origin/@@'
}


find_development_branch() {
    find_branch "development" || find_branch "dev"
}


find_default_branch() {
    find_branch "main" || find_branch "master" \
        || find_development_branch \
        || find_remote_branch
}
