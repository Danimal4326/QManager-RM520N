# Software Update Feature — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add OTA software updates to QManager — check GitHub Releases, show changelog, install, reboot, and rollback — all from the System Settings page.

**Architecture:** Single CGI endpoint (`system/update.sh`) handles check/install/rollback via action-based routing. Background process (double-forked) handles download + install + reboot. Frontend hook polls a status file during updates. Reuses existing `install.sh` with a new `--no-reboot` flag.

**Tech Stack:** POSIX shell (BusyBox), jq, uclient-fetch/wget/curl, Next.js, shadcn/ui, TypeScript

**Spec:** `docs/superpowers/specs/2026-03-21-software-update-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `scripts/install.sh` | Modify | Add `--no-reboot` flag, write `/etc/qmanager/VERSION` |
| `scripts/www/cgi-bin/quecmanager/system/update.sh` | Create | CGI endpoint: check, install, rollback, status, save_prerelease |
| `scripts/usr/bin/qmanager_update` | Create | Background updater script (owns its PID, handles download/install/reboot) |
| `hooks/use-software-update.ts` | Create | Frontend hook: fetch, poll, install, rollback, toggle |
| `components/system-settings/software-update-card.tsx` | Create | Card component with all states (UniFi-inspired) |
| `components/system-settings/system-settings.tsx` | Modify | Add SoftwareUpdateCard to the page grid |

---

## Task 1: Add `--no-reboot` flag and VERSION file to install.sh

**Files:**
- Modify: `scripts/install.sh:22-28` (flags section), `scripts/install.sh:838-844` (main function end)

- [ ] **Step 1: Add the `--no-reboot` flag to the flags parsing block**

In `scripts/install.sh`, find the flags section (around line 22-28 in the header comments, and the actual parsing around line 145-170). Add `--no-reboot` to the help text and parsing:

```sh
# In the help text (line 27, add after --skip-packages):
#   --no-reboot        Don't reboot after install (for OTA updates)

# In the flags parsing loop, add a case:
DO_REBOOT=1
# ... in the while loop:
        --no-reboot)    DO_REBOOT=0 ;;
```

- [ ] **Step 2: Write VERSION file during install**

After `print_summary` (line 840), add:

```sh
# Write version marker for OTA update checking
mkdir -p /etc/qmanager
echo "$VERSION" > /etc/qmanager/VERSION
```

- [ ] **Step 3: Gate the reboot on the flag**

Replace lines 842-844 (the unconditional reboot):

```sh
# Before (lines 842-844):
printf "  Rebooting in 5 seconds — press Ctrl+C to cancel...\n\n"
sleep 5
reboot

# After:
if [ "$DO_REBOOT" = "1" ]; then
    printf "  Rebooting in 5 seconds — press Ctrl+C to cancel...\n\n"
    sleep 5
    reboot
fi
```

- [ ] **Step 4: Verify the flag is initialized to 1 alongside other flags**

Find where `DO_FRONTEND`, `DO_BACKEND`, `DO_PACKAGES`, etc. are initialized (around line 130-142). Add `DO_REBOOT=1` in that block.

- [ ] **Step 5: Commit**

```bash
git add scripts/install.sh
git commit -m "feat(install): add --no-reboot flag and write VERSION file"
```

---

## Task 2: Create the background updater script — qmanager_update

**Files:**
- Create: `scripts/usr/bin/qmanager_update`

The CGI endpoint spawns this as a separate process. This script owns its PID (so `$$` is correct), handles download/install/reboot, and logs to `/tmp/qmanager_update.log`. This follows the existing pattern where CGI scripts spawn external daemons (like `profiles/apply.sh` spawns `qmanager_profile_apply`).

- [ ] **Step 1: Create the updater script**

```sh
#!/bin/sh
# =============================================================================
# qmanager_update — Background OTA updater
# =============================================================================
# Spawned by update.sh CGI. Downloads, verifies, installs, and reboots.
#
# Usage:
#   qmanager_update install <download_url> <version> [download_size]
#   qmanager_update rollback
# =============================================================================

LOG_FILE="/tmp/qmanager_update.log"
STATUS_FILE="/tmp/qmanager_update.json"
PID_FILE="/tmp/qmanager_update.pid"
VERSION_FILE="/etc/qmanager/VERSION"
UPDATES_DIR="/etc/qmanager/updates"
GITHUB_URL_PATTERN="https://github.com/iamromulan/quecmanager/releases/download/*"

# --- Helpers -----------------------------------------------------------------

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"; }

write_status() {
    local status="$1" msg="$2" version="$3" size="$4"
    jq -n \
        --arg status "$status" \
        --arg message "$msg" \
        --arg version "$version" \
        --arg size "$size" \
        '{status: $status, message: $message, version: $version, size: $size}' \
        > "$STATUS_FILE"
}

get_current_version() {
    if [ -f "$VERSION_FILE" ]; then
        tr -d '[:space:]' < "$VERSION_FILE"
    else
        echo "0.0.0"
    fi
}

http_download() {
    local url="$1" dest="$2" timeout="${3:-120}"
    if command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -qO "$dest" --timeout="$timeout" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$dest" -T "$timeout" "$url"
    elif command -v curl >/dev/null 2>&1; then
        curl -sL --max-time "$timeout" -o "$dest" "$url"
    else
        return 1
    fi
}

cleanup() {
    rm -f "$PID_FILE"
    rm -rf /tmp/qmanager_install
}

die() {
    log "ERROR: $1"
    write_status "error" "$1" "${VERSION:-}" ""
    cleanup
    exit 1
}

# --- Lock & setup ------------------------------------------------------------

echo $$ > "$PID_FILE"
trap cleanup EXIT INT TERM
: > "$LOG_FILE"

MODE="$1"
log "Starting qmanager_update mode=$MODE"

# Stop watchdog early to prevent interference during download/install
/etc/init.d/qmanager_watchcat stop 2>/dev/null
log "Watchdog stopped"

# =============================================================================
# INSTALL mode
# =============================================================================
if [ "$MODE" = "install" ]; then
    URL="$2"
    VERSION="$3"
    SIZE="$4"

    # Validate URL origin (prevent SSRF)
    case "$URL" in
        https://github.com/iamromulan/quecmanager/releases/download/*/qmanager.tar.gz) ;;
        *) die "Invalid download URL" ;;
    esac

    # 1. Download
    write_status "downloading" "Downloading update..." "$VERSION" "$SIZE"
    log "Downloading $URL"
    download_path="/tmp/qmanager_update_new.tar.gz"
    rm -f "$download_path"

    if ! http_download "$URL" "$download_path"; then
        die "Download failed. Check your internet connection."
    fi
    log "Download complete"

    # 2. Verify archive integrity
    if ! tar tzf "$download_path" >/dev/null 2>&1; then
        rm -f "$download_path"
        die "Downloaded file is corrupt. Please try again."
    fi

    if ! tar tzf "$download_path" | grep -q "install.sh"; then
        rm -f "$download_path"
        die "Invalid update package — missing install.sh."
    fi
    log "Archive verified"

    # 3. Rotate archives safely
    write_status "installing" "Installing update..." "$VERSION" ""
    current_ver=$(get_current_version)
    mkdir -p "$UPDATES_DIR"

    if [ -f "$UPDATES_DIR/current.tar.gz" ]; then
        mv "$UPDATES_DIR/current.tar.gz" "$UPDATES_DIR/previous.tar.gz"
        echo "$current_ver" > "$UPDATES_DIR/previous_version"
    fi
    mv "$download_path" "$UPDATES_DIR/current.tar.gz"
    log "Archives rotated (previous=$current_ver)"

    # 4. Extract and install
    rm -rf /tmp/qmanager_install
    tar xzf "$UPDATES_DIR/current.tar.gz" -C /tmp/
    cd /tmp/qmanager_install || die "Extraction failed — /tmp/qmanager_install not found"

    log "Running install.sh --skip-packages --no-reboot"
    if ! sh install.sh --skip-packages --no-reboot >> "$LOG_FILE" 2>&1; then
        die "Installation failed. Check /tmp/qmanager_update.log for details."
    fi
    log "Install complete"

    # 5. Cleanup and reboot
    rm -rf /tmp/qmanager_install
    write_status "rebooting" "Rebooting device..." "$VERSION" ""
    log "Rebooting"
    rm -f "$PID_FILE"
    trap - EXIT INT TERM
    sleep 1
    reboot
    exit 0
fi

# =============================================================================
# ROLLBACK mode
# =============================================================================
if [ "$MODE" = "rollback" ]; then
    VERSION=$(cat "$UPDATES_DIR/previous_version" 2>/dev/null)

    if [ ! -f "$UPDATES_DIR/previous.tar.gz" ]; then
        die "No previous version available for rollback"
    fi

    write_status "installing" "Restoring previous version..." "$VERSION" ""

    # Swap archives: current <-> previous
    current_ver=$(get_current_version)
    tmp_swap="/tmp/qmanager_swap.tar.gz"

    mv "$UPDATES_DIR/current.tar.gz" "$tmp_swap"
    mv "$UPDATES_DIR/previous.tar.gz" "$UPDATES_DIR/current.tar.gz"
    mv "$tmp_swap" "$UPDATES_DIR/previous.tar.gz"
    echo "$current_ver" > "$UPDATES_DIR/previous_version"
    log "Archives swapped (rolling back to $VERSION, previous=$current_ver)"

    # Extract and install
    rm -rf /tmp/qmanager_install
    tar xzf "$UPDATES_DIR/current.tar.gz" -C /tmp/
    cd /tmp/qmanager_install || die "Extraction failed"

    log "Running install.sh --skip-packages --no-reboot"
    if ! sh install.sh --skip-packages --no-reboot >> "$LOG_FILE" 2>&1; then
        die "Rollback installation failed. Check /tmp/qmanager_update.log"
    fi
    log "Rollback install complete"

    # Cleanup and reboot
    rm -rf /tmp/qmanager_install
    write_status "rebooting" "Rebooting device..." "$VERSION" ""
    log "Rebooting"
    rm -f "$PID_FILE"
    trap - EXIT INT TERM
    sleep 1
    reboot
    exit 0
fi

die "Unknown mode: $MODE"
```

- [ ] **Step 2: Commit**

```bash
git add scripts/usr/bin/qmanager_update
git commit -m "feat(scripts): add qmanager_update background updater script"
```

---

## Task 3: Create the CGI endpoint — update.sh

**Files:**
- Create: `scripts/www/cgi-bin/quecmanager/system/update.sh`

The CGI handles version checking (GET), status polling (GET action=status), and dispatches the background updater for install/rollback (POST). Thin layer — heavy lifting is in `qmanager_update`.

- [ ] **Step 1: Create the CGI file with helpers and GET handler**

```sh
#!/bin/sh
. /usr/lib/qmanager/cgi_base.sh
# =============================================================================
# update.sh — CGI Endpoint: Software Update (GET + POST)
# =============================================================================
# GET:              Check for updates via GitHub Releases API
# GET action=status: Read update progress from status file
# POST action=install: Spawn qmanager_update to download and install
# POST action=rollback: Spawn qmanager_update to restore previous version
# POST action=save_prerelease: Toggle pre-release preference
#
# Config: UCI quecmanager.update.*
# State:  /tmp/qmanager_update.json, /tmp/qmanager_update.pid
#
# Endpoint: GET/POST /cgi-bin/quecmanager/system/update.sh
# =============================================================================

qlog_init "cgi_system_update"
cgi_headers
cgi_handle_options

# --- Configuration -----------------------------------------------------------

GITHUB_REPO="iamromulan/quecmanager"
VERSION_FILE="/etc/qmanager/VERSION"
UPDATES_DIR="/etc/qmanager/updates"
STATUS_FILE="/tmp/qmanager_update.json"
PID_FILE="/tmp/qmanager_update.pid"
UPDATER="/usr/bin/qmanager_update"

# --- Helpers -----------------------------------------------------------------

get_current_version() {
    if [ -f "$VERSION_FILE" ]; then
        tr -d '[:space:]' < "$VERSION_FILE"
    else
        echo "0.0.0"
    fi
}

uci_update_get() {
    local val
    val=$(uci -q get "quecmanager.update.$1" 2>/dev/null)
    if [ -z "$val" ]; then echo "$2"; else echo "$val"; fi
}

ensure_update_config() {
    uci -q get quecmanager.update >/dev/null 2>&1 && return
    uci set quecmanager.update=update
    uci set quecmanager.update.include_prerelease=1
    uci commit quecmanager
}

# Check if an update process is already running
check_lock() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            cgi_error "update_in_progress" "An update is already in progress"
            exit 0
        fi
        rm -f "$PID_FILE"
    fi
}

# Fetch URL to a file, capturing HTTP status. Returns body in $1, status in $2.
# Uses wget -S to capture headers for rate-limit detection.
http_api_fetch() {
    local url="$1" out_file="$2" header_file="$3" timeout="${4:-15}"
    if command -v wget >/dev/null 2>&1; then
        wget -qO "$out_file" -T "$timeout" -S "$url" 2>"$header_file"
    elif command -v curl >/dev/null 2>&1; then
        curl -sL --max-time "$timeout" -o "$out_file" -D "$header_file" "$url"
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -qO "$out_file" --timeout="$timeout" "$url" 2>"$header_file"
    else
        return 1
    fi
}

# Semver comparison. Exit codes: 0 = $1 newer, 1 = same, 2 = $1 older
semver_compare() {
    local a="$1" b="$2"
    a="${a#v}"; b="${b#v}"
    local a_ver="${a%%-*}" a_pre="" b_ver="${b%%-*}" b_pre=""
    case "$a" in *-*) a_pre="${a#*-}" ;; esac
    case "$b" in *-*) b_pre="${b#*-}" ;; esac

    local a1 a2 a3 b1 b2 b3
    IFS='.' read a1 a2 a3 <<EOF
$a_ver
EOF
    IFS='.' read b1 b2 b3 <<EOF
$b_ver
EOF
    a1=${a1:-0}; a2=${a2:-0}; a3=${a3:-0}
    b1=${b1:-0}; b2=${b2:-0}; b3=${b3:-0}

    [ "$a1" -gt "$b1" ] 2>/dev/null && return 0
    [ "$a1" -lt "$b1" ] 2>/dev/null && return 2
    [ "$a2" -gt "$b2" ] 2>/dev/null && return 0
    [ "$a2" -lt "$b2" ] 2>/dev/null && return 2
    [ "$a3" -gt "$b3" ] 2>/dev/null && return 0
    [ "$a3" -lt "$b3" ] 2>/dev/null && return 2

    # Equal major.minor.patch — no pre-release > any pre-release
    [ -z "$a_pre" ] && [ -n "$b_pre" ] && return 0
    [ -n "$a_pre" ] && [ -z "$b_pre" ] && return 2
    [ -z "$a_pre" ] && [ -z "$b_pre" ] && return 1

    # Both have pre-release — lexical
    [ "$a_pre" \> "$b_pre" ] && return 0
    [ "$a_pre" \< "$b_pre" ] && return 2
    return 1
}

# =============================================================================
# GET — Check for updates / Read status
# =============================================================================
if [ "$REQUEST_METHOD" = "GET" ]; then
    action=$(echo "$QUERY_STRING" | sed -n 's/.*action=\([^&]*\).*/\1/p')

    # --- Status polling ---
    if [ "$action" = "status" ]; then
        if [ -f "$STATUS_FILE" ]; then
            cat "$STATUS_FILE"
        else
            jq -n '{"status":"idle"}'
        fi
        exit 0
    fi

    # --- Update check ---
    qlog_info "Checking for updates"
    ensure_update_config

    current_version=$(get_current_version)
    include_prerelease=$(uci_update_get include_prerelease "1")

    # Rollback availability
    rollback_available="false"
    rollback_version=""
    if [ -f "$UPDATES_DIR/previous.tar.gz" ] && [ -f "$UPDATES_DIR/previous_version" ]; then
        rollback_available="true"
        rollback_version=$(cat "$UPDATES_DIR/previous_version" 2>/dev/null)
    fi

    # Query GitHub Releases API with header capture for rate-limit detection
    api_url="https://api.github.com/repos/$GITHUB_REPO/releases"
    tmp_body="/tmp/qm_update_api_body.json"
    tmp_headers="/tmp/qm_update_api_headers.txt"
    rm -f "$tmp_body" "$tmp_headers"

    if ! http_api_fetch "$api_url" "$tmp_body" "$tmp_headers"; then
        rm -f "$tmp_body" "$tmp_headers"
        jq -n \
            --arg cv "$current_version" \
            --argjson prerelease "$include_prerelease" \
            --argjson rb "$rollback_available" \
            --arg rbv "$rollback_version" \
            '{
                success: true, current_version: $cv,
                latest_version: null, update_available: false,
                changelog: null, download_url: null, download_size: null,
                rollback_available: $rb, rollback_version: $rbv,
                include_prerelease: ($prerelease == 1),
                check_error: "Unable to check for updates. Check your internet connection."
            }'
        exit 0
    fi

    # Check for rate limiting (HTTP 403)
    if grep -qi "403 Forbidden\|HTTP/[0-9.]* 403" "$tmp_headers" 2>/dev/null; then
        # Try to parse reset time
        reset_ts=$(grep -i 'x-ratelimit-reset' "$tmp_headers" | sed 's/.*: *//;s/\r//' | head -1)
        wait_msg="Rate limit reached. Try again later."
        if [ -n "$reset_ts" ]; then
            now_ts=$(date +%s 2>/dev/null)
            if [ -n "$now_ts" ] && [ "$reset_ts" -gt "$now_ts" ] 2>/dev/null; then
                wait_mins=$(( (reset_ts - now_ts + 59) / 60 ))
                wait_msg="Rate limit reached. Try again in ${wait_mins} minute(s)."
            fi
        fi
        rm -f "$tmp_body" "$tmp_headers"
        jq -n \
            --arg cv "$current_version" \
            --argjson prerelease "$include_prerelease" \
            --argjson rb "$rollback_available" \
            --arg rbv "$rollback_version" \
            --arg err "$wait_msg" \
            '{
                success: true, current_version: $cv,
                latest_version: null, update_available: false,
                changelog: null, download_url: null, download_size: null,
                rollback_available: $rb, rollback_version: $rbv,
                include_prerelease: ($prerelease == 1),
                check_error: $err
            }'
        exit 0
    fi

    api_response=$(cat "$tmp_body" 2>/dev/null)
    rm -f "$tmp_body" "$tmp_headers"

    # Filter by pre-release preference
    if [ "$include_prerelease" = "1" ]; then
        release_filter='.[0]'
    else
        release_filter='[ .[] | select(.prerelease == false) ] | .[0]'
    fi

    # Extract release info
    latest_tag=$(echo "$api_response" | jq -r "$release_filter | .tag_name // empty")
    changelog=$(echo "$api_response" | jq -r "$release_filter | .body // empty")
    download_url=$(echo "$api_response" | jq -r "$release_filter | .assets[] | select(.name == \"qmanager.tar.gz\") | .browser_download_url // empty")
    download_size_bytes=$(echo "$api_response" | jq -r "$release_filter | .assets[] | select(.name == \"qmanager.tar.gz\") | .size // empty")

    download_size=""
    if [ -n "$download_size_bytes" ] && [ "$download_size_bytes" -gt 0 ] 2>/dev/null; then
        download_size=$(awk "BEGIN { printf \"%.1f MB\", $download_size_bytes / 1048576 }")
    fi

    update_available="false"
    if [ -n "$latest_tag" ]; then
        semver_compare "$latest_tag" "$current_version"
        case $? in
            0) update_available="true" ;;
        esac
    fi

    jq -n \
        --arg cv "$current_version" \
        --arg lv "${latest_tag:-}" \
        --argjson ua "$update_available" \
        --arg cl "$changelog" \
        --arg dl "${download_url:-}" \
        --arg ds "$download_size" \
        --argjson rb "$rollback_available" \
        --arg rbv "$rollback_version" \
        --argjson prerelease "$include_prerelease" \
        '{
            success: true,
            current_version: $cv,
            latest_version: (if $lv == "" then null else $lv end),
            update_available: $ua,
            changelog: (if $cl == "" then null else $cl end),
            download_url: (if $dl == "" then null else $dl end),
            download_size: (if $ds == "" then null else $ds end),
            rollback_available: $rb,
            rollback_version: (if $rbv == "" then null else $rbv end),
            include_prerelease: ($prerelease == 1),
            check_error: null
        }'
    exit 0
fi
```

- [ ] **Step 2: Add the POST handler**

```sh
# =============================================================================
# POST — Install / Rollback / Save preferences
# =============================================================================
if [ "$REQUEST_METHOD" = "POST" ]; then
    cgi_read_post

    ACTION=$(printf '%s' "$POST_DATA" | jq -r '.action // empty')
    if [ -z "$ACTION" ]; then
        cgi_error "missing_action" "action field is required"
        exit 0
    fi

    # --- Save pre-release preference ---
    if [ "$ACTION" = "save_prerelease" ]; then
        ensure_update_config
        enabled=$(printf '%s' "$POST_DATA" | jq -r '.enabled // empty')
        case "$enabled" in
            true)  uci set quecmanager.update.include_prerelease=1 ;;
            false) uci set quecmanager.update.include_prerelease=0 ;;
            *) cgi_error "invalid_value" "enabled must be true or false"; exit 0 ;;
        esac
        uci commit quecmanager
        cgi_success
        exit 0
    fi

    # --- Install update ---
    if [ "$ACTION" = "install" ]; then
        check_lock

        download_url=$(printf '%s' "$POST_DATA" | jq -r '.download_url // empty')
        version=$(printf '%s' "$POST_DATA" | jq -r '.version // empty')
        download_size=$(printf '%s' "$POST_DATA" | jq -r '.download_size // empty')

        if [ -z "$download_url" ]; then
            cgi_error "missing_url" "download_url is required"; exit 0
        fi

        # Respond immediately, spawn background updater (double-fork)
        jq -n '{"success":true,"status":"starting"}'
        ( "$UPDATER" install "$download_url" "$version" "$download_size" </dev/null >>/tmp/qmanager_update.log 2>&1 & )
        exit 0
    fi

    # --- Rollback ---
    if [ "$ACTION" = "rollback" ]; then
        check_lock

        if [ ! -f "$UPDATES_DIR/previous.tar.gz" ]; then
            cgi_error "no_rollback" "No previous version available for rollback"
            exit 0
        fi

        rollback_version=$(cat "$UPDATES_DIR/previous_version" 2>/dev/null)
        jq -n --arg v "$rollback_version" '{"success":true,"status":"starting","version":$v}'
        ( "$UPDATER" rollback </dev/null >>/tmp/qmanager_update.log 2>&1 & )
        exit 0
    fi

    cgi_error "unknown_action" "Unknown action: $ACTION"
    exit 0
fi

cgi_method_not_allowed
```

- [ ] **Step 3: Commit**

Ensure both files have LF line endings.

```bash
git add scripts/www/cgi-bin/quecmanager/system/update.sh
git commit -m "feat(cgi): add software update CGI endpoint"
```

---

## Task 4: Create the frontend hook — use-software-update.ts

**Files:**
- Create: `hooks/use-software-update.ts`

- [ ] **Step 1: Create the hook file**

Follow the pattern from `hooks/use-system-settings.ts` — `authFetch`, `mountedRef`, silent re-fetch pattern.

```typescript
"use client";

import { useState, useCallback, useRef, useEffect } from "react";
import { authFetch } from "@/lib/auth-fetch";

// =============================================================================
// useSoftwareUpdate — Check, install, rollback QManager updates
// =============================================================================
// Checks GitHub Releases via the backend CGI on mount.
// Polls /tmp/qmanager_update.json during install/rollback.
//
// Backend: GET/POST /cgi-bin/quecmanager/system/update.sh
// =============================================================================

const CGI_ENDPOINT = "/cgi-bin/quecmanager/system/update.sh";
const POLL_INTERVAL = 2000;
const LAST_CHECKED_KEY = "qm_update_last_checked";

// ─── Types ──────────────────────────────────────────────────────────────────

export interface UpdateInfo {
  current_version: string;
  latest_version: string | null;
  update_available: boolean;
  changelog: string | null;
  download_url: string | null;
  download_size: string | null;
  rollback_available: boolean;
  rollback_version: string | null;
  include_prerelease: boolean;
  check_error: string | null;
}

export interface UpdateStatus {
  status: "idle" | "downloading" | "installing" | "rebooting" | "error";
  message?: string;
  version?: string;
  size?: string;
}

export interface UseSoftwareUpdateReturn {
  updateInfo: UpdateInfo | null;
  updateStatus: UpdateStatus;
  isLoading: boolean;
  isChecking: boolean;
  isUpdating: boolean;
  error: string | null;
  lastChecked: string | null;
  checkForUpdates: () => Promise<void>;
  installUpdate: () => Promise<void>;
  rollback: () => Promise<void>;
  togglePrerelease: (enabled: boolean) => Promise<void>;
}

// ─── Hook ───────────────────────────────────────────────────────────────────

export function useSoftwareUpdate(): UseSoftwareUpdateReturn {
  const [updateInfo, setUpdateInfo] = useState<UpdateInfo | null>(null);
  const [updateStatus, setUpdateStatus] = useState<UpdateStatus>({ status: "idle" });
  const [isLoading, setIsLoading] = useState(true);
  const [isChecking, setIsChecking] = useState(false);
  const [isUpdating, setIsUpdating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lastChecked, setLastChecked] = useState<string | null>(null);

  const mountedRef = useRef(true);
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    mountedRef.current = true;
    // Load last checked from localStorage
    const stored = localStorage.getItem(LAST_CHECKED_KEY);
    if (stored) setLastChecked(stored);
    return () => {
      mountedRef.current = false;
      if (pollRef.current) clearInterval(pollRef.current);
    };
  }, []);

  // ---------------------------------------------------------------------------
  // Fetch update info from CGI
  // ---------------------------------------------------------------------------
  const fetchUpdateInfo = useCallback(async (silent = false) => {
    if (!silent) setIsLoading(true);
    setError(null);

    try {
      const resp = await authFetch(CGI_ENDPOINT);
      if (!resp.ok) throw new Error(`HTTP ${resp.status}: ${resp.statusText}`);

      const json = await resp.json();
      if (!mountedRef.current) return;

      if (!json.success) {
        setError(json.detail || json.error || "Failed to check for updates");
        return;
      }

      setUpdateInfo(json as UpdateInfo);

      // Update last checked timestamp
      const now = new Date().toISOString();
      localStorage.setItem(LAST_CHECKED_KEY, now);
      setLastChecked(now);
    } catch (err) {
      if (!mountedRef.current) return;
      setError(err instanceof Error ? err.message : "Failed to check for updates");
    } finally {
      if (mountedRef.current && !silent) setIsLoading(false);
    }
  }, []);

  // Fetch on mount
  useEffect(() => {
    fetchUpdateInfo();
  }, [fetchUpdateInfo]);

  // ---------------------------------------------------------------------------
  // Poll update status during install/rollback
  // ---------------------------------------------------------------------------
  const startPolling = useCallback(() => {
    if (pollRef.current) clearInterval(pollRef.current);

    pollRef.current = setInterval(async () => {
      try {
        const resp = await authFetch(`${CGI_ENDPOINT}?action=status`);
        if (!resp.ok) return;

        const json: UpdateStatus = await resp.json();
        if (!mountedRef.current) return;

        setUpdateStatus(json);

        if (json.status === "rebooting") {
          // Stop polling, navigate to reboot page
          if (pollRef.current) clearInterval(pollRef.current);
          pollRef.current = null;

          setTimeout(() => {
            sessionStorage.setItem("qm_rebooting", "1");
            document.cookie = "qm_logged_in=; Path=/; Max-Age=0";
            window.location.href = "/reboot/";
          }, 2000);
        }

        if (json.status === "error") {
          if (pollRef.current) clearInterval(pollRef.current);
          pollRef.current = null;
          setIsUpdating(false);
          setError(json.message || "Update failed");
        }
      } catch {
        // Device may be rebooting — stop polling and redirect
        if (pollRef.current) clearInterval(pollRef.current);
        pollRef.current = null;

        setTimeout(() => {
          sessionStorage.setItem("qm_rebooting", "1");
          document.cookie = "qm_logged_in=; Path=/; Max-Age=0";
          window.location.href = "/reboot/";
        }, 2000);
      }
    }, POLL_INTERVAL);
  }, []);

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------
  const checkForUpdates = useCallback(async () => {
    setIsChecking(true);
    await fetchUpdateInfo(true);
    if (mountedRef.current) setIsChecking(false);
  }, [fetchUpdateInfo]);

  const installUpdate = useCallback(async () => {
    if (!updateInfo?.download_url || !updateInfo?.latest_version) return;

    setError(null);
    setIsUpdating(true);
    setUpdateStatus({ status: "downloading", version: updateInfo.latest_version });

    try {
      const resp = await authFetch(CGI_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "install",
          download_url: updateInfo.download_url,
          version: updateInfo.latest_version,
          download_size: updateInfo.download_size,
        }),
      });

      const json = await resp.json();
      if (!json.success) {
        setError(json.detail || json.error || "Failed to start update");
        setIsUpdating(false);
        return;
      }

      // Start polling for progress
      startPolling();
    } catch (err) {
      if (!mountedRef.current) return;
      setError(err instanceof Error ? err.message : "Failed to start update");
      setIsUpdating(false);
    }
  }, [updateInfo, startPolling]);

  const rollbackFn = useCallback(async () => {
    setError(null);
    setIsUpdating(true);
    setUpdateStatus({ status: "installing", message: "Restoring previous version..." });

    try {
      const resp = await authFetch(CGI_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "rollback" }),
      });

      const json = await resp.json();
      if (!json.success) {
        setError(json.detail || json.error || "Failed to start rollback");
        setIsUpdating(false);
        return;
      }

      startPolling();
    } catch (err) {
      if (!mountedRef.current) return;
      setError(err instanceof Error ? err.message : "Failed to start rollback");
      setIsUpdating(false);
    }
  }, [startPolling]);

  const togglePrerelease = useCallback(async (enabled: boolean) => {
    try {
      const resp = await authFetch(CGI_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "save_prerelease", enabled }),
      });

      const json = await resp.json();
      if (!json.success) {
        setError(json.detail || json.error || "Failed to save preference");
        return;
      }

      // Re-check with new preference
      await fetchUpdateInfo(true);
    } catch (err) {
      if (!mountedRef.current) return;
      setError(err instanceof Error ? err.message : "Failed to save preference");
    }
  }, [fetchUpdateInfo]);

  return {
    updateInfo,
    updateStatus,
    isLoading,
    isChecking,
    isUpdating,
    error,
    lastChecked,
    checkForUpdates,
    installUpdate,
    rollback: rollbackFn,
    togglePrerelease,
  };
}
```

- [ ] **Step 2: Commit**

```bash
git add hooks/use-software-update.ts
git commit -m "feat(hooks): add useSoftwareUpdate hook for OTA update management"
```

---

## Task 5: Create the Software Update card component

**Files:**
- Create: `components/system-settings/software-update-card.tsx`

- [ ] **Step 1: Create the card component**

This is a self-contained card (like ScheduledOperationsCard) with its own hook instance. Uses the project's shadcn/ui components: Card, Badge, Switch, Label, Button, Skeleton, Alert, AlertDialog, Separator.

UniFi-inspired design: status badge in header, version comparison with arrow, recessed release notes, step indicators during update, rollback row.

Reference the mockup at `.superpowers/brainstorm/1883-1774082897/update-card-unifi.html` for visual direction.

Key states to implement:
1. **Loading** — Skeleton matching existing card patterns
2. **Up to date** — Version + green Badge + pre-release toggle + "Check for Updates" + timestamp
3. **Update available** — Version compare + changelog + "Install Update" button
4. **Updating** — Spinner + status text + step indicators (Download / Install / Reboot)
5. **Error** — Alert with error message
6. **Rollback row** — Shown when `rollback_available` is true

Component imports to use:
- `Card`, `CardContent`, `CardHeader`, `CardTitle`, `CardDescription` from `@/components/ui/card`
- `Badge` with `variant="success"`, `variant="warning"`, `variant="info"` from `@/components/ui/badge`
- `Switch` + `Label` from `@/components/ui/switch` and `@/components/ui/label`
- `Button` with `variant="default"` (primary) and `variant="outline"` (ghost) from `@/components/ui/button`
- `Skeleton` from `@/components/ui/skeleton`
- `Alert`, `AlertDescription` from `@/components/ui/alert`
- `AlertDialog*` from `@/components/ui/alert-dialog` (for confirmation before install/rollback)
- `Separator` from `@/components/ui/separator`
- Icons from `lucide-react`: `CheckIcon`, `AlertCircleIcon`, `DownloadIcon`, `LoaderCircleIcon`, `RotateCcwIcon`, `RefreshCwIcon`

Relative time helper for "Last checked" — inline function:
```typescript
function formatRelativeTime(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  return `${Math.floor(hrs / 24)}d ago`;
}
```

Step indicators during update:
```typescript
const STEPS = ["Download", "Install", "Reboot"] as const;
const stepIndex = { downloading: 0, installing: 1, rebooting: 2 } as const;
```

- [ ] **Step 2: Commit**

```bash
git add components/system-settings/software-update-card.tsx
git commit -m "feat(ui): add SoftwareUpdateCard with UniFi-inspired design"
```

---

## Task 6: Wire the card into the System Settings page

**Files:**
- Modify: `components/system-settings/system-settings.tsx`

- [ ] **Step 1: Import and render the SoftwareUpdateCard**

In `components/system-settings/system-settings.tsx`, add the import and render the card. It is self-contained (owns its own hook), so it just needs to be placed in the grid.

```typescript
// Add import:
import SoftwareUpdateCard from "@/components/system-settings/software-update-card";

// In the grid div, add after ScheduledOperationsCard:
<SoftwareUpdateCard />
```

The card should span the full width of the grid (both columns on wide screens) since it has more content than the other cards. Add `className="@3xl/main:col-span-2"` to the card or wrap it.

- [ ] **Step 2: Commit**

```bash
git add components/system-settings/system-settings.tsx
git commit -m "feat(system-settings): add Software Update card to settings page"
```

---

## Task 7: Validate the shell scripts for OpenWRT

**Files:**
- Validate: `scripts/www/cgi-bin/quecmanager/system/update.sh`
- Validate: `scripts/usr/bin/qmanager_update`
- Validate: `scripts/install.sh`

- [ ] **Step 1: Run the openwrt-script-validator agent**

Use the openwrt-script-validator agent to check `update.sh`, `qmanager_update`, and the modified `install.sh` for:
- LF line endings (no CRLF)
- BusyBox/POSIX compatibility (no bashisms)
- Proper quoting and variable handling

- [ ] **Step 2: Fix any issues found**

- [ ] **Step 3: Commit fixes if needed**

```bash
git add scripts/www/cgi-bin/quecmanager/system/update.sh scripts/usr/bin/qmanager_update scripts/install.sh
git commit -m "fix(scripts): address OpenWRT compatibility issues in update scripts"
```

---

## Task 8: Final verification

- [ ] **Step 1: Run TypeScript type check**

```bash
bun tsc --noEmit
```

Fix any type errors.

- [ ] **Step 2: Verify the build succeeds**

```bash
bun run build
```

- [ ] **Step 3: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: address build and type errors in software update feature"
```
