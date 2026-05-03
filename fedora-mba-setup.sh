#!/usr/bin/env bash
# ============================================================================
# Fedora 44 post-install setup for 2017 MacBook Air (MacBookAir7,2)
# ----------------------------------------------------------------------------
# Run AFTER you have:
#   1. Done a fresh Fedora 44 install
#   2. Booted into the new system
#   3. Connected to the internet via USB-C ethernet or phone tethering
#      (WiFi won't work yet — that's what this script fixes)
#   4. Run a full system update + reboot:
#        sudo dnf upgrade --refresh -y && sudo reboot
#
# Usage:
#   sudo bash fedora-mba-setup.sh
#
# After it finishes, reboot once more.
# ============================================================================

set -euo pipefail

# ---------------- CONFIG — toggle features on/off ---------------------------
INSTALL_WIFI=true            # Broadcom BCM4360 driver (you definitely want this)
INSTALL_CODECS=true          # H.264, MP3, hardware video decode, etc.
INSTALL_CAMERA=false         # FaceTime HD webcam — fragile, set true only if you need it
INSTALL_TLP=true             # Better battery life vs default power-profiles-daemon
INSTALL_MBPFAN=true          # Sensible fan curves (default Apple SMC curve runs hot)
SWAP_FN_KEYS=true            # Make brightness/volume keys work WITHOUT pressing Fn
INSTALL_FLATHUB=true         # Add full Flathub remote (Fedora's default is filtered)
INSTALL_DEV_TOOLS=true       # git, neovim, tmux, gcc, clang, etc.
INSTALL_GNOME_TWEAKS=true    # gnome-tweaks + extension manager

# ---------------- Helpers ---------------------------------------------------
log()  { echo -e "\n\033[1;34m==>\033[0m \033[1m$*\033[0m"; }
warn() { echo -e "\033[1;33m[warn]\033[0m $*"; }
err()  { echo -e "\033[1;31m[error]\033[0m $*" >&2; }

# ---------------- Sanity checks ---------------------------------------------
if [[ $EUID -ne 0 ]]; then
    err "Must run as root: sudo bash $0"
    exit 1
fi

if ! grep -q "Fedora" /etc/os-release; then
    err "This script is for Fedora. Aborting."
    exit 1
fi

if ! ping -c 1 -W 3 fedoraproject.org &>/dev/null; then
    err "No internet connection. Plug in ethernet or tether your phone first."
    exit 1
fi

REBOOT_NEEDED=false

# ---------------- 1. RPM Fusion ---------------------------------------------
log "Enabling RPM Fusion (free + non-free)…"
dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
dnf upgrade --refresh -y

# ---------------- 2. WiFi (Broadcom BCM4360) --------------------------------
if $INSTALL_WIFI; then
    log "Installing Broadcom WiFi driver (akmod-wl)…"
    dnf install -y "kernel-devel-$(uname -r)" akmod-wl
    # Trigger akmod to build immediately rather than wait for next boot
    akmods --force || warn "akmods reported errors — module should still build on next boot"
    REBOOT_NEEDED=true
fi

# ---------------- 3. Multimedia codecs --------------------------------------
if $INSTALL_CODECS; then
    log "Installing multimedia codecs…"
    dnf group install -y multimedia
    dnf swap -y ffmpeg-free ffmpeg --allowerasing || warn "ffmpeg swap skipped (already swapped?)"
    dnf install -y libavcodec-freeworld
fi

# ---------------- 4. FaceTime HD camera (optional, fragile) -----------------
if $INSTALL_CAMERA; then
    log "Installing FaceTime HD camera driver…"
    warn "Camera setup is the most fragile part. If it fails, see the manual route at"
    warn "  https://github.com/patjak/facetimehd/wiki/Get-Started"
    if dnf copr enable -y mulderje/facetimehd-dkms 2>/dev/null; then
        dnf install -y facetimehd-firmware facetimehd-dkms || warn "Camera package install failed"
        modprobe facetimehd 2>/dev/null || warn "facetimehd module didn't load — try after reboot"
    else
        warn "COPR not available for this Fedora version — skipping camera"
    fi
fi

# ---------------- 5. TLP power management -----------------------------------
if $INSTALL_TLP; then
    log "Installing TLP for better battery life…"
    dnf install -y tlp tlp-rdw
    systemctl enable --now tlp
    systemctl mask power-profiles-daemon || true
fi

# ---------------- 6. mbpfan -------------------------------------------------
if $INSTALL_MBPFAN; then
    log "Setting up mbpfan for sensible fan curves…"
    if dnf install -y mbpfan 2>/dev/null; then
        systemctl enable --now mbpfan
    else
        warn "mbpfan not in repos — building from source"
        dnf install -y git make gcc
        tmpdir=$(mktemp -d)
        git clone https://github.com/dgraziotin/mbpfan.git "$tmpdir/mbpfan"
        (cd "$tmpdir/mbpfan" && make && make install)
        systemctl daemon-reload
        systemctl enable --now mbpfan
        rm -rf "$tmpdir"
    fi
fi

# ---------------- 7. Function key behavior ----------------------------------
if $SWAP_FN_KEYS; then
    log "Configuring brightness/volume keys to work WITHOUT pressing Fn…"
    echo "options hid_apple fnmode=2" > /etc/modprobe.d/hid_apple.conf
    dracut --force
    REBOOT_NEEDED=true
fi

# ---------------- 8. Flathub ------------------------------------------------
if $INSTALL_FLATHUB; then
    log "Adding Flathub remote…"
    flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
fi

# ---------------- 9. Dev tools ----------------------------------------------
if $INSTALL_DEV_TOOLS; then
    log "Installing dev tools…"
    dnf install -y git neovim tmux htop curl wget gcc clang make jq ripgrep fd-find
fi

# ---------------- 10. GNOME tweaks -----------------------------------------
if $INSTALL_GNOME_TWEAKS; then
    log "Installing GNOME tweaks and extensions app…"
    dnf install -y gnome-tweaks gnome-extensions-app
fi

# ---------------- Done ------------------------------------------------------
log "Setup complete!"
echo
if $REBOOT_NEEDED; then
    echo "  ⚠  Reboot required to activate:"
    $INSTALL_WIFI    && echo "     - Broadcom WiFi (wl module)"
    $SWAP_FN_KEYS    && echo "     - Function key behavior change (initramfs)"
    echo
    echo "  Run: sudo reboot"
fi
echo
echo "  After reboot, verify with:"
echo "    lspci -k | grep -A 3 Network    # should show 'Kernel driver in use: wl'"
echo "    sensors                          # should show fan RPMs + temps"
echo "    upower -i \$(upower -e | grep BAT)"
echo
