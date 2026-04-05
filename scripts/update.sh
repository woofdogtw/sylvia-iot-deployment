#!/bin/bash

# Sylvia-IoT Update Script
# Installs or upgrades components to their latest versions.
# Uses the VERSION file from each GitHub release to detect changes.
#
# Usage: ./update.sh <COMPONENT...>
#
# Components:
#   core          - sylvia-iot-core (auth+broker+coremgr+data)
#   router        - sylvia-router (core + router functionality)
#   router-cli    - sylvia-router-cli
#   coremgr-cli   - sylvia-iot-coremgr-cli
#   lora-ifroglab - LoRa iFrogLab gateway (from sylvia-iot-examples)
#   app-demo      - Application demo (from sylvia-iot-examples)
#   gui           - Sylvia-IoT GUI web app
#   plugin-lora   - GUI shell plugin: LoRa iFrogLab
#   plugin-app    - GUI shell plugin: App Demo

if [[ "$1" = "--help" || "$1" = "-h" ]]; then
    sed -n '2,/^[^#]/{ /^#/s/^# \?//p }' "$0"
    exit 0
fi

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_DIR="$SCRIPT_DIR/.versions"

mkdir -p "$VERSIONS_DIR"

# Detect system architecture
ARCH="$(uname -m)"
if [ "$ARCH" = "aarch64" ]; then
    ARCH="arm64"
elif [ "$ARCH" != "x86_64" ]; then
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

# Component definitions: REPO ASSET_PATTERN TYPE
# TYPE: binary | gui | plugin
declare -A COMPONENT_REPO=(
    ["core"]="woofdogtw/sylvia-iot-core"
    ["router"]="woofdogtw/sylvia-iot-core"
    ["router-cli"]="woofdogtw/sylvia-iot-core"
    ["coremgr-cli"]="woofdogtw/sylvia-iot-core"
    ["lora-ifroglab"]="woofdogtw/sylvia-iot-examples"
    ["app-demo"]="woofdogtw/sylvia-iot-examples"
    ["gui"]="woofdogtw/sylvia-iot-gui-genai"
    ["plugin-lora"]="woofdogtw/sylvia-iot-mfe-examples"
    ["plugin-app"]="woofdogtw/sylvia-iot-mfe-examples"
)

declare -A COMPONENT_ASSET=(
    ["core"]="sylvia-iot-core-${ARCH}.tar.xz"
    ["router"]="sylvia-router-${ARCH}.tar.xz"
    ["router-cli"]="sylvia-router-cli-${ARCH}.tar.xz"
    ["coremgr-cli"]="sylvia-iot-coremgr-cli-${ARCH}.tar.xz"
    ["lora-ifroglab"]="lora-ifroglab-${ARCH}.tar.xz"
    ["app-demo"]="app-demo-${ARCH}.tar.xz"
    ["gui"]="sylvia-iot-gui.tar.xz"
    ["plugin-lora"]="plugin-lora-ifroglab.tar.xz"
    ["plugin-app"]="plugin-app-demo.tar.xz"
)

declare -A COMPONENT_TYPE=(
    ["core"]="binary"
    ["router"]="binary"
    ["router-cli"]="binary"
    ["coremgr-cli"]="binary"
    ["lora-ifroglab"]="binary"
    ["app-demo"]="binary"
    ["gui"]="gui"
    ["plugin-lora"]="plugin"
    ["plugin-app"]="plugin"
)

# Plugin JS filename -> config key name mapping
declare -A PLUGIN_CONFIG_KEY=(
    ["plugin-lora-ifroglab.js"]="loraIfroglab"
    ["plugin-app-demo.js"]="appDemo"
)

# Plugin config key -> baseUrl mapping
declare -A PLUGIN_BASE_URL=(
    ["loraIfroglab"]="http://localhost:6080"
    ["appDemo"]="http://localhost:7080"
)

if [ $# -eq 0 ]; then
    echo "Usage: ./update.sh <COMPONENT...>"
    echo ""
    echo "Available components:"
    echo "  core          sylvia-iot-core (auth+broker+coremgr+data)"
    echo "  router        sylvia-router"
    echo "  router-cli    sylvia-router-cli"
    echo "  coremgr-cli   sylvia-iot-coremgr-cli"
    echo "  lora-ifroglab LoRa iFrogLab gateway"
    echo "  app-demo      Application demo"
    echo "  gui           Sylvia-IoT GUI"
    echo "  plugin-lora   GUI plugin: LoRa iFrogLab"
    echo "  plugin-app    GUI plugin: App Demo"
    exit 1
fi

# Rebuild plugins array and plugin configs in static/js/config.js
update_gui_plugins() {
    local config_js="$SCRIPT_DIR/static/js/config.js"
    [ -f "$config_js" ] || return

    local plugins_dir="$SCRIPT_DIR/static/js/plugins"
    local plugin_entries=""

    # Remove old plugins line, comment, and all known plugin config blocks
    sed -i '/\/\/.*plugins/d; /^\s*plugins\s*:/d' "$config_js"
    for config_key in "${PLUGIN_CONFIG_KEY[@]}"; do
        sed -i "/^\s*${config_key}\s*:/,/^\s*},\?$/d" "$config_js"
    done

    # Build plugins array and config entries from installed .js files
    local plugin_configs=""
    if [ -d "$plugins_dir" ]; then
        for js_file in "$plugins_dir"/*.js; do
            [ -f "$js_file" ] || continue
            local basename
            basename="$(basename "$js_file")"
            if [ -n "$plugin_entries" ]; then
                plugin_entries="$plugin_entries, '/js/plugins/$basename'"
            else
                plugin_entries="'/js/plugins/$basename'"
            fi
            # Add plugin-specific config if mapping exists
            local config_key="${PLUGIN_CONFIG_KEY[$basename]}"
            if [ -n "$config_key" ]; then
                local base_url="${PLUGIN_BASE_URL[$config_key]}"
                plugin_configs="$plugin_configs  $config_key: {\n    baseUrl: '$base_url',\n  },\n"
            fi
        done
    fi

    # Insert plugin configs and plugins array before closing brace
    sed -i "s|^}$|${plugin_configs}  plugins: [$plugin_entries],\n}|" "$config_js"
    echo "  Updated config.js plugins: [$plugin_entries]"
}

install_component() {
    local component="$1"
    local repo="${COMPONENT_REPO[$component]}"
    local asset="${COMPONENT_ASSET[$component]}"
    local type="${COMPONENT_TYPE[$component]}"

    if [ -z "$repo" ]; then
        echo "Unknown component: $component"
        return 1
    fi

    local base_url="https://github.com/${repo}/releases/latest/download"
    local version_url="${base_url}/VERSION"
    local local_version_file="$VERSIONS_DIR/${component}"

    echo ""
    echo "Checking $component..."

    # Fetch latest version
    local latest_version
    latest_version=$(curl -sf "$version_url") || {
        echo "  Failed to fetch VERSION from $version_url"
        return 1
    }
    latest_version=$(echo "$latest_version" | tr -d '[:space:]')

    # Compare with local version
    local local_version=""
    if [ -f "$local_version_file" ]; then
        local_version=$(cat "$local_version_file" | tr -d '[:space:]')
    fi

    if [ "$latest_version" = "$local_version" ]; then
        local skip=false
        case "$type" in
            gui)    [ -d "$SCRIPT_DIR/static" ] && skip=true ;;
            binary) [ -f "$SCRIPT_DIR/${component}" ] && skip=true ;;
            plugin) [ -f "$local_version_file" ] && skip=true ;;
        esac
        if $skip; then
            echo "  Already up to date ($latest_version)"
            return 0
        fi
    fi

    echo "  Installing $component $latest_version..."
    local asset_url="${base_url}/${asset}"
    local tmp_file="/tmp/${asset}"

    curl -L -o "$tmp_file" "$asset_url" || {
        echo "  Failed to download $asset_url"
        return 1
    }

    cd "$SCRIPT_DIR"

    case "$type" in
        binary)
            tar xf "$tmp_file" -C "$SCRIPT_DIR"
            chmod +x "$SCRIPT_DIR/${component}"
            ;;
        gui)
            rm -rf "$SCRIPT_DIR/static"
            mkdir -p "$SCRIPT_DIR/static"
            tar xf "$tmp_file" -C "$SCRIPT_DIR/static" --strip-components=1
            # Update redirectUri from port 9000 to 1080 (served by main binary)
            sed -i "s|http://localhost:9000/|http://localhost:1080/|g" \
                "$SCRIPT_DIR/static/js/config.js"
            ;;
        plugin)
            # Ensure GUI is installed (needed for config.js)
            if [ ! -d "$SCRIPT_DIR/static" ]; then
                echo "  GUI not installed, installing first..."
                install_component gui
            fi
            mkdir -p "$SCRIPT_DIR/static/js/plugins"
            tar xf "$tmp_file" -C "$SCRIPT_DIR/static/js/plugins"
            ;;
    esac

    rm -f "$tmp_file"
    echo "$latest_version" > "$local_version_file"
    echo "  Installed $component $latest_version"
}

echo "======================================"
echo "Sylvia-IoT Component Updater"
echo "  Architecture: $ARCH"
echo "======================================"

FAILED=()
for component in "$@"; do
    if ! install_component "$component"; then
        FAILED+=("$component")
    fi
done

# Update plugins list in config.js if any gui/plugin was touched
if [ -f "$SCRIPT_DIR/static/js/config.js" ]; then
    update_gui_plugins
fi

echo ""
echo "======================================"
echo "Installed Components"
echo "======================================"
for vfile in "$VERSIONS_DIR"/*; do
    [ -f "$vfile" ] || continue
    name="$(basename "$vfile")"
    version="$(cat "$vfile")"
    echo "  $name: $version"
done

if [ ${#FAILED[@]} -gt 0 ]; then
    echo ""
    echo "Failed: ${FAILED[*]}"
    exit 1
fi
