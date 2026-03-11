#/bin/bash

set -euo pipefail

sudo groupadd -f handoff
sudo usermod -aG handoff tom
sudo usermod -aG handoff bob

sudo mkdir -p /srv/git
sudo git init --bare /srv/git/handoff.git

sudo chown -R bob:handoff /srv/git/handoff.git
sudo chmod -R 2770 /srv/git/handoff.git

