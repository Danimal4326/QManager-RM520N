#!/bin/sh
# =============================================================================
# delete.sh — CGI Endpoint: Delete SIM Profile
# =============================================================================
# Removes a profile by ID. If the deleted profile was active, clears the
# active profile tracker. Modem settings are NOT reverted — they persist
# in modem NVM. The UI shows "No active profile" after deletion.
#
# Endpoint: POST /cgi-bin/quecmanager/profiles/delete.sh
# Request body: {"id": "<profile_id>"}
# Response: {"success":true,"id":"<profile_id>"}
#       or: {"success":false,"error":"...","detail":"..."}
#
# Install location: /www/cgi-bin/quecmanager/profiles/delete.sh
# =============================================================================

# --- Logging -----------------------------------------------------------------
. /usr/lib/qmanager/qlog.sh 2>/dev/null || {
    qlog_init() { :; }
    qlog_debug() { :; }
    qlog_info() { :; }
    qlog_warn() { :; }
    qlog_error() { :; }
}
qlog_init "cgi_profile_delete"

# --- Source profile manager library ------------------------------------------
. /usr/lib/qmanager/profile_mgr.sh

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

# --- Extract profile ID from JSON body ----------------------------------------
PROFILE_ID=$(printf '%s' "$POST_DATA" | jq -r '.id // empty')

if [ -z "$PROFILE_ID" ]; then
    echo '{"success":false,"error":"no_id","detail":"Missing id field in request body"}'
    exit 0
fi

# --- Sanitize ID (prevent path traversal) ------------------------------------
case "$PROFILE_ID" in
    p_[0-9]*_[0-9a-f]*)
        # Valid format
        ;;
    *)
        echo '{"success":false,"error":"invalid_id","detail":"Invalid profile ID format"}'
        exit 0
        ;;
esac

qlog_info "Profile delete request: $PROFILE_ID"

# --- Delete -------------------------------------------------------------------
profile_delete "$PROFILE_ID"
