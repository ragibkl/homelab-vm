#!/bin/bash
# Dump Coder's Postgres and back it up to Wasabi with restic.
# Run nightly by coder-db-backup.timer, with /etc/coder-backup/env (see
# sample.env). Pushes the result to Gatus (external endpoint
# backup_coder-db), which alerts on a failure or when no push arrives.
set -uo pipefail
umask 077   # the dump holds secrets (keys, tokens)

dir=/var/backups/coder-db
start=$(date +%s)

push() {  # push true|false [error]
    [ -n "${GATUS_PUSH_TOKEN:-}" ] || return 0
    local err base
    err=$(printf %s "${2:-}" | tr -c 'A-Za-z0-9._-' '+' | cut -c1-200)
    for base in ${GATUS_PUSH_URLS:-}; do
        if curl -fsS -m 10 -o /dev/null -X POST \
            -H "Authorization: Bearer $GATUS_PUSH_TOKEN" \
            "$base/api/v1/endpoints/backup_coder-db/external?success=$1&error=$err&duration=$(( $(date +%s) - start ))s"; then
            return 0
        fi
    done
    echo "coder-db-backup: could not push the result to Gatus" >&2
}

fail() {
    echo "coder-db-backup: $1" >&2
    push false "$1"
    exit 1
}

mkdir -p -m 700 "$dir"
db=$(docker compose -p ubuntu-coder ps -q database) && [ -n "$db" ] \
    || fail "database container not running"

# -Fc: compressed custom format, restored with pg_restore. Check the dump
# is readable before it replaces the last good one.
docker exec "$db" pg_dump -U coder -d coder -Fc > "$dir/coder.dump.tmp" \
    || fail "pg_dump failed"
docker exec -i "$db" pg_restore --list < "$dir/coder.dump.tmp" > /dev/null \
    || fail "dump is not readable by pg_restore"
mv "$dir/coder.dump.tmp" "$dir/coder.dump"

# First run: create the repository. On an existing one this only fails.
restic cat config > /dev/null 2>&1 || restic init || fail "restic init failed"

restic backup --host vmbr1-ubuntu-coder --tag coder-db "$dir/coder.dump" \
    || fail "restic backup failed"
restic forget --host vmbr1-ubuntu-coder --tag coder-db \
    --keep-daily 14 --keep-weekly 8 --keep-monthly 12 --prune \
    || fail "restic forget failed"

push true
