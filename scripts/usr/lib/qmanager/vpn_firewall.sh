#!/bin/sh
# =============================================================================
# vpn_firewall.sh — Shared VPN Firewall & Routing Management (RM520N-GL)
# =============================================================================
# Sourced by VPN CGI scripts (tailscale.sh, netbird.sh) to:
#   1. Add/remove iptables FORWARD rules for VPN interfaces
#   2. mwan3 ipset exception — no-op on RM520N-GL (mwan3 not present)
#
# On RM520N-GL, iptables' default FORWARD policy is ACCEPT, so we only need
# to ensure MASQUERADE is set for VPN traffic leaving the modem interface
# and that traffic can flow between the VPN tunnel and rmnet_data interfaces.
#
# Rules are inserted into the FORWARD chain of the filter table.
# Rules are tagged with a comment for idempotent add/remove.
#
# Usage:
#   . /usr/lib/qmanager/vpn_firewall.sh
#   vpn_fw_ensure_zone "tailscale" "tailscale0"
#   vpn_fw_remove_zone "tailscale"
# =============================================================================

[ -n "$_VPN_FW_LOADED" ] && return 0
_VPN_FW_LOADED=1

# Source logging if available
. /usr/lib/qmanager/qlog.sh 2>/dev/null || {
    qlog_info()  { :; }
    qlog_error() { :; }
}

VPN_CGNAT_RANGE="100.64.0.0/10"

# Comment prefix used to identify our iptables rules for a given zone
_vpn_comment_prefix() {
    echo "qmanager_vpn_${1}"
}

# -----------------------------------------------------------------------------
# vpn_fw_zone_exists <zone_name>
#   Returns 0 if iptables FORWARD rules for this zone exist, 1 otherwise.
# -----------------------------------------------------------------------------
vpn_fw_zone_exists() {
    local zone_name="$1"
    local comment
    comment=$(_vpn_comment_prefix "$zone_name")
    iptables -t filter -L FORWARD -n 2>/dev/null | grep -q "$comment"
}

# -----------------------------------------------------------------------------
# vpn_fw_ensure_zone <zone_name> <device>
#   Idempotent: inserts iptables FORWARD rules for VPN traffic if not present.
#   Allows bidirectional forwarding between VPN interface and rmnet_data+.
# -----------------------------------------------------------------------------
vpn_fw_ensure_zone() {
    local zone_name="$1" device="$2"

    if [ -z "$zone_name" ] || [ -z "$device" ]; then
        qlog_error "vpn_fw_ensure_zone: missing zone_name or device"
        return 1
    fi

    if vpn_fw_zone_exists "$zone_name"; then
        qlog_info "VPN rules for '$zone_name' already exist"
        return 0
    fi

    local comment
    comment=$(_vpn_comment_prefix "$zone_name")

    qlog_info "Creating iptables rules for VPN '$zone_name' on device '$device'"

    # Allow forwarding: VPN → rmnet_data (outbound via modem)
    iptables -t filter -A FORWARD -i "$device" -o rmnet_data+ \
        -m comment --comment "$comment" -j ACCEPT 2>/dev/null

    # Allow forwarding: rmnet_data → VPN (return traffic)
    iptables -t filter -A FORWARD -i rmnet_data+ -o "$device" \
        -m state --state RELATED,ESTABLISHED \
        -m comment --comment "$comment" -j ACCEPT 2>/dev/null

    # Allow forwarding: VPN → LAN bridge
    iptables -t filter -A FORWARD -i "$device" -o br-lan \
        -m comment --comment "$comment" -j ACCEPT 2>/dev/null

    # Allow forwarding: LAN bridge → VPN
    iptables -t filter -A FORWARD -i br-lan -o "$device" \
        -m comment --comment "$comment" -j ACCEPT 2>/dev/null

    # Masquerade VPN traffic leaving via rmnet_data (NAT for VPN clients)
    iptables -t nat -A POSTROUTING -s "$VPN_CGNAT_RANGE" -o rmnet_data+ \
        -m comment --comment "$comment" -j MASQUERADE 2>/dev/null

    qlog_info "VPN rules for '$zone_name' created"
    return 0
}

# -----------------------------------------------------------------------------
# vpn_fw_ensure_mwan3_exception
#   No-op on RM520N-GL — mwan3 is not present on this platform.
# -----------------------------------------------------------------------------
vpn_fw_ensure_mwan3_exception() {
    qlog_info "mwan3 not present on RM520N-GL, skipping exception"
    return 0
}

# -----------------------------------------------------------------------------
# vpn_fw_remove_mwan3_exception
#   No-op on RM520N-GL — mwan3 is not present on this platform.
# -----------------------------------------------------------------------------
vpn_fw_remove_mwan3_exception() {
    return 0
}

# -----------------------------------------------------------------------------
# vpn_fw_remove_zone <zone_name>
#   Removes all iptables rules tagged with the zone's comment.
# -----------------------------------------------------------------------------
vpn_fw_remove_zone() {
    local zone_name="$1"

    if [ -z "$zone_name" ]; then
        qlog_error "vpn_fw_remove_zone: missing zone_name"
        return 1
    fi

    if ! vpn_fw_zone_exists "$zone_name"; then
        qlog_info "VPN rules for '$zone_name' do not exist, skipping"
        return 0
    fi

    local comment
    comment=$(_vpn_comment_prefix "$zone_name")

    qlog_info "Removing iptables rules for VPN '$zone_name'"

    # Remove filter FORWARD rules (iterate until none left)
    local changed=true
    while [ "$changed" = "true" ]; do
        changed=false
        local nums
        nums=$(iptables -t filter -L FORWARD --line-numbers -n 2>/dev/null | \
            awk '/'"$comment"'/ {print $1}' | sort -rn)
        for num in $nums; do
            iptables -t filter -D FORWARD "$num" 2>/dev/null && changed=true
        done
    done

    # Remove nat POSTROUTING rules
    changed=true
    while [ "$changed" = "true" ]; do
        changed=false
        local nums
        nums=$(iptables -t nat -L POSTROUTING --line-numbers -n 2>/dev/null | \
            awk '/'"$comment"'/ {print $1}' | sort -rn)
        for num in $nums; do
            iptables -t nat -D POSTROUTING "$num" 2>/dev/null && changed=true
        done
    done

    qlog_info "VPN rules for '$zone_name' removed"
    return 0
}

# -----------------------------------------------------------------------------
# vpn_check_other_installed <binary_name>
#   Echoes "true" if the given binary is found, "false" otherwise.
# -----------------------------------------------------------------------------
vpn_check_other_installed() {
    if [ -x "$1" ] || command -v "$1" >/dev/null 2>&1; then
        echo "true"
    else
        echo "false"
    fi
}
