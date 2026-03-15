---
name: busybox-quirks
description: BusyBox-specific incompatibilities confirmed or found in this project
type: project
---

## Confirmed BusyBox Incompatibilities

### `tac` — NOT available on BusyBox
`tac` reverses line order (GNU coreutils). Not in BusyBox.
**Why:** Found in `email_alert_log.sh` — `tac "$LOG_FILE" | jq -s '.'` looked like it had a fallback but the fallback was dead code (jq exits 0 with `[]` on empty input from tac).
**How to apply:** Always use `jq -s 'reverse'` to reverse NDJSON lines. This is the idiomatic, jq-approved pattern for this project.

### `date -r <epoch>` — NOT available on BusyBox
`date -r N` is macOS/FreeBSD syntax for converting an epoch to a date string. BusyBox `date -r` means something else (file modification time).
**Why:** Found in `email_alerts.sh` library. The fallback chain `date -d "@$epoch" || date -r "$epoch" || raw_epoch` had the second fallback silently fail and drop through to raw epoch.
**How to apply:** Use `date -d "@$epoch"` as primary. Use `awk "BEGIN{print strftime(\"%Y-%m-%d %H:%M:%S\",$epoch)}"` as portable fallback. BusyBox awk includes strftime.

### Threshold validation with `2>/dev/null` on `[ ]` numeric tests
Using `[ "$var" -lt N ] 2>/dev/null` swallows the error when `$var` is non-numeric, making the test silently return false (non-zero). If guarding a range check, a non-numeric input passes validation.
**How to apply:** Always add a `case "$var" in ''|*[!0-9]*) ... esac` guard before numeric `[ ]` comparisons when the input comes from user/POST data.

## Confirmed Safe Patterns

### `jq -s 'reverse'` for NDJSON newest-first
Fully portable on this project's OpenWRT target. Reads all lines as JSON array and reverses. No external tools needed.

### `awk BEGIN{print strftime(...)}` for epoch formatting
BusyBox awk includes strftime. Confirmed safe fallback for epoch-to-date conversion.

### `wc -l < "$file"` for line counting
BusyBox `wc -l` with input redirect works correctly.

### `tail -n N "$file" > "$tmp" && mv "$tmp" "$file"` for log trimming
The in-place tail-trim pattern used for NDJSON log capping is correct for BusyBox.

## External Tools Status

| Tool | Status | Notes |
|------|--------|-------|
| `jq` | Approved/available | All jq patterns used in project are compatible |
| `qcmd` | Approved/available | Project-specific AT command tool |
| `msmtp` | Optional external | Must be installed via `opkg install msmtp`; email_alerts.sh guards with `command -v msmtp` |
| `tac` | NOT available | GNU coreutils only; use `jq -s 'reverse'` instead |
