#!/bin/bash

# Sylvia-IoT Services Status Script
#
# Usage: ./status.sh

if [[ "$1" = "--help" || "$1" = "-h" ]]; then
    sed -n '2,/^[^#]/{ /^#/s/^# \?//p }' "$0"
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Sylvia-IoT Services Status"
echo "======================================"

check_process() {
    local label="$1"
    local name="$2"
    local pid_file="$SCRIPT_DIR/${name}.pid"

    echo ""
    echo "$label:"
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo "  Running (PID: $pid)"
        else
            echo "  Not running (stale PID file)"
        fi
    else
        echo "  Not running"
    fi
}

check_api() {
    local url="$1"
    if curl -s "$url" > /dev/null 2>&1; then
        echo "  API responding: $url"
    else
        echo "  API not responding"
    fi
}

check_container() {
    local label="$1"
    local name="$2"
    local info="$3"

    echo ""
    echo "$label:"
    if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
        echo "  Running"
        [ -n "$info" ] && echo "  $info"
    elif docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
        echo "  Stopped (container exists)"
    else
        echo "  Not found"
    fi
}

# Main binaries
for name in sylvia-iot-core sylvia-router; do
    pid_file="$SCRIPT_DIR/${name}.pid"
    [ -f "$pid_file" ] || continue
    check_process "$name" "$name"
    check_api "http://localhost:1080/version"
done

# Optional services
for name in lora-ifroglab app-demo; do
    pid_file="$SCRIPT_DIR/${name}.pid"
    [ -f "$pid_file" ] || continue
    check_process "$name" "$name"
done

# Docker
echo ""
echo "Docker:"
if docker info > /dev/null 2>&1; then
    echo "  Running"
else
    echo "  Not running"
fi

check_container "RabbitMQ" "sylvia-rabbitmq" "http://localhost:15672  (guest/guest)"
check_container "EMQX" "sylvia-emqx" "http://localhost:18083  (admin/public)"
check_container "MongoDB" "sylvia-mongodb" "localhost:27017"
check_container "Redis" "sylvia-redis" "localhost:6379"

# Installed components
echo ""
echo "======================================"
echo "Installed Components"
echo "======================================"
VERSIONS_DIR="$SCRIPT_DIR/.versions"
if [ -d "$VERSIONS_DIR" ] && [ -n "$(ls -A "$VERSIONS_DIR" 2>/dev/null)" ]; then
    for vfile in "$VERSIONS_DIR"/*; do
        [ -f "$vfile" ] || continue
        echo "  $(basename "$vfile"): $(cat "$vfile")"
    done
else
    echo "  None installed yet (run: ./update.sh <component>)"
fi

echo ""
echo "======================================"
echo "Endpoints"
echo "======================================"
echo "  Auth:     http://localhost:1080/auth"
echo "  Broker:   http://localhost:1080/broker"
echo "  Coremgr:  http://localhost:1080/coremgr"
echo "  Data:     http://localhost:1080/data"
echo ""
echo "Credentials: admin / admin"
