# 🚀 QManager RM520N v0.1.9-beta.1.dc

**Configurable session timeout, custom update repository** — Sessions can now be set to any duration (or never expire) from System Settings. Updates can be pulled from any GitHub fork, both in the UI and via the `QMANAGER_REPO` env var in the installer.

## ✨ What's New

### 🔒 Configurable Session Timeout

A new **Security** card under System Settings lets you set how long a session stays active before requiring re-login. Choose any duration in minutes, hours, or days, or enable **Never expire** for persistent sessions (browser-side cookie uses the 400-day maximum; server enforces the setting on every request).

### 🔄 Custom Update Repository

The Software Update preferences card now includes an **Update Repository** field. Enter any `owner/repo` GitHub fork to pull updates from — useful for testing forks or staging builds. Leave empty to use the default (`dr-dolomite/QManager-RM520N`). The installer also accepts a `QMANAGER_REPO` environment variable for the same purpose.

# 🚀 QManager RM520N BETA v0.1.8

The connectivity engine got a real fix: it now uses a primary-then-fallback probe with configurable URLs, defaults to Cloudflare so installs in regions that block Google still come up clean, and finally speaks HTTPS. Also fixes Network Priority on Quectel x6x firmwares.

> One-click OTA from **System Settings → Software Update** if you're on v0.1.5 or newer. SSH/ADB is not required.

## ✨ New Features

- **Configurable connectivity probe targets with HTTPS.** System Settings → Connectivity Sensitivity now exposes Primary and Secondary URLs — paste anything from `youtube.com` to `https://example.com/health` and it just works. Defaults are Cloudflare primary, Google secondary, and the probe falls through to the secondary when the primary fails so a single blocked endpoint can never lock the device on "failed" again.

## 🛠️ Improvements

- **Network Priority Settings now populate on RM521F-GL (x65).** The card was rendering blank on x6x-series modems because their firmware echoes the RAT order under the key `rat_order_pref` instead of the `rat_acq_order` x5x firmwares use — same value, different label. The parser now accepts either key, so the three RAT entries (NR5G / LTE / WCDMA) load and reorder correctly across both firmware generations.

## 📥 Installation

### Upgrading from v0.1.7

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

If QManager saves you time, consider tipping with [GitHub](https://github.com/sponsors/dr-dolomite) or [PayPal](https://paypal.me/iamrusss).

<div align="center">
  <a href="https://github.com/sponsors/dr-dolomite" target="_blank">
    <img height="40" src="https://img.shields.io/badge/GitHub%20Tip-%E2%9D%A4-EA4AAA?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Tip on GitHub" />
  </a>
  <a href="https://paypal.me/iamrusss" target="_blank">
    <img height="40" src="https://img.shields.io/badge/PayPal%20Tip-00457C?style=for-the-badge&logo=paypal&logoColor=white" alt="Tip via PayPal" />
  </a>
</div>

GCash via Remitly remains available to **Russel Yasol** (+639544817486).

**License:** MIT + Commons Clause — **Happy connecting!**

---
