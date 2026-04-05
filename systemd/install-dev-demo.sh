#!/bin/bash
#
# Install dev-demo as a systemd service.
# IoT device demo (Raspberry Pi + sensors + LoRa).
#
# Usage: sudo ./install-dev-demo.sh [--uninstall]

if [[ "$1" = "--help" || "$1" = "-h" ]]; then
    sed -n '2,/^[^#]/{ /^#/s/^# \?//p }' "$0"
    exit 0
fi

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="/usr/local/bin"
SERVICE_DIR="/etc/systemd/system"

if [ "$1" = "--uninstall" ]; then
    echo "Uninstalling dev-demo..."
    systemctl stop dev-demo 2>/dev/null || true
    systemctl disable dev-demo 2>/dev/null || true
    rm -f "$SERVICE_DIR/dev-demo.service"
    systemctl daemon-reload
    rm -f "$BIN_DIR/dev-demo"
    echo "Done."
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: must run as root (sudo ./install-dev-demo.sh)"
    exit 1
fi

ARCH="$(uname -m)"
if [ "$ARCH" = "aarch64" ]; then
    ARCH="arm64"
elif [ "$ARCH" != "x86_64" ]; then
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

echo "Installing dev-demo ($ARCH)..."

if [ ! -f "$BIN_DIR/dev-demo" ]; then
    curl -sL -o /tmp/dev-demo.tar.xz \
        "https://github.com/woofdogtw/sylvia-iot-examples/releases/latest/download/dev-demo-${ARCH}.tar.xz"
    tar xf /tmp/dev-demo.tar.xz -C "$BIN_DIR"
    chmod +x "$BIN_DIR/dev-demo"
    rm -f /tmp/dev-demo.tar.xz
    echo "  Binary installed"
else
    echo "  Binary already installed, skipping"
fi

cp "$SCRIPT_DIR/dev-demo.service" "$SERVICE_DIR/"
systemctl daemon-reload
systemctl enable --now dev-demo
echo "  Service started"

echo ""
echo "Manage:"
echo "  systemctl status dev-demo"
echo "  journalctl -u dev-demo -f"
echo "  sudo ./install-dev-demo.sh --uninstall"
