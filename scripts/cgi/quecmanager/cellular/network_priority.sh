#!/bin/sh
. /usr/lib/qmanager/cgi_base.sh
# =============================================================================
# network_priority.sh — CGI Endpoint: RAT Acquisition Order (GET + POST)
# =============================================================================
# GET:  Reads current RAT acquisition order via AT+QNWPREFCFG="rat_acq_order"
# POST: Sets new RAT acquisition order
#
# AT commands:
#   AT+QNWPREFCFG="rat_acq_order"              -> Current order (e.g. NR5G:LTE)
#   AT+QNWPREFCFG="rat_acq_order",<order>      -> Set order (e.g. LTE:NR5G)
#
# Endpoint: GET/POST /cgi-bin/quecmanager/cellular/network_priority.sh
# Install location: /www/cgi-bin/quecmanager/cellular/network_priority.sh
# =============================================================================

# --- Logging -----------------------------------------------------------------
qlog_init "cgi_net_prio"
cgi_headers
cgi_handle_options

# --- HTTP Headers ------------------------------------------------------------

# --- Handle CORS preflight ---------------------------------------------------

# --- Helper: Execute AT command via qcmd, return stripped response -----------
strip_at_response() {
    printf '%s' "$1" | tr -d '\r' | sed '1d' | sed '/^OK$/d' | sed '/^ERROR$/d'
}

run_at() {
    local raw
    raw=$(qcmd "$1" 2>/dev/null)
    local rc=$?
    if [ $rc -ne 0 ] || [ -z "$raw" ]; then
        return 1
    fi
    case "$raw" in
        *ERROR*) return 1 ;;
    esac
    strip_at_response "$raw"
}

# =============================================================================
# GET — Fetch current RAT acquisition order
# =============================================================================
if [ "$REQUEST_METHOD" = "GET" ]; then
    qlog_info "Fetching RAT acquisition order"

    resp=$(run_at 'AT+QNWPREFCFG="rat_acq_order"')

    if [ -z "$resp" ]; then
        echo '{"success":false,"error":"at_failed","detail":"Failed to query rat_acq_order"}'
        exit 0
    fi

    # +QNWPREFCFG: "rat_acq_order",NR5G:LTE:WCDMA
    order=$(printf '%s' "$resp" | awk -F',' '
        /\+QNWPREFCFG:.*"rat_acq_order"/ {
            val = $2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
            if (val != "") print val
        }
    ')

    if [ -z "$order" ]; then
        echo '{"success":false,"error":"parse_failed","detail":"Could not parse rat_acq_order response"}'
        exit 0
    fi

    qlog_info "RAT acquisition order: $order"

    jq -n --arg order "$order" '{success: true, order: $order}'
    exit 0
fi

# =============================================================================
# POST — Set RAT acquisition order
# =============================================================================
if [ "$REQUEST_METHOD" = "POST" ]; then

    # --- Read POST body ---
    if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
        POST_DATA=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
    else
        echo '{"success":false,"error":"no_body","detail":"POST body is empty"}'
        exit 0
    fi

    ORDER=$(printf '%s' "$POST_DATA" | jq -r '.order // empty')

    if [ -z "$ORDER" ]; then
        echo '{"success":false,"error":"missing_order","detail":"order field is required"}'
        exit 0
    fi

    # Validate: only allow known RAT names separated by colons
    case "$ORDER" in
        *[!A-Z0-9:]*)
            echo '{"success":false,"error":"invalid_order","detail":"order must contain only RAT names separated by colons"}'
            exit 0
            ;;
    esac

    qlog_info "Setting RAT acquisition order: $ORDER"

    result=$(qcmd "AT+QNWPREFCFG=\"rat_acq_order\",$ORDER" 2>/dev/null)
    case "$result" in
        *ERROR*)
            qlog_error "Failed to set rat_acq_order: $result"
            echo '{"success":false,"error":"at_failed","detail":"AT+QNWPREFCFG returned ERROR"}'
            exit 0
            ;;
    esac

    qlog_info "RAT acquisition order set to: $ORDER"
    jq -n '{"success":true}'
    exit 0
fi

# --- Method not allowed -------------------------------------------------------
cgi_method_not_allowed
