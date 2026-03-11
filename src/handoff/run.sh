#!/bin/bash

set -euo pipefail

BOT_GNUPGNOME="/home/bob/.config/sign-bot/gnupg"
CLIENT_GNUPGHOME="/home/bob/.config/sign-bot/gnupg-client"
CONTAINER_GITCONFIG="/home/bob/.config/sign-bot/gitconfig-container"
PGP_AGENT_SOCK="$(GNUPGHOME="$BOT_GNUPGHOME" gpgconf --list-dirs agent-socket)"
USE_EXISTING_SSH_AGENT="{USE_EXISTING_SSH_AGENT:-0}"


start_agent=0
cleanup() {
    if [[ "$start_agent" == "1" ]]; then
        ssh-agent -k > /dev/null 2>&1 || true
        rm -f "SSH_AGENT_SOCK_HOST" || true
    fi
}
trap cleanup EXIT

if [[ "$USE_EXISTING_SSH_AGENT" == "1" ]]; then
    if [[ -z "${SSH_AUTH_SOCK:-}" || ! -S "$SSH_AUTH_SOCK" ]]; then
        echo "ERROR: SSH_AUTH_SOCK is not a unix socket: ${SSH_AUTH_SOCK:-<empty>}" >&2
        exit 1
    fi

    SSH_AGENT_SOCK_HOST="$SSH_AUTH_SOCK"
else
    mkdir -p /home/bob/.config/sign-bot
    chmod 0700 /home/bob/.config/sign-bot
    SSH_AGENT_SOCK_HOST="/home/bob/.config/sign-bot/ssh-agent.sock"
    rm -f "$SSH_AGENT_SOCK_HOST"

    eval "$(ssh-agent -a $SSH_AGENT_SOCK_HOST)"
    start_agent=1

    if [[ ! -S "$SSH_AGENT_SOCK_HOST" ]]; then
        echo "ERROR: ssh-agent socket not created: $SSH_AGENT_SOCK_HOST" >&2
        exit 1
    fi
    ssh-add /home/bob/.ssh/github_deploy_ed25519 > /dev/null
    ssh-add -l > /dev/null || {
        echo "ERROR: NO SSH keys loaded in ssh-agent." >&2
        exit 1
    }
fi

podman run --rm \
    -v /home/bob/.local/bin/:/usr/local/bin:ro \
    -v /home/bob/repos/project:/repo:Z \
    -v /srv/git:/srv/git:Z \
    --mount type=bind,src="$SSH_AGENT_SOCK_HOST",dst=/ssh-agent.sock,relabel=shared \
    -v "$CLIENT_GNUPGHOME":/gnupg:Z \
    -v "$PGP_AGENT_SOCK":/gpupg/S.gpg-agent \
    -v "$CONTAINER_GITCONFIG":/etc/gitconfig-bob:ro,Z \
    -e SSH_AUTH_SOCK=/ssh-agent.sock \
    -e GNUPGHOME=/gnupg \
    -e GIT_CONFIG_GLOBAL=/etc/gitconfig-bob \
    -e REPO_DIR=/repo \
    -e HANDOFF_REMOTE=handoff \
    -e ORIGIN_REMOTE=origin \
    -e PUSH_TAGS=0 \
    -w /repo \
    localhost/sign-bot \
    /bin/sh -lc '/usr/local/bin/sync-handoff-to-github.sh'

