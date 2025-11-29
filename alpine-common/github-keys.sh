#!/bin/sh

# Usage: github-keys.sh <network>
# Example: github-keys.sh vmbr1

# GitHub base URL and repo
GITHUB_REPO="ragibkl/homelab-vm"
GITHUB_BRANCH="master"

# Auto-detect network from hostname prefix
NETWORK=$(hostname | cut -d'-' -f1)

USERS_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/ssh-users/${NETWORK}.txt"
CACHE_FILE="/tmp/github-keys-${NETWORK}.txt"
CACHE_DURATION=3600

refresh_keys() {
    # Check if cache is still valid
    if [ -f "$CACHE_FILE" ]; then
        CURRENT_TIME=$(date +%s)
        FILE_TIME=$(date -r "$CACHE_FILE" +%s 2>/dev/null || echo 0)
        CACHE_AGE=$((CURRENT_TIME - FILE_TIME))
        
        if [ "$CACHE_AGE" -lt "$CACHE_DURATION" ]; then
            # Cache still valid, no need to refresh
            return 0
        fi
    fi

    # Fetch users file from GitHub
    USERS_CONTENT=$(curl -sf --max-time 5 "$USERS_URL")
    if [ $? -ne 0 ] || [ -z "$USERS_CONTENT" ]; then
        echo "# ERROR: Failed to fetch users file from: $USERS_URL" >&2
        return 1
    fi

    # Parse GitHub usernames (ignore comments and empty lines)
    GITHUB_USERS=$(echo "$USERS_CONTENT" | grep -v '^#' | grep -v '^$' | tr '\n' ' ')
    if [ -z "$GITHUB_USERS" ]; then
        echo "# ERROR: No users found in users file" >&2
        return 1
    fi

    # Fetch keys from all users
    ALL_KEYS=""
    for USER in $GITHUB_USERS; do
        KEYS=$(curl -sf --max-time 5 "https://github.com/${USER}.keys")
        
        if [ $? -eq 0 ] && [ -n "$KEYS" ]; then
            # Add comment to identify which user
            COMMENTED_KEYS=$(echo "$KEYS" | sed "s/$/ # github:${USER}/")
            ALL_KEYS="${ALL_KEYS}${COMMENTED_KEYS}
"
        else
            echo "# WARN: Failed to fetch keys for user: $USER" >&2
        fi
    done

    # Save to cache
    if [ -n "$ALL_KEYS" ]; then
        echo "$ALL_KEYS" > "$CACHE_FILE"
        chmod 600 "$CACHE_FILE"
        return 0
    else
        echo "# ERROR: Failed to fetch any keys from GitHub" >&2
        return 1
    fi
}

# Try to refresh keys
refresh_keys

# Output cached keys (whether fresh or stale)
if [ -f "$CACHE_FILE" ]; then
    cat "$CACHE_FILE"
    exit 0
fi

# No cache available at all
echo "# ERROR: No cached keys available" >&2
exit 1
