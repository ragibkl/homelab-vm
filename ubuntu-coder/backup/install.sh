#!/bin/sh
# Install the nightly Coder Postgres backup (run as root on vmbr1-ubuntu-coder,
# from this directory). /etc/coder-backup/env must exist first (sample.env).
set -eu
[ -f /etc/coder-backup/env ] || { echo "create /etc/coder-backup/env first (see sample.env)" >&2; exit 1; }
apt-get install -y restic curl
install -m 755 coder-db-backup.sh /usr/local/sbin/coder-db-backup.sh
install -m 644 coder-db-backup.service coder-db-backup.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now coder-db-backup.timer
systemctl list-timers coder-db-backup.timer
