# 🚀 QManager RM520N BETA v0.1.5

A Tower Locking quality-of-life upgrade, plus a major install/update/uninstall reliability overhaul that unlocks one-click OTA updates from this version forward.

## ✨ New Features

- **System Health Check.** A new page under System Settings that runs end-to-end diagnostics across binaries, permissions, AT transport, SMS, sudoers, systemd services, network, and configuration. Failed and warning rows expand to show the captured output, and a one-click download produces a redacted `.tar.gz` bundle ready for support handoff.
- **Simple Mode for Tower Locking (LTE & NR-SA).** A per-card toggle that swaps the Channel field for a dropdown of currently visible carriers from `AT+QCAINFO` — band, channel, PCI, and RSRP at a glance. NR auto-fills band and SCS; LTE dedups picks across all 3 slots. Falls back to manual entry when no carriers are visible.
- **Live step-by-step install progress in the UI.** The Software Update card now streams each install step as it happens (Stopping services → Installing backend → Cleaning up legacy → Enabling services → …) instead of just "Installing update…". Same status surfaces in the staged-download flow.
- **Crash detection for interrupted updates.** If an install was killed mid-flight (power loss, OOM, accidental reboot), the next update check banners "Previous update did not complete cleanly" so you know to investigate before continuing.

## ✅ Improvements

- **System Health Check on-device hardening.** Hardware-validated against an RM520N-GL: BusyBox-safe AT response parsing (no more spurious failures from carriage returns in `qcmd "AT"` and `AT+CGSN`), accurate freshness check for the poller cache, and a sudoers test that correctly inspects the `www-data` CGI user's privileges instead of root's. Several rows that previously reported false failures now pass cleanly.
- **Tower Locking polish.** Signal Failover now defaults to disabled on fresh installs and is no longer auto-enabled when you lock a tower — you opt in deliberately. The Signal Failover toggle now shows a success toast on enable, disables itself during the in-flight save (no more spam-clicks), and snaps back to the correct state immediately on disable instead of staying visually stuck until a page refresh. The locking spinner is also scoped to the main lock toggle only, so settings interactions no longer flash a global spinner.
- **Fixed installer falsely labelling any device as RM520N-GL.** The pre-flight check now reads the actual model from `/etc/quectel-project-version`. RM520N-GL proceeds silently as before. RM551E is blocked immediately with a clear error. Any other unrecognized device (RG501Q, etc.) shows the detected model and prompts `"Do you want to proceed anyway? [y/N]"` so you stay in control.
- **Made `/dev/smd11` permissions self-healing.** A new udev rule sets the AT device to `root:dialout 660` whenever the kernel creates it — fixes PRAIRE-derived modems (RG502Q/RM502Q) where the device was recreated after the boot-time permission script ran, and auto-restores access if the modem resets mid-session.
- **Crash-resilient version tracking.** Two-phase VERSION write (pending → final) means a partial install never overwrites the old version stamp. The update CGI surfaces stale pending markers so the UI can warn you.
- **Atomic file installs.** Every script and binary is now written via temp-file + atomic rename, with ELF-aware CRLF handling so binaries can't be corrupted by a Windows-built tarball. Replaces the older copy + `sed -i` + `chmod` triplets that could leave files in inconsistent states on disk-full or interrupt.
- **Filesystem-driven service handling.** The installer and uninstaller now scan `/lib/systemd/system/qmanager-*.service` and `/usr/bin/qmanager_*` instead of hardcoded daemon lists, so new daemons added in future releases are stopped, started, enabled, and removed automatically — no installer edits needed.
- **Watchcat protected during install.** A maintenance lock file prevents the connectivity watchdog from interpreting install-induced disruption as a failure and rebooting the device mid-update.
- **Active conflict-package removal.** `socat` and `socat-at-bridge` (the packages that fight QManager for `/dev/smd11`) are now actively `opkg remove`d during install, with retries through `--force-removal-of-dependent-packages` and `--force-depends`.
- **Auto-skip SSH setup when already configured.** Installer detects an existing port-22 listener (vendor dropbear, OpenSSH, anything) and skips the SSH prompt instead of asking redundantly. Detection works on BusyBox `pgrep -x` quirks via `ss`/`netstat` fallback.
- **Filesystem-driven uninstall** with proper teardown for the web console and (with `--purge`) Tailscale. Entware (`/opt/`) is intentionally preserved unconditionally — manual removal instructions in `--help`.
- **Post-install verification.** The updater now verifies VERSION was actually stamped to the target version after install, and runs a 3-attempt `qcmd 'ATI'` check to confirm the AT command stack survived the upgrade.
- **Self-cleaning install staging.** `/tmp/qmanager_install/` is now removed by the installer itself on success, not just by the OTA worker.
- **Faster "Stopping QManager services" step.** The installer now batches all qmanager-* and socat-* service stops into single `systemctl stop` calls instead of one per unit, letting systemd shut them down in parallel — noticeably quicker on every install and update. A `TimeoutStopSec=10` cap on the long-running daemons (poller, ping, watchcat, tower-failover, console) also bounds the worst case at 10s instead of systemd's 90s default if a service ever wedges on the AT lock.

## 📥 Installation

### Fresh Install

ADB or SSH into the modem and run:

```sh
curl -fsSL -o /tmp/qmanager-installer.sh \
  https://github.com/dr-dolomite/QManager-RM520N/raw/refs/heads/main/qmanager-installer.sh && \
  bash /tmp/qmanager-installer.sh
```

### Upgrading from v0.1.4

**This one-time hop requires ADB or SSH** — the v0.1.4 update CGI lacks the sudo elevation needed to install v0.1.5 cleanly. Run the same fresh-install command above; your settings, profiles, and password are preserved.

### Upgrading from v0.1.5 onward

**System Settings → Software Update.** Click Download, then Install. Live step-by-step progress is shown in the UI. No SSH/ADB needed. All settings preserved.

## 💙 Thank You

Bug reports and feature requests welcome on [GitHub Issues](https://github.com/dr-dolomite/QManager-RM520N/issues).

If QManager saves you time, consider [sponsoring on GitHub](https://github.com/sponsors/dr-dolomite) or sending GCash via Remitly to **Russel Yasol** (+639544817486).

**License:** MIT + Commons Clause — **Happy connecting!**

---
