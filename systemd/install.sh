#!/bin/bash
#
# Sylvia-IoT systemd deployment installer.
#
# Usage: sudo ./install.sh [OPTIONS]
#
# Options:
#   --bin core|router     Main binary (default: core)
#   --with SERVICE,...    Optional: lora-ifroglab, app-demo
#   --gui                 Install GUI and plugins
#   --host HOSTNAME       Hostname for GUI config.js URLs (default: localhost)
#   --uninstall           Remove all installed components

if [[ "$1" = "--help" || "$1" = "-h" ]]; then
    sed -n '2,/^[^#]/{ /^#/s/^# \?//p }' "$0"
    exit 0
fi

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONF_DIR="/etc/sylvia-iot"
BIN_DIR="/usr/local/bin"
SHARE_DIR="/usr/local/share/sylvia-iot"
DATA_DIR="/var/lib/sylvia-iot"
SERVICE_DIR="/etc/systemd/system"

BIN_MODE="core"
WITH_SERVICES=""
INSTALL_GUI=false
GUI_HOST="localhost"

# --- Parse arguments ---

if [ "$1" = "--uninstall" ]; then
    echo "Uninstalling Sylvia-IoT..."
    systemctl stop sylvia-iot-core sylvia-router lora-ifroglab app-demo sylvia-iot-infra 2>/dev/null || true
    systemctl disable sylvia-iot-core sylvia-router lora-ifroglab app-demo sylvia-iot-infra 2>/dev/null || true
    rm -f "$SERVICE_DIR"/sylvia-iot-core.service \
          "$SERVICE_DIR"/sylvia-router.service \
          "$SERVICE_DIR"/lora-ifroglab.service \
          "$SERVICE_DIR"/app-demo.service \
          "$SERVICE_DIR"/sylvia-iot-infra.service
    systemctl daemon-reload
    rm -f "$BIN_DIR"/sylvia-iot-core "$BIN_DIR"/sylvia-router \
          "$BIN_DIR"/lora-ifroglab "$BIN_DIR"/app-demo
    rm -rf "$SHARE_DIR" "$CONF_DIR" "$DATA_DIR"
    echo "Done. Docker volumes not removed (run 'docker volume prune' if needed)."
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bin) BIN_MODE="$2"; shift 2 ;;
        --with) WITH_SERVICES="$2"; shift 2 ;;
        --gui) INSTALL_GUI=true; shift ;;
        --host) GUI_HOST="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ "$BIN_MODE" != "core" && "$BIN_MODE" != "router" ]]; then
    echo "Invalid --bin value: $BIN_MODE (use core or router)"
    exit 1
fi

# --- Check prerequisites ---

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: must run as root (sudo ./install.sh)"
    exit 1
fi

if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running."
    exit 1
fi

# --- Detect architecture ---

ARCH="$(uname -m)"
if [ "$ARCH" = "aarch64" ]; then
    ARCH="arm64"
elif [ "$ARCH" != "x86_64" ]; then
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

BINARY_NAME="sylvia-iot-core"
BINARY_ASSET="sylvia-iot-core-${ARCH}.tar.xz"
SERVICE_NAME="sylvia-iot-core"
if [ "$BIN_MODE" = "router" ]; then
    BINARY_NAME="sylvia-router"
    BINARY_ASSET="sylvia-router-${ARCH}.tar.xz"
    SERVICE_NAME="sylvia-router"
fi

echo "======================================"
echo "Sylvia-IoT systemd Installer"
echo "  Binary: $BINARY_NAME"
echo "  Arch:   $ARCH"
[ -n "$WITH_SERVICES" ] && echo "  With:   $WITH_SERVICES"
if $INSTALL_GUI; then
    echo "  GUI:    yes"
    [ "$GUI_HOST" != "localhost" ] && echo "  Host:   $GUI_HOST"
fi
echo "======================================"

# --- Create directories ---

mkdir -p "$CONF_DIR/certificates" "$DATA_DIR" "$SHARE_DIR"

# --- Install config files ---

echo ""
echo "Installing config files to $CONF_DIR..."
cp "$SCRIPT_DIR/docker-compose.yaml" "$CONF_DIR/"
cp "$SCRIPT_DIR/emqx.conf" "$CONF_DIR/"
cp "$SCRIPT_DIR/rabbitmq.conf" "$CONF_DIR/"
cp "$SCRIPT_DIR/init-mongodb.js" "$CONF_DIR/"
cp "$SCRIPT_DIR/certificates/"* "$CONF_DIR/certificates/"

for cfg in config.json5 config-lora-ifroglab.json5 config-app-demo.json5; do
    if [ -f "$SCRIPT_DIR/$cfg" ] && [ ! -f "$CONF_DIR/$cfg" ]; then
        cp "$SCRIPT_DIR/$cfg" "$CONF_DIR/"
        echo "  $cfg installed (new)"
    elif [ -f "$CONF_DIR/$cfg" ]; then
        echo "  $cfg exists, skipping (won't overwrite)"
    fi
done

# --- Download binary ---

download_binary() {
    local name="$1"
    local asset="$2"
    local repo="$3"

    if [ -f "$BIN_DIR/$name" ]; then
        echo "  $name already installed, skipping"
        return
    fi

    echo "  Downloading $name..."
    local url="https://github.com/${repo}/releases/latest/download/${asset}"
    local tmp="/tmp/${asset}"
    curl -sL -o "$tmp" "$url"
    tar xf "$tmp" -C "$BIN_DIR"
    chmod +x "$BIN_DIR/$name"
    rm -f "$tmp"
    echo "  $name installed"
}

echo ""
echo "Installing binaries to $BIN_DIR..."
download_binary "$BINARY_NAME" "$BINARY_ASSET" "woofdogtw/sylvia-iot-core"

if [ -n "$WITH_SERVICES" ]; then
    IFS=',' read -ra SERVICES <<< "$WITH_SERVICES"
    for service in "${SERVICES[@]}"; do
        service="$(echo "$service" | tr -d ' ')"
        case "$service" in
            lora-ifroglab)
                download_binary "lora-ifroglab" "lora-ifroglab-${ARCH}.tar.xz" "woofdogtw/sylvia-iot-examples"
                ;;
            app-demo)
                download_binary "app-demo" "app-demo-${ARCH}.tar.xz" "woofdogtw/sylvia-iot-examples"
                ;;
            *)
                echo "  Unknown service: $service"
                ;;
        esac
    done
fi

# --- Install GUI ---

if $INSTALL_GUI; then
    echo ""
    echo "Installing GUI to $SHARE_DIR..."
    if [ ! -d "$SHARE_DIR/static" ]; then
        curl -sL -o /tmp/sylvia-iot-gui.tar.xz \
            "https://github.com/woofdogtw/sylvia-iot-gui-genai/releases/latest/download/sylvia-iot-gui.tar.xz"
        mkdir -p "$SHARE_DIR/static"
        tar xf /tmp/sylvia-iot-gui.tar.xz -C "$SHARE_DIR/static" --strip-components=1
        rm -f /tmp/sylvia-iot-gui.tar.xz
        sed -i "s|http://localhost:9000/|http://localhost:1080/|g" \
            "$SHARE_DIR/static/js/config.js"
        echo "  GUI installed"
    else
        echo "  GUI already installed, skipping"
    fi

    # Install GUI plugins for optional services
    if [ -n "$WITH_SERVICES" ]; then
        PLUGINS_DIR="$SHARE_DIR/static/js/plugins"
        CONFIG_JS="$SHARE_DIR/static/js/config.js"
        mkdir -p "$PLUGINS_DIR"

        download_plugin() {
            local name="$1"
            local asset="$2"
            if [ ! -f "$PLUGINS_DIR/$name" ]; then
                echo "  Installing plugin: $name..."
                curl -sL -o "/tmp/$asset" \
                    "https://github.com/woofdogtw/sylvia-iot-mfe-examples/releases/latest/download/$asset"
                tar xf "/tmp/$asset" -C "$PLUGINS_DIR"
                rm -f "/tmp/$asset"
            fi
        }

        echo "$WITH_SERVICES" | grep -q "lora-ifroglab" && \
            download_plugin "plugin-lora-ifroglab.js" "plugin-lora-ifroglab.tar.xz"
        echo "$WITH_SERVICES" | grep -q "app-demo" && \
            download_plugin "plugin-app-demo.js" "plugin-app-demo.tar.xz"

        # Rebuild plugins array and config blocks from installed .js files
        # Remove old: comments, plugins line, and known config blocks
        sed -i '/\/\/.*plugins/d; /^\s*plugins\s*:/d' "$CONFIG_JS"
        for key in loraIfroglab appDemo; do
            sed -i "/^\s*${key}\s*:/,/^\s*},\?$/d" "$CONFIG_JS"
        done

        # Build entries from installed plugin files
        declare -A PLUGIN_KEY=(["plugin-lora-ifroglab.js"]="loraIfroglab" ["plugin-app-demo.js"]="appDemo")
        declare -A PLUGIN_URL=(["loraIfroglab"]="http://localhost:6080" ["appDemo"]="http://localhost:7080")

        plugin_entries=""
        plugin_configs=""
        for js_file in "$PLUGINS_DIR"/*.js; do
            [ -f "$js_file" ] || continue
            basename="$(basename "$js_file")"
            if [ -n "$plugin_entries" ]; then
                plugin_entries="$plugin_entries, '/js/plugins/$basename'"
            else
                plugin_entries="'/js/plugins/$basename'"
            fi
            config_key="${PLUGIN_KEY[$basename]}"
            if [ -n "$config_key" ]; then
                base_url="${PLUGIN_URL[$config_key]}"
                plugin_configs="$plugin_configs  $config_key: {\n    baseUrl: '$base_url',\n  },\n"
            fi
        done

        sed -i "s|^}$|${plugin_configs}  plugins: [$plugin_entries],\n}|" "$CONFIG_JS"
        echo "  Plugins configured: [$plugin_entries]"
    fi

    # Update hostname in GUI config.js
    if [ "$GUI_HOST" != "localhost" ]; then
        CONFIG_JS="$SHARE_DIR/static/js/config.js"
        sed -i "s|://[a-zA-Z0-9._-]*:|://localhost:|g" "$CONFIG_JS"
        sed -i "s|://localhost|://$GUI_HOST|g" "$CONFIG_JS"
        echo "  GUI host: $GUI_HOST"
    fi
fi

# --- Install systemd services ---

echo ""
echo "Installing systemd services..."
cp "$SCRIPT_DIR/sylvia-iot-infra.service" "$SERVICE_DIR/"
cp "$SCRIPT_DIR/${SERVICE_NAME}.service" "$SERVICE_DIR/"

ENABLE_SERVICES="sylvia-iot-infra $SERVICE_NAME"

if [ -n "$WITH_SERVICES" ]; then
    IFS=',' read -ra SERVICES <<< "$WITH_SERVICES"
    for service in "${SERVICES[@]}"; do
        service="$(echo "$service" | tr -d ' ')"
        if [ -f "$SCRIPT_DIR/${service}.service" ]; then
            cp "$SCRIPT_DIR/${service}.service" "$SERVICE_DIR/"
            ENABLE_SERVICES="$ENABLE_SERVICES $service"
        fi
    done
fi

systemctl daemon-reload

# --- Start infrastructure ---

echo ""
echo "Starting infrastructure..."
systemctl enable --now sylvia-iot-infra

# --- Wait for MongoDB and seed data ---

echo ""
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
    sleep 2
done

ADMIN_EXISTS=$(docker exec sylvia-mongodb mongosh --quiet --eval \
    "use('sylvia-iot-auth'); db.user.countDocuments({userId:'admin'})" 2>/dev/null || echo "0")
if [ "$ADMIN_EXISTS" = "0" ]; then
    echo "Initializing MongoDB seed data..."
    docker exec -i sylvia-mongodb mongosh < "$CONF_DIR/init-mongodb.js" > /dev/null
    echo "  MongoDB initialized"
else
    echo "  MongoDB seed data exists"
fi

# --- Setup EMQX API key ---

EXISTING_API_KEY=$(grep -oP '"apiKey": "\K[^"]+' "$CONF_DIR/config.json5" || true)

if [ -z "$EXISTING_API_KEY" ]; then
    echo ""
    echo "Waiting for EMQX..."
    for i in {1..30}; do
        if curl -sf http://localhost:18083/api/v5/status > /dev/null 2>&1; then
            echo "  EMQX ready"
            break
        fi
        if [ $i -eq 30 ]; then
            echo "Error: EMQX did not become ready in time"
            exit 1
        fi
        sleep 2
    done

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

    sed -i \
        -e "s/\"apiKey\": \"\"/\"apiKey\": \"$EMQX_API_KEY\"/" \
        -e "s/\"apiSecret\": \"\"/\"apiSecret\": \"$EMQX_API_SECRET\"/" \
        "$CONF_DIR/config.json5"
    echo "  EMQX API key configured"
else
    echo ""
    echo "Using existing EMQX API key from config"
fi

# --- Enable and start services ---

echo ""
echo "Starting services..."
for svc in $ENABLE_SERVICES; do
    systemctl enable --now "$svc"
    echo "  $svc started"
done

# --- Wait for API and initialize platform data ---

echo ""
echo "Waiting for API..."
for i in {1..30}; do
    if curl -sf http://localhost:1080/version > /dev/null 2>&1; then
        echo "  API ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "Warning: API may not be ready yet"
    fi
    sleep 2
done

BASE_URL="http://localhost:1080"
MQ_PASSWORD="password"

echo ""
echo "Initializing platform data..."

REDIRECT_URI="http%3A%2F%2Flocalhost%3A1080%2Fauth%2Foauth2%2Fredirect"
LOGIN_STATE="response_type%3Dcode%26client_id%3Dpublic%26redirect_uri%3D${REDIRECT_URI}"

SESSION_ID=$(curl -s -D - -o /dev/null -X POST "$BASE_URL/auth/oauth2/login" \
    -d "state=${LOGIN_STATE}&account=admin&password=admin" \
    | grep -oP 'session_id=\K[^&;]+' | tr -d '\r')

AUTH_CODE=$(curl -s -D - -o /dev/null -X POST "$BASE_URL/auth/oauth2/authorize" \
    -d "allow=yes&session_id=${SESSION_ID}&client_id=public&response_type=code&redirect_uri=${REDIRECT_URI}" \
    | grep -oP 'code=\K[^&\s]+' | tr -d '\r')

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

# --- Done ---

echo ""
echo "======================================"
echo "Sylvia-IoT Installed"
echo "======================================"
echo ""
echo "Endpoints:"
echo "  Core API:  http://$GUI_HOST:1080"
$INSTALL_GUI && echo "  GUI:       http://$GUI_HOST:1080"
echo ""
echo "Credentials:  admin / admin"
echo ""
echo "Manage:"
echo "  systemctl status $SERVICE_NAME"
echo "  journalctl -u $SERVICE_NAME -f"
echo "  sudo ./install.sh --uninstall"
