#!/bin/bash

# Sylvia-IoT API Initialization Script
# Initializes platform data via REST API after services are running.
# Creates demo unit, network (lora-ifroglab), and application (test-app).
# Sets known passwords for mqUri in config files.
#
# Usage: ./init-api.sh

if [[ "$1" = "--help" || "$1" = "-h" ]]; then
    sed -n '2,/^[^#]/{ /^#/s/^# \?//p }' "$0"
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_URL="http://localhost:1080"
MQ_PASSWORD="password"

echo "======================================"
echo "Sylvia-IoT API Initialization"
echo "======================================"

# Check API is available
if ! curl -s "$BASE_URL/version" > /dev/null 2>&1; then
    echo ""
    echo "Error: Sylvia-IoT is not running or not ready."
    echo "  Start it first: ./start.sh"
    exit 1
fi

echo ""
echo "API is ready"

# Get OAuth2 access token (authorization code flow)
echo ""
echo "Authenticating as admin..."
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

if [ -z "$ACCESS_TOKEN" ]; then
    echo "Error: Failed to obtain access token"
    echo "  Response: $TOKEN_RESPONSE"
    exit 1
fi
echo "  Access token obtained"

AUTH_HEADER="Authorization: Bearer $ACCESS_TOKEN"

# Create demo unit
echo ""
echo "Creating unit: demo..."
UNIT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/coremgr/api/v1/unit" \
    -H "Content-Type: application/json" \
    -H "$AUTH_HEADER" \
    -d '{"data":{"code":"demo","name":"Demo Unit"}}')
HTTP_CODE=$(echo "$UNIT_RESPONSE" | tail -1)
BODY=$(echo "$UNIT_RESPONSE" | head -1)

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    UNIT_ID=$(echo "$BODY" | grep -o '"unitId":"[^"]*"' | cut -d'"' -f4)
    echo "  Unit created: $UNIT_ID"
elif [ "$HTTP_CODE" = "400" ] && echo "$BODY" | grep -q "duplicate"; then
    echo "  Unit already exists"
    UNIT_ID=$(curl -s "$BASE_URL/coremgr/api/v1/unit/list?code=demo" \
        -H "$AUTH_HEADER" | grep -o '"unitId":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo "  Unit ID: $UNIT_ID"
else
    echo "  Warning: Unexpected response ($HTTP_CODE): $BODY"
fi

# Create network: lora-ifroglab
echo ""
echo "Creating network: lora-ifroglab..."
NET_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/coremgr/api/v1/network" \
    -H "Content-Type: application/json" \
    -H "$AUTH_HEADER" \
    -d "{\"data\":{\"code\":\"lora-ifroglab\",\"unitId\":\"$UNIT_ID\",\"hostUri\":\"amqp://localhost\",\"name\":\"LoRa iFrogLab\"}}")
HTTP_CODE=$(echo "$NET_RESPONSE" | tail -1)
BODY=$(echo "$NET_RESPONSE" | head -1)

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    NET_ID=$(echo "$BODY" | grep -o '"networkId":"[^"]*"' | cut -d'"' -f4)
    echo "  Network created: $NET_ID"

    # Set known password via PATCH
    curl -s -X PATCH "$BASE_URL/coremgr/api/v1/network/$NET_ID" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d "{\"data\":{\"password\":\"$MQ_PASSWORD\"}}" > /dev/null
    echo "  Password set"
elif [ "$HTTP_CODE" = "400" ] && echo "$BODY" | grep -q "duplicate"; then
    echo "  Network already exists"
else
    echo "  Warning: Unexpected response ($HTTP_CODE): $BODY"
fi

# Create application: test-app
echo ""
echo "Creating application: test-app..."
APP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/coremgr/api/v1/application" \
    -H "Content-Type: application/json" \
    -H "$AUTH_HEADER" \
    -d "{\"data\":{\"code\":\"test-app\",\"unitId\":\"$UNIT_ID\",\"hostUri\":\"amqp://localhost\",\"name\":\"App Demo\"}}")
HTTP_CODE=$(echo "$APP_RESPONSE" | tail -1)
BODY=$(echo "$APP_RESPONSE" | head -1)

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    APP_ID=$(echo "$BODY" | grep -o '"applicationId":"[^"]*"' | cut -d'"' -f4)
    echo "  Application created: $APP_ID"

    # Set known password via PATCH
    curl -s -X PATCH "$BASE_URL/coremgr/api/v1/application/$APP_ID" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d "{\"data\":{\"password\":\"$MQ_PASSWORD\"}}" > /dev/null
    echo "  Password set"
elif [ "$HTTP_CODE" = "400" ] && echo "$BODY" | grep -q "duplicate"; then
    echo "  Application already exists"
else
    echo "  Warning: Unexpected response ($HTTP_CODE): $BODY"
fi

echo ""
echo "======================================"
echo "Initialization Complete"
echo "======================================"
echo ""
echo "  Unit:        demo"
echo "  Network:     lora-ifroglab (amqp://network.demo.lora-ifroglab:$MQ_PASSWORD@localhost/...)"
echo "  Application: test-app (amqp://application.demo.test-app:$MQ_PASSWORD@localhost/...)"
echo ""
echo "Access the API at: $BASE_URL/coremgr/api/v1/"
