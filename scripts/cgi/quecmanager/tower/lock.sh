#!/bin/sh
# =============================================================================
# lock.sh — CGI Endpoint: Apply/Clear Tower Lock
# =============================================================================
# Handles tower lock and unlock operations for both LTE and NR-SA.
# On successful lock, updates config file and spawns failover watcher.
# On unlock, updates config and kills any running watcher.
#
# NOTE: Cell lock commands may disconnect the modem for 3-5 seconds
# before reconnecting. The failover watcher accounts for this with a
# 20-second settle delay.
#
# POST body examples:
#   LTE lock:   {"type":"lte","action":"lock","cells":[{"earfcn":1300,"pci":123},{"earfcn":1850,"pci":456}]}
#   LTE unlock: {"type":"lte","action":"unlock"}
#   NR-SA lock: {"type":"nr_sa","action":"lock","pci":901,"arfcn":504990,"scs":30,"band":41}
#   NR-SA unlock: {"type":"nr_sa","action":"unlock"}
#
# Endpoint: POST /cgi-bin/quecmanager/tower/lock.sh
# Install location: /www/cgi-bin/quecmanager/tower/lock.sh
# =============================================================================

# --- Logging -----------------------------------------------------------------
. /usr/lib/qmanager/qlog.sh 2>/dev/null || {
    qlog_init() { :; }
    qlog_info() { :; }
    qlog_warn() { :; }
    qlog_error() { :; }
    qlog_debug() { :; }
}
qlog_init "cgi_tower_lock"

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

# --- Parse common fields using jq --------------------------------------------
LOCK_TYPE=$(printf '%s' "$POST_DATA" | jq -r '.type // empty' 2>/dev/null)
ACTION=$(printf '%s' "$POST_DATA" | jq -r '.action // empty' 2>/dev/null)

if [ -z "$LOCK_TYPE" ]; then
    echo '{"success":false,"error":"no_type","detail":"Missing type field (lte or nr_sa)"}'
    exit 0
fi

if [ -z "$ACTION" ]; then
    echo '{"success":false,"error":"no_action","detail":"Missing action field (lock or unlock)"}'
    exit 0
fi

# --- Ensure config exists ----------------------------------------------------
tower_config_init

# =============================================================================
# LTE Lock/Unlock
# =============================================================================
if [ "$LOCK_TYPE" = "lte" ]; then

    if [ "$ACTION" = "lock" ]; then
        # --- Parse cells array from POST data using jq ---
        c1_earfcn=$(printf '%s' "$POST_DATA" | jq -r '.cells[0].earfcn // empty' 2>/dev/null)
        c1_pci=$(printf '%s' "$POST_DATA" | jq -r '.cells[0].pci // empty' 2>/dev/null)
        c2_earfcn=$(printf '%s' "$POST_DATA" | jq -r '.cells[1].earfcn // empty' 2>/dev/null)
        c2_pci=$(printf '%s' "$POST_DATA" | jq -r '.cells[1].pci // empty' 2>/dev/null)
        c3_earfcn=$(printf '%s' "$POST_DATA" | jq -r '.cells[2].earfcn // empty' 2>/dev/null)
        c3_pci=$(printf '%s' "$POST_DATA" | jq -r '.cells[2].pci // empty' 2>/dev/null)

        # Count valid cells
        num_cells=0
        at_args=""
        if [ -n "$c1_earfcn" ] && [ -n "$c1_pci" ]; then
            num_cells=$((num_cells + 1))
            at_args="$c1_earfcn $c1_pci"
        fi
        if [ -n "$c2_earfcn" ] && [ -n "$c2_pci" ]; then
            num_cells=$((num_cells + 1))
            at_args="$at_args $c2_earfcn $c2_pci"
        fi
        if [ -n "$c3_earfcn" ] && [ -n "$c3_pci" ]; then
            num_cells=$((num_cells + 1))
            at_args="$at_args $c3_earfcn $c3_pci"
        fi

        if [ "$num_cells" -eq 0 ]; then
            echo '{"success":false,"error":"no_cells","detail":"At least one EARFCN+PCI pair is required"}'
            exit 0
        fi

        # Validate ranges
        for val in $c1_earfcn $c2_earfcn $c3_earfcn; do
            [ -z "$val" ] && continue
            case "$val" in
                *[!0-9]*) echo '{"success":false,"error":"invalid_earfcn","detail":"EARFCN must be numeric"}'; exit 0 ;;
            esac
        done
        for val in $c1_pci $c2_pci $c3_pci; do
            [ -z "$val" ] && continue
            case "$val" in
                *[!0-9]*) echo '{"success":false,"error":"invalid_pci","detail":"PCI must be numeric"}'; exit 0 ;;
            esac
            if [ "$val" -gt 503 ]; then
                echo '{"success":false,"error":"invalid_pci","detail":"PCI must be 0-503"}'
                exit 0
            fi
        done

        qlog_info "LTE tower lock: $num_cells cell(s) — $at_args"

        # Send AT command
        result=$(tower_lock_lte "$num_cells" $at_args)
        rc=$?

        if [ $rc -ne 0 ] || [ -z "$result" ]; then
            qlog_error "LTE tower lock failed (rc=$rc)"
            echo '{"success":false,"error":"modem_error","detail":"Failed to send tower lock command"}'
            exit 0
        fi

        case "$result" in
            *ERROR*)
                qlog_error "LTE tower lock AT ERROR: $result"
                echo '{"success":false,"error":"at_error","detail":"Modem rejected tower lock command"}'
                exit 0
                ;;
        esac

        qlog_info "LTE tower lock applied successfully"

        # Update config file
        tower_config_update_lte "true" "$c1_earfcn" "$c1_pci" "$c2_earfcn" "$c2_pci" "$c3_earfcn" "$c3_pci"

        # Spawn failover watcher
        failover_armed=$(tower_spawn_failover_watcher)

        jq -n --argjson nc "$num_cells" --argjson fa "$failover_armed" \
            '{"success":true,"type":"lte","action":"lock","num_cells":$nc,"failover_armed":$fa}'

    elif [ "$ACTION" = "unlock" ]; then
        result=$(tower_unlock_lte)
        rc=$?

        if [ $rc -ne 0 ] || [ -z "$result" ]; then
            qlog_error "LTE tower unlock failed (rc=$rc)"
            echo '{"success":false,"error":"modem_error","detail":"Failed to clear tower lock"}'
            exit 0
        fi

        case "$result" in
            *ERROR*)
                qlog_error "LTE tower unlock AT ERROR: $result"
                echo '{"success":false,"error":"at_error","detail":"Modem rejected unlock command"}'
                exit 0
                ;;
        esac

        qlog_info "LTE tower lock cleared"

        # Update config — preserve ALL cell data, just set enabled=false
        tower_config_update '.lte.enabled = false'

        # Kill failover watcher
        tower_kill_failover_watcher
        rm -f "$TOWER_FAILOVER_FLAG"

        echo '{"success":true,"type":"lte","action":"unlock"}'
    else
        echo '{"success":false,"error":"invalid_action","detail":"action must be lock or unlock"}'
    fi

# =============================================================================
# NR-SA Lock/Unlock
# =============================================================================
elif [ "$LOCK_TYPE" = "nr_sa" ]; then

    if [ "$ACTION" = "lock" ]; then
        nr_pci=$(printf '%s' "$POST_DATA" | jq -r '.pci // empty' 2>/dev/null)
        nr_arfcn=$(printf '%s' "$POST_DATA" | jq -r '.arfcn // empty' 2>/dev/null)
        nr_scs=$(printf '%s' "$POST_DATA" | jq -r '.scs // empty' 2>/dev/null)
        nr_band=$(printf '%s' "$POST_DATA" | jq -r '.band // empty' 2>/dev/null)

        # Validate all fields present
        if [ -z "$nr_pci" ] || [ -z "$nr_arfcn" ] || [ -z "$nr_scs" ] || [ -z "$nr_band" ]; then
            echo '{"success":false,"error":"missing_fields","detail":"NR-SA lock requires pci, arfcn, scs, and band"}'
            exit 0
        fi

        # Validate SCS value
        case "$nr_scs" in
            15|30|60|120|240) ;;  # Valid SCS kHz values
            *)
                echo '{"success":false,"error":"invalid_scs","detail":"SCS must be 15, 30, 60, 120, or 240 kHz"}'
                exit 0
                ;;
        esac

        qlog_info "NR-SA tower lock: PCI=$nr_pci ARFCN=$nr_arfcn SCS=$nr_scs Band=$nr_band"

        result=$(tower_lock_nr "$nr_pci" "$nr_arfcn" "$nr_scs" "$nr_band")
        rc=$?

        if [ $rc -ne 0 ] || [ -z "$result" ]; then
            qlog_error "NR-SA tower lock failed (rc=$rc)"
            echo '{"success":false,"error":"modem_error","detail":"Failed to send NR tower lock command"}'
            exit 0
        fi

        case "$result" in
            *ERROR*)
                qlog_error "NR-SA tower lock AT ERROR: $result"
                echo '{"success":false,"error":"at_error","detail":"Modem rejected NR tower lock command"}'
                exit 0
                ;;
        esac

        qlog_info "NR-SA tower lock applied successfully"

        # Update config
        tower_config_update_nr "true" "$nr_pci" "$nr_arfcn" "$nr_scs" "$nr_band"

        # Spawn failover watcher
        failover_armed=$(tower_spawn_failover_watcher)

        jq -n --argjson fa "$failover_armed" \
            '{"success":true,"type":"nr_sa","action":"lock","failover_armed":$fa}'

    elif [ "$ACTION" = "unlock" ]; then
        result=$(tower_unlock_nr)
        rc=$?

        if [ $rc -ne 0 ] || [ -z "$result" ]; then
            qlog_error "NR-SA tower unlock failed (rc=$rc)"
            echo '{"success":false,"error":"modem_error","detail":"Failed to clear NR tower lock"}'
            exit 0
        fi

        case "$result" in
            *ERROR*)
                qlog_error "NR-SA tower unlock AT ERROR: $result"
                echo '{"success":false,"error":"at_error","detail":"Modem rejected NR unlock command"}'
                exit 0
                ;;
        esac

        qlog_info "NR-SA tower lock cleared"

        # Update config — preserve ALL NR params, just set enabled=false
        tower_config_update '.nr_sa.enabled = false'

        # Kill failover watcher
        tower_kill_failover_watcher
        rm -f "$TOWER_FAILOVER_FLAG"

        echo '{"success":true,"type":"nr_sa","action":"unlock"}'
    else
        echo '{"success":false,"error":"invalid_action","detail":"action must be lock or unlock"}'
    fi

else
    echo '{"success":false,"error":"invalid_type","detail":"type must be lte or nr_sa"}'
fi
