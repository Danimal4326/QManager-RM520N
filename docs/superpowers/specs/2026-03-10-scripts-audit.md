# QManager Scripts Audit: Redundancy & Architecture Issues

**Date:** 2026-03-10
**Scope:** All scripts under `scripts/` — 49 CGI scripts, 10+ daemon scripts, 6 shared libs, 6 init.d scripts
**Total estimated duplicate code:** ~1,300+ lines across ~70 files

---

## Summary

The backend shell scripts have grown organically and now carry significant redundancy. No CGI infrastructure library exists — every script independently implements HTTP headers, CORS handling, POST body parsing, and AT command wrappers. The core fixes are creating ~3 new shared libraries and extending 2 existing ones, which would eliminate the bulk of the duplication.

---

## ISSUE-01 — Missing `cgi_base.sh`: HTTP boilerplate in ALL CGI scripts
**Priority: CRITICAL | Savings: ~650 lines**

Every CGI script independently implements identical HTTP infrastructure:

| Block | Lines per script | Scripts | Total |
|-------|-----------------|---------|-------|
| HTTP response headers | 7 | 49 | ~343 |
| CORS OPTIONS preflight | 3 | ~45 | ~135 |
| POST body reader + error | 7 | ~20 | ~140 |
| Method-not-allowed fallback | 2 | 49 | ~98 |

**Affected files:** All 49 scripts in `scripts/cgi/quecmanager/`

**Duplicated pattern per script:**
```sh
echo "Content-Type: application/json"
echo "Cache-Control: no-cache, no-store, must-revalidate"
echo "Access-Control-Allow-Origin: *"
echo "Access-Control-Allow-Methods: GET, POST, OPTIONS"
echo "Access-Control-Allow-Headers: Content-Type"
echo ""
if [ "$REQUEST_METHOD" = "OPTIONS" ]; then exit 0; fi
if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
    POST_DATA=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
else
    echo '{"success":false,"error":"no_body","detail":"POST body is empty"}'
    exit 0
fi
```

**Fix:** Create `scripts/usr/lib/qmanager/cgi_base.sh` with:
- `cgi_headers` — emit HTTP headers + blank line
- `cgi_handle_options` — CORS OPTIONS short-circuit
- `cgi_read_post` — read POST body, error on empty
- `cgi_method_not_allowed` — 405 fallback
- `cgi_success` / `cgi_error <code> <detail>` — JSON response helpers (see ISSUE-11)
- `cgi_reboot_response` — flush + async reboot (see ISSUE-10)

---

## ISSUE-02 — Missing `cgi_at.sh`: `strip_at_response()` + `run_at()` in 8 files
**Priority: HIGH | Savings: ~128 lines**

Identical 16-line AT command wrappers defined independently in 6 CGI scripts and 2 daemons.

**Affected files:**
- `scripts/cgi/quecmanager/cellular/apn.sh` (lines ~50–65)
- `scripts/cgi/quecmanager/cellular/imei.sh` (lines ~50–65)
- `scripts/cgi/quecmanager/cellular/mbn.sh` (lines ~54–69)
- `scripts/cgi/quecmanager/cellular/network_priority.sh` (lines ~40–55)
- `scripts/cgi/quecmanager/profiles/current_settings.sh` (lines ~49–64)
- `scripts/cgi/quecmanager/network/ip_passthrough.sh` (lines ~64–79)
- `scripts/usr/bin/qmanager_profile_apply` (lines ~79–101)
- `scripts/usr/bin/qmanager_wan_guard` (lines ~40–56)

**Duplicated pattern:**
```sh
strip_at_response() {
    printf '%s' "$1" | tr -d '\r' | sed '1d' | sed '/^OK$/d' | sed '/^ERROR$/d'
}
run_at() {
    local raw; raw=$(qcmd "$1" 2>/dev/null)
    local rc=$?
    if [ $rc -ne 0 ] || [ -z "$raw" ]; then return 1; fi
    case "$raw" in *ERROR*) return 1 ;; esac
    strip_at_response "$raw"
}
```

**Fix:** Create `scripts/usr/lib/qmanager/cgi_at.sh` with these two functions.
CGI scripts and the two daemons source it instead of defining inline.

---

## ISSUE-03 — `qlog.sh` fallback noop block in 20+ scripts
**Priority: HIGH | Savings: ~200 lines**

Every script has an identical 10-line defensive block:

```sh
. /usr/lib/qmanager/qlog.sh 2>/dev/null || {
    qlog_init() { :; }
    qlog_debug() { :; }
    qlog_info() { :; }
    qlog_warn() { :; }
    qlog_error() { :; }
}
qlog_init "component_name"
```

**Affected files:** ~20+ scripts across `scripts/cgi/`, `scripts/usr/bin/`, `scripts/etc/init.d/`

**Fix options:**
- **Option A (preferred):** Add idempotency guard to `qlog.sh` (check `[ -n "$_QLOG_LOADED" ]` at top) and ensure it never exits non-zero. Scripts then just do `. /usr/lib/qmanager/qlog.sh` with no fallback block.
- **Option B:** Create `scripts/usr/lib/qmanager/qlog_stub.sh` with noop stubs. Source on failure: `. /usr/lib/qmanager/qlog.sh 2>/dev/null || . /usr/lib/qmanager/qlog_stub.sh 2>/dev/null`

---

## ISSUE-04 — Active CID detection (QMAP/CGPADDR cross-reference) in 2 scripts
**Priority: HIGH | Savings: ~100 lines**

The most complex business logic in the CGI layer is duplicated nearly identically. Any fix or improvement must be applied in two places and will inevitably drift.

**Affected files:**
- `scripts/cgi/quecmanager/cellular/apn.sh` (lines ~99–153)
- `scripts/cgi/quecmanager/profiles/current_settings.sh` (lines ~107–159)

**Duplicated logic (~50 lines):**
1. `AT+CGPADDR` → collect all CIDs with a real IPv4 address
2. `AT+QMAP="WWAN"` → get the WAN-connected CID
3. Cross-reference: QMAP is authoritative, fallback to CGPADDR, then default to `1`

**Fix:** Add `get_active_cid()` function to `scripts/usr/lib/qmanager/parse_at.sh`.
Both scripts call it instead of embedding the logic inline.

---

## ISSUE-05 — Ethtool advertise hex builder in CGI + init.d
**Priority: HIGH | Savings: ~80 lines**

A 40+ line `awk` function mapping link mode names to kernel bit positions (including 2.5G / bit 47, which exceeds 32-bit range) is duplicated in two files. They have already drifted (different line counts).

**Affected files:**
- `scripts/cgi/quecmanager/network/ethernet.sh` (lines ~87–128) — CGI endpoint
- `scripts/etc/init.d/qmanager_eth_link` (lines ~25–65) — boot init script

**Risk:** Next 2.5G / ethtool fix must be applied in two places. This already caused bugs before.

**Fix:** Extract `get_supported_advertise_hex()` into a shared library. Both files source and call it.
Best home: new `scripts/usr/lib/qmanager/ethtool_helper.sh` (or extend `cgi_at.sh`).

---

## ISSUE-06 — CGDCONT response parsing similar in 3 scripts
**Priority: MEDIUM | Savings: ~45 lines**

The awk+jq pipeline parsing `AT+CGDCONT?` → `[{cid, pdp_type, apn}]` is similar across 3 scripts.

**Affected files:**
- `scripts/cgi/quecmanager/cellular/apn.sh` (lines ~79–94)
- `scripts/cgi/quecmanager/profiles/current_settings.sh` (lines ~77–92)
- `scripts/cgi/quecmanager/cellular/settings.sh` (lines ~124–137, AMBR variant)

**Fix:** Add `parse_cgdcont()` to `scripts/usr/lib/qmanager/parse_at.sh`.

---

## ISSUE-07 — IMEI validation duplicated in 3 files
**Priority: MEDIUM | Savings: ~18 lines**

15-digit IMEI validation pattern in 3 files (slight variant: one allows empty IMEI for "clear" operation).

**Affected files:**
- `scripts/cgi/quecmanager/cellular/imei.sh` (lines ~67–73) — no empty
- `scripts/usr/lib/qmanager/profile_mgr.sh` (lines ~48–55) — empty allowed
- `scripts/usr/bin/qmanager_imei_check` (lines ~40–46) — no empty

**Fix:** `profile_mgr.sh` already has the canonical implementation. Extract `validate_imei()` from it into `cgi_at.sh` with an `allow_empty` parameter, and have all three source that.

---

## ISSUE-08 — NDJSON→JSON array pattern in 3 fetch scripts
**Priority: MEDIUM | Savings: ~18 lines**

Three "serve history" endpoints share an identical 6-line pattern:

```sh
if [ -f "$HISTORY_FILE" ] && [ -s "$HISTORY_FILE" ]; then
    jq -s '.' "$HISTORY_FILE"
else
    echo "[]"
fi
```

**Affected files:**
- `scripts/cgi/quecmanager/at_cmd/fetch_ping_history.sh` (lines ~29–34)
- `scripts/cgi/quecmanager/at_cmd/fetch_events.sh` (lines ~26–31)
- `scripts/cgi/quecmanager/at_cmd/fetch_signal_history.sh` (lines ~29–34)

**Fix:** Add `serve_ndjson_as_array <file>` to `cgi_base.sh`. Or accept as minor acceptable duplication since scripts are trivially simple.

---

## ISSUE-09 — Modem readiness settle logic in 3 daemons
**Priority: MEDIUM | Savings: ~30 lines**

Each one-shot boot daemon independently implements modem settle logic before issuing AT commands.

**Affected files:**
- `scripts/usr/bin/qmanager_imei_check` — `sleep 20` fixed settle
- `scripts/usr/bin/qmanager_wan_guard` — `sleep 10` fixed settle
- `scripts/usr/bin/qmanager_mtu_apply` — polling loop (60 × 2s for `rmnet_data0`)

**Fix:** Create `scripts/usr/lib/qmanager/modem_ready.sh` with `wait_modem_ready <timeout>` function.
The MTU daemon's interface-specific wait stays inline (different condition: interface up vs. AT port ready).

---

## ISSUE-10 — Reboot-after-response pattern in 2 CGI scripts
**Priority: LOW | Savings: ~12 lines**

The flush-HTTP-then-reboot pattern is duplicated:

```sh
jq -n '{"success":true}'
( sleep 1 && reboot ) &
exit 0
```

**Affected files:**
- `scripts/cgi/quecmanager/cellular/mbn.sh` (lines ~248–252)
- `scripts/cgi/quecmanager/cellular/imei.sh` (lines ~249–253)

**Fix:** Add `cgi_reboot_response()` to `cgi_base.sh`. Ensures future reboot endpoints don't accidentally omit the async pattern.

---

## ISSUE-11 — JSON response generation inconsistent across 49 scripts
**Priority: LOW**

Success/error JSON is generated three different ways:
- `echo '{"success":false,"error":"..."}'`
- `jq -n '{"success":false}'`
- `jq -n --arg error "..." '{"success":false,"error":$error}'`

**Fix:** Add `cgi_success()` and `cgi_error <code> <detail>` to `cgi_base.sh`. Style consistency fix.

---

## ISSUE-12 — PID file singleton pattern in 2 files
**Priority: LOW | Savings: ~18 lines**

Identical 9-line PID file check + write pattern in the profile apply CGI and its daemon.

**Affected files:**
- `scripts/cgi/quecmanager/profiles/apply.sh` (lines ~88–97)
- `scripts/usr/bin/qmanager_profile_apply` (lines ~60–68)

**Fix:** Extract `profile_acquire_lock()` to `profile_mgr.sh`. Low urgency — same feature, co-located files.

---

## Proposed New Shared Libraries

| New/Modified File | Issues | Savings |
|-------------------|--------|---------|
| `scripts/usr/lib/qmanager/cgi_base.sh` *(new)* | 01, 10, 11 | ~700 lines |
| `scripts/usr/lib/qmanager/cgi_at.sh` *(new)* | 02, 07 | ~146 lines |
| `scripts/usr/lib/qmanager/qlog.sh` *(modify)* | 03 | ~200 lines |
| `scripts/usr/lib/qmanager/parse_at.sh` *(extend)* | 04, 06 | ~145 lines |
| `scripts/usr/lib/qmanager/ethtool_helper.sh` *(new)* | 05 | ~80 lines |
| `scripts/usr/lib/qmanager/modem_ready.sh` *(new)* | 09 | ~30 lines |

**Total recoverable: ~1,300+ lines**

---

## Recommended Execution Order

Execute in this order to maximize impact while minimizing risk:

1. **ISSUE-02** — `cgi_at.sh` — pure utility extraction, zero behavior change, safe starting point
2. **ISSUE-04** — active CID in `parse_at.sh` — high drift risk, critical business logic
3. **ISSUE-05** — ethtool hex builder — already drifted, reunify before next ethtool bug
4. **ISSUE-01** — `cgi_base.sh` — largest impact, touches all 49 scripts; do after helpers are stable
5. **ISSUE-03** — `qlog.sh` fallback — high line-count cosmetic; do after other refactors settle
6. **ISSUE-06** — CGDCONT parsing in `parse_at.sh` — low risk extension
7. **ISSUE-07** — IMEI validation consolidation
8. **ISSUE-08** — NDJSON helper (or accept duplication)
9. **ISSUE-09** — modem readiness library
10. **ISSUE-10, 11, 12** — low-impact, last

---

## Verification (Per Fix)

1. Deploy changed scripts to device
2. `curl http://router/cgi-bin/quecmanager/<endpoint>` — verify JSON response correct
3. `logread | grep qmanager` — check for sourcing errors
4. For init.d changes: reboot and verify daemon starts cleanly
5. For active CID changes: test with both SIM slots, QMAP available/unavailable
