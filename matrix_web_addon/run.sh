#!/bin/bash
# HA add-on startup script for Matrix Web Chat
# Reads options from /data/options.json (mounted by HA Supervisor),
# patches config.json with the configured values, then starts nginx.

set -e

OPTIONS_FILE="/data/options.json"

if [ -f "$OPTIONS_FILE" ]; then
    HOMESERVER_URL="$(jq -r '.homeserver_url // "https://matrix.example.com"' "$OPTIONS_FILE")"
    HOMESERVER_NAME="$(jq -r '.homeserver_name // "matrix.example.com"' "$OPTIONS_FILE")"
    SERVER_NAME="$(jq -r '.server_name // "matrix.example.com"' "$OPTIONS_FILE")"
    BRAND="$(jq -r '.brand // "Matrix Chat"' "$OPTIONS_FILE")"
    LOG_LEVEL="$(jq -r '.log_level // "info"' "$OPTIONS_FILE")"
else
    HOMESERVER_URL="https://matrix.example.com"
    HOMESERVER_NAME="matrix.example.com"
    SERVER_NAME="matrix.example.com"
    BRAND="Matrix Chat"
    LOG_LEVEL="info"
fi

# Patch config.json with configured values
CONFIG_FILE="/app/webapp/config.json"
jq --arg hs "$HOMESERVER_URL" --arg sn "$SERVER_NAME" --arg brand "$BRAND" '
    .default_server_config["m.homeserver"].base_url = $hs |
    .default_server_config["m.homeserver"].server_name = $sn |
    .brand = $brand |
    .room_directory.servers = [$sn]
' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

echo "Starting Matrix Web Chat add-on..."
echo "  Homeserver: ${HOMESERVER_URL}"
echo "  Server name: ${SERVER_NAME}"
echo "  Brand: ${BRAND}"
echo "  Log level: ${LOG_LEVEL}"

exec nginx -g "daemon off;"
