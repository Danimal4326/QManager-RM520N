#!/bin/sh
# =============================================================================
# delete.sh — CGI Endpoint: Delete Custom Connection Scenario
# =============================================================================
# Removes a custom scenario definition by ID. If the deleted scenario was
# active, resets the active scenario to "balanced".
#
# Endpoint: POST /cgi-bin/quecmanager/scenarios/delete.sh
# Request body: {"id": "custom-..."}
# Response: {"success":true,"id":"custom-..."}
#
# Install location: /www/cgi-bin/quecmanager/scenarios/delete.sh
# =============================================================================

# --- Configuration -----------------------------------------------------------
SCENARIOS_DIR="/etc/qmanager/scenarios"
ACTIVE_SCENARIO_FILE="/etc/qmanager/active_scenario"

# --- HTTP Headers ------------------------------------------------------------
echo "Content-Type: application/json"
echo "Cache-Control: no-cache"
echo "Access-Control-Allow-Origin: *"
echo "Access-Control-Allow-Methods: POST, OPTIONS"
echo "Access-Control-Allow-Headers: Content-Type"
echo ""

# --- Handle CORS preflight ---------------------------------------------------
if [ "$REQUEST_METHOD" = "OPTIONS" ]; then
    exit 0
fi

# --- Validate method ---------------------------------------------------------
if [ "$REQUEST_METHOD" != "POST" ]; then
    echo '{"success":false,"error":"method_not_allowed","detail":"Use POST"}'
    exit 0
fi

# --- Read POST body ----------------------------------------------------------
if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
    POST_DATA=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
else
    echo '{"success":false,"error":"no_body","detail":"POST body is empty"}'
    exit 0
fi

# --- Extract scenario ID from JSON body ---------------------------------------
SCENARIO_ID=$(printf '%s' "$POST_DATA" | jq -r '.id // empty')

if [ -z "$SCENARIO_ID" ]; then
    echo '{"success":false,"error":"no_id","detail":"Missing id field in request body"}'
    exit 0
fi

# --- Sanitize ID (prevent path traversal) ------------------------------------
case "$SCENARIO_ID" in
    custom-[0-9]*)
        # Valid format
        ;;
    *)
        echo '{"success":false,"error":"invalid_id","detail":"Only custom scenarios can be deleted"}'
        exit 0
        ;;
esac

# --- Delete the scenario file ------------------------------------------------
SCENARIO_FILE="$SCENARIOS_DIR/${SCENARIO_ID}.json"

if [ ! -f "$SCENARIO_FILE" ]; then
    echo '{"success":false,"error":"not_found","detail":"Scenario not found"}'
    exit 0
fi

rm -f "$SCENARIO_FILE"

# --- If deleted scenario was active, reset to balanced ------------------------
if [ -f "$ACTIVE_SCENARIO_FILE" ]; then
    ACTIVE_ID=$(cat "$ACTIVE_SCENARIO_FILE" 2>/dev/null | tr -d ' \n\r')
    if [ "$ACTIVE_ID" = "$SCENARIO_ID" ]; then
        printf 'balanced' > "$ACTIVE_SCENARIO_FILE"
    fi
fi

jq -n --arg id "$SCENARIO_ID" '{"success":true,"id":$id}'
