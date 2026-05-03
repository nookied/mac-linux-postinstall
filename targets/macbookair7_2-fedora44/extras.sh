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
    "mbpfan|Sensible fan curves (cooler than Apple SMC default)|on"
    "flathub|Full Flathub remote (Fedora's default is filtered)|on"
    "dev_tools|Developer tools (git, neovim, tmux, gcc, clang, etc.)|on"
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
    warn "FaceTime HD setup is fragile. Manual route: https://github.com/patjak/facetimehd/wiki/Get-Started"

    if ! dnf copr enable -y mulderje/facetimehd-dkms 2>/dev/null; then
        warn "COPR not available for Fedora $(rpm -E %fedora) — skipping FaceTime HD"
        return 0
    fi

    if ! dnf install -y facetimehd-firmware facetimehd-dkms; then
        warn "Camera package install failed — skipping FaceTime HD"
        return 0
    fi

    # Build the DKMS module for the running kernel right now, not just on next boot.
    dkms autoinstall 2>/dev/null || warn "DKMS autoinstall had errors — module may still build on next boot"

    # The facetimehd-firmware %post scriptlet downloads firmware from Apple CDN.
    # It silently fails if the network request fails. Verify and warn explicitly.
    local fw_path="/usr/lib/firmware/facetimehd/firmware.bin"
    if [ ! -f "$fw_path" ]; then
        # The package may ship a helper script to re-run the firmware download.
        local fw_script
        fw_script=$(find /usr/lib/facetimehd /usr/share/facetimehd /usr/sbin \
                         -maxdepth 1 -name "*firmware*" -executable 2>/dev/null | head -1)
        if [ -n "$fw_script" ]; then
            log "Re-running firmware download script: $fw_script"
            "$fw_script" 2>/dev/null || true
        fi
    fi

    if [ -f "$fw_path" ]; then
        ok "FaceTime HD firmware present at $fw_path"
    else
        warn "Firmware not found at $fw_path — camera will not work."
        warn "After reboot, run the firmware helper manually or follow:"
        warn "  https://github.com/patjak/facetimehd/wiki/Get-Started#firmware"
    fi

    # Ensure the module loads on every boot, not just the current session.
    echo "facetimehd" > /etc/modules-load.d/facetimehd.conf

    modprobe facetimehd 2>/dev/null || warn "facetimehd module not loadable yet — should work after reboot"
    mark_reboot "FaceTime HD camera (kernel module + firmware)"
}
