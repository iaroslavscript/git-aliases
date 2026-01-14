#!/bin/bash

set -e
set -o pipefail


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
    # shellcheck source=src/scripts/common.sh
    source "$SCRIPT_DIR/common.sh"
else
    # shellcheck source=/dev/null
    source ~/.git-scripts/common.sh
fi


do_checkout_default() {
    local branch
    branch="$(find_default_branch)"

    if [[ -n "$branch" ]]; then
        command git checkout "$branch"
    else
        echo "error: no local or remote default branch found" > /dev/stderr
        false
    fi
}


do_checkout_default
