#!/bin/bash

# Sylvia-IoT Services Startup Script
#
# Usage: ./start.sh [OPTIONS]
#
# Options:
#   --db sqlite|mongodb   Database backend (default: sqlite)
#   --bin core|router     Main binary to run (default: core)
#   --with SERVICE,...    Optional services: lora-ifroglab, app-demo (comma-separated)
#   --gui                 Serve installed GUI via staticPath (requires: ./update.sh gui)
#   --host HOSTNAME       Hostname for GUI config.js URLs (default: localhost)

if [[ "$1" = "--help" || "$1" = "-h" ]]; then
    sed -n '2,/^[^#]/{ /^#/s/^# \?//p }' "$0"
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load centralized versions
source "$SCRIPT_DIR/versions.env"

DB_MODE="sqlite"
BIN_MODE="core"
WITH_SERVICES=""
START_GUI=false
GUI_HOST="localhost"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db) DB_MODE="$2"; shift 2 ;;
        --bin) BIN_MODE="$2"; shift 2 ;;
        --with) WITH_SERVICES="$2"; shift 2 ;;
        --gui) START_GUI=true; shift ;;
        --host) GUI_HOST="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ "$DB_MODE" != "sqlite" && "$DB_MODE" != "mongodb" ]]; then
    echo "Invalid --db value: $DB_MODE (use sqlite or mongodb)"
    exit 1
fi
if [[ "$BIN_MODE" != "core" && "$BIN_MODE" != "router" ]]; then
    echo "Invalid --bin value: $BIN_MODE (use core or router)"
    exit 1
fi

BINARY_NAME="sylvia-iot-core"
if [ "$BIN_MODE" = "router" ]; then
    BINARY_NAME="sylvia-router"
fi

CONFIG_FILE="$SCRIPT_DIR/config.json5"
RUNTIME_CONFIG="$SCRIPT_DIR/config.runtime.json5"

echo "======================================"
echo "Starting Sylvia-IoT Services"
echo "  DB:     $DB_MODE"
echo "  Binary: $BINARY_NAME"
[ -n "$WITH_SERVICES" ] && echo "  With:   $WITH_SERVICES"
if $START_GUI; then
    echo "  GUI:    enabled (staticPath)"
    [ "$GUI_HOST" != "localhost" ] && echo "  Host:   $GUI_HOST"
fi
echo "======================================"

# Check Docker
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running. Please start Docker first."
    exit 1
fi
echo "Docker is running"

# Start MongoDB + Redis (mongodb mode only)
if [ "$DB_MODE" = "mongodb" ]; then
    echo ""
    echo "Starting MongoDB..."
    if docker ps -a --format '{{.Names}}' | grep -q '^sylvia-mongodb$'; then
        if ! docker ps --format '{{.Names}}' | grep -q '^sylvia-mongodb$'; then
            docker start sylvia-mongodb > /dev/null
        fi
        echo "  MongoDB running"
    else
        docker run -d \
            --name sylvia-mongodb \
            -p 27017:27017 \
            mongo:$MONGODB_VERSION > /dev/null
        echo "  MongoDB started"
    fi

    echo "Starting Redis..."
    if docker ps -a --format '{{.Names}}' | grep -q '^sylvia-redis$'; then
        if ! docker ps --format '{{.Names}}' | grep -q '^sylvia-redis$'; then
            docker start sylvia-redis > /dev/null
        fi
        echo "  Redis running"
    else
        docker run -d \
            --name sylvia-redis \
            -p 6379:6379 \
            redis:$REDIS_VERSION-alpine > /dev/null
        echo "  Redis started"
    fi
fi

# Start RabbitMQ
echo ""
echo "Starting RabbitMQ..."
if docker ps -a --format '{{.Names}}' | grep -q '^sylvia-rabbitmq$'; then
    if docker ps --format '{{.Names}}' | grep -q '^sylvia-rabbitmq$'; then
        echo "  RabbitMQ already running"
    else
        docker start sylvia-rabbitmq > /dev/null
        echo "  RabbitMQ started"
    fi
else
    docker run -d \
        --name sylvia-rabbitmq \
        -p 5671:5671 \
        -p 5672:5672 \
        -p 15672:15672 \
        rabbitmq:$RABBITMQ_VERSION-management-alpine > /dev/null
    echo "  RabbitMQ started"
fi

# Start EMQX
echo ""
echo "Starting EMQX..."
if docker ps --format '{{.Names}}' | grep -q '^sylvia-emqx$'; then
    echo "  EMQX already running"
else
    docker rm sylvia-emqx > /dev/null 2>&1 || true
    docker run -d \
        --name sylvia-emqx \
        -p 1883:1883 \
        -p 8883:8883 \
        -p 18083:18083 \
        -v "$SCRIPT_DIR/emqx.conf":"/opt/emqx/etc/emqx.conf" \
        emqx/emqx:$EMQX_VERSION > /dev/null
    echo "  EMQX started"
fi

# Check if config already has EMQX API key
EXISTING_API_KEY=$(grep -oP '"apiKey": "\K[^"]+' "$CONFIG_FILE" || true)

if [ -n "$EXISTING_API_KEY" ]; then
    # Config already has EMQX credentials, use as-is
    echo ""
    echo "Using existing EMQX API key from config"
    cp "$CONFIG_FILE" "$RUNTIME_CONFIG"
else
    # Wait for EMQX and create API key
    echo ""
    echo "Waiting for EMQX..."
    for i in {1..30}; do
        if curl -sf http://localhost:18083/api/v5/status > /dev/null 2>&1; then
            echo "  EMQX ready"
            break
        fi
        if [ $i -eq 30 ]; then
            echo "Error: EMQX did not become ready in time"
            echo "  Check logs: docker logs sylvia-emqx"
            exit 1
        fi
        sleep 1
    done

    echo ""
    echo "Creating EMQX API key..."
    docker exec sylvia-emqx emqx eval 'emqx_mgmt_auth:delete(<<"coremgr">>).' > /dev/null 2>&1 || true
    EMQX_EVAL_RESULT=$(docker exec sylvia-emqx emqx eval \
        'emqx_mgmt_auth:create(<<"coremgr">>, true, infinity, #{}, <<"administrator">>).' 2>&1)

    EMQX_API_KEY=$(echo "$EMQX_EVAL_RESULT" | grep -oP 'api_key => <<"\K[^"]+')
    EMQX_API_SECRET=$(echo "$EMQX_EVAL_RESULT" | grep -oP 'api_secret => <<"\K[^"]+')

    if [ -z "$EMQX_API_KEY" ] || [ -z "$EMQX_API_SECRET" ]; then
        echo "Error: Could not create EMQX API key"
        echo "  Result: $EMQX_EVAL_RESULT"
        exit 1
    fi
    echo "  EMQX API key created"

    # Generate runtime config with injected credentials
    sed -e "s/\"apiKey\": \"\"/\"apiKey\": \"$EMQX_API_KEY\"/" \
        -e "s/\"apiSecret\": \"\"/\"apiSecret\": \"$EMQX_API_SECRET\"/" \
        "$CONFIG_FILE" > "$RUNTIME_CONFIG"
fi

if [ "$DB_MODE" = "mongodb" ]; then
    sed -i 's/"engine": "sqlite"/"engine": "mongodb"/g' "$RUNTIME_CONFIG"
fi

if $START_GUI; then
    if [ ! -d "$SCRIPT_DIR/static" ]; then
        echo "  static/ not found, installing GUI..."
        "$SCRIPT_DIR/update.sh" gui
    fi
    # Install GUI plugins for optional services
    if [ -n "$WITH_SERVICES" ]; then
        PLUGIN_ARGS=""
        echo "$WITH_SERVICES" | grep -q "lora-ifroglab" && PLUGIN_ARGS="$PLUGIN_ARGS plugin-lora"
        echo "$WITH_SERVICES" | grep -q "app-demo" && PLUGIN_ARGS="$PLUGIN_ARGS plugin-app"
        if [ -n "$PLUGIN_ARGS" ]; then
            echo "  Installing GUI plugins..."
            "$SCRIPT_DIR/update.sh" $PLUGIN_ARGS
        fi
    fi
    # Update hostname in GUI config.js
    if [ "$GUI_HOST" != "localhost" ]; then
        GUI_CONFIG="$SCRIPT_DIR/static/js/config.js"
        # Normalize any previous host back to localhost, then apply new host
        sed -i "s|://[a-zA-Z0-9._-]*:|://localhost:|g" "$GUI_CONFIG"
        sed -i "s|://localhost|://$GUI_HOST|g" "$GUI_CONFIG"
        echo "  GUI host: $GUI_HOST"
    fi
    sed -i 's/"server": {}/"server": { "staticPath": "static" }/' "$RUNTIME_CONFIG"
    echo "  Runtime config generated (engine: $DB_MODE, staticPath)"
else
    echo "  Runtime config generated (engine: $DB_MODE)"
fi

# Check main binary
if [ ! -f "$SCRIPT_DIR/$BINARY_NAME" ]; then
    echo ""
    echo "$BINARY_NAME not found, installing..."
    "$SCRIPT_DIR/update.sh" "$BIN_MODE"
fi

# Setup database
echo ""
if [ "$DB_MODE" = "sqlite" ]; then
    if ! command -v sqlite3 &> /dev/null; then
        echo "Error: sqlite3 is not installed."
        echo "  Ubuntu/Debian: sudo apt-get install sqlite3"
        exit 1
    fi
    DB_FILE="$SCRIPT_DIR/test.db"
    if [ ! -f "$DB_FILE" ]; then
        echo "Creating SQLite database..."
        sqlite3 "$DB_FILE" < "$SCRIPT_DIR/test.db.sql"
        echo "  Database created"
    else
        echo "SQLite database exists"
    fi
else
    echo "Waiting for MongoDB..."
    for i in {1..30}; do
        if docker exec sylvia-mongodb mongosh --quiet --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
            echo "  MongoDB ready"
            break
        fi
        if [ $i -eq 30 ]; then
            echo "Error: MongoDB did not become ready in time"
            exit 1
        fi
        sleep 1
    done
    # Only seed if admin user does not exist yet
    ADMIN_EXISTS=$(docker exec sylvia-mongodb mongosh --quiet --eval \
        "use('sylvia-iot-auth'); db.user.countDocuments({userId:'admin'})" 2>/dev/null || echo "0")
    if [ "$ADMIN_EXISTS" = "0" ]; then
        echo "Initializing MongoDB seed data..."
        docker exec -i sylvia-mongodb mongosh < "$SCRIPT_DIR/init-mongodb.js" > /dev/null
        echo "  MongoDB initialized"
    else
        echo "MongoDB seed data exists"
    fi
fi

# Stop existing main process if running
PID_FILE="$SCRIPT_DIR/${BINARY_NAME}.pid"
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo ""
    echo "Stopping existing $BINARY_NAME (PID: $(cat "$PID_FILE"))..."
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    sleep 1
fi

# Start main binary
echo ""
echo "Starting $BINARY_NAME..."
cd "$SCRIPT_DIR"
nohup ./"$BINARY_NAME" -f "$RUNTIME_CONFIG" > "${BINARY_NAME}.log" 2>&1 &
echo $! > "$PID_FILE"
echo "  PID: $(cat "$PID_FILE")  Log: ${BINARY_NAME}.log"

# Wait for API
echo ""
echo "Waiting for $BINARY_NAME API..."
for i in {1..30}; do
    if curl -s http://localhost:1080/version > /dev/null 2>&1; then
        echo "  API ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "Warning: API may not be ready yet"
        echo "  Check: tail -f $SCRIPT_DIR/${BINARY_NAME}.log"
    fi
    sleep 1
done

# Initialize platform data (unit, network, application)
BASE_URL="http://localhost:1080"
MQ_PASSWORD="password"

echo ""
echo "Initializing platform data..."

REDIRECT_URI="http%3A%2F%2Flocalhost%3A1080%2Fauth%2Foauth2%2Fredirect"
LOGIN_STATE="response_type%3Dcode%26client_id%3Dpublic%26redirect_uri%3D${REDIRECT_URI}"

# Step 1: Login to get session_id
SESSION_ID=$(curl -s -D - -o /dev/null -X POST "$BASE_URL/auth/oauth2/login" \
    -d "state=${LOGIN_STATE}&account=admin&password=admin" \
    | grep -oP 'session_id=\K[^&;]+' | tr -d '\r')

# Step 2: Authorize to get code
AUTH_CODE=$(curl -s -D - -o /dev/null -X POST "$BASE_URL/auth/oauth2/authorize" \
    -d "allow=yes&session_id=${SESSION_ID}&client_id=public&response_type=code&redirect_uri=${REDIRECT_URI}" \
    | grep -oP 'code=\K[^&\s]+' | tr -d '\r')

# Step 3: Exchange code for token
TOKEN_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/oauth2/token" \
    -d "grant_type=authorization_code&code=${AUTH_CODE}&redirect_uri=${REDIRECT_URI}&client_id=public")
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

if [ -n "$ACCESS_TOKEN" ]; then
    AUTH_HEADER="Authorization: Bearer $ACCESS_TOKEN"

    # Create unit: demo
    UNIT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/coremgr/api/v1/unit" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d '{"data":{"code":"demo","name":"Demo Unit"}}')
    HTTP_CODE=$(echo "$UNIT_RESPONSE" | tail -1)
    BODY=$(echo "$UNIT_RESPONSE" | head -1)

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        UNIT_ID=$(echo "$BODY" | grep -o '"unitId":"[^"]*"' | cut -d'"' -f4)
        echo "  Unit created: demo"
    else
        UNIT_ID=$(curl -s "$BASE_URL/coremgr/api/v1/unit/list?code=demo" \
            -H "$AUTH_HEADER" | grep -o '"unitId":"[^"]*"' | head -1 | cut -d'"' -f4)
        echo "  Unit exists: demo"
    fi

    if [ -n "$UNIT_ID" ]; then
        # Create network: lora-ifroglab
        NET_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/coremgr/api/v1/network" \
            -H "Content-Type: application/json" \
            -H "$AUTH_HEADER" \
            -d "{\"data\":{\"code\":\"lora-ifroglab\",\"unitId\":\"$UNIT_ID\",\"hostUri\":\"amqp://localhost\",\"name\":\"LoRa iFrogLab\"}}")
        HTTP_CODE=$(echo "$NET_RESPONSE" | tail -1)
        BODY=$(echo "$NET_RESPONSE" | head -1)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
            NET_ID=$(echo "$BODY" | grep -o '"networkId":"[^"]*"' | cut -d'"' -f4)
            curl -s -X PATCH "$BASE_URL/coremgr/api/v1/network/$NET_ID" \
                -H "Content-Type: application/json" \
                -H "$AUTH_HEADER" \
                -d "{\"data\":{\"password\":\"$MQ_PASSWORD\"}}" > /dev/null
            echo "  Network created: lora-ifroglab"
        else
            echo "  Network exists: lora-ifroglab"
        fi

        # Create application: test-app
        APP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/coremgr/api/v1/application" \
            -H "Content-Type: application/json" \
            -H "$AUTH_HEADER" \
            -d "{\"data\":{\"code\":\"test-app\",\"unitId\":\"$UNIT_ID\",\"hostUri\":\"amqp://localhost\",\"name\":\"App Demo\"}}")
        HTTP_CODE=$(echo "$APP_RESPONSE" | tail -1)
        BODY=$(echo "$APP_RESPONSE" | head -1)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
            APP_ID=$(echo "$BODY" | grep -o '"applicationId":"[^"]*"' | cut -d'"' -f4)
            curl -s -X PATCH "$BASE_URL/coremgr/api/v1/application/$APP_ID" \
                -H "Content-Type: application/json" \
                -H "$AUTH_HEADER" \
                -d "{\"data\":{\"password\":\"$MQ_PASSWORD\"}}" > /dev/null
            echo "  Application created: test-app"
        else
            echo "  Application exists: test-app"
        fi
    fi
else
    echo "  Warning: Could not authenticate, skipping platform init"
fi

# Start optional services
if [ -n "$WITH_SERVICES" ]; then
    echo ""
    IFS=',' read -ra SERVICES <<< "$WITH_SERVICES"
    for service in "${SERVICES[@]}"; do
        service="$(echo "$service" | tr -d ' ')"
        if [ ! -f "$SCRIPT_DIR/$service" ]; then
            echo "$service not found, installing..."
            "$SCRIPT_DIR/update.sh" "$service"
        fi
        SVC_PID_FILE="$SCRIPT_DIR/${service}.pid"
        if [ -f "$SVC_PID_FILE" ] && kill -0 "$(cat "$SVC_PID_FILE")" 2>/dev/null; then
            kill "$(cat "$SVC_PID_FILE")" 2>/dev/null || true
            sleep 1
        fi
        SVC_CONFIG=""
        if [ -f "$SCRIPT_DIR/config-${service}.json5" ]; then
            SVC_CONFIG="-f $SCRIPT_DIR/config-${service}.json5"
        fi
        echo "Starting $service..."
        nohup "$SCRIPT_DIR/$service" $SVC_CONFIG > "$SCRIPT_DIR/${service}.log" 2>&1 &
        echo $! > "$SVC_PID_FILE"
        echo "  PID: $(cat "$SVC_PID_FILE")  Log: ${service}.log"
    done
fi


echo ""
echo "======================================"
echo "All Services Started"
echo "======================================"
echo ""
echo "Credentials:  admin / admin"
$START_GUI && echo "GUI:  http://localhost:1080"
echo ""
echo "To stop: ./stop.sh"
