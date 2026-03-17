#!/bin/sh
# login.sh — Login and first-time password setup endpoint.
# POST {"password":"..."} for login
# POST {"password":"...","confirm":"..."} for first-time setup
#
# NOTE: This script defers cgi_headers to emit proper HTTP status codes
# (429 for rate limiting). Do NOT move cgi_headers to the top.
_SKIP_AUTH=1
. /usr/lib/qmanager/cgi_base.sh

qlog_init "cgi_auth_login"

# Handle CORS preflight before anything else
if [ "$REQUEST_METHOD" = "OPTIONS" ]; then
    cgi_headers
    exit 0
fi

# Only POST allowed
if [ "$REQUEST_METHOD" != "POST" ]; then
    cgi_headers
    cgi_method_not_allowed
fi

# Read POST body inline (not via cgi_read_post, to defer headers)
if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
    POST_DATA=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
else
    cgi_headers
    cgi_error "no_body" "POST body is empty"
    exit 0
fi

_password=$(printf '%s' "$POST_DATA" | jq -r '.password // empty')
_confirm=$(printf '%s' "$POST_DATA" | jq -r '.confirm // empty')

# Validate password is present
if [ -z "$_password" ]; then
    cgi_headers
    cgi_error "missing_password" "Password is required"
    exit 0
fi

# ---------------------------------------------------------------------------
# First-time setup mode
# ---------------------------------------------------------------------------
if is_setup_required; then
    cgi_headers

    # If only password sent (no confirm), tell client setup is required
    if [ -z "$_confirm" ]; then
        jq -n '{"success":false,"error":"setup_required","setup_required":true}'
        exit 0
    fi

    # Validate password length
    _pw_len=$(printf '%s' "$_password" | wc -c)
    if [ "$_pw_len" -lt 6 ]; then
        cgi_error "password_too_short" "Password must be at least 6 characters"
        exit 0
    fi

    # Confirm must match
    if [ "$_password" != "$_confirm" ]; then
        cgi_error "password_mismatch" "Passwords do not match"
        exit 0
    fi

    # Create the password
    qm_save_password "$_password"
    qlog_info "First-time password configured"

    # Create session and return token
    _token=$(qm_create_session)
    jq -n --arg token "$_token" '{"success":true,"token":$token}'
    exit 0
fi

# ---------------------------------------------------------------------------
# Normal login — rate limit check BEFORE emitting headers
# ---------------------------------------------------------------------------
if ! qm_check_rate_limit; then
    echo "Status: 429 Too Many Requests"
    cgi_headers
    jq -n --argjson retry "$RATE_LIMIT_RETRY_AFTER" \
        '{"success":false,"error":"rate_limited","detail":"Too many failed attempts","retry_after":$retry}'
    exit 0
fi

# Past rate limit — emit standard 200 headers
cgi_headers

# Verify password
if ! qm_verify_password "$_password"; then
    qm_record_failed_attempt
    qlog_warn "Failed login attempt"
    cgi_error "invalid_password" "Invalid password"
    exit 0
fi

# Success — clear rate limiter, create session
qm_clear_attempts
_token=$(qm_create_session)
qlog_info "Successful login"

jq -n --arg token "$_token" '{"success":true,"token":$token}'
