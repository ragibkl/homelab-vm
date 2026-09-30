#!/bin/sh
# Copy or sync each bucket from Garage to its offsite Wasabi bucket.
# Usage: offsite-sync.sh copy|sync
# On success, writes the time to /state/last-<mode>. Either way, pushes the
# result to Gatus (external endpoint storage_offsite-<mode>), which alerts on
# a failure or when no push arrives in time.
set -u
mode=${1:-}
case $mode in copy|sync) ;; *) echo "usage: $0 copy|sync" >&2; exit 2 ;; esac

# garage bucket : wasabi bucket
BUCKETS="cloud-bancuh-s3:cloud-bancuh-s3"

# GATUS_PUSH_URLS: base URLs to try in turn (the gatus-push NodePort on each
# k3s node; only the node running Gatus answers). GATUS_PUSH_TOKEN: bearer.
push() {  # push true|false [error]
    [ -n "${GATUS_PUSH_TOKEN:-}" ] || return 0
    err=$(printf %s "${2:-}" | tr -c 'A-Za-z0-9._-' '+' | cut -c1-200)
    for base in ${GATUS_PUSH_URLS:-}; do
        if wget -q -T 10 -O /dev/null --post-data "" \
            --header "Authorization: Bearer $GATUS_PUSH_TOKEN" \
            "$base/api/v1/endpoints/storage_offsite-$mode/external?success=$1&error=$err&duration=$(( $(date +%s) - start ))s"; then
            return 0
        fi
    done
    echo "offsite-sync: could not push the result to Gatus" >&2
}

exec 9>/state/lock
flock -n 9 || { echo "offsite-sync: another run is in progress" >&2; exit 0; }

start=$(date +%s)
failed=""
for pair in $BUCKETS; do
    src=${pair%%:*}; dst=${pair#*:}
    echo "offsite-sync: $mode garage:$src -> wasabi:$dst"
    # --max-delete: a sync from a wrongly empty source would otherwise
    # delete the whole offsite copy.
    rclone "$mode" "garage:$src" "wasabi:$dst" \
        --fast-list --transfers 16 --checkers 32 \
        --max-delete 2000 \
        --stats 5m --stats-one-line --log-level INFO \
        || failed="$failed $src"
done

if [ -n "$failed" ]; then
    echo "offsite-sync: $mode failed for:$failed" >&2
    push false "rclone $mode failed for$failed"
    exit 1
fi
date -Iseconds > "/state/last-$mode"
push true
