# 🚀 QManager RM520N v0.1.7-beta.1.dc

**Configurable session timeout, custom update repository** — Sessions can now be set to any duration (or never expire) from System Settings. Updates can be pulled from any GitHub fork, both in the UI and via the `QMANAGER_REPO` env var in the installer.

## ✨ What's New

### 🔒 Configurable Session Timeout

A new **Security** card under System Settings lets you set how long a session stays active before requiring re-login. Choose any duration in minutes, hours, or days, or enable **Never expire** for persistent sessions (browser-side cookie uses the 400-day maximum; server enforces the setting on every request).

### 🔄 Custom Update Repository

The Software Update preferences card now includes an **Update Repository** field. Enter any `owner/repo` GitHub fork to pull updates from — useful for testing forks or staging builds. Leave empty to use the default (`dr-dolomite/QManager-RM520N`). The installer also accepts a `QMANAGER_REPO` environment variable for the same purpose.

## 📥 Installation

### Upgrading from v0.1.5

**System Settings → Software Update.** Click Download, then Install. No SSH/ADB needed. All settings preserved.

### Fresh Install

ADB or SSH into the modem and run:

```sh
curl -fsSL -o /tmp/qmanager-installer.sh \
  https://github.com/dr-dolomite/QManager-RM520N/raw/refs/heads/main/qmanager-installer.sh && \
  bash /tmp/qmanager-installer.sh
```

### Upgrading from v0.1.4

**This one-time hop requires ADB or SSH** — the v0.1.4 update CGI lacks the sudo elevation needed to install v0.1.5+ cleanly. Run the same fresh-install command above; your settings, profiles, and password are preserved.

## 💙 Thank You

Bug reports and feature requests welcome on [GitHub Issues](https://github.com/dr-dolomite/QManager-RM520N/issues).

If QManager saves you time, consider [sponsoring on GitHub](https://github.com/sponsors/dr-dolomite) or sending GCash via Remitly to **Russel Yasol** (+639544817486).

**License:** MIT + Commons Clause — **Happy connecting!**

---
