#!/bin/bash
#
# Deploy Sylvia-IoT to a Kubernetes cluster.
# Requires kubectl configured and connected to a cluster.
#
# Usage: ./install.sh [OPTIONS]
#
# Options:
#   --with SERVICE,...    Install GUI plugins: lora-ifroglab, app-demo
#   --host HOSTNAME       Hostname for GUI URLs (default: localhost)
#   --port PORT           Port for GUI URLs (default: 80)
#   --uninstall           Remove all resources

if [[ "$1" = "--help" || "$1" = "-h" ]]; then
    sed -n '2,/^[^#]/{ /^#/s/^# \?//p }' "$0"
    exit 0
fi

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$1" = "--uninstall" ]; then
    echo "Removing Sylvia-IoT resources..."
    kubectl delete -k "$SCRIPT_DIR" --ignore-not-found 2>/dev/null || true
    echo "Done."
    exit 0
fi

# Parse options and update settings.env
SETTINGS="$SCRIPT_DIR/settings.env"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --with)
            sed -i "s|^INSTALL_PLUGINS=.*|INSTALL_PLUGINS=$2|" "$SETTINGS"
            shift 2 ;;
        --host)
            sed -i "s|^GUI_HOST=.*|GUI_HOST=$2|" "$SETTINGS"
            shift 2 ;;
        --port)
            sed -i "s|^GUI_PORT=.*|GUI_PORT=$2|" "$SETTINGS"
            shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Read back for display
GUI_HOST=$(grep '^GUI_HOST=' "$SETTINGS" | cut -d= -f2)
GUI_PORT=$(grep '^GUI_PORT=' "$SETTINGS" | cut -d= -f2)
INSTALL_PLUGINS=$(grep '^INSTALL_PLUGINS=' "$SETTINGS" | cut -d= -f2)

if [ "$GUI_PORT" = "80" ]; then
    GUI_BASE="http://$GUI_HOST"
else
    GUI_BASE="http://$GUI_HOST:$GUI_PORT"
fi

# Check kubectl
if ! command -v kubectl &>/dev/null; then
    echo "Error: kubectl not found."
    exit 1
fi

if ! kubectl cluster-info &>/dev/null; then
    echo "Error: cannot connect to Kubernetes cluster."
    exit 1
fi

echo "======================================"
echo "Sylvia-IoT Kubernetes Installer"
[ -n "$INSTALL_PLUGINS" ] && echo "  Plugins: $INSTALL_PLUGINS"
[ "$GUI_HOST" != "localhost" ] && echo "  Host:    $GUI_HOST"
[ "$GUI_PORT" != "80" ] && echo "  Port:    $GUI_PORT"
echo "======================================"

# Delete old jobs (jobs are immutable)
kubectl delete job mongodb-seed platform-init --ignore-not-found 2>/dev/null || true

# Deploy
echo ""
echo "Deploying Sylvia-IoT..."
kubectl apply -k "$SCRIPT_DIR"

echo ""
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=mongodb --timeout=120s 2>/dev/null || true
kubectl wait --for=condition=ready pod -l app=redis --timeout=60s 2>/dev/null || true
kubectl wait --for=condition=ready pod -l app=rabbitmq --timeout=120s 2>/dev/null || true
kubectl wait --for=condition=ready pod -l app=emqx --timeout=120s 2>/dev/null || true
kubectl wait --for=condition=complete job/mongodb-seed --timeout=60s 2>/dev/null || true
kubectl wait --for=condition=ready pod -l app=sylvia-iot-auth --timeout=60s 2>/dev/null || true
kubectl wait --for=condition=ready pod -l app=sylvia-iot-broker --timeout=60s 2>/dev/null || true
kubectl wait --for=condition=ready pod -l app=sylvia-iot-coremgr --timeout=60s 2>/dev/null || true
kubectl wait --for=condition=ready pod -l app=sylvia-iot-data --timeout=60s 2>/dev/null || true
kubectl wait --for=condition=ready pod -l app=sylvia-iot-gui --timeout=60s 2>/dev/null || true

echo ""
echo "Waiting for platform init..."
kubectl wait --for=condition=complete job/platform-init --timeout=120s 2>/dev/null || true
kubectl logs job/platform-init 2>/dev/null | tail -5

echo ""
echo "======================================"
echo "Sylvia-IoT Deployed"
echo "======================================"
echo ""
echo "Credentials:  admin / admin"
echo ""
echo "Access via Ingress or port-forward:"
echo "  kubectl port-forward deploy/sylvia-iot-gui --address=0.0.0.0 ${GUI_PORT}:80"
