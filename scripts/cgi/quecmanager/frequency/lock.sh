#!/bin/sh
. /usr/lib/qmanager/cgi_base.sh
# =============================================================================
# lock.sh — CGI Endpoint: Apply/Clear Frequency Lock
# =============================================================================
# Handles frequency lock and unlock operations for both LTE and NR5G.
# Checks tower lock mutual exclusion before applying frequency locks.
#
# NOTE: The NR5G earfcn_lock command cannot coexist with AT+QNWLOCK="common/5g".
# NOTE: LTE earfcn_lock on unsupported bands may cause modem crash dump.
#
# POST body examples:
#   LTE lock:   {"type":"lte","action":"lock","earfcns":[1300,3400]}
#   LTE unlock: {"type":"lte","action":"unlock"}
#   NR lock:    {"type":"nr","action":"lock","entries":[{"arfcn":504990,"scs":30}]}
#   NR unlock:  {"type":"nr","action":"unlock"}
#
# Endpoint: POST /cgi-bin/quecmanager/frequency/lock.sh
# Install location: /www/cgi-bin/quecmanager/frequency/lock.sh
# =============================================================================

# --- Logging -----------------------------------------------------------------
qlog_init "cgi_freq_lock"
cgi_headers
cgi_handle_options

# --- Load tower lock library (for tower_read_lte_lock / tower_read_nr_lock) --
. /usr/lib/qmanager/tower_lock_mgr.sh 2>/dev/null

# --- HTTP Headers ------------------------------------------------------------

# --- Handle CORS preflight ---------------------------------------------------

# --- Validate method ---------------------------------------------------------
if [ "$REQUEST_METHOD" != "POST" ]; then
    echo '{"success":false,"error":"method_not_allowed","detail":"Use POST"}'
    exit 0
fi

# --- Read POST body ----------------------------------------------------------
cgi_read_post

# --- Parse common fields ----------------------------------------------------
LOCK_TYPE=$(printf '%s' "$POST_DATA" | jq -r '.type // empty' 2>/dev/null)
ACTION=$(printf '%s' "$POST_DATA" | jq -r '.action // empty' 2>/dev/null)

if [ -z "$LOCK_TYPE" ]; then
    echo '{"success":false,"error":"no_type","detail":"Missing type field (lte or nr)"}'
    exit 0
fi

if [ -z "$ACTION" ]; then
    echo '{"success":false,"error":"no_action","detail":"Missing action field (lock or unlock)"}'
    exit 0
fi

# =============================================================================
# LTE Frequency Lock/Unlock
# =============================================================================
if [ "$LOCK_TYPE" = "lte" ]; then

    if [ "$ACTION" = "lock" ]; then
        # --- Check tower lock mutual exclusion ---
        lte_tower_state=$(tower_read_lte_lock 2>/dev/null)
        case "$lte_tower_state" in
            locked*)
                echo '{"success":false,"error":"tower_lock_active","detail":"Cannot use frequency lock while LTE tower lock is active. Disable tower lock first."}'
                exit 0
                ;;
        esac

        # --- Parse earfcns array ---
        earfcn_count=$(printf '%s' "$POST_DATA" | jq -r '.earfcns | length' 2>/dev/null)

        if [ -z "$earfcn_count" ] || [ "$earfcn_count" -lt 1 ] 2>/dev/null || [ "$earfcn_count" -gt 2 ] 2>/dev/null; then
            echo '{"success":false,"error":"invalid_count","detail":"LTE frequency lock requires 1-2 EARFCNs"}'
            exit 0
        fi

        # Build colon-separated EARFCN list and validate
        earfcn_list=""
        i=0
        while [ "$i" -lt "$earfcn_count" ]; do
            val=$(printf '%s' "$POST_DATA" | jq -r ".earfcns[$i] // empty" 2>/dev/null)

            # Validate numeric
            case "$val" in
                ''|*[!0-9]*)
                    echo '{"success":false,"error":"invalid_earfcn","detail":"EARFCN must be a positive integer"}'
                    exit 0
                    ;;
            esac

            if [ -z "$earfcn_list" ]; then
                earfcn_list="$val"
            else
                earfcn_list="${earfcn_list}:${val}"
            fi
            i=$((i + 1))
        done

        qlog_info "LTE freq lock: $earfcn_count EARFCN(s) — $earfcn_list"

        # Send AT command
        result=$(qcmd "AT+QNWCFG=\"lte_earfcn_lock\",$earfcn_count,$earfcn_list" 2>/dev/null)
        rc=$?

        if [ $rc -ne 0 ] || [ -z "$result" ]; then
            qlog_error "LTE freq lock failed (rc=$rc)"
            echo '{"success":false,"error":"modem_error","detail":"Failed to send LTE frequency lock command"}'
            exit 0
        fi

        case "$result" in
            *ERROR*)
                qlog_error "LTE freq lock AT ERROR: $result"
                echo '{"success":false,"error":"at_error","detail":"Modem rejected LTE frequency lock command"}'
                exit 0
                ;;
        esac

        qlog_info "LTE freq lock applied successfully"
        jq -n --argjson count "$earfcn_count" \
            '{"success":true,"type":"lte","action":"lock","count":$count}'

    elif [ "$ACTION" = "unlock" ]; then
        result=$(qcmd 'AT+QNWCFG="lte_earfcn_lock",0' 2>/dev/null)
        rc=$?

        if [ $rc -ne 0 ] || [ -z "$result" ]; then
            qlog_error "LTE freq unlock failed (rc=$rc)"
            echo '{"success":false,"error":"modem_error","detail":"Failed to clear LTE frequency lock"}'
            exit 0
        fi

        case "$result" in
            *ERROR*)
                qlog_error "LTE freq unlock AT ERROR: $result"
                echo '{"success":false,"error":"at_error","detail":"Modem rejected LTE frequency unlock command"}'
                exit 0
                ;;
        esac

        qlog_info "LTE freq lock cleared"
        echo '{"success":true,"type":"lte","action":"unlock"}'
    else
        echo '{"success":false,"error":"invalid_action","detail":"action must be lock or unlock"}'
    fi

# =============================================================================
# NR5G Frequency Lock/Unlock
# =============================================================================
elif [ "$LOCK_TYPE" = "nr" ]; then

    if [ "$ACTION" = "lock" ]; then
        # --- Check tower lock mutual exclusion ---
        nr_tower_state=$(tower_read_nr_lock 2>/dev/null)
        case "$nr_tower_state" in
            locked*)
                echo '{"success":false,"error":"tower_lock_active","detail":"Cannot use frequency lock while NR tower lock is active. This command cannot be used together with AT+QNWLOCK common/5g."}'
                exit 0
                ;;
        esac

        # --- Parse entries array ---
        nr_count=$(printf '%s' "$POST_DATA" | jq -r '.entries | length' 2>/dev/null)

        if [ -z "$nr_count" ] || [ "$nr_count" -lt 1 ] 2>/dev/null || [ "$nr_count" -gt 32 ] 2>/dev/null; then
            echo '{"success":false,"error":"invalid_count","detail":"NR frequency lock requires 1-32 entries"}'
            exit 0
        fi

        # Build colon-separated EARFCN:SCS pairs and validate
        arfcn_list=""
        i=0
        while [ "$i" -lt "$nr_count" ]; do
            arfcn=$(printf '%s' "$POST_DATA" | jq -r ".entries[$i].arfcn // empty" 2>/dev/null)
            scs=$(printf '%s' "$POST_DATA" | jq -r ".entries[$i].scs // empty" 2>/dev/null)

            # Validate ARFCN is numeric
            case "$arfcn" in
                ''|*[!0-9]*)
                    echo '{"success":false,"error":"invalid_arfcn","detail":"NR-ARFCN must be a positive integer"}'
                    exit 0
                    ;;
            esac

            # Validate SCS value
            case "$scs" in
                15|30|60|120|240) ;;
                *)
                    echo '{"success":false,"error":"invalid_scs","detail":"SCS must be 15, 30, 60, 120, or 240 kHz"}'
                    exit 0
                    ;;
            esac

            if [ -z "$arfcn_list" ]; then
                arfcn_list="${arfcn}:${scs}"
            else
                arfcn_list="${arfcn_list}:${arfcn}:${scs}"
            fi
            i=$((i + 1))
        done

        qlog_info "NR freq lock: $nr_count entry/entries — $arfcn_list"

        # Send AT command
        result=$(qcmd "AT+QNWCFG=\"nr5g_earfcn_lock\",$nr_count,$arfcn_list" 2>/dev/null)
        rc=$?

        if [ $rc -ne 0 ] || [ -z "$result" ]; then
            qlog_error "NR freq lock failed (rc=$rc)"
            echo '{"success":false,"error":"modem_error","detail":"Failed to send NR frequency lock command"}'
            exit 0
        fi

        case "$result" in
            *ERROR*)
                qlog_error "NR freq lock AT ERROR: $result"
                echo '{"success":false,"error":"at_error","detail":"Modem rejected NR frequency lock command"}'
                exit 0
                ;;
        esac

        qlog_info "NR freq lock applied successfully"
        jq -n --argjson count "$nr_count" \
            '{"success":true,"type":"nr","action":"lock","count":$count}'

    elif [ "$ACTION" = "unlock" ]; then
        result=$(qcmd 'AT+QNWCFG="nr5g_earfcn_lock",0' 2>/dev/null)
        rc=$?

        if [ $rc -ne 0 ] || [ -z "$result" ]; then
            qlog_error "NR freq unlock failed (rc=$rc)"
            echo '{"success":false,"error":"modem_error","detail":"Failed to clear NR frequency lock"}'
            exit 0
        fi

        case "$result" in
            *ERROR*)
                qlog_error "NR freq unlock AT ERROR: $result"
                echo '{"success":false,"error":"at_error","detail":"Modem rejected NR frequency unlock command"}'
                exit 0
                ;;
        esac

        qlog_info "NR freq lock cleared"
        echo '{"success":true,"type":"nr","action":"unlock"}'
    else
        echo '{"success":false,"error":"invalid_action","detail":"action must be lock or unlock"}'
    fi

else
    echo '{"success":false,"error":"invalid_type","detail":"type must be lte or nr"}'
fi
