#!/system/bin/sh

# --------------------------------------------------
# Uninstall script for the module
# Cleans up module-created artifacts only
# --------------------------------------------------

MODDIR="${0%/*}"
LOGFILE="/data/local/tmp/module_uninstall.log"

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

log() {
  printf "%s [UNINSTALL] %s\n" "$(timestamp)" "$*" | tee -a "$LOGFILE"
}

log "Starting module uninstall process"

# --------------------------------------------------
# Stop any running services started by this module
# --------------------------------------------------
log "Stopping module services (if any)"

# Magisk will handle service shutdown automatically,
# but we log this for clarity
pkill -f "$MODDIR" 2>/dev/null

# --------------------------------------------------
# Reset ZRAM (Magisk handles reboot cleanup, but be polite)
# --------------------------------------------------
if [ -e /dev/block/zram0 ]; then
  log "Disabling ZRAM swap"
  swapoff /dev/block/zram0 2>/dev/null
fi

# --------------------------------------------------
# Remove temporary / runtime files created by module
# --------------------------------------------------
log "Removing temporary files"

rm -f /data/local/tmp/module_uninstall.log 2>/dev/null

# --------------------------------------------------
# Final message
# --------------------------------------------------
log "Module uninstall completed. Reboot recommended."

exit 0