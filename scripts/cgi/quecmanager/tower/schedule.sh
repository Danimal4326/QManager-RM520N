#!/bin/sh
# =============================================================================
# schedule.sh — CGI Endpoint: Update Tower Lock Schedule
# =============================================================================
# Updates the schedule section of tower_lock.json and manages crontab
# entries for automatic tower lock enable/disable.
#
# POST body:
#   {"enabled": true, "start_time": "08:00", "end_time": "22:00", "days": [1,2,3,4,5]}
#
# When enabled, writes cron entries to apply/clear locks at scheduled times.
# When disabled, removes QManager tower schedule cron entries.
#
# Endpoint: POST /cgi-bin/quecmanager/tower/schedule.sh
# Install location: /www/cgi-bin/quecmanager/tower/schedule.sh
# =============================================================================

# --- Logging -----------------------------------------------------------------
. /usr/lib/qmanager/qlog.sh 2>/dev/null || {
    qlog_init() { :; }
    qlog_info() { :; }
    qlog_warn() { :; }
    qlog_error() { :; }
    qlog_debug() { :; }
}
qlog_init "cgi_tower_schedule"

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
parse_bool() {
    printf '%s' "$POST_DATA" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\(true\|false\|\"true\"\|\"false\"\).*/\1/p" | tr -d '"' | head -1
}
parse_str() {
    printf '%s' "$POST_DATA" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

ENABLED=$(parse_bool "enabled")
START_TIME=$(parse_str "start_time")
END_TIME=$(parse_str "end_time")

# Extract days array: [1,2,3,4,5] → "1,2,3,4,5"
DAYS_RAW=$(printf '%s' "$POST_DATA" | sed -n 's/.*"days"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' | tr -d ' ')

# --- Validate ----------------------------------------------------------------
if [ -z "$ENABLED" ]; then
    echo '{"success":false,"error":"no_enabled","detail":"Missing enabled field"}'
    exit 0
fi

if [ "$ENABLED" = "true" ]; then
    # Validate time format HH:MM
    case "$START_TIME" in
        [0-2][0-9]:[0-5][0-9]) ;;
        *)
            echo '{"success":false,"error":"invalid_start_time","detail":"start_time must be HH:MM format"}'
            exit 0
            ;;
    esac
    case "$END_TIME" in
        [0-2][0-9]:[0-5][0-9]) ;;
        *)
            echo '{"success":false,"error":"invalid_end_time","detail":"end_time must be HH:MM format"}'
            exit 0
            ;;
    esac

    # Validate days
    if [ -z "$DAYS_RAW" ]; then
        echo '{"success":false,"error":"no_days","detail":"At least one day must be selected"}'
        exit 0
    fi

    # Validate each day is 0-6
    invalid_day=""
    for d in $(echo "$DAYS_RAW" | tr ',' ' '); do
        case "$d" in
            0|1|2|3|4|5|6) ;;
            *) invalid_day="$d" ;;
        esac
    done
    if [ -n "$invalid_day" ]; then
        echo '{"success":false,"error":"invalid_day","detail":"Days must be 0-6 (0=Sun, 6=Sat)"}'
        exit 0
    fi
fi

# Ensure config exists
tower_config_init

qlog_info "Schedule update: enabled=$ENABLED start=$START_TIME end=$END_TIME days=$DAYS_RAW"

# --- Update config file schedule section -------------------------------------
# Read current config to preserve non-schedule fields
config=$(cat "$TOWER_CONFIG_FILE" 2>/dev/null)

# Read LTE section
lte_enabled=$(printf '%s' "$config" | sed -n '/"lte"/,/\]/p' | grep '"enabled"' | head -1 | sed 's/.*: *//;s/[, ]//g')
[ -z "$lte_enabled" ] && lte_enabled="false"
cells_json=$(awk '/"cells"/{found=1} found{print} /\]/{if(found)exit}' "$TOWER_CONFIG_FILE" | \
    sed '1s/.*\[/[/;' | tr -d '\n' | sed 's/[[:space:]]*//g')
[ -z "$cells_json" ] && cells_json="[null,null,null]"

# Read NR-SA section
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

# Read persist + failover
persist=$(tower_config_get "persist")
[ "$persist" != "true" ] && persist="false"
failover_enabled=$(printf '%s' "$config" | sed -n '/"failover"/,/}/p' | grep '"enabled"' | head -1 | sed 's/.*: *//;s/[, ]//g')
fo_threshold=$(tower_config_get "threshold")
[ -z "$failover_enabled" ] && failover_enabled="true"
[ -z "$fo_threshold" ] && fo_threshold="20"

# Use defaults for schedule if not provided (when disabling)
[ -z "$START_TIME" ] && START_TIME="08:00"
[ -z "$END_TIME" ] && END_TIME="22:00"
[ -z "$DAYS_RAW" ] && DAYS_RAW="1,2,3,4,5"

# Build days JSON array
DAYS_JSON=$(echo "$DAYS_RAW" | sed 's/,/, /g')

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
    "enabled": $failover_enabled,
    "threshold": $fo_threshold
  },
  "schedule": {
    "enabled": $ENABLED,
    "start_time": "$START_TIME",
    "end_time": "$END_TIME",
    "days": [$DAYS_JSON]
  }
}
EOF
mv "${TOWER_CONFIG_FILE}.tmp" "$TOWER_CONFIG_FILE"

# --- Manage crontab entries --------------------------------------------------
CRON_MARKER="qmanager_tower_schedule"
SCHEDULE_SCRIPT="/usr/bin/qmanager_tower_schedule"

# Read current crontab (suppress "no crontab" message)
current_cron=$(crontab -l 2>/dev/null || true)

# Remove any existing QManager tower schedule entries
cleaned_cron=$(printf '%s\n' "$current_cron" | grep -v "$CRON_MARKER")

if [ "$ENABLED" = "true" ]; then
    # Parse times into hour/minute
    start_hour=$(printf '%s' "$START_TIME" | cut -d: -f1 | sed 's/^0//')
    start_min=$(printf '%s' "$START_TIME" | cut -d: -f2 | sed 's/^0//')
    end_hour=$(printf '%s' "$END_TIME" | cut -d: -f1 | sed 's/^0//')
    end_min=$(printf '%s' "$END_TIME" | cut -d: -f2 | sed 's/^0//')

    # Handle leading zero removal edge case (00 becomes empty)
    [ -z "$start_hour" ] && start_hour="0"
    [ -z "$start_min" ] && start_min="0"
    [ -z "$end_hour" ] && end_hour="0"
    [ -z "$end_min" ] && end_min="0"

    # Build cron day list (comma-separated, same format as days array)
    day_list="$DAYS_RAW"

    new_cron="${cleaned_cron}
# QManager Tower Lock Schedule — DO NOT EDIT MANUALLY
${start_min} ${start_hour} * * ${day_list} ${SCHEDULE_SCRIPT} apply  # ${CRON_MARKER}
${end_min} ${end_hour} * * ${day_list} ${SCHEDULE_SCRIPT} clear  # ${CRON_MARKER}"

    printf '%s\n' "$new_cron" | crontab -
    qlog_info "Tower schedule cron entries installed: apply at ${START_TIME}, clear at ${END_TIME}, days=${day_list}"
else
    # Remove entries only (already cleaned above)
    if [ -n "$cleaned_cron" ]; then
        printf '%s\n' "$cleaned_cron" | crontab -
    else
        # Empty crontab
        echo "" | crontab -
    fi
    qlog_info "Tower schedule cron entries removed"
fi

# --- Response ----------------------------------------------------------------
printf '{"success":true,"enabled":%s,"start_time":"%s","end_time":"%s","days":[%s]}\n' \
    "$ENABLED" "$START_TIME" "$END_TIME" "$DAYS_JSON"
