---
name: validated-scripts
description: Scripts that have been audited for OpenWRT/BusyBox compatibility and their status
type: project
---

## Validated Scripts

### 2026-03-15 — Email Alerts Feature

| Script | Status | Issues Found | Fixed? |
|--------|--------|-------------|--------|
| `scripts/usr/lib/qmanager/email_alerts.sh` | PASS (after fixes) | CRLF line endings; `date -r` fallback (W) | Yes |
| `scripts/cgi/quecmanager/monitoring/email_alerts.sh` | PASS (after fixes) | CRLF line endings; threshold validation gap (W) | Yes |
| `scripts/cgi/quecmanager/monitoring/email_alert_log.sh` | PASS (after fixes) | CRLF line endings; `tac` not on BusyBox (C) | Yes |
| `scripts/usr/bin/qmanager_poller` | PASS | LF already correct; new email_alerts integration lines are clean | N/A |

Severity key: C=critical (will break), W=warning (may produce wrong behavior), I=info
