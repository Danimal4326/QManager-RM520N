# 🚀 QManager RM520N v0.1.9.dc

**Configurable session timeout, custom update repository** — Sessions can now be set to any duration (or never expire) from System Settings. Updates can be pulled from any GitHub fork, both in the UI and via the `QMANAGER_REPO` env var in the installer.

## ✨ What's New

### 🔒 Configurable Session Timeout

A new **Security** card under System Settings lets you set how long a session stays active before requiring re-login. Choose any duration in minutes, hours, or days, or enable **Never expire** for persistent sessions (browser-side cookie uses the 400-day maximum; server enforces the setting on every request).

### 🔄 Custom Update Repository

The Software Update preferences card now includes an **Update Repository** field. Enter any `owner/repo` GitHub fork to pull updates from — useful for testing forks or staging builds. Leave empty to use the default (`dr-dolomite/QManager-RM520N`). The installer also accepts a `QMANAGER_REPO` environment variable for the same purpose.

# 🚀 QManager RM520N BETA v0.1.9

> One-click OTA from **System Settings → Software Update** if you're on v0.1.5 or newer. SSH/ADB is not required.

## ✨ New Features

- **Enable Tailscale SSH from the UI.** A new toggle in the Tailscale Connection card lets you turn on Tailscale's built-in SSH server with one click. Access is controlled entirely by your Tailscale admin-panel ACL policy — no changes to the device's existing SSH. A confirmation prompt reminds you to review your ACLs before enabling. The setting sticks across reconnects and reboots.

- **System Health now shows load averages.** A new row beneath CPU Usage displays the 1-minute, 5-minute, and 15-minute load averages. On the single-core RM520N-GL, these give a clearer picture of sustained load than a single CPU % snapshot — the bar turns yellow or red when the device is under pressure, and an info icon explains what the three numbers mean.

- **Data Used counter now survives reboots.** Previously, the counter reset every time the modem restarted or the data session re-attached — making it unreliable for tracking usage over days. QManager now maintains its own running total independently of the modem session. A new **Reset** button on the Device Metrics card lets you zero it on demand, handy for tracking usage within a billing window.

## 🛠️ Improvements

- **Live Traffic fixed on x5x-class modems (RM501, RM502, RG502Q).** The traffic display was looking at the wrong network interface on these platforms and showing zeroed counters. It now auto-detects the active interface correctly each time.

- **Connectivity status no longer gets stuck on "Offline."** On certain device variants, the connectivity check was reading from a fixed interface that wasn't active — so it always appeared offline even when internet was working. The check now uses HTTP probes to Cloudflare and Google, which is the correct and reliable signal.

- **OTA upgrades no longer abort on non-standard device variants.** Users on variant firmware IDs (e.g. `RM520FGL_VA`) were seeing "Installation aborted by user" during upgrade — even though they hadn't cancelled anything. The installer now handles non-interactive environments correctly and proceeds with a warning instead of exiting.

- **LAN Gateway now displays correctly on all variants.** On some devices (notably RM501-class), the LAN Gateway field was occasionally stuck on `-`. It's now fetched once at startup by the background poller and cached, so it loads instantly and renders correctly across all supported models.

- **Modem access fixed on older Quectel platforms (RM502Q-AE, RG502Q).** A permissions issue on X55-family devices could silently prevent the web server from communicating with the modem, causing AT commands to fail. The installer now uses multiple fallback methods to ensure access is set up correctly, and removes any conflicting rules from third-party tools.

## 📥 Installation

### Upgrading from v0.1.8

**System Settings → Software Update.** Click Download, then Install. No SSH/ADB needed. All settings preserved.

### Fresh Install

ADB or SSH into the modem and run:

```sh
curl -fsSL -o /tmp/qmanager-installer.sh \
  https://github.com/dr-dolomite/QManager-RM520N/raw/refs/heads/main/qmanager-installer.sh && \
  bash /tmp/qmanager-installer.sh
```

If your modem has `wget` but not `curl` (common on x5x/x6x firmwares like RM502/RM520/RM521), just use `wget` to fetch the installer — preflight auto-installs `curl` from Entware so future OTA updates work (Entware must already be bootstrapped):

```sh
wget -O /tmp/qmanager-installer.sh \
  https://github.com/dr-dolomite/QManager-RM520N/raw/refs/heads/main/qmanager-installer.sh && \
  bash /tmp/qmanager-installer.sh
```

## 💙 Thank You!

Bug reports and feature requests welcome on [GitHub Issues](https://github.com/dr-dolomite/QManager-RM520N/issues).

Like what's new? QManager is built and maintained for free — if these updates have made your setup a little better, you can show your support via [Wise](https://wise.com/pay/business/blackcatdev?currency=USD). Every bit helps keep this project alive and growing. [GitHub Sponsors](https://github.com/sponsors/dr-dolomite) is also an option if that works better for you.


**License:** MIT + Commons Clause — **Happy connecting!**

---
