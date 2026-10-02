#!/bin/sh
set -e

# Add a swapfile, so a burst of memory use slows the VM down instead of
# getting processes OOM-killed. Low swappiness keeps it as a safety net:
# the kernel only swaps when RAM is nearly full.
#
# Usage: sudo ./setup-swap.sh [size]   (default 4G)

SIZE=${1:-4G}
SWAPFILE=/swapfile

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

if swapon --show=NAME --noheadings | grep -qx "$SWAPFILE"; then
    echo "$SWAPFILE is already in use"
else
    fallocate -l "$SIZE" "$SWAPFILE"
    chmod 600 "$SWAPFILE"
    mkswap "$SWAPFILE" >/dev/null
    swapon "$SWAPFILE"
    echo "Enabled $SIZE of swap at $SWAPFILE"
fi

grep -q "^$SWAPFILE " /etc/fstab || echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab

echo "vm.swappiness=10" > /etc/sysctl.d/90-swap.conf
sysctl -q -p /etc/sysctl.d/90-swap.conf

free -m
