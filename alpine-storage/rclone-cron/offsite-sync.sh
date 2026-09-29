#!/bin/sh
# Copy or sync each bucket from Garage to its offsite Wasabi bucket.
# Usage: offsite-sync.sh copy|sync
# On success, writes the time to /state/last-<mode> (for monitoring).
set -eu
mode=$1
case $mode in copy|sync) ;; *) echo "usage: $0 copy|sync" >&2; exit 2 ;; esac

# garage bucket : wasabi bucket
BUCKETS="cloud-bancuh-s3:cloud-bancuh-s3"

exec 9>/state/lock
flock -n 9 || { echo "offsite-sync: another run is in progress" >&2; exit 0; }

for pair in $BUCKETS; do
    src=${pair%%:*}; dst=${pair#*:}
    echo "offsite-sync: $mode garage:$src -> wasabi:$dst"
    # --max-delete: a sync from a wrongly empty source would otherwise
    # delete the whole offsite copy.
    rclone "$mode" "garage:$src" "wasabi:$dst" \
        --fast-list --transfers 16 --checkers 32 \
        --max-delete 2000 \
        --stats 5m --stats-one-line --log-level INFO
done
date -Iseconds > "/state/last-$mode"
