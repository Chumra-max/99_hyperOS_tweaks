# HyperOS Tweaks (Conservative Performance & Stability Module)

A conservative, system-level tweak module for Xiaomi HyperOS devices focused on:
- Smoother UI during burst events (VPN connect, app switching, multitasking)
- Better background app retention
- Reduced system overhead from excessive logging, tracing, and analytics
- Minimal battery impact

This module **does NOT** perform mass debloating or aggressive kernel hacks.

---

## ✨ Features

### Scheduler & Latency
- Improved task scheduling responsiveness
- Reduced wakeup and context-switch overhead
- Better handling of short system bursts

### I/O Tweaks
- Prefer noop I/O scheduler where available
- Optimized read-ahead values
- Safer queue depth tuning

### Logging & Tracing Hygiene
- Disables unnecessary kernel tracing events
- Reduces binder, scheduler, and power wakeup noise
- Caps logcat buffers to avoid CPU wake storms

### Memory Management
- Conservative LMK tuning (≈20% threshold reduction)
- ZRAM enabled and configured safely
- No aggressive `vm.*` sysctl changes

### Binder / IPC Cleanup
- Disables binder trace events when supported
- Reduces IPC contention during system activity spikes

### Android Framework Tweaks
- Background process limit increase
- Background dexopt trigger
- No animation or UI changes

### GPU (Safe Properties Only)
- Enables GPU-based composition paths
- No frequency manipulation

### Network & Background Services
- Reduces aggressive Wi-Fi and BLE scanning
- AppOps-based background throttling for known analytics/services
- Optional handling of `com.miui.msa.global` (MSA)

---

## 🛑 What This Module Does NOT Do

- ❌ No mass app disabling or uninstalling
- ❌ No risky power-kill policies
- ❌ No animation speed hacks

This module is designed to be predictable, and safe.

---

## 📁 Logging & Backups

All actions are logged and reversible.

**Location:**

**Contents:**
- `hyperos_tweaks.log` – full execution log
- `hyperos_tweaks.status` – summary report
- `backup/` – original values before modification

---

## 📱 Compatibility

- Xiaomi HyperOS devices
- Root required
- Tested on HyperOS (Android 14/15 base)
- Should gracefully skip unsupported paths on other Android ROMs

---

## ⚙️ Installation

1. Flash via:
   - KernelSU
   - Magisk
   - APatch
2. Reboot
3. Check logs at `/sdcard/HyperOS_Tweaks/`

---

## 🧪 Observed Effects

Users may notice:
- Reduced lag during short term bursts
- Smoother app switching
- Fewer background app reloads
- More consistent UI responsiveness under load

Actual results depend on device, RAM size, and firmware version.

---

## ⚠️ Disclaimer

This module modifies system behavior.
While designed to be conservative and reversible, use at your own risk.

Always keep a backup.