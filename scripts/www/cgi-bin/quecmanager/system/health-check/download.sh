#!/bin/sh
# NOTE: NOT sourcing cgi_base.sh — it emits Content-Type: application/json
# and a CORS preflight blank line. We need binary streaming with a custom
# Content-Type, so we replicate just the auth gate inline.

# Auth: reuse the same require_auth implementation
. /usr/lib/qmanager/cgi_auth.sh 2>/dev/null
require_auth >/dev/null 2>&1 || {
    printf 'Status: 401 Unauthorized\r\n'
    printf 'Content-Type: application/json\r\n\r\n'
    printf '{"success":false,"error":"unauthorized"}\n'
    exit 0
}

# Method check
if [ "$REQUEST_METHOD" != "GET" ]; then
    printf 'Status: 405 Method Not Allowed\r\n'
    printf 'Content-Type: application/json\r\n\r\n'
    printf '{"success":false,"error":"method_not_allowed"}\n'
    exit 0
fi

# Parse and validate job_id (must match runner's regex).
job_id=""
case "$QUERY_STRING" in
    *job_id=*) job_id=$(printf '%s' "$QUERY_STRING" | sed -n 's/.*job_id=\([^&]*\).*/\1/p') ;;
esac
if ! printf '%s' "$job_id" | grep -qE '^[0-9]{8}-[0-9]{6}-[a-f0-9]{4}$'; then
    printf 'Status: 400 Bad Request\r\n'
    printf 'Content-Type: application/json\r\n\r\n'
    printf '{"success":false,"error":"invalid_job_id"}\n'
    exit 0
fi

tarball="/tmp/qmanager_health_check_${job_id}.tar.gz"
if [ ! -f "$tarball" ]; then
    printf 'Status: 404 Not Found\r\n'
    printf 'Content-Type: application/json\r\n\r\n'
    printf '{"success":false,"error":"bundle_not_found"}\n'
    exit 0
fi

size=$(stat -c %s "$tarball" 2>/dev/null || echo 0)
filename="qmanager-health-check-${job_id}.tar.gz"

printf 'Content-Type: application/gzip\r\n'
printf 'Content-Length: %s\r\n' "$size"
printf 'Content-Disposition: attachment; filename="%s"\r\n' "$filename"
printf 'Cache-Control: no-cache, no-store, must-revalidate\r\n'
printf '\r\n'
cat "$tarball"
