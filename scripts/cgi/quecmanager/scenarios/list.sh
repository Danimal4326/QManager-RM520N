#!/bin/sh
# =============================================================================
# list.sh — CGI Endpoint: List Custom Connection Scenarios
# =============================================================================
# Returns all custom scenario definitions stored on the device, plus the
# active scenario ID. No modem interaction — reads from flash only.
#
# Storage: /etc/qmanager/scenarios/ directory with one JSON file per scenario.
#
# Endpoint: GET /cgi-bin/quecmanager/scenarios/list.sh
# Response: {
#   "scenarios": [ { "id":"custom-...", "name":"...", ... }, ... ],
#   "active_scenario_id": "balanced"
# }
#
# Install location: /www/cgi-bin/quecmanager/scenarios/list.sh
# =============================================================================

# --- Configuration -----------------------------------------------------------
SCENARIOS_DIR="/etc/qmanager/scenarios"
ACTIVE_SCENARIO_FILE="/etc/qmanager/active_scenario"

# --- HTTP Headers ------------------------------------------------------------
echo "Content-Type: application/json"
echo "Cache-Control: no-cache"
echo "Access-Control-Allow-Origin: *"
echo "Access-Control-Allow-Methods: GET, OPTIONS"
echo "Access-Control-Allow-Headers: Content-Type"
echo ""

# --- Handle CORS preflight ---------------------------------------------------
if [ "$REQUEST_METHOD" = "OPTIONS" ]; then
    exit 0
fi

# --- Read active scenario ----------------------------------------------------
ACTIVE_ID=""
if [ -f "$ACTIVE_SCENARIO_FILE" ]; then
    ACTIVE_ID=$(cat "$ACTIVE_SCENARIO_FILE" 2>/dev/null | tr -d ' \n\r')
fi
[ -z "$ACTIVE_ID" ] && ACTIVE_ID="balanced"

# --- Collect custom scenarios from individual JSON files ----------------------
mkdir -p "$SCENARIOS_DIR" 2>/dev/null

FIRST=1
printf '{"scenarios":['

for f in "$SCENARIOS_DIR"/*.json; do
    [ -f "$f" ] || continue
    CONTENT=$(cat "$f" 2>/dev/null)
    [ -z "$CONTENT" ] && continue

    if [ "$FIRST" -eq 1 ]; then
        FIRST=0
    else
        printf ','
    fi
    printf '%s' "$CONTENT"
done

printf '],"active_scenario_id":"%s"}\n' "$ACTIVE_ID"
