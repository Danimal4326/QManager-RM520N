#!/bin/sh
# =============================================================================
# status.sh — CGI Endpoint: Get Tower Lock Status
# =============================================================================
# Returns current tower lock state from the modem, config from file,
# and failover state from flag files.
#
# Queries 3 AT commands (sip-don't-gulp: sleep between each):
#   1. AT+QNWLOCK="common/4g"   — LTE lock state
#   2. AT+QNWLOCK="common/5g"   — NR-SA lock state
#   3. AT+QNWLOCK="save_ctrl"   — Persistence state
#
# Plus reads config file and failover flags (no modem contact).
#
# Endpoint: GET /cgi-bin/quecmanager/tower/status.sh
# Install location: /www/cgi-bin/quecmanager/tower/status.sh
# =============================================================================

# --- Logging -----------------------------------------------------------------
. /usr/lib/qmanager/qlog.sh 2>/dev/null || {
    qlog_init() { :; }
    qlog_info() { :; }
    qlog_warn() { :; }
    qlog_error() { :; }
    qlog_debug() { :; }
}
qlog_init "cgi_tower_status"

# --- Load library ------------------------------------------------------------
. /usr/lib/qmanager/tower_lock_mgr.sh 2>/dev/null

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

# --- Ensure config exists ----------------------------------------------------
tower_config_init

# --- Query LTE lock state ----------------------------------------------------
qlog_debug "Querying LTE lock state"
lte_state=$(tower_read_lte_lock)
sleep 0.1

# --- Query NR-SA lock state --------------------------------------------------
qlog_debug "Querying NR-SA lock state"
nr_state=$(tower_read_nr_lock)
sleep 0.1

# --- Query persist state -----------------------------------------------------
qlog_debug "Querying persist state"
persist_state=$(tower_read_persist)

# --- Parse LTE lock state into JSON ------------------------------------------
lte_locked="false"
lte_cells_json="[]"

case "$lte_state" in
    locked*)
        lte_locked="true"
        # Parse: "locked <num> <earfcn1> <pci1> [<earfcn2> <pci2> ...]"
        set -- $lte_state  # word split
        shift  # remove "locked"
        local_num="$1"
        shift  # remove num_cells
        lte_cells_json="["
        local_first="true"
        while [ $# -ge 2 ]; do
            if [ "$local_first" = "true" ]; then
                local_first="false"
            else
                lte_cells_json="${lte_cells_json},"
            fi
            lte_cells_json="${lte_cells_json}{\"earfcn\":$1,\"pci\":$2}"
            shift 2
        done
        lte_cells_json="${lte_cells_json}]"
        ;;
    error)
        qlog_warn "Failed to read LTE lock state"
        ;;
esac

# --- Parse NR-SA lock state into JSON ----------------------------------------
nr_locked="false"
nr_cell_json="null"

case "$nr_state" in
    locked*)
        nr_locked="true"
        # Parse: "locked <pci> <arfcn> <scs> <band>"
        set -- $nr_state
        shift  # remove "locked"
        nr_cell_json="{\"pci\":$1,\"arfcn\":$2,\"scs\":$3,\"band\":$4}"
        ;;
    error)
        qlog_warn "Failed to read NR-SA lock state"
        ;;
esac

# --- Parse persist state -----------------------------------------------------
persist_lte="false"
persist_nr="false"

set -- $persist_state
[ "$1" = "1" ] && persist_lte="true"
[ "$2" = "1" ] && persist_nr="true"

# --- Read config file (no modem contact) -------------------------------------
config_json=$(tower_config_read)

# --- Read failover state (no modem contact) ----------------------------------
failover_enabled="false"
failover_activated="false"
watcher_running="false"

# Check failover enabled from config
fo_enabled_val=$(printf '%s' "$config_json" | sed -n '/"failover"/,/}/p' | grep '"enabled"' | head -1 | sed 's/.*: *//;s/[, ]//g')
[ "$fo_enabled_val" = "true" ] && failover_enabled="true"

# Check activation flag
[ -f "$TOWER_FAILOVER_FLAG" ] && failover_activated="true"

# Check watcher PID
if [ -f "$TOWER_FAILOVER_PID" ]; then
    watcher_pid=$(cat "$TOWER_FAILOVER_PID" 2>/dev/null | tr -d ' \n\r')
    if [ -n "$watcher_pid" ] && kill -0 "$watcher_pid" 2>/dev/null; then
        watcher_running="true"
    fi
fi

# --- Build response ----------------------------------------------------------
printf '{"success":true,'
printf '"modem_state":{'
printf '"lte_locked":%s,' "$lte_locked"
printf '"lte_cells":%s,' "$lte_cells_json"
printf '"nr_locked":%s,' "$nr_locked"
printf '"nr_cell":%s,' "$nr_cell_json"
printf '"persist_lte":%s,' "$persist_lte"
printf '"persist_nr":%s' "$persist_nr"
printf '},'
printf '"config":%s,' "$config_json"
printf '"failover_state":{'
printf '"enabled":%s,' "$failover_enabled"
printf '"activated":%s,' "$failover_activated"
printf '"watcher_running":%s' "$watcher_running"
printf '}}\n'
