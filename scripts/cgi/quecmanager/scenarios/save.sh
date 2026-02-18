#!/bin/sh
# =============================================================================
# save.sh — CGI Endpoint: Create / Update Custom Connection Scenario
# =============================================================================
# Saves a custom scenario definition to persistent storage (flash).
# Each scenario is stored as an individual JSON file.
#
# If the JSON body contains an "id" field starting with "custom-", it updates.
# Otherwise, it generates a new ID with timestamp.
#
# Endpoint: POST /cgi-bin/quecmanager/scenarios/save.sh
# Request body: {
#   "id": "custom-..." (optional — omit for create),
#   "name": "My Scenario",
#   "description": "...",
#   "gradient": "from-violet-600 via-purple-600 to-indigo-700",
#   "config": {
#     "atModeValue": "AUTO",
#     "mode": "Auto",
#     "optimization": "Custom",
#     "lte_bands": "1:3:28",
#     "nsa_nr_bands": "",
#     "sa_nr_bands": ""
#   }
# }
# Response: {"success":true,"id":"custom-..."}
#
# Install location: /www/cgi-bin/quecmanager/scenarios/save.sh
# =============================================================================

# --- Configuration -----------------------------------------------------------
SCENARIOS_DIR="/etc/qmanager/scenarios"
MAX_SCENARIOS=20

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

# --- Parse fields from JSON --------------------------------------------------
json_field() {
    echo "$POST_DATA" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

SCENARIO_ID=$(json_field "id")
SCENARIO_NAME=$(json_field "name")

# --- Validate name -----------------------------------------------------------
if [ -z "$SCENARIO_NAME" ]; then
    echo '{"success":false,"error":"no_name","detail":"Scenario name is required"}'
    exit 0
fi

# --- Create directory --------------------------------------------------------
mkdir -p "$SCENARIOS_DIR" 2>/dev/null

# --- Generate ID if creating new scenario ------------------------------------
IS_NEW=0
if [ -z "$SCENARIO_ID" ] || ! echo "$SCENARIO_ID" | grep -q "^custom-"; then
    # New scenario — generate a unique ID
    SCENARIO_ID="custom-$(date +%s)"
    IS_NEW=1
fi

# --- Sanitize ID (prevent path traversal) ------------------------------------
case "$SCENARIO_ID" in
    custom-[0-9]*)
        # Valid format
        ;;
    *)
        echo '{"success":false,"error":"invalid_id","detail":"Invalid scenario ID format"}'
        exit 0
        ;;
esac

# --- Check limit on new creation ---------------------------------------------
if [ "$IS_NEW" -eq 1 ]; then
    COUNT=$(ls "$SCENARIOS_DIR"/*.json 2>/dev/null | wc -l)
    if [ "$COUNT" -ge "$MAX_SCENARIOS" ]; then
        printf '{"success":false,"error":"limit_reached","detail":"Maximum %d custom scenarios allowed"}\n' "$MAX_SCENARIOS"
        exit 0
    fi
fi

# --- Ensure the stored JSON has the correct ID --------------------------------
# Replace or inject the "id" field in the POST data
# We use sed to replace any existing "id" value with the canonical one
SAVE_DATA=$(echo "$POST_DATA" | sed "s/\"id\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"id\":\"$SCENARIO_ID\"/")

# If there was no "id" field at all, inject it after the opening brace
if ! echo "$SAVE_DATA" | grep -q "\"id\""; then
    SAVE_DATA=$(echo "$SAVE_DATA" | sed "s/^{/{\"id\":\"$SCENARIO_ID\",/")
fi

# --- Write to file ------------------------------------------------------------
SCENARIO_FILE="$SCENARIOS_DIR/${SCENARIO_ID}.json"
printf '%s' "$SAVE_DATA" > "$SCENARIO_FILE"

if [ $? -ne 0 ]; then
    echo '{"success":false,"error":"write_failed","detail":"Failed to write scenario file"}'
    exit 0
fi

printf '{"success":true,"id":"%s"}\n' "$SCENARIO_ID"
