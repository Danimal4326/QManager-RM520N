#!/bin/sh
. /usr/lib/qmanager/cgi_base.sh
# =============================================================================
# current_settings.sh — CGI Endpoint: Current Modem Settings
# =============================================================================
# Queries the modem for current APN, IMEI, and ICCID.
# Used to pre-fill the profile creation form with live modem values.
#
# Sip-don't-gulp: each AT command goes through qcmd individually with
# sleep gaps between, so the poller can slip in.
#
# Called ONCE when the user opens the profile form, not on a timer.
#
# NOTE: Band locking and network mode queries have been removed.
# They will be owned by the Connection Scenarios feature.
#
# Endpoint: GET /cgi-bin/quecmanager/profiles/current_settings.sh
# Response: CurrentModemSettings JSON (see types/sim-profile.ts)
#
# Install location: /www/cgi-bin/quecmanager/profiles/current_settings.sh
# =============================================================================

# --- Logging -----------------------------------------------------------------
qlog_init "cgi_current_settings"
cgi_headers

# --- Configuration -----------------------------------------------------------
CMD_GAP=0.2   # Gap between AT commands (seconds)

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

# --- APN array: parse AT response → TSV → jq for safe JSON construction ------

qlog_info "Querying current modem settings for profile form"

# --- 1. APN profiles from AT+CGDCONT? ----------------------------------------
cgdcont_resp=$(run_at "AT+CGDCONT?")
sleep "$CMD_GAP"

# Parse: +CGDCONT: <cid>,"<pdp_type>","<apn>",...
# Build JSON array of {cid, pdp_type, apn} via TSV intermediate + jq
if [ -n "$cgdcont_resp" ]; then
    apn_array=$(printf '%s' "$cgdcont_resp" | awk -F'"' '
        /\+CGDCONT:/ {
            split($0, a, /[,]/)
            gsub(/[^0-9]/, "", a[1])
            cid = a[1]
            pdp = $2
            apn = $4
            if (cid != "") {
                printf "%s\t%s\t%s\n", cid, pdp, apn
            }
        }
    ' | jq -Rsc '
        split("\n") | map(select(length > 0) | split("\t") |
            {cid: (.[0] | tonumber), pdp_type: .[1], apn: .[2]}
        )
    ')
else
    apn_array="[]"
fi

# --- 2. Current IMEI from AT+CGSN --------------------------------------------
imei_resp=$(run_at "AT+CGSN")
current_imei=$(printf '%s' "$imei_resp" | grep -o '[0-9]\{15\}' | head -1)
sleep "$CMD_GAP"

# --- 3. Current ICCID from AT+QCCID ------------------------------------------
iccid_resp=$(run_at "AT+QCCID")
current_iccid=$(printf '%s' "$iccid_resp" | grep -o '[0-9]\{19,20\}' | head -1)
sleep "$CMD_GAP"

# --- 4. Determine active CID (cross-reference CGPADDR + QMAP) ---------------
active_cid=""

# 4a. AT+CGPADDR — collect ALL CIDs with a real IPv4 address
cgpaddr_resp=$(run_at "AT+CGPADDR")
sleep "$CMD_GAP"

cgpaddr_cids=""
if [ -n "$cgpaddr_resp" ]; then
    cgpaddr_cids=$(printf '%s' "$cgpaddr_resp" | awk -F'[,"]' '
        /\+CGPADDR:/ {
            cid = $1; gsub(/[^0-9]/, "", cid)
            ip = $3
            if (ip != "" && ip != "0.0.0.0" && ip !~ /^0+(\.0+)*$/) {
                split(ip, octets, ".")
                if (length(octets) == 4 && octets[1]+0 > 0) {
                    print cid
                }
            }
        }
    ')
fi

# 4b. AT+QMAP="WWAN" — get the WAN-connected CID (authoritative)
qmap_cid=""
qmap_resp=$(run_at 'AT+QMAP="WWAN"')
if [ -n "$qmap_resp" ]; then
    # +QMAP: "WWAN",<connected>,<cid>,"<type>","<ip>"
    qmap_cid=$(printf '%s' "$qmap_resp" | awk -F',' '
        /\+QMAP:/ {
            gsub(/"/, "", $5)
            ip = $5
            cid = $3
            gsub(/[^0-9]/, "", cid)
            if (ip != "" && ip != "0.0.0.0" && ip != "0:0:0:0:0:0:0:0") {
                print cid
                exit
            }
        }
    ')
fi

# 4c. Cross-reference: QMAP is authoritative, CGPADDR is fallback
if [ -n "$qmap_cid" ]; then
    active_cid="$qmap_cid"
    qlog_debug "Active CID from QMAP: $qmap_cid (CGPADDR CIDs: $cgpaddr_cids)"
elif [ -n "$cgpaddr_cids" ]; then
    active_cid=$(printf '%s\n' "$cgpaddr_cids" | head -1)
    qlog_debug "Active CID from CGPADDR fallback: $active_cid"
fi

# Default to CID 1 if both detection methods failed
[ -z "$active_cid" ] && active_cid="1"

# =============================================================================
# Build and output response JSON
# =============================================================================

jq -n --argjson apns "$apn_array" \
    --arg imei "$current_imei" \
    --arg iccid "$current_iccid" \
    --arg active_cid "$active_cid" \
    '{
        "apn_profiles": $apns,
        "imei": $imei,
        "iccid": $iccid,
        "active_cid": ($active_cid | tonumber)
    }'

qlog_info "Current settings query complete (active_cid=$active_cid)"
