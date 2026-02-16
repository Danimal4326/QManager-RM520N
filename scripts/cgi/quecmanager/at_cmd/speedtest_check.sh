#!/bin/sh
# =============================================================================
# speedtest_check.sh — CGI Endpoint: Speedtest Availability Check
# =============================================================================
# Returns whether speedtest-cli (Ookla) is installed and executable.
# Called once on component mount to enable/disable the speedtest button.
#
# Endpoint: GET /cgi-bin/quecmanager/at_cmd/speedtest_check.sh
# Response: {"available": true} or {"available": false}
#
# Install location: /www/cgi-bin/quecmanager/at_cmd/speedtest_check.sh
# =============================================================================

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

# --- Check for speedtest binary ----------------------------------------------
if command -v speedtest >/dev/null 2>&1; then
    echo '{"available":true}'
else
    echo '{"available":false}'
fi
