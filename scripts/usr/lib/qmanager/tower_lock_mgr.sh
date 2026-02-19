#!/bin/sh
# =============================================================================
# tower_lock_mgr.sh — QManager Tower Lock Manager Library
# =============================================================================
# A sourceable library providing tower lock config CRUD, AT command
# builders/parsers, and signal quality calculation.
#
# This is a LIBRARY — no persistent process, no polling.
# CGI scripts and the failover/schedule scripts source it.
#
# Dependencies: qcmd, qlog_* functions (from qlog.sh)
# Install location: /usr/lib/qmanager/tower_lock_mgr.sh
#
# Usage:
#   . /usr/lib/qmanager/tower_lock_mgr.sh
#   tower_config_read           → Cat config JSON to stdout
#   tower_config_init           → Create default config if missing
#   tower_config_update_field   → Update a top-level field in config
#   tower_lock_lte <n> <pairs>  → Send AT+QNWLOCK="common/4g" command
#   tower_unlock_lte            → Clear LTE lock
#   tower_lock_nr <pci> <arfcn> <scs> <band> → Send AT+QNWLOCK="common/5g"
#   tower_unlock_nr             → Clear NR-SA lock
#   tower_read_lte_lock         → Query and parse LTE lock state
#   tower_read_nr_lock          → Query and parse NR-SA lock state
#   tower_set_persist <0|1>     → Send AT+QNWLOCK="save_ctrl"
#   tower_read_persist          → Query and parse persist state
#   calc_signal_quality <rsrp>  → Returns 0-100 integer
# =============================================================================

# --- Configuration -----------------------------------------------------------
TOWER_CONFIG_FILE="/etc/qmanager/tower_lock.json"
TOWER_FAILOVER_FLAG="/tmp/qmanager_tower_failover"
TOWER_FAILOVER_PID="/tmp/qmanager_tower_failover.pid"
TOWER_FAILOVER_SCRIPT="/usr/bin/qmanager_tower_failover"

# Ensure config directory exists
mkdir -p /etc/qmanager 2>/dev/null

# =============================================================================
# Config File Operations
# =============================================================================

# Create default config file if it doesn't exist
tower_config_init() {
    [ -f "$TOWER_CONFIG_FILE" ] && return 0

    cat > "$TOWER_CONFIG_FILE" << 'DEFAULTCFG'
{
  "lte": {
    "enabled": false,
    "cells": [null, null, null]
  },
  "nr_sa": {
    "enabled": false,
    "pci": null,
    "arfcn": null,
    "scs": null,
    "band": null
  },
  "persist": false,
  "failover": {
    "enabled": true,
    "threshold": 20
  },
  "schedule": {
    "enabled": false,
    "start_time": "08:00",
    "end_time": "22:00",
    "days": [1, 2, 3, 4, 5]
  }
}
DEFAULTCFG
    qlog_info "Created default tower lock config"
}

# Read the entire config file to stdout
tower_config_read() {
    tower_config_init
    cat "$TOWER_CONFIG_FILE" 2>/dev/null
}

# Write complete config JSON (from stdin or $1) to file atomically
tower_config_write() {
    local json="$1"
    if [ -z "$json" ]; then
        json=$(cat)
    fi
    local tmp="${TOWER_CONFIG_FILE}.tmp"
    printf '%s\n' "$json" > "$tmp"
    mv "$tmp" "$TOWER_CONFIG_FILE"
}

# Extract a simple value from the config by grep pattern
# Args: $1=key (exact JSON key to search for)
# Returns: raw value (unquoted for strings, raw for numbers/bools)
tower_config_get() {
    local key="$1"
    tower_config_init
    # Try string value first, then numeric/bool
    local val
    val=$(grep "\"$key\"" "$TOWER_CONFIG_FILE" 2>/dev/null | head -1 | \
        sed 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*//' | \
        sed 's/[",]//g' | tr -d ' \r\n')
    printf '%s' "$val"
}

# =============================================================================
# LTE Lock Config Update
# =============================================================================
# Rewrites the lte section of the config file.
# Args: $1=enabled (true/false), $2=cell1_earfcn, $3=cell1_pci,
#       $4=cell2_earfcn, $5=cell2_pci, $6=cell3_earfcn, $7=cell3_pci
# Empty earfcn/pci pairs become null slots.
tower_config_update_lte() {
    local enabled="$1"
    local c1_e="$2" c1_p="$3" c2_e="$4" c2_p="$5" c3_e="$6" c3_p="$7"

    tower_config_init
    local config
    config=$(cat "$TOWER_CONFIG_FILE" 2>/dev/null)

    # Build cells array
    local cell1="null" cell2="null" cell3="null"
    [ -n "$c1_e" ] && [ -n "$c1_p" ] && cell1="{\"earfcn\":$c1_e,\"pci\":$c1_p}"
    [ -n "$c2_e" ] && [ -n "$c2_p" ] && cell2="{\"earfcn\":$c2_e,\"pci\":$c2_p}"
    [ -n "$c3_e" ] && [ -n "$c3_p" ] && cell3="{\"earfcn\":$c3_e,\"pci\":$c3_p}"

    # Read existing config sections to preserve them
    local nr_sa persist failover schedule
    nr_sa=$(printf '%s' "$config" | sed -n '/"nr_sa"/,/^  }/p')
    persist=$(tower_config_get "persist")
    [ "$persist" != "true" ] && persist="false"

    # Extract failover section
    local fo_enabled fo_threshold
    fo_enabled=$(printf '%s' "$config" | grep '"enabled"' | tail -2 | head -1 | sed 's/.*: *//;s/[, ]//g')
    fo_threshold=$(tower_config_get "threshold")
    [ -z "$fo_threshold" ] && fo_threshold="20"

    # Extract schedule section
    local sch_enabled sch_start sch_end sch_days
    sch_enabled=$(printf '%s' "$config" | sed -n '/"schedule"/,/}/p' | grep '"enabled"' | head -1 | sed 's/.*: *//;s/[, ]//g')
    sch_start=$(printf '%s' "$config" | grep '"start_time"' | head -1 | sed 's/.*: *"//;s/".*//;s/\r//')
    sch_end=$(printf '%s' "$config" | grep '"end_time"' | head -1 | sed 's/.*: *"//;s/".*//;s/\r//')
    sch_days=$(printf '%s' "$config" | grep '"days"' | head -1 | sed 's/.*\[//;s/\].*//')

    [ -z "$sch_enabled" ] && sch_enabled="false"
    [ -z "$sch_start" ] && sch_start="08:00"
    [ -z "$sch_end" ] && sch_end="22:00"
    [ -z "$sch_days" ] && sch_days="1, 2, 3, 4, 5"

    # Extract NR-SA fields
    local nr_pci nr_arfcn nr_scs nr_band nr_enabled
    nr_enabled=$(printf '%s' "$config" | sed -n '/"nr_sa"/,/}/p' | grep '"enabled"' | head -1 | sed 's/.*: *//;s/[, ]//g')
    nr_pci=$(printf '%s' "$config" | sed -n '/"nr_sa"/,/}/p' | grep '"pci"' | head -1 | sed 's/.*: *//;s/[, ]//g')
    nr_arfcn=$(printf '%s' "$config" | sed -n '/"nr_sa"/,/}/p' | grep '"arfcn"' | head -1 | sed 's/.*: *//;s/[, ]//g')
    nr_scs=$(printf '%s' "$config" | sed -n '/"nr_sa"/,/}/p' | grep '"scs"' | head -1 | sed 's/.*: *//;s/[, ]//g')
    nr_band=$(printf '%s' "$config" | sed -n '/"nr_sa"/,/}/p' | grep '"band"' | head -1 | sed 's/.*: *//;s/[, ]//g')
    [ -z "$nr_enabled" ] && nr_enabled="false"
    [ -z "$nr_pci" ] && nr_pci="null"
    [ -z "$nr_arfcn" ] && nr_arfcn="null"
    [ -z "$nr_scs" ] && nr_scs="null"
    [ -z "$nr_band" ] && nr_band="null"

    # Failover enabled — need to look specifically in the failover section
    local failover_enabled_val
    failover_enabled_val=$(printf '%s' "$config" | sed -n '/"failover"/,/}/p' | grep '"enabled"' | head -1 | sed 's/.*: *//;s/[, ]//g')
    [ -z "$failover_enabled_val" ] && failover_enabled_val="true"

    # Write complete config
    cat > "${TOWER_CONFIG_FILE}.tmp" << EOF
{
  "lte": {
    "enabled": $enabled,
    "cells": [$cell1, $cell2, $cell3]
  },
  "nr_sa": {
    "enabled": $nr_enabled,
    "pci": $nr_pci,
    "arfcn": $nr_arfcn,
    "scs": $nr_scs,
    "band": $nr_band
  },
  "persist": $persist,
  "failover": {
    "enabled": $failover_enabled_val,
    "threshold": $fo_threshold
  },
  "schedule": {
    "enabled": $sch_enabled,
    "start_time": "$sch_start",
    "end_time": "$sch_end",
    "days": [$sch_days]
  }
}
EOF
    mv "${TOWER_CONFIG_FILE}.tmp" "$TOWER_CONFIG_FILE"
}

# =============================================================================
# NR-SA Lock Config Update
# =============================================================================
# Args: $1=enabled (true/false), $2=pci, $3=arfcn, $4=scs, $5=band
tower_config_update_nr() {
    local enabled="$1"
    local pci="${2:-null}" arfcn="${3:-null}" scs="${4:-null}" band="${5:-null}"

    tower_config_init
    local config
    config=$(cat "$TOWER_CONFIG_FILE" 2>/dev/null)

    # Read LTE section
    local lte_enabled c1 c2 c3
    lte_enabled=$(printf '%s' "$config" | sed -n '/"lte"/,/\]/p' | grep '"enabled"' | head -1 | sed 's/.*: *//;s/[, ]//g')
    [ -z "$lte_enabled" ] && lte_enabled="false"

    # Extract cells array as-is (preserve existing cells)
    local cells_line
    cells_line=$(printf '%s' "$config" | tr '\n' '|' | sed 's/.*"cells"[[:space:]]*:[[:space:]]*\[//;s/\].*//' | tr '|' '\n')
    # Reconstruct: extract each cell object or null
    c1=$(printf '%s' "$cells_line" | awk -F',' 'NR==1{
        gsub(/^[[:space:]]+|[[:space:]]+$/,"",$0)
        # Find first cell - could be null or object
    }' 2>/dev/null)

    # Simpler approach: re-read the full cells array from the file
    local cells_json
    cells_json=$(awk '/"cells"/{found=1} found{print} /\]/{if(found)exit}' "$TOWER_CONFIG_FILE" | \
        sed '1s/.*\[/[/;' | tr -d '\n' | sed 's/[[:space:]]*//g')
    [ -z "$cells_json" ] && cells_json="[null,null,null]"

    # Read other sections
    local persist failover_enabled fo_threshold
    persist=$(tower_config_get "persist")
    [ "$persist" != "true" ] && persist="false"
    failover_enabled=$(printf '%s' "$config" | sed -n '/"failover"/,/}/p' | grep '"enabled"' | head -1 | sed 's/.*: *//;s/[, ]//g')
    fo_threshold=$(tower_config_get "threshold")
    [ -z "$failover_enabled" ] && failover_enabled="true"
    [ -z "$fo_threshold" ] && fo_threshold="20"

    local sch_enabled sch_start sch_end sch_days
    sch_enabled=$(printf '%s' "$config" | sed -n '/"schedule"/,/}/p' | grep '"enabled"' | head -1 | sed 's/.*: *//;s/[, ]//g')
    sch_start=$(printf '%s' "$config" | grep '"start_time"' | head -1 | sed 's/.*: *"//;s/".*//;s/\r//')
    sch_end=$(printf '%s' "$config" | grep '"end_time"' | head -1 | sed 's/.*: *"//;s/".*//;s/\r//')
    sch_days=$(printf '%s' "$config" | grep '"days"' | head -1 | sed 's/.*\[//;s/\].*//')
    [ -z "$sch_enabled" ] && sch_enabled="false"
    [ -z "$sch_start" ] && sch_start="08:00"
    [ -z "$sch_end" ] && sch_end="22:00"
    [ -z "$sch_days" ] && sch_days="1, 2, 3, 4, 5"

    cat > "${TOWER_CONFIG_FILE}.tmp" << EOF
{
  "lte": {
    "enabled": $lte_enabled,
    "cells": $cells_json
  },
  "nr_sa": {
    "enabled": $enabled,
    "pci": $pci,
    "arfcn": $arfcn,
    "scs": $scs,
    "band": $band
  },
  "persist": $persist,
  "failover": {
    "enabled": $failover_enabled,
    "threshold": $fo_threshold
  },
  "schedule": {
    "enabled": $sch_enabled,
    "start_time": "$sch_start",
    "end_time": "$sch_end",
    "days": [$sch_days]
  }
}
EOF
    mv "${TOWER_CONFIG_FILE}.tmp" "$TOWER_CONFIG_FILE"
}

# =============================================================================
# Settings Config Update (persist + failover)
# =============================================================================
# Args: $1=persist(true/false), $2=failover_enabled(true/false), $3=threshold
tower_config_update_settings() {
    local persist="$1" fo_enabled="$2" fo_threshold="$3"

    tower_config_init
    local config
    config=$(cat "$TOWER_CONFIG_FILE" 2>/dev/null)

    # Read LTE section
    local lte_enabled
    lte_enabled=$(printf '%s' "$config" | sed -n '/"lte"/,/\]/p' | grep '"enabled"' | head -1 | sed 's/.*: *//;s/[, ]//g')
    [ -z "$lte_enabled" ] && lte_enabled="false"
    local cells_json
    cells_json=$(awk '/"cells"/{found=1} found{print} /\]/{if(found)exit}' "$TOWER_CONFIG_FILE" | \
        sed '1s/.*\[/[/;' | tr -d '\n' | sed 's/[[:space:]]*//g')
    [ -z "$cells_json" ] && cells_json="[null,null,null]"

    # Read NR-SA section
    local nr_enabled nr_pci nr_arfcn nr_scs nr_band
    nr_enabled=$(printf '%s' "$config" | sed -n '/"nr_sa"/,/}/p' | grep '"enabled"' | head -1 | sed 's/.*: *//;s/[, ]//g')
    nr_pci=$(printf '%s' "$config" | sed -n '/"nr_sa"/,/}/p' | grep '"pci"' | head -1 | sed 's/.*: *//;s/[, ]//g')
    nr_arfcn=$(printf '%s' "$config" | sed -n '/"nr_sa"/,/}/p' | grep '"arfcn"' | head -1 | sed 's/.*: *//;s/[, ]//g')
    nr_scs=$(printf '%s' "$config" | sed -n '/"nr_sa"/,/}/p' | grep '"scs"' | head -1 | sed 's/.*: *//;s/[, ]//g')
    nr_band=$(printf '%s' "$config" | sed -n '/"nr_sa"/,/}/p' | grep '"band"' | head -1 | sed 's/.*: *//;s/[, ]//g')
    [ -z "$nr_enabled" ] && nr_enabled="false"
    [ -z "$nr_pci" ] && nr_pci="null"
    [ -z "$nr_arfcn" ] && nr_arfcn="null"
    [ -z "$nr_scs" ] && nr_scs="null"
    [ -z "$nr_band" ] && nr_band="null"

    # Read schedule section
    local sch_enabled sch_start sch_end sch_days
    sch_enabled=$(printf '%s' "$config" | sed -n '/"schedule"/,/}/p' | grep '"enabled"' | head -1 | sed 's/.*: *//;s/[, ]//g')
    sch_start=$(printf '%s' "$config" | grep '"start_time"' | head -1 | sed 's/.*: *"//;s/".*//;s/\r//')
    sch_end=$(printf '%s' "$config" | grep '"end_time"' | head -1 | sed 's/.*: *"//;s/".*//;s/\r//')
    sch_days=$(printf '%s' "$config" | grep '"days"' | head -1 | sed 's/.*\[//;s/\].*//')
    [ -z "$sch_enabled" ] && sch_enabled="false"
    [ -z "$sch_start" ] && sch_start="08:00"
    [ -z "$sch_end" ] && sch_end="22:00"
    [ -z "$sch_days" ] && sch_days="1, 2, 3, 4, 5"

    cat > "${TOWER_CONFIG_FILE}.tmp" << EOF
{
  "lte": {
    "enabled": $lte_enabled,
    "cells": $cells_json
  },
  "nr_sa": {
    "enabled": $nr_enabled,
    "pci": $nr_pci,
    "arfcn": $nr_arfcn,
    "scs": $nr_scs,
    "band": $nr_band
  },
  "persist": $persist,
  "failover": {
    "enabled": $fo_enabled,
    "threshold": $fo_threshold
  },
  "schedule": {
    "enabled": $sch_enabled,
    "start_time": "$sch_start",
    "end_time": "$sch_end",
    "days": [$sch_days]
  }
}
EOF
    mv "${TOWER_CONFIG_FILE}.tmp" "$TOWER_CONFIG_FILE"
}

# =============================================================================
# AT Command Operations — LTE Tower Lock
# =============================================================================

# Send LTE tower lock command
# Args: $1=num_cells, then pairs: $2=earfcn1, $3=pci1, $4=earfcn2, $5=pci2, ...
tower_lock_lte() {
    local num="$1"
    shift
    local cmd="AT+QNWLOCK=\"common/4g\",$num"
    while [ $# -ge 2 ]; do
        cmd="${cmd},$1,$2"
        shift 2
    done
    qlog_info "LTE tower lock: $cmd"
    local result
    result=$(qcmd "$cmd" 2>/dev/null)
    local rc=$?
    printf '%s' "$result"
    return $rc
}

# Clear LTE tower lock
tower_unlock_lte() {
    qlog_info "Clearing LTE tower lock"
    local result
    result=$(qcmd 'AT+QNWLOCK="common/4g",0' 2>/dev/null)
    local rc=$?
    printf '%s' "$result"
    return $rc
}

# Query current LTE lock state
# Output: "locked <num_cells> <earfcn1> <pci1> [<earfcn2> <pci2> ...]" or "unlocked"
tower_read_lte_lock() {
    local result
    result=$(qcmd 'AT+QNWLOCK="common/4g"' 2>/dev/null)
    local rc=$?

    if [ $rc -ne 0 ] || [ -z "$result" ]; then
        printf 'error'
        return 1
    fi

    # Parse response: +QNWLOCK: "common/4g",<num>,<freq>,<pci>[,...]
    # or: +QNWLOCK: "common/4g",0
    local line
    line=$(printf '%s' "$result" | grep '+QNWLOCK:' | head -1 | tr -d '\r')

    if [ -z "$line" ]; then
        printf 'error'
        return 1
    fi

    # Extract everything after "common/4g",
    local params
    params=$(printf '%s' "$line" | sed 's/.*"common\/4g",//' | tr -d ' ')

    # First param is num_cells (or 0 for unlocked)
    local num_cells
    num_cells=$(printf '%s' "$params" | cut -d',' -f1)

    if [ "$num_cells" = "0" ] || [ -z "$num_cells" ]; then
        printf 'unlocked'
        return 0
    fi

    # Output: locked <num_cells> <earfcn1> <pci1> ...
    printf 'locked %s' "$num_cells"
    local remaining
    remaining=$(printf '%s' "$params" | sed 's/^[^,]*,//')
    # Parse pairs
    local i=0
    while [ $i -lt "$num_cells" ] && [ -n "$remaining" ]; do
        local earfcn pci
        earfcn=$(printf '%s' "$remaining" | cut -d',' -f1)
        pci=$(printf '%s' "$remaining" | cut -d',' -f2)
        printf ' %s %s' "$earfcn" "$pci"
        # Remove the consumed pair
        remaining=$(printf '%s' "$remaining" | sed 's/^[^,]*,[^,]*//' | sed 's/^,//')
        i=$((i + 1))
    done

    return 0
}

# =============================================================================
# AT Command Operations — NR-SA Tower Lock
# =============================================================================

# Send NR-SA tower lock command
# Args: $1=pci, $2=arfcn, $3=scs, $4=band
tower_lock_nr() {
    local pci="$1" arfcn="$2" scs="$3" band="$4"
    local cmd="AT+QNWLOCK=\"common/5g\",$pci,$arfcn,$scs,$band"
    qlog_info "NR-SA tower lock: $cmd"
    local result
    result=$(qcmd "$cmd" 2>/dev/null)
    local rc=$?
    printf '%s' "$result"
    return $rc
}

# Clear NR-SA tower lock
tower_unlock_nr() {
    qlog_info "Clearing NR-SA tower lock"
    local result
    result=$(qcmd 'AT+QNWLOCK="common/5g",0' 2>/dev/null)
    local rc=$?
    printf '%s' "$result"
    return $rc
}

# Query current NR-SA lock state
# Output: "locked <pci> <arfcn> <scs> <band>" or "unlocked"
tower_read_nr_lock() {
    local result
    result=$(qcmd 'AT+QNWLOCK="common/5g"' 2>/dev/null)
    local rc=$?

    if [ $rc -ne 0 ] || [ -z "$result" ]; then
        printf 'error'
        return 1
    fi

    local line
    line=$(printf '%s' "$result" | grep '+QNWLOCK:' | head -1 | tr -d '\r')

    if [ -z "$line" ]; then
        # No +QNWLOCK line could mean unlocked or error
        printf 'unlocked'
        return 0
    fi

    # Extract params after "common/5g"
    local params
    params=$(printf '%s' "$line" | sed 's/.*"common\/5g"//' | sed 's/^,//' | tr -d ' ')

    # If empty or just the key with no params — unlocked
    if [ -z "$params" ] || [ "$params" = "0" ]; then
        printf 'unlocked'
        return 0
    fi

    # Locked: params = <pci>,<arfcn>,<scs>,<band>
    local pci arfcn scs band
    pci=$(printf '%s' "$params" | cut -d',' -f1)
    arfcn=$(printf '%s' "$params" | cut -d',' -f2)
    scs=$(printf '%s' "$params" | cut -d',' -f3)
    band=$(printf '%s' "$params" | cut -d',' -f4)

    printf 'locked %s %s %s %s' "$pci" "$arfcn" "$scs" "$band"
    return 0
}

# =============================================================================
# AT Command Operations — Persistence Control
# =============================================================================

# Set persistence for both LTE and NR locks
# Args: $1=value (0 or 1)
tower_set_persist() {
    local val="$1"
    qlog_info "Setting tower lock persistence: $val"
    local result
    result=$(qcmd "AT+QNWLOCK=\"save_ctrl\",$val,$val" 2>/dev/null)
    local rc=$?
    printf '%s' "$result"
    return $rc
}

# Read current persistence state
# Output: "<lte_ctrl> <nr_ctrl>" (e.g., "1 1" or "0 0")
tower_read_persist() {
    local result
    result=$(qcmd 'AT+QNWLOCK="save_ctrl"' 2>/dev/null)
    local rc=$?

    if [ $rc -ne 0 ] || [ -z "$result" ]; then
        printf '0 0'
        return 1
    fi

    local line
    line=$(printf '%s' "$result" | grep '+QNWLOCK:' | head -1 | tr -d '\r')

    if [ -z "$line" ]; then
        printf '0 0'
        return 1
    fi

    # +QNWLOCK: "save_ctrl",<lte>,<nr>
    local params
    params=$(printf '%s' "$line" | sed 's/.*"save_ctrl",//' | tr -d ' ')
    local lte_ctrl nr_ctrl
    lte_ctrl=$(printf '%s' "$params" | cut -d',' -f1)
    nr_ctrl=$(printf '%s' "$params" | cut -d',' -f2)
    [ -z "$lte_ctrl" ] && lte_ctrl="0"
    [ -z "$nr_ctrl" ] && nr_ctrl="0"

    printf '%s %s' "$lte_ctrl" "$nr_ctrl"
    return 0
}

# =============================================================================
# Signal Quality Calculation
# =============================================================================

# Calculate signal quality percentage from RSRP
# Formula: clamp(0, 100, ((rsrp + 140) * 100) / 60)
# Maps: -140 dBm → 0%, -80 dBm → 100%
# Args: $1=rsrp (integer, e.g., -95)
# Output: integer 0-100
calc_signal_quality() {
    local rsrp="$1"

    # Validate input
    case "$rsrp" in
        ''|*[!0-9-]*) printf '0'; return 1 ;;
    esac

    local quality
    quality=$(( (rsrp + 140) * 100 / 60 ))
    [ "$quality" -lt 0 ] && quality=0
    [ "$quality" -gt 100 ] && quality=100
    printf '%s' "$quality"
    return 0
}

# =============================================================================
# Failover Watcher Management
# =============================================================================

# Kill any running failover watcher
tower_kill_failover_watcher() {
    if [ -f "$TOWER_FAILOVER_PID" ]; then
        local old_pid
        old_pid=$(cat "$TOWER_FAILOVER_PID" 2>/dev/null | tr -d ' \n\r')
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            kill "$old_pid" 2>/dev/null
            qlog_debug "Killed tower failover watcher (PID=$old_pid)"
        fi
        rm -f "$TOWER_FAILOVER_PID"
    fi
}

# Spawn failover watcher if enabled
# Returns: "true" if spawned, "false" if not
tower_spawn_failover_watcher() {
    # Check if failover is enabled in config
    local fo_enabled
    fo_enabled=$(tower_config_get "threshold" 2>/dev/null)
    # Actually check the failover.enabled field
    local config
    config=$(cat "$TOWER_CONFIG_FILE" 2>/dev/null)
    fo_enabled=$(printf '%s' "$config" | sed -n '/"failover"/,/}/p' | grep '"enabled"' | head -1 | sed 's/.*: *//;s/[, ]//g')

    if [ "$fo_enabled" != "true" ]; then
        printf 'false'
        return 0
    fi

    if [ ! -x "$TOWER_FAILOVER_SCRIPT" ]; then
        qlog_warn "Failover script not found or not executable: $TOWER_FAILOVER_SCRIPT"
        printf 'false'
        return 1
    fi

    # Kill any existing watcher
    tower_kill_failover_watcher

    # Clear previous activation flag
    rm -f "$TOWER_FAILOVER_FLAG"

    # Spawn new watcher (detached)
    ( "$TOWER_FAILOVER_SCRIPT" ) >/dev/null 2>&1 &
    qlog_info "Tower failover watcher spawned"
    printf 'true'
    return 0
}
