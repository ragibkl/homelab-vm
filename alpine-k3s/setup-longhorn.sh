#!/bin/sh
set -e

echo "=== Alpine Longhorn Dependencies Setup ==="
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# Update system
echo "Updating system..."
apk update
apk upgrade

# Install required packages
echo "Installing packages..."
apk add open-iscsi nfs-utils

# Enable iscsid service
rc-update add iscsid default
rc-service iscsid start

# Enable Linux mount propagation
mount --make-rshared /
