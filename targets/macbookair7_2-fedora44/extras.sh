#!/usr/bin/env bash
# ============================================================================
# targets/macbookair7_2-fedora44/extras.sh
# ----------------------------------------------------------------------------
# OPTIONAL "universally-agreed must-haves" for MBA 2017 + Fedora 44.
# The bootstrap presents these as a whiptail checklist before install.
#
# Each extra is:
#   - A function named install_<key>
#   - A row in EXTRAS_MANIFEST below: "<key>|<short description>|on|off"
#     (third field is the default selection state in the checklist)
#
# Sourced TWICE during a run:
#   1. Pre-escalation, in user context — the bootstrap reads EXTRAS_MANIFEST
#      to build the checklist, then writes selections to selections.env.
#   2. Post-escalation, under sudo — the install runner sources
#      selections.env (sets SELECTED_<KEY>=true for chosen items) and calls
#      install_<key> for each selected item.
#
# This means: do not put side-effecting code at the top level here.
# Define functions and the manifest only.
# ============================================================================

# ---------------- Manifest --------------------------------------------------
# Format per line: key|description shown in checklist|default(on|off)
# Order here is the order shown in the menu.
EXTRAS_MANIFEST=(
    "tlp|TLP power management (better battery life)|on"
    "mbpfan|mbpfan (sensible fan curves, runs cooler than Apple SMC default)|on"
    "flathub|Full Flathub remote (Fedora's default is filtered)|on"
    "dev_tools|Developer tools (git, neovim, tmux, gcc, clang, ripgrep, etc.)|on"
    "gnome_tweaks|GNOME Tweaks + Extension Manager|on"
    "facetimehd|FaceTime HD camera driver (FRAGILE — see notes)|off"
)

# ---------------- 1. TLP ----------------------------------------------------
install_tlp() {
    log "Installing TLP (battery optimization)…"
    # On Fedora 44, tuned-ppd ships dbus files that conflict with TLP at the
    # package level — DNF will refuse to install TLP until tuned-ppd is gone.
    systemctl disable --now tuned-ppd.service 2>/dev/null || true
    systemctl disable --now power-profiles-daemon.service 2>/dev/null || true
    dnf remove -y tuned-ppd 2>/dev/null || true
    systemctl mask power-profiles-daemon.service 2>/dev/null || true
    dnf install -y tlp tlp-rdw
    systemctl enable --now tlp.service
}

# ---------------- 2. mbpfan -------------------------------------------------
install_mbpfan() {
    log "Setting up mbpfan…"
    if dnf install -y mbpfan 2>/dev/null; then
        systemctl enable --now mbpfan.service
    else
        warn "mbpfan not in repos — building from source"
        if ! dnf install -y git make gcc; then
            warn "Could not install mbpfan build dependencies — skipping mbpfan"
            return 0
        fi
        local tmpdir
        tmpdir=$(mktemp -d)
        if git clone --depth=1 https://github.com/linux-on-mac/mbpfan.git "$tmpdir/mbpfan" \
            && ( cd "$tmpdir/mbpfan" && make && make install ) \
            && [ -f "$tmpdir/mbpfan/mbpfan.service" ] \
            && install -m 0644 "$tmpdir/mbpfan/mbpfan.service" /etc/systemd/system/mbpfan.service \
            && systemctl daemon-reload \
            && systemctl enable --now mbpfan.service; then
            ok "mbpfan built and enabled from source"
        else
            warn "mbpfan source install failed — skipping mbpfan"
        fi
        rm -rf "$tmpdir"
    fi
}

# ---------------- 3. Flathub ------------------------------------------------
install_flathub() {
    log "Adding Flathub remote…"
    flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
}

# ---------------- 4. Dev tools ----------------------------------------------
install_dev_tools() {
    log "Installing dev tools…"
    dnf install -y git neovim tmux htop curl wget gcc clang make jq ripgrep fd-find
}

# ---------------- 5. GNOME tweaks -------------------------------------------
install_gnome_tweaks() {
    log "Installing GNOME Tweaks + Extension Manager…"
    dnf install -y gnome-tweaks gnome-extensions-app
}

# ---------------- 6. FaceTime HD camera (fragile, off by default) -----------
install_facetimehd() {
    log "Installing FaceTime HD camera driver…"
    warn "FaceTime HD setup is the most fragile part of this script."
    warn "If it fails, manual route: https://github.com/patjak/facetimehd/wiki/Get-Started"
    if dnf copr enable -y mulderje/facetimehd-dkms 2>/dev/null; then
        dnf install -y facetimehd-firmware facetimehd-dkms || warn "Camera package install failed"
        modprobe facetimehd 2>/dev/null || warn "facetimehd module didn't load — try after reboot"
        mark_reboot "FaceTime HD camera (kernel module)"
    else
        warn "COPR not available for this Fedora version — skipping FaceTime HD"
    fi
}
