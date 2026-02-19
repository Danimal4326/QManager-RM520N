#!/bin/sh
# =============================================================================
# settings.sh — CGI Endpoint: Update Tower Lock Settings
# =============================================================================
# Updates persist and failover settings. Persist changes are sent to the
# modem immediately via AT+QNWLOCK="save_ctrl". Failover settings are
# written to the config file only.
#
# POST body:
#   {"persist": true, "failover_enabled": true, "failover_threshold": 20}
#
# Endpoint: POST /cgi-bin/quecmanager/tower/settings.sh
# Install location: /www/cgi-bin/quecmanager/tower/settings.sh
# =============================================================================

# --- Logging -----------------------------------------------------------------
. /usr/lib/qmanager/qlog.sh 2>/dev/null || {
    qlog_init() { :; }
    qlog_info() { :; }
    qlog_warn() { :; }
    qlog_error() { :; }
    qlog_debug() { :; }
}
qlog_init "cgi_tower_settings"

# --- Load library ------------------------------------------------------------
. /usr/lib/qmanager/tower_lock_mgr.sh 2>/dev/null

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

# --- Parse fields ------------------------------------------------------------
# Handle both quoted and unquoted booleans
parse_bool() {
    printf '%s' "$POST_DATA" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\(true\|false\|\"true\"\|\"false\"\).*/\1/p" | tr -d '"' | head -1
}
parse_num() {
    printf '%s' "$POST_DATA" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p" | head -1
}

PERSIST=$(parse_bool "persist")
FO_ENABLED=$(parse_bool "failover_enabled")
FO_THRESHOLD=$(parse_num "failover_threshold")

# --- Validate ----------------------------------------------------------------
if [ -z "$PERSIST" ] && [ -z "$FO_ENABLED" ] && [ -z "$FO_THRESHOLD" ]; then
    echo '{"success":false,"error":"no_fields","detail":"No settings fields provided"}'
    exit 0
fi

# Ensure config exists
tower_config_init

# Read current values as defaults
config=$(cat "$TOWER_CONFIG_FILE" 2>/dev/null)
current_persist=$(tower_config_get "persist")
[ "$current_persist" != "true" ] && current_persist="false"

current_fo_enabled=$(printf '%s' "$config" | sed -n '/"failover"/,/}/p' | grep '"enabled"' | head -1 | sed 's/.*: *//;s/[, ]//g')
[ -z "$current_fo_enabled" ] && current_fo_enabled="true"

current_fo_threshold=$(tower_config_get "threshold")
[ -z "$current_fo_threshold" ] && current_fo_threshold="20"

# Apply provided values (or keep current)
[ -z "$PERSIST" ] && PERSIST="$current_persist"
[ -z "$FO_ENABLED" ] && FO_ENABLED="$current_fo_enabled"
[ -z "$FO_THRESHOLD" ] && FO_THRESHOLD="$current_fo_threshold"

# Validate threshold range
if [ -n "$FO_THRESHOLD" ]; then
    case "$FO_THRESHOLD" in
        *[!0-9]*)
            echo '{"success":false,"error":"invalid_threshold","detail":"Threshold must be a number 0-100"}'
            exit 0
            ;;
    esac
    if [ "$FO_THRESHOLD" -lt 0 ] 2>/dev/null || [ "$FO_THRESHOLD" -gt 100 ] 2>/dev/null; then
        echo '{"success":false,"error":"invalid_threshold","detail":"Threshold must be 0-100"}'
        exit 0
    fi
fi

qlog_info "Updating tower settings: persist=$PERSIST failover_enabled=$FO_ENABLED threshold=$FO_THRESHOLD"

# --- Send persist AT command if changed --------------------------------------
persist_ok="true"
if [ "$PERSIST" != "$current_persist" ]; then
    local_val="0"
    [ "$PERSIST" = "true" ] && local_val="1"

    result=$(tower_set_persist "$local_val")
    rc=$?

    if [ $rc -ne 0 ] || [ -z "$result" ]; then
        qlog_error "Persist AT command failed (rc=$rc)"
        persist_ok="false"
    else
        case "$result" in
            *ERROR*)
                qlog_error "Persist AT ERROR: $result"
                persist_ok="false"
                ;;
            *)
                qlog_info "Persist set to $local_val"
                ;;
        esac
    fi
fi

# --- Update config file ------------------------------------------------------
tower_config_update_settings "$PERSIST" "$FO_ENABLED" "$FO_THRESHOLD"

# --- Response ----------------------------------------------------------------
if [ "$persist_ok" = "true" ]; then
    printf '{"success":true,"persist":%s,"failover_enabled":%s,"failover_threshold":%s}\n' \
        "$PERSIST" "$FO_ENABLED" "$FO_THRESHOLD"
else
    printf '{"success":true,"persist_command_failed":true,"persist":%s,"failover_enabled":%s,"failover_threshold":%s}\n' \
        "$PERSIST" "$FO_ENABLED" "$FO_THRESHOLD"
fi
