# 🚀 QManager RM520N BETA v0.1.5

A Tower Locking quality-of-life upgrade plus installer and AT-device reliability fixes.

## ✨ New Features

- **Simple Mode for Tower Locking (LTE & NR-SA).** A per-card toggle that swaps the Channel field for a dropdown of currently visible carriers from `AT+QCAINFO` — band, channel, PCI, and RSRP at a glance. NR auto-fills band and SCS; LTE dedups picks across all 3 slots. Falls back to manual entry when no carriers are visible.

## ✅ Improvements

- **Fixed installer falsely labelling any device as RM520N-GL.** The pre-flight check now reads the actual model from `/etc/quectel-project-version`. RM520N-GL proceeds silently as before. RM551E is blocked immediately with a clear error. Any other unrecognized device (RG501Q, etc.) shows the detected model and prompts `"Do you want to proceed anyway? [y/N]"` so you stay in control.
- **Made `/dev/smd11` permissions self-healing.** A new udev rule sets the AT device to `root:dialout 660` whenever the kernel creates it — fixes PRAIRE-derived modems (RG502Q/RM502Q) where the device was recreated after the boot-time permission script ran, and auto-restores access if the modem resets mid-session.

## 📥 Installation

### Fresh Install

ADB or SSH into the modem and run:

```sh
curl -fsSL -o /tmp/qmanager-installer.sh \
  https://github.com/dr-dolomite/QManager-RM520N/raw/refs/heads/main/qmanager-installer.sh && \
  bash /tmp/qmanager-installer.sh
```

### Upgrading from v0.1.4

**System Settings → Software Update.** No migration steps needed. All settings preserved.

## 💙 Thank You

Bug reports and feature requests welcome on [GitHub Issues](https://github.com/dr-dolomite/QManager-RM520N/issues).

If QManager saves you time, consider [sponsoring on GitHub](https://github.com/sponsors/dr-dolomite) or sending GCash via Remitly to **Russel Yasol** (+639544817486).

**License:** MIT + Commons Clause — **Happy connecting!**

---
