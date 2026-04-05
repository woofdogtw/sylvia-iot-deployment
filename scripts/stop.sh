#!/bin/bash

# Sylvia-IoT Services Stop Script
#
# Usage: ./stop.sh

if [[ "$1" = "--help" || "$1" = "-h" ]]; then
    sed -n '2,/^[^#]/{ /^#/s/^# \?//p }' "$0"
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Stopping Sylvia-IoT Services"
echo "======================================"

stop_process() {
    local name="$1"
    local pid_file="$SCRIPT_DIR/${name}.pid"

    if [ ! -f "$pid_file" ]; then
        return
    fi

    local pid
    pid=$(cat "$pid_file")

    if kill -0 "$pid" 2>/dev/null; then
        echo "Stopping $name (PID: $pid)..."
        kill "$pid"
        for i in {1..10}; do
            if ! kill -0 "$pid" 2>/dev/null; then
                rm -f "$pid_file"
                echo "  $name stopped"
                return
            fi
            if [ $i -eq 10 ]; then
                kill -9 "$pid" 2>/dev/null || true
                rm -f "$pid_file"
                echo "  $name force stopped"
                return
            fi
            sleep 1
        done
    else
        echo "$name not running (stale PID file)"
        rm -f "$pid_file"
    fi
}

echo ""
# Stop all known processes (main binaries + optional services + GUI)
for name in sylvia-iot-core sylvia-router lora-ifroglab app-demo; do
    stop_process "$name"
done

echo ""
echo "Stopping Docker containers..."

stop_container() {
    local name="$1"
    if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
        echo "  Stopping $name..."
        docker stop "$name" > /dev/null
        echo "  $name stopped"
    elif docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
        echo "  $name already stopped"
    fi
}

stop_container sylvia-rabbitmq
stop_container sylvia-emqx
stop_container sylvia-mongodb
stop_container sylvia-redis

echo ""
echo "======================================"
echo "All Services Stopped"
echo "======================================"
echo ""
echo "To start again: ./start.sh"
