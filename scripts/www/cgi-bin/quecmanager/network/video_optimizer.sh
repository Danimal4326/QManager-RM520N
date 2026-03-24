#!/bin/sh
. /usr/lib/qmanager/cgi_base.sh
. /usr/lib/qmanager/dpi_helper.sh

qlog_init "cgi_video_optimizer"
cgi_headers
cgi_handle_options

DPI_VERIFY_RESULT="/tmp/qmanager_dpi_verify.json"
DPI_VERIFY_PID="/tmp/qmanager_dpi_verify.pid"
RELOAD_FLAG="/tmp/qmanager_dpi_reload"

# Ensure UCI section exists with defaults
ensure_dpi_config() {
    local section
    section=$(uci -q get quecmanager.video_optimizer)
    if [ -z "$section" ]; then
        uci set quecmanager.video_optimizer=video_optimizer
        uci set quecmanager.video_optimizer.enabled='0'
        uci set quecmanager.video_optimizer.quic_enabled='1'
        uci set quecmanager.video_optimizer.interface='wwan0'
        uci commit quecmanager
    fi
}

ensure_dpi_config

case "$REQUEST_METHOD" in
GET)
    # Check for verify_status action
    action=$(echo "$QUERY_STRING" | sed -n 's/.*action=\([^&]*\).*/\1/p')

    if [ "$action" = "verify_status" ]; then
        # Return verification test results
        if [ -f "$DPI_VERIFY_RESULT" ]; then
            cat "$DPI_VERIFY_RESULT"
        else
            printf '{"success":true,"status":"idle"}'
        fi
        exit 0
    fi

    # Read UCI settings
    enabled=$(uci -q get quecmanager.video_optimizer.enabled)
    quic_enabled=$(uci -q get quecmanager.video_optimizer.quic_enabled)
    iface=$(uci -q get quecmanager.video_optimizer.interface)

    # Read live status
    status=$(dpi_get_status)
    uptime=$(dpi_get_uptime)
    packets=$(dpi_get_packet_count)
    domains=$(dpi_get_domain_count)
    dpi_check_binary && binary_ok="true" || binary_ok="false"
    dpi_check_kmod && kmod_ok="true" || kmod_ok="false"

    # Build response
    jq -n \
        --argjson success true \
        --argjson enabled "${enabled:-false}" \
        --arg status "$status" \
        --arg uptime "$uptime" \
        --argjson packets_processed "${packets:-0}" \
        --argjson domains_loaded "${domains:-0}" \
        --argjson binary_installed "$binary_ok" \
        --argjson kernel_module_loaded "$kmod_ok" \
        '{
            success: $success,
            enabled: (if $enabled == "1" or $enabled == true then true else false end),
            status: $status,
            uptime: $uptime,
            packets_processed: $packets_processed,
            domains_loaded: $domains_loaded,
            binary_installed: $binary_installed,
            kernel_module_loaded: $kernel_module_loaded
        }'
    ;;

POST)
    cgi_read_post
    action=$(echo "$POST_DATA" | jq -r '.action // empty')

    case "$action" in
    save)
        # Extract enabled field
        new_enabled=$(echo "$POST_DATA" | jq -r '(.enabled) | if . == null then empty else tostring end')

        if [ -z "$new_enabled" ]; then
            cgi_error "missing_field" "enabled field is required"
            exit 0
        fi

        # Map to UCI value
        if [ "$new_enabled" = "true" ]; then
            uci set quecmanager.video_optimizer.enabled='1'
        else
            uci set quecmanager.video_optimizer.enabled='0'
        fi
        uci commit quecmanager

        # Start or stop service
        if [ "$new_enabled" = "true" ]; then
            /etc/init.d/qmanager_dpi start
            qlog_info "Video Optimizer enabled"
        else
            /etc/init.d/qmanager_dpi stop
            qlog_info "Video Optimizer disabled"
        fi

        cgi_success
        ;;

    verify)
        # Check if verification is already running
        if [ -f "$DPI_VERIFY_PID" ] && kill -0 "$(cat "$DPI_VERIFY_PID" 2>/dev/null)" 2>/dev/null; then
            printf '{"success":true,"status":"running"}'
            exit 0
        fi

        # Clear old results
        rm -f "$DPI_VERIFY_RESULT"

        # Spawn background verification
        /usr/bin/qmanager_dpi_verify </dev/null >/dev/null 2>&1 &
        echo $! > "$DPI_VERIFY_PID"

        qlog_info "Verification test started"
        printf '{"success":true,"status":"started"}'
        ;;

    *)
        cgi_error "invalid_action" "Unknown action: $action"
        ;;
    esac
    ;;

*)
    cgi_method_not_allowed
    ;;
esac

exit 0
