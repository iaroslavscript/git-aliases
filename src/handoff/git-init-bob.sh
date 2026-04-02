#!/bin/bash

set -euo pipefail


REPO_BASE_DIR="${REPO_BASE_DIR:-/srv/git}"


function usage {
	echo "Usage: git-init-bob ORIGIN_URL"
	echo "   URIGIN_URL - git repository url in ssh format, i.e. git@hostname:username/reponame.git"
}


if [[ $# -ne 1 ]]; then
    echo "Error: No argument provided." >&2
    usage
    exit 1
fi

# Note: Do NOT quote the regex variable in the 'if' statement
pattern='^git@([[:alnum:]_-]+):([[:alnum:]_-/]+\.git)$'

if [[ $1 =~ $pattern ]]; then
    ORIGIN_URL="$1"
    HANDOFF_REPO_PATH="${REPO_BASE_DIR}/handoff/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    REPO_PATH="${REPO_BASE_DIR}/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}" 
else
    echo "Error: Argument '$1' does not match the required pattern: git@hostname:username/reponame.git" >&2
    exit 1
fi

git init --bare "${HANDOFF_REPO_PATH}"

chown -R bob:handoff "${HANDOFF_REPO_PATH}"
chmod -R 2770 "${HANDOFF_REPO_PATH}"

git init "${REPO_PATH}"
git --git-dir="${REPO_PATH}" remote add origin "${ORIGIN_URL}"
git --git-dir="${REPO_PATH}" remote add handoff "${HANDOFF_REPO_PATH}"

