#!/system/bin/sh
#
# 99_hyperos_tweaks.sh
#
LOG_DIR=/data/local/tmp/HyperOS_Tweaks
LOG="$LOG_DIR/hyperos_tweaks.log"
BAK_DIR="$LOG_DIR/backup"
mkdir -p "$LOG_DIR" "$BAK_DIR"
exec >>"$LOG" 2>&1

timestamp() { date +"%Y-%m-%d %H:%M:%S"; }

# logging helpers
_info()  { printf "%s [INFO]  %s\n" "$(timestamp)" "$*"; }
_warn()  { printf "%s [WARN]  %s\n" "$(timestamp)" "$*"; }
_error() { printf "%s [ERROR] %s\n" "$(timestamp)" "$*"; }
_section(){ printf "\n%s [SECTION] %s\n" "$(timestamp)" "$*"; }

_info "HyperOS Tweaks starting. Log is being written to: $LOG"
_info "If you need to share this output, the file is saved at: $LOG (user-accessible storage)."

# require root
if [ "$(id -u 2>/dev/null)" != "0" ]; then
  _error "This script must run as root. Exiting."
  exit 1
fi

# small helpers
safe_echo() {
  val="$1"; file="$2"
  if [ -w "$file" ] || ([ -f "$file" ] && [ -w "$(dirname "$file")" ]); then
    if [ ! -f "$BAK_DIR/$(echo $file | sed 's,/,_,g')_orig" ] && [ -f "$file" ]; then
      cat "$file" > "$BAK_DIR/$(echo $file | sed 's,/,_,g')_orig" 2>/dev/null || true
      _info "Backed up original: $file -> $BAK_DIR/$(echo $file | sed 's,/,_,g')_orig"
    fi
    if echo "$val" > "$file" 2>/dev/null; then
      _info "Wrote value to: $file"
    else
      _warn "Failed to write value to: $file (permission or unsupported)"
    fi
  else
    _warn "Skipped write (no access): $file"
  fi
}

safe_setprop() {
  key="$1"; val="$2"
  setprop "$key" "$val" 2>/dev/null
  cur=$(getprop "$key" 2>/dev/null)
  if [ "$cur" = "$val" ]; then
    _info "System property applied: $key -> $val"
  else
    _warn "Could not apply property or unchanged: $key (attempted: $val, got: '$cur')"
  fi
}

# -----------------------
# Scheduler / latency tweaks
# -----------------------
_section "Scheduler and CPU latency tuning"
[ -f /proc/sys/kernel/sched_autogroup_enabled ] && safe_echo 1 /proc/sys/kernel/sched_autogroup_enabled
[ -f /proc/sys/kernel/sched_min_granularity_ns ] && safe_echo 30000000 /proc/sys/kernel/sched_min_granularity_ns
[ -f /proc/sys/kernel/sched_wakeup_granularity_ns ] && safe_echo 15000000 /proc/sys/kernel/sched_wakeup_granularity_ns
[ -f /proc/sys/kernel/sched_power_aware ] && safe_echo 1 /proc/sys/kernel/sched_power_aware

# -----------------------
# I/O scheduler -> prefer noop for physical flash if available
# -----------------------
_section "Storage I/O scheduler configuration"
for dev in /sys/block/*; do
  bname=$(basename "$dev")
  case "$bname" in
    loop*|ram*|dm-*|zram*|sr*|nvme* ) continue ;;
  esac
  sched="$dev/queue/scheduler"
  if [ -f "$sched" ]; then
    if [ ! -f "$BAK_DIR/${sched//\//_}_orig" ]; then
      cat "$sched" > "$BAK_DIR/${sched//\//_}_orig" 2>/dev/null || true
      _info "Saved scheduler snapshot for $bname"
    fi
    if grep -q noop "$sched"; then
      echo noop > "$sched" 2>/dev/null && _info "Set scheduler 'noop' on $bname" || _warn "Failed to set 'noop' on $bname"
    else
      _info "Noop not available for $bname; current scheduler: $(cat $sched 2>/dev/null)"
    fi
  fi
done

# -----------------------
# IO latency polish - read_ahead & queue depth sanity (safe, per-device)
# -----------------------
_section "I/O latency and queue optimization"
for dev in /sys/block/*; do
  bname=$(basename "$dev")
  case "$bname" in
    loop*|ram*|dm-*|zram*|sr* ) continue ;;
  esac

  ra="$dev/queue/read_ahead_kb"
  if [ -f "$ra" ]; then
    safe_echo 128 "$ra"
  fi

  nr="$dev/queue/nr_requests"
  if [ -f "$nr" ]; then
    cur_nr=$(cat "$nr" 2>/dev/null)
    if [ -n "$cur_nr" ]; then
      if [ "$cur_nr" -gt 1024 ]; then
        safe_echo 256 "$nr"
      else
        _info "nr_requests for $bname is reasonable: $cur_nr"
      fi
    fi
  fi
done

# -----------------------
# Reduce noisy kernel logging/tracing that may wake CPU
# -----------------------
_section "Kernel logging and wakeup reduction"
[ -f /proc/sys/kernel/printk ] && safe_echo 0 /proc/sys/kernel/printk
for ev in /sys/kernel/debug/tracing/events/sched/sched_wakeup/enable \
          /sys/kernel/debug/tracing/events/sched/sched_switch/enable \
          /sys/kernel/debug/tracing/events/power/pm_wakeup/enable; do
  [ -f "$ev" ] && safe_echo 0 "$ev"
done

# -----------------------
# Binder / IPC tuning: disable binder tracing events (if present) and reduce binder event noise
# -----------------------
_section "Binder and IPC noise reduction"
if [ -d /sys/kernel/debug/tracing/events/binder ]; then
  for ev in /sys/kernel/debug/tracing/events/binder/*/enable; do
    [ -f "$ev" ] && safe_echo 0 "$ev"
  done
  _info "Binder trace events disabled where possible."
else
  _info "Binder tracing not present or debugfs not mounted; skipping binder trace changes."
fi

for path in /sys/kernel/debug/tracing/events/*/binder*; do
  [ -f "$path/enable" ] && safe_echo 0 "$path/enable"
done

# -----------------------
# LMK adjustments (conservative: reduce thresholds ~20% to keep apps in BG longer)
# -----------------------
_section "Low Memory Killer (LMK) tuning"
LMK_MINFREE=/sys/module/lowmemorykiller/parameters/minfree
if [ -f "$LMK_MINFREE" ]; then
  old=$(cat $LMK_MINFREE)
  _info "LMK current minfree: $old"
  [ ! -f "$BAK_DIR/LMK_minfree_orig" ] && echo "$old" > "$BAK_DIR/LMK_minfree_orig"
  new=$(echo "$old" | awk -F, '{
    for(i=1;i<=NF;i++){
      v=int($i * 0.8);
      if(v<8) v=8;
      printf("%d", v);
      if(i<NF) printf(",");
    }
  }')
  if [ "$new" != "$old" ]; then
    safe_echo "$new" "$LMK_MINFREE"
    _info "LMK minfree adjusted to: $new (conservative)"
  else
    _info "LMK minfree left unchanged."
  fi
else
  _info "LMK minfree not detected; skipping LMK tuning."
fi

# -----------------------
# Android framework tweaks (no animation changes)
# -----------------------
_section "Android framework behavior"
settings put global activity_manager_bg_process_limit 48 2>/dev/null && _info "Background process limit set to 48" || _warn "Could not set background process limit (settings may be read-only)"
if command -v cmd >/dev/null 2>&1; then
  cmd package bg-dexopt-job 2>/dev/null && _info "Triggered background dexopt job" || _warn "bg-dexopt-job trigger unsupported"
fi

# -----------------------
# ZRAM configuration (conservative). No vm.* sysctl changes.
# -----------------------
_section "ZRAM memory compression and swap priority"
ZRAM_FRACTION_PERCENT=25
ZRAM_COMPR_ALGO="lz4"
# Maximum swap priority to prefer zram over killing processes
ZRAM_PRIORITY=32767

MemTotalKB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
if [ -n "$MemTotalKB" ]; then
  zram_bytes=$(( MemTotalKB * ZRAM_FRACTION_PERCENT / 100 * 1024 ))
  [ "$zram_bytes" -lt $((64 * 1024 * 1024)) ] && zram_bytes=$((64 * 1024 * 1024))
  if [ ! -d /sys/block/zram0 ]; then
    command -v modprobe >/dev/null 2>&1 && modprobe zram 2>/dev/null || _warn "modprobe zram not available or failed"
  fi
  if [ -d /sys/block/zram0 ]; then
    [ -w /sys/block/zram0/reset ] && safe_echo 1 /sys/block/zram0/reset
    [ -f /sys/block/zram0/comp_algorithm ] && ( echo "$ZRAM_COMPR_ALGO" > /sys/block/zram0/comp_algorithm 2>/dev/null && _info "ZRAM comp_algorithm set to $ZRAM_COMPR_ALGO" || _warn "Could not set ZRAM comp_algorithm" )
    [ -w /sys/block/zram0/disksize ] && safe_echo "$zram_bytes" /sys/block/zram0/disksize && _info "ZRAM size configured"
    if command -v mkswap >/dev/null 2>&1 && command -v swapon >/dev/null 2>&1; then
      if ! grep -q zram0 /proc/swaps 2>/dev/null; then
        mkswap /dev/block/zram0 2>/dev/null && _info "Initialized swap on /dev/block/zram0" || _warn "mkswap failed"
        if swapon -p $ZRAM_PRIORITY /dev/block/zram0 2>/dev/null; then
          _info "Activated zram swap with HIGH priority ($ZRAM_PRIORITY). Swap will be preferred over killing apps."
        else
          _warn "swapon failed"
        fi
      else
        _info "ZRAM swap already active."
      fi
    else
      _warn "mkswap/swapon unavailable; skipping swap activation"
    fi
  else
    _warn "ZRAM not present after modprobe; skipping ZRAM configuration."
  fi
else
  _warn "Could not detect MemTotal; skipping ZRAM configuration."
fi

# -----------------------
# Runtime setprop properties (safe list)
# -----------------------
_section "Runtime system properties"
safe_props="
sys.haptic.onetrack:false
persist.sys.cachebuffer.enable:true
persist.sys.dynamicbuffer.max_adjust_num:3
persist.sys.disable_bganimate:true
persist.sys.mi.prerender:false
debug.renderengine.blur_algorithm:kawase2
persist.sys.trim_rendernode.enable:true
persist.sys.add_blurnoise_supported:false
persist.sys.stability.smartfocusio:on
persist.miui.extm.dm_opt.enable:true
"

try_props="
persist.sys.stability.lz4asm:on
"

skip_props="
persist.sf.force_setaffinity.bigcore:0
persist.sys.spc.powerkill.newpolicy.enable:false
"

_info "Applying safe properties."
for p in $safe_props; do
  key=$(echo "$p" | cut -d: -f1)
  val=$(echo "$p" | cut -d: -f2-)
  safe_setprop "$key" "$val"
done

_info "Attempting optional properties (best-effort)."
for p in $try_props; do
  key=$(echo "$p" | cut -d: -f1)
  val=$(echo "$p" | cut -d: -f2-)
  setprop "$key" "$val" 2>/dev/null
  got=$(getprop "$key" 2>/dev/null)
  if [ "$got" = "$val" ]; then
    _info "Optional property applied: $key -> $val"
  else
    _warn "Optional property unchanged or unsupported: $key"
  fi
done

_info "Risky properties intentionally skipped (logged for your review)."
for p in $skip_props; do
  key=$(echo "$p" | cut -d: -f1)
  val=$(echo "$p" | cut -d: -f2-)
  _info "SKIPPED: $key (recommended to skip). Would have set: $val"
done

# -----------------------
# GPU tweaks (performance-leaning; no frequency controls)
# -----------------------
_section "GPU rendering configuration"
GPU_PROPS="
persist.sys.ui.hw:1
debug.sf.hw:1
persist.sys.composition.type:gpu
debug.composition.type:mdp
debug.egl.force_msaa:false
debug.egl.force_fxaa:false
debug.egl.force_taa:false
debug.graphics.gpu.profiler.support:true
debug.sf.disable_backpressure:1
debug.sf.high_fps.early.sf.duration:10000000
debug.sf.high_fps.hwc.min.duration:8500000
debug.sf.kernel_idle_timer_update_overlay:true
"

for p in $GPU_PROPS; do
  key=$(echo "$p" | cut -d: -f1)
  val=$(echo "$p" | cut -d: -f2-)
  safe_setprop "$key" "$val"
done

# -----------------------
# Reduce Wi-Fi/BLE scanning where writable
# -----------------------
_section "Wireless scanning behavior"
settings put secure wifi_scan_always_enabled 0 2>/dev/null && _info "wifi_scan_always_enabled -> 0" || _warn "Could not change wifi_scan_always_enabled"
settings put secure ble_scan_always_enabled 0 2>/dev/null && _info "ble_scan_always_enabled -> 0" || _warn "Could not change ble_scan_always_enabled"

# -----------------------
# Background service throttling (appops best-effort)
# -----------------------
_section "Background service restrictions (appops best-effort)"
BG_THROTTLE_PACKAGES="
com.miui.analytics
com.miui.msa.global
com.miui.daemon
com.xiaomi.joyose
com.facebook.services
com.xiaomi.glgm
"

if command -v cmd >/dev/null 2>&1; then
  for pkg in $BG_THROTTLE_PACKAGES; do
    if pm list packages "$pkg" 2>/dev/null | grep -q "$pkg"; then
      if cmd appops set "$pkg" RUN_IN_BACKGROUND deny >/dev/null 2>&1; then
        _info "Applied background-run restriction for: $pkg"
        echo "$pkg:appops_denied" >> "$BAK_DIR/bg_throttle.log"
      else
        _warn "appops restriction not supported for: $pkg"
      fi
    else
      _info "Package not installed: $pkg"
    fi
  done
else
  _warn "cmd tool not present; skipping appops throttling"
fi

# -----------------------
# Debloat: NO mass disables. Only attempt to limit MSA safely (single-package handling)
# -----------------------
_section "MSA handling (conservative)"
_info "Debloat policy: No general package removal will be performed."
_info "Attempting an optional, single-package action for com.miui.msa.global (MSA). This is conservative and reversible."

MSA_PKG="com.miui.msa.global"
if pm list packages "$MSA_PKG" 2>/dev/null | grep -q "$MSA_PKG"; then
  _info "MSA detected: $MSA_PKG - attempting to disable for the current user only (user 0)."
  if pm disable-user --user 0 "$MSA_PKG" >/dev/null 2>&1; then
    _info "Successfully disabled MSA for the current user. To restore: pm enable $MSA_PKG"
    echo "$MSA_PKG:disabled" >> "$BAK_DIR/disabled_packages.log"
  else
    _warn "Could not disable MSA via pm disable-user. Will attempt to restrict background run via appops if possible."
    if command -v cmd >/dev/null 2>&1 && cmd appops set "$MSA_PKG" RUN_IN_BACKGROUND deny >/dev/null 2>&1; then
      _info "Applied appops restriction to MSA."
      echo "$MSA_PKG:appops_denied" >> "$BAK_DIR/disabled_packages.log"
    else
      _warn "All attempts to limit MSA failed (package may be privileged). No further action taken."
      echo "$MSA_PKG:action_failed" >> "$BAK_DIR/disabled_packages.log"
    fi
  fi
else
  _info "MSA package not installed; no action needed."
fi

# -----------------------
# Logging hygiene: cap logcat buffers, rotate/truncate our log
# -----------------------
_section "Logging hygiene and rotation"
if command -v logcat >/dev/null 2>&1; then
  logcat -G 1M 2>/dev/null && _info "Set main logcat buffer to 1M" || _warn "logcat -G unsupported"
  logcat -b all -G 2M 2>/dev/null && _info "Set all logcat buffers to 2M" || _warn "logcat -b all -G unsupported"
else
  _warn "logcat not available; skipping buffer configuration"
fi

if [ -f "$LOG" ]; then
  size=$(stat -c%s "$LOG" 2>/dev/null || echo 0)
  max=$((5 * 1024 * 1024))
  if [ "$size" -gt "$max" ]; then
    _info "Log file size is $size bytes — rotating and keeping last 200k bytes."
    tail -c 204800 "$LOG" > "$BAK_DIR/hyperos_tweaks.log.tail" 2>/dev/null || true
    mv "$BAK_DIR/hyperos_tweaks.log.tail" "$LOG" 2>/dev/null || true
    _info "Rotation complete. Old content saved to $BAK_DIR/hyperos_tweaks.log.tail"
  fi
fi

if getprop persist.logd.size >/dev/null 2>&1; then
  safe_setprop persist.logd.size 1048576
fi

# -----------------------
# Finalize & user-status
# -----------------------
_section "Final status and summary"
_info "All tweaks applied. A status summary is being written to the user directory."

cat > "$LOG_DIR/hyperos_tweaks.status" <<EOF
$(timestamp) - HyperOS Tweaks report
ZRAM_FRACTION_PERCENT=${ZRAM_FRACTION_PERCENT:-25}
ZRAM_PRIORITY=${ZRAM_PRIORITY:-32767}
LOG_PATH=${LOG}
BACKUP_DIR=${BAK_DIR}
Notes:
 - No mass debloat performed. Only attempted conservative handling of com.miui.msa.global (MSA).
 - For any reversible action, please consult the backup folder in $BAK_DIR.
EOF

# Disable OEM / telemetry / logging junk
settings put system rakuten_denwa 0
settings put system send_security_reports 0
settings put secure send_action_app_error 0
settings put global activity_starts_logging_enabled 0

chmod 644 "$LOG_DIR/hyperos_tweaks.status" 2>/dev/null || _warn "Could not set permissions on status file."
_info "HyperOS Tweaks finished. Review $LOG for details or open $LOG_DIR/hyperos_tweaks.status for a quick summary."

SD_LOG_DIR=/sdcard/HyperOS_Tweaks
mkdir -p "$SD_LOG_DIR"
cp -r "$LOG_DIR"/* "$SD_LOG_DIR"/ 2>/dev/null
chmod -R 644 "$SD_LOG_DIR"/* 2>/dev/null

exit 0