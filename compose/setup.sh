#!/bin/bash
#
# Sylvia-IoT Docker Compose setup script.
#
# Usage: ./setup.sh [OPTIONS]
#
# Options:
#   --with SERVICE,...    Install GUI plugins: lora-ifroglab, app-demo
#   --host HOSTNAME       Hostname for GUI URLs (default: localhost)
#   --port PORT           GUI listen port (default: 80)
#   --down                Stop and remove containers
#   --down-v              Stop and remove containers and volumes

if [[ "$1" = "--help" || "$1" = "-h" ]]; then
    sed -n '2,/^[^#]/{ /^#/s/^# \?//p }' "$0"
    exit 0
fi

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$1" = "--down-v" ]; then
    docker compose -f "$SCRIPT_DIR/docker-compose.yaml" down -v
    exit 0
elif [ "$1" = "--down" ]; then
    docker compose -f "$SCRIPT_DIR/docker-compose.yaml" down
    exit 0
fi

# Parse arguments and update .env
while [[ $# -gt 0 ]]; do
    case "$1" in
        --with)
            sed -i "s|^INSTALL_PLUGINS=.*|INSTALL_PLUGINS=$2|" "$SCRIPT_DIR/.env"
            shift 2 ;;
        --host)
            sed -i "s|^GUI_HOST=.*|GUI_HOST=$2|" "$SCRIPT_DIR/.env"
            shift 2 ;;
        --port)
            sed -i "s|^GUI_PORT=.*|GUI_PORT=$2|" "$SCRIPT_DIR/.env"
            shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

source "$SCRIPT_DIR/.env"
GUI_HOST="${GUI_HOST:-localhost}"
GUI_PORT="${GUI_PORT:-80}"

if [ "$GUI_PORT" = "80" ]; then
    GUI_URL="http://$GUI_HOST"
else
    GUI_URL="http://$GUI_HOST:$GUI_PORT"
fi

echo "======================================"
echo "Sylvia-IoT Docker Compose Setup"
echo "  URL:     $GUI_URL"
[ -n "$INSTALL_PLUGINS" ] && echo "  Plugins: $INSTALL_PLUGINS"
echo "======================================"
echo ""

docker compose -f "$SCRIPT_DIR/docker-compose.yaml" up -d

echo ""
echo "Waiting for platform init to complete..."
docker compose -f "$SCRIPT_DIR/docker-compose.yaml" logs -f platform-init 2>/dev/null || true

echo ""
echo "======================================"
echo "Sylvia-IoT Ready"
echo "======================================"
echo ""
echo "GUI:          $GUI_URL"
echo "Credentials:  admin / admin"
echo ""
echo "Stop:   ./setup.sh --down"
echo "Remove: ./setup.sh --down-v"
