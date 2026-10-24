#!/bin/sh
# Install the adb server for the Android test devices passed through from
# Proxmox (run as root on vmbr1-ubuntu-coder, from this directory).
# Keep PT_VERSION equal to the workspace's adb (`adb version`).
set -eu
PT_VERSION=37.0.1
PT_SHA256=d230f13842f60f782a8645f9c813f8f845bf36089ea7289f28c48f17979313f1
apt-get install -y curl unzip
if ! /opt/platform-tools/adb version 2>/dev/null | grep -q "Version $PT_VERSION-"; then
    tmp=$(mktemp -d)
    curl -fsSo "$tmp/pt.zip" "https://dl.google.com/android/repository/platform-tools_r$PT_VERSION-linux.zip"
    echo "$PT_SHA256  $tmp/pt.zip" | sha256sum -c -
    unzip -q "$tmp/pt.zip" -d "$tmp"
    rm -rf /opt/platform-tools
    mv "$tmp/platform-tools" /opt/platform-tools
    rm -rf "$tmp"
fi
getent group plugdev >/dev/null || groupadd --system plugdev
usermod -aG plugdev ragib
install -m 644 51-android-test-devices.rules /etc/udev/rules.d/
udevadm control --reload-rules
udevadm trigger --subsystem-match=usb --action=change
install -m 644 adb-server.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable adb-server
systemctl restart adb-server
sleep 3
sudo -u ragib /opt/platform-tools/adb devices -l
