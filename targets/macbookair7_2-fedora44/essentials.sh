#!/usr/bin/env bash
# ============================================================================
# targets/macbookair7_2-fedora44/essentials.sh
# ----------------------------------------------------------------------------
# CRITICAL post-install steps for MacBook Air 2017 + Fedora Workstation 44.
# These are NOT optional — they fix things that are broken out-of-the-box on
# this hardware/OS combo (no WiFi, no codecs, broken function keys).
#
# Sourced by docs/install.sh after sudo re-exec. Expects:
#   - root privileges (require_root will check)
#   - lib/common.sh already sourced
#   - $MACLIN_REBOOT_FILE set (mark_reboot writes there)
# ============================================================================

set -euo pipefail
require_root

# ---------------- 1. RPM Fusion ---------------------------------------------
# Free + non-free repos. Required for codecs and Broadcom WiFi (akmod-wl).
log "Enabling RPM Fusion (free + non-free)…"
dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
dnf upgrade --refresh -y

# ---------------- 2. Broadcom BCM4360 WiFi ----------------------------------
# Without this, no WiFi. Hard requirement.
log "Installing Broadcom WiFi driver (akmod-wl)…"
dnf install -y "kernel-devel-$(uname -r)" akmod-wl
# Trigger akmod build now rather than waiting for next boot.
# Note: akmods --force can report spurious errors; the module typically still
# builds correctly on next boot. Treat as warning only.
akmods --force || warn "akmods reported errors — module should still build on next boot"
mark_reboot "Broadcom WiFi (wl module)"

# ---------------- 3. Multimedia codecs --------------------------------------
# H.264, MP3, hardware video decode. Without these, lots of media won't play.
log "Installing multimedia codecs…"
dnf group install -y multimedia
dnf swap -y ffmpeg-free ffmpeg --allowerasing || warn "ffmpeg swap skipped (already swapped?)"
dnf install -y libavcodec-freeworld

# ---------------- 4. Function key behavior ----------------------------------
# Make F-row keys default to brightness/volume/etc. without holding Fn.
# This matches macOS behavior. Requires regenerating the initramfs.
log "Configuring brightness/volume keys to work WITHOUT pressing Fn…"
HID_APPLE_CONF="/etc/modprobe.d/hid_apple.conf"
if grep -Eq '^options[[:space:]]+hid_apple([[:space:]].*)?[[:space:]]fnmode=2([[:space:]]|$)' "$HID_APPLE_CONF" 2>/dev/null; then
    ok "hid_apple fnmode=2 already configured"
else
    if [ -f "$HID_APPLE_CONF" ] && grep -Eq '^options[[:space:]]+hid_apple([[:space:]].*)?[[:space:]]fnmode=' "$HID_APPLE_CONF"; then
        sed -i -E '/^options[[:space:]]+hid_apple/ s/(^|[[:space:]])fnmode=[^[:space:]]+/\1fnmode=2/' "$HID_APPLE_CONF"
    else
        printf '%s\n' "options hid_apple fnmode=2" >> "$HID_APPLE_CONF"
    fi
    dracut --force
    mark_reboot "Function key behavior (initramfs rebuilt)"
fi
