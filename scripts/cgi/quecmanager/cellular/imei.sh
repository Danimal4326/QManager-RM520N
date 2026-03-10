#!/bin/sh
. /usr/lib/qmanager/cgi_base.sh
. /usr/lib/qmanager/cgi_at.sh
# =============================================================================
# imei.sh — CGI Endpoint: IMEI Mangling Settings (GET + POST)
# =============================================================================
# GET:  Reads current IMEI from poller cache and backup config.
# POST: Writes new IMEI, saves backup config, or triggers reboot.
#
# AT commands used (POST, action=set_imei):
#   AT+EGMR=1,7,"<IMEI>"  -> Write IMEI to modem NVM (reboot required)
#
# Config files:
#   /tmp/qmanager_status.json         -> Poller cache (read IMEI from .device.imei)
#   /etc/qmanager/imei_backup.json    -> Backup IMEI configuration
#   /etc/qmanager/imei_check_pending  -> Flag for boot-time rejection check
#
# Endpoint: GET/POST /cgi-bin/quecmanager/cellular/imei.sh
# Install location: /www/cgi-bin/quecmanager/cellular/imei.sh
# =============================================================================

# --- Logging -----------------------------------------------------------------
qlog_init "cgi_imei"
cgi_headers
cgi_handle_options

# --- Configuration -----------------------------------------------------------
POLLER_CACHE="/tmp/qmanager_status.json"
BACKUP_CONFIG="/etc/qmanager/imei_backup.json"
CHECK_PENDING="/etc/qmanager/imei_check_pending"
CMD_GAP=0.2

# --- HTTP Headers ------------------------------------------------------------

# --- Handle CORS preflight ---------------------------------------------------

# =============================================================================
# GET — Fetch current IMEI and backup configuration
# =============================================================================
if [ "$REQUEST_METHOD" = "GET" ]; then
    qlog_info "Fetching IMEI settings"

    # --- 1. Read current IMEI from poller cache ---
    current_imei=""
    if [ -f "$POLLER_CACHE" ]; then
        current_imei=$(jq -r '.device.imei // ""' "$POLLER_CACHE" 2>/dev/null)
    fi

    # --- 2. Read backup config ---
    backup_enabled="false"
    backup_imei=""
    if [ -f "$BACKUP_CONFIG" ]; then
        backup_enabled=$(jq -r '(.enabled) | if . == null then "false" else tostring end' "$BACKUP_CONFIG" 2>/dev/null)
        backup_imei=$(jq -r '.imei // ""' "$BACKUP_CONFIG" 2>/dev/null)
    fi

    qlog_info "IMEI: current=$current_imei backup_enabled=$backup_enabled"

    jq -n \
        --arg imei "$current_imei" \
        --argjson b_enabled "$backup_enabled" \
        --arg b_imei "$backup_imei" \
        '{
            success: true,
            current_imei: $imei,
            backup: {
                enabled: $b_enabled,
                imei: $b_imei
            }
        }'
    exit 0
fi

# =============================================================================
# POST — Apply IMEI changes, save backup config, or reboot
# =============================================================================
if [ "$REQUEST_METHOD" = "POST" ]; then

    # --- Read POST body ---
    if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
        POST_DATA=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
    else
        echo '{"success":false,"error":"no_body","detail":"POST body is empty"}'
        exit 0
    fi

    # --- Extract action ---
    ACTION=$(printf '%s' "$POST_DATA" | jq -r '.action // empty')

    if [ -z "$ACTION" ]; then
        echo '{"success":false,"error":"missing_action","detail":"action field is required"}'
        exit 0
    fi

    # -------------------------------------------------------------------------
    # action: set_imei — Write new IMEI to modem NVM
    # -------------------------------------------------------------------------
    if [ "$ACTION" = "set_imei" ]; then
        NEW_IMEI=$(printf '%s' "$POST_DATA" | jq -r '.imei // empty')

        if [ -z "$NEW_IMEI" ]; then
            echo '{"success":false,"error":"missing_imei","detail":"imei field is required"}'
            exit 0
        fi

        if ! validate_imei "$NEW_IMEI"; then
            echo '{"success":false,"error":"invalid_imei","detail":"IMEI must be exactly 15 digits"}'
            exit 0
        fi

        # Compare with current IMEI from poller cache
        current_imei=""
        if [ -f "$POLLER_CACHE" ]; then
            current_imei=$(jq -r '.device.imei // ""' "$POLLER_CACHE" 2>/dev/null)
        fi

        if [ "$NEW_IMEI" = "$current_imei" ]; then
            echo '{"success":true,"detail":"IMEI already set to this value","reboot_required":false}'
            exit 0
        fi

        qlog_info "Writing IMEI: $NEW_IMEI"

        # Write IMEI to modem NVM
        result=$(qcmd "AT+EGMR=1,7,\"${NEW_IMEI}\"" 2>/dev/null)
        case "$result" in
            *ERROR*)
                qlog_error "Failed to write IMEI: $result"
                echo '{"success":false,"error":"egmr_failed","detail":"Failed to write IMEI to modem"}'
                exit 0
                ;;
        esac

        # Set check-pending flag if backup IMEI is enabled
        if [ -f "$BACKUP_CONFIG" ]; then
            b_enabled=$(jq -r '(.enabled) | if . == null then "false" else tostring end' "$BACKUP_CONFIG" 2>/dev/null)
            if [ "$b_enabled" = "true" ]; then
                touch "$CHECK_PENDING"
                qlog_info "Backup enabled — set IMEI check pending flag"
            fi
        fi

        qlog_info "IMEI written successfully (reboot required)"
        jq -n '{"success":true,"reboot_required":true}'
        exit 0
    fi

    # -------------------------------------------------------------------------
    # action: save_backup — Persist backup IMEI configuration
    # -------------------------------------------------------------------------
    if [ "$ACTION" = "save_backup" ]; then
        ENABLED=$(printf '%s' "$POST_DATA" | jq -r 'if has("enabled") then (.enabled | tostring) else "" end')
        BACKUP_IMEI=$(printf '%s' "$POST_DATA" | jq -r '.backup_imei // ""')

        if [ -z "$ENABLED" ]; then
            echo '{"success":false,"error":"missing_enabled","detail":"enabled field is required"}'
            exit 0
        fi

        case "$ENABLED" in
            true|false) ;;
            *)
                echo '{"success":false,"error":"invalid_enabled","detail":"enabled must be true or false"}'
                exit 0
                ;;
        esac

        # When enabling, backup IMEI must be valid
        if [ "$ENABLED" = "true" ]; then
            if ! validate_imei "$BACKUP_IMEI"; then
                echo '{"success":false,"error":"invalid_backup_imei","detail":"Backup IMEI must be exactly 15 digits"}'
                exit 0
            fi
        fi

        qlog_info "Saving backup config: enabled=$ENABLED imei=$BACKUP_IMEI"

        # Ensure config directory exists
        mkdir -p /etc/qmanager

        # Write config atomically
        jq -n \
            --argjson enabled "$ENABLED" \
            --arg imei "$BACKUP_IMEI" \
            '{ enabled: $enabled, imei: $imei }' \
            > "${BACKUP_CONFIG}.tmp" && mv "${BACKUP_CONFIG}.tmp" "$BACKUP_CONFIG"

        if [ $? -ne 0 ]; then
            qlog_error "Failed to write backup config"
            echo '{"success":false,"error":"write_failed","detail":"Failed to save backup configuration"}'
            exit 0
        fi

        # If disabling, remove any pending check flag
        if [ "$ENABLED" = "false" ]; then
            rm -f "$CHECK_PENDING"
        fi

        qlog_info "Backup config saved"
        jq -n '{"success":true}'
        exit 0
    fi

    # -------------------------------------------------------------------------
    # action: reboot — Trigger device reboot
    # -------------------------------------------------------------------------
    if [ "$ACTION" = "reboot" ]; then
        qlog_info "Device reboot requested via IMEI settings"

        # Return response BEFORE rebooting
        jq -n '{"success":true}'

        # Schedule reboot with delay to ensure HTTP response is flushed
        ( sleep 1 && reboot ) &
        exit 0
    fi

    # --- Unknown action ---
    echo '{"success":false,"error":"invalid_action","detail":"action must be set_imei, save_backup, or reboot"}'
    exit 0
fi

# --- Method not allowed -------------------------------------------------------
cgi_method_not_allowed
