#!/bin/bash

set -euo pipefail


cat > "$HOME/.gitconfig" << "EOF"
[user]
	name = $GIT_USERNAME
	email = $GIT_USEREMAIL
[safe]
	directory = /srv/git/handoff.git
EOF

git remote add handoff /srv/git/handoff.git
git push handoff HEAD:refs/heads/tom-work

