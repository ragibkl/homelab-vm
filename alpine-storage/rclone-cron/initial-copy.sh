#!/bin/sh
# One-off: copy a bucket from Wasabi into Garage before cutting an app over.
# Usage: initial-copy.sh <bucket> [bwlimit]   (bwlimit in bytes/s, e.g. 30M
# = 30 MiB/s ~ 250 Mbit/s)
# Needs a Garage key with write access in RCLONE_CONFIG_GARAGEW_* (the
# offsite-sync key is read-only), e.g. a temporary one:
#   garage key create initial-copy --expires-in 2d
set -eu
bucket=$1; bwlimit=${2:-30M}
rclone copy "wasabi:$bucket" "garagew:$bucket" \
    --fast-list --transfers 32 --checkers 32 \
    --bwlimit "$bwlimit" \
    --stats 1m --stats-one-line --log-level INFO
