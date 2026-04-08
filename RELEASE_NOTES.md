# QManager RM520N BETA v0.1.2

**Stability and installer improvements** — fixes SMS multi-part messages, adds SSH password management, bundles Speedtest CLI, and hardens the installer for reliable upgrades.

> Upgrading from v0.1.1? Go to **System Settings -> Software Update** or re-run the installer via ADB/SSH. All existing settings and profiles are preserved.

---

## What's New

### SMS Multi-Part Message Support

SMS messages that span multiple segments (common for carrier notifications) are now properly reassembled and displayed as a single message. Previously, each segment appeared as a separate entry in the inbox.

- Switched SMS backend to `sms_tool` which handles PDU-level multi-part reassembly natively
- Merged messages show all storage indexes for proper deletion
- Sending and deleting SMS messages works reliably

### SSH Password Management

SSH access no longer requires manual `passwd root` setup via ADB.

- **Automatic setup during onboarding** — the web UI password you set during first-time setup is automatically applied as the SSH root password
- **System Settings > SSH Password** — new card to change the SSH password independently from the web UI password at any time
- Connect via `ssh root@192.168.225.1` using the password set during onboarding or from the settings card

### Speedtest CLI Auto-Install

The Ookla Speedtest CLI is now automatically downloaded and installed during QManager setup. No need to install it separately from the RGMII toolkit.

- Downloaded from Ookla's servers during install (ARMv7 armhf binary)
- Installed to `/usrdata/root/bin/speedtest` (persistent across reboots)
- Non-fatal if download fails (feature shows as unavailable in the UI)

### Cell Scanner Fix

Cell scanning now works correctly with operator name resolution.

- Fixed operator-list.json path for the RM520N-GL directory structure
- Fixed JSON assembly crash when operator list is empty or missing
- Provider names now resolve properly via MCC/MNC lookup

---

## Installer Improvements

### Windows Line Ending Safety

Tarballs built on Windows no longer cause script failures. The installer now strips `\r` (carriage return) characters from all deployed shell scripts, systemd units, and sudoers rules after copying them to the device.

### lighttpd Module Version Sync

When upgrading, the installer now runs `opkg upgrade` on lighttpd and all its modules together, preventing the `plugin-version doesn't match lighttpd-version` crash that could occur when modules were out of sync.

### Graceful No-Internet Handling

If `opkg update` fails due to no internet connection, the installer now prints clear warning messages and skips all Entware package installs instead of crashing. The rest of the installation (scripts, frontend, systemd units) continues normally. Re-run the installer with internet to complete package setup.

---

## Installation

**No prerequisites required** — QManager is fully independent. The installer bootstraps Entware, installs lighttpd, and sets up everything from scratch. You only need ADB or SSH access and internet connectivity on the modem.

ADB or SSH into the modem and run:

```sh
curl -fsSL -o /tmp/qmanager-installer.sh \
  https://github.com/dr-dolomite/QManager-RM520N/raw/refs/heads/main/qmanager-installer.sh && \
  bash /tmp/qmanager-installer.sh
```

### Bundled Dependencies

- `atcli_smd11` — AT command transport via `/dev/smd11`
- `sms_tool` — SMS send/recv/delete with multi-part reassembly
- `jq` — JSON processor (Entware package)
- `dropbear` — SSH server (Entware package)
- `speedtest` — Ookla Speedtest CLI (downloaded during install)

### Uninstalling

```sh
bash /tmp/qmanager_install/uninstall_rm520n.sh

# To also remove config/profiles/passwords:
bash /tmp/qmanager_install/uninstall_rm520n.sh --purge
```

---

## Platform Notes

This is a **native port** to the RM520N-GL's internal Linux (SDXLEMUR, ARMv7l, kernel 5.4.180). Uses systemd for service management, lighttpd for web serving, iptables for firewall rules, and `/usrdata/` for persistent storage.

### Features Not Yet Ported

The following RM551E features are deferred due to platform differences:

- VPN management (Tailscale + NetBird) — **for Tailscale, please use the [RGMII Toolkit](https://github.com/iamromulan/quectel-rgmii-toolkit) for now**
- Video optimizer / traffic masquerade (DPI)
- Bandwidth monitor
- Ethernet status & link speed
- Custom DNS
- WAN interface guard
- Email Alerts

---

## Known Issues

- This is a **pre-release** — please report bugs at [GitHub Issues](https://github.com/dr-dolomite/QManager-RM520N/issues).
- Email alerts require `msmtp` which can be installed from within the app (System Settings).
- BusyBox `flock` lacks `-w` (timeout flag) — all flock usage has been adapted to use non-blocking polling loops.

---

## Thank You

Thanks for using QManager! If you find it useful, consider [supporting the project on Ko-fi](https://ko-fi.com/drdolomite) or [PayPal](https://paypal.me/iamrusss). Bug reports and feature requests are always welcome.

**License:** MIT + Commons Clause

**Happy connecting!**
