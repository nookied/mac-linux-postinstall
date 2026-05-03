#!/usr/bin/env bash
# ============================================================================
# targets/macbookair7_2-debian13/essentials.sh
# ----------------------------------------------------------------------------
# CRITICAL post-install steps for MacBook Air 2017 + Debian 13 (Trixie).
# These are NOT optional — they fix things that are broken out-of-the-box on
# this hardware/OS combo (no WiFi, missing codecs, broken function keys).
#
# Sourced by docs/install.sh after sudo re-exec. Expects:
#   - root privileges (require_root will check)
#   - lib/common.sh already sourced
#   - $MACLIN_REBOOT_FILE set (mark_reboot writes there)
#
# Distro notes:
#   - Debian 13 ships kernel 6.12 LTS — *before* the patjak/facetimehd
#     freeze regression on 6.15+. Camera streams normally on this distro.
#   - The Broadcom driver lives in the `non-free-firmware` component which
#     we enable explicitly here. Recent installers add it by default but
#     we can't assume the user used a recent installer.
# ============================================================================

set -euo pipefail
require_root

export DEBIAN_FRONTEND=noninteractive

# ---------------- 1. Refresh + ensure software-properties-common ------------
log "Refreshing apt metadata…"
apt-get update -qq

# add-apt-repository lives in software-properties-common. We use it to add
# the non-free-firmware and contrib components to existing apt sources
# without having to know whether the system uses the legacy /etc/apt/sources.list
# or the newer deb822 /etc/apt/sources.list.d/debian.sources format.
log "Installing software-properties-common (for add-apt-repository)…"
apt-get install -y software-properties-common

# ---------------- 2. Enable non-free-firmware + contrib --------------------
log "Enabling non-free-firmware and contrib components…"
add-apt-repository -y -c non-free-firmware
add-apt-repository -y -c contrib
apt-get update

# ---------------- 3. Build essentials + kernel headers ----------------------
# Needed for DKMS to compile the Broadcom and (later) facetimehd modules
# against the running kernel.
log "Installing build essentials and kernel headers…"
apt-get install -y \
    build-essential \
    dkms \
    "linux-headers-$(uname -r)"

# ---------------- 4. Broadcom BCM4360 WiFi ----------------------------------
# Without this, no WiFi. Hard requirement.
# Conflicts with brcmfmac/brcmsmac/b43/b44 — those need to be unloaded
# before the proprietary `wl` module can take over.
log "Installing Broadcom WiFi driver (broadcom-sta-dkms)…"
apt-get install -y broadcom-sta-dkms

log "Unloading conflicting open-source Broadcom modules (if loaded)…"
for mod in brcmfmac brcmsmac b43 b43legacy bcma ssb; do
    modprobe -r "$mod" 2>/dev/null || true
done
modprobe wl 2>/dev/null || warn "wl module did not load now — should work after reboot"

mark_reboot "Broadcom WiFi (wl module)"

# ---------------- 5. Multimedia codecs --------------------------------------
# H.264, MP3, hardware video decode. Most codecs are now in main on Debian 13,
# but the non-free-firmware bits and a couple gstreamer plugins still come
# from contrib/non-free.
log "Installing multimedia codecs…"
apt-get install -y \
    ffmpeg \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav

# ---------------- 6. Function key behavior ----------------------------------
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
    update-initramfs -u
    mark_reboot "Function key behavior (initramfs rebuilt)"
fi
