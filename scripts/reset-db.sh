#!/bin/bash

# Sylvia-IoT Database Reset Script
# Resets the database to its initial state.
#
# Usage: ./reset-db.sh [--db sqlite|mongodb]
#        Default: sqlite

if [[ "$1" = "--help" || "$1" = "-h" ]]; then
    sed -n '2,/^[^#]/{ /^#/s/^# \?//p }' "$0"
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_MODE="sqlite"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db) DB_MODE="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ "$DB_MODE" != "sqlite" && "$DB_MODE" != "mongodb" ]]; then
    echo "Invalid --db value: $DB_MODE (use sqlite or mongodb)"
    exit 1
fi

echo "======================================"
echo "Reset Sylvia-IoT Database ($DB_MODE)"
echo "======================================"

# Warn if any service is running
for name in sylvia-iot-core sylvia-router; do
    pid_file="$SCRIPT_DIR/${name}.pid"
    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        echo ""
        echo "Warning: $name is currently running."
        echo "  It is recommended to stop it before resetting the database."
        read -p "  Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            exit 0
        fi
        break
    fi
done

echo ""

if [ "$DB_MODE" = "sqlite" ]; then
    if ! command -v sqlite3 &> /dev/null; then
        echo "Error: sqlite3 is not installed."
        echo "  Ubuntu/Debian: sudo apt-get install sqlite3"
        exit 1
    fi

    SQL_FILE="$SCRIPT_DIR/test.db.sql"
    if [ ! -f "$SQL_FILE" ]; then
        echo "Error: $SQL_FILE not found."
        exit 1
    fi

    DB_FILE="$SCRIPT_DIR/test.db"
    echo "Resetting SQLite database..."
    rm -f "$DB_FILE"
    sqlite3 "$DB_FILE" < "$SQL_FILE"
    echo "  Database reset complete"

else
    # MongoDB mode
    if ! docker ps --format '{{.Names}}' | grep -q '^sylvia-mongodb$'; then
        echo "Error: sylvia-mongodb container is not running."
        echo "  Start it first: ./start.sh --db mongodb"
        exit 1
    fi

    echo "Dropping MongoDB databases..."
    docker exec sylvia-mongodb mongosh --quiet --eval "
        db.getSiblingDB('sylvia-iot-auth').dropDatabase();
        db.getSiblingDB('sylvia-iot-broker').dropDatabase();
        db.getSiblingDB('sylvia-iot-data').dropDatabase();
        print('Databases dropped.');
    "

    echo "Re-initializing seed data..."
    docker exec -i sylvia-mongodb mongosh < "$SCRIPT_DIR/init-mongodb.js" > /dev/null
    echo "  MongoDB reset complete"
fi

echo ""
echo "======================================"
echo "Database Reset Complete"
echo "======================================"
echo ""
echo "Credentials: admin / admin"
