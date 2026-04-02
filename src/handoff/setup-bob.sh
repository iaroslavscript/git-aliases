#!/bin/bash 

set -euo pipefail


GENERATE_GPG_KEY="${GENERATE_GPG_KEY:-0}"


function generate_deploy_key {

    local keyfile="$HOME/.ssh/github_deploy_ed25519"
    ssh-keygen -t ed25519 -f "$keyfile" -C "bob-sync deploy key $(date)"
    chmod 0600 "$keyfile"

    local hostalias='github-deploy'
    if [[ ! -f "$HOME/.ssh/config" ]] || ! grep -q "Host $hostalias" "$HOME/.ssh/config" > /dev/null 2>&1 ; then 
        cat <<EOF | sed 's/^.*|//' >> "$HOME/.ssh/config"
	    |
            |Host $hostalias
	    |    HostName github.com
	    |    User git
	    |    IdentityFile $keyfile
	    |    IdentitiesOnly yes
EOF
   fi
}


function generate_gpg_key {

    # Create a dedicated GPG hoem for the bot bob-sync
    # NOTE: Currently this generates a key WITHOUT a passphrase.
    export GNUPGHOME="$HOME/.config/bob-sync/gnupg"
    mkdir -p "$GNUPGHOME"
    chmod 0700 "$GNUPGHOME"

    if ! gpg --homedir "$GNUPGHOME" --list-secret-keys --with-colons | grep -q '^sec:'; then
        cat <<EOF | sed 's/^.*|//' > "$GNUPGHOME/keygen-batch"
            |Key-Type: eddsa
            |Key-Curve: ed25519
            |Key-Usage: sign
            |Name-Real: $GIT_USERNAME
            |Name-Email: $GIT_USEREMAIL
            |Expire-Date: 0
            |%no-protection
            |%commit
EOF

	gpg --homedir "$GNUPGHOME" --batch --generate-key "$GNUPGHOME/keygen-batch"
	rm -f "$GNUPGHOME/keygen-batch"
    fi

    SIGNING_FPR="$(gpg --homedir "$GNUPGHOME" --list-secret-keys --with-colons | awk -F: '/^fpr:/{print $10; exit}')"
    if [[ -z "$SIGNING_FPR" ]]; then
        echo "ERROR: Cound not determine  GPG keys fingerprint in $GNUPGHOME" >&2
        exit 1
    fi

    # Export a public key you can paste into GitHub.
    gpg --homedir "$GNUPGHOME" --batch --import "$HOME/.config/bob-sync/bob-sync-publickey.asc" > /dev/null 2>&1 || true

    # A minimal GNUPGHOME for th econtainer client (public keys only).
    CLIENT_GNUPGHOME="$HOME/.config/bob-sync/gnupg-client"
    mkdir -p "$CLIENT_GNUPGHOME"
    chmod 0700 "$CLIENT_GNUPGHOME"
    gpg --homedir "$GNUPGHOME" --armor --export "$SIGNING_FPR" > "$HOME/.config/bob-sync/bob-sync-publickey.asc"

    # Ensure gpg-agent is running for the bot key home
    gpgconf --homedir "$GNUPGHOME" --launch gpg-agent

    # Wrapper so Git can sign without needing GNUPGHOME exported.
    # Git's gpg.program must be a single executable path (no inline args).
    mkdir -p "$HOME/.local/bin"
    cat <<EOF | sed 's/^.*|//' > "$HOME/.localbin/gpg-bob-sync"
        |#!/bin/sh
        |
        |exec gpg --homedir "$GNUPGHOME" "\$@"
	|
EOF
    chmod 0700 "$HOME/.local/bin/gpg-bob-sync"

    # Minimal, safe gitconfig for containers (uses forwarded gpg-agent)
    cat <<EOF | sed 's/^.*|//' > "$HOME/.config/bob-sync/gitconfig-container"
        |[init]
        |     defaultBranch = main
        |[core]
        |    hooksPath = /dev/null  # Hardening
        |    pager = cat  # Hardening
        |[user]
        |    name = $GIT_USERNAME
        |    email = $GIT_USEREMAIL
        |    singingKey = $SINGING_FPR
        |[commit]
        |    gpgsign = true
        |[tag]
        |    gpgsign = true
        |[gpg]
        |    format = opengpg
        |    # Should we use an absolute path here?
        |    program = gpg
        |[submodule]
        |    resque = false  # Hardening
        |[fetch]
        |    fsckObjects = true  # Hardening
        |[transfer]
        |    fsckObjects = true  # Hardening
EOF
}


function generate_bob_minimal_git_config {
    # Bob's minimal, safe gitconfig (all git operations MUST be done in containers)
    cat <<EOF | sed 's/^.*|//' > "$HOME/.gitconfig"
    |[init]
    |    defaultBranch = main
    |[core]
    |    hooksPath = /dev/null  # Hardening
    |    pager = cat  # Hardening
    |[submodule]
    |    resque = false  # Hardening
    |[fetch]
    |    fsckObjects = true  # Hardening
    |[transfer]
    |    fsckObjects = true  # Hardening
EOF
}


function do_setup_bob {
    mkdir -p ~/.ssh
    chmod 0700 ~/.ssh

    mkdir -p ~/.config/bob-sync
    chmod 0700 ~/.config/bob-sync

    generate_deploy_key

    if [[ "$GENERATE_GPG_KEY" == 1 ]]; then
        generate_gpg_key
    fi

    generate_bob_minimal_git_config
}


do_setup_bob

