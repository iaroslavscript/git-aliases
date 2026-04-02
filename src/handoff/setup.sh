#/bin/bash

set -euo pipefail


if (( $EUID != 0 )); then
    echo "This script must be run as root. Exiting."
    exit 1
fi


REPO_BASE_DIR="${REPO_BASE_DIR:-/srv/git}"


groupadd -f handoff
usermod -aG handoff tom
usermod -aG handoff bob

mkdir -p $REPO_BASE_DIR
chmod -R bob:bob $REPO_BASE_DIR

