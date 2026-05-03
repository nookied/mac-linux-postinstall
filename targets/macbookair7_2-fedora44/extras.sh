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
# Uses the `mulderje/facetimehd-kmod` COPR (NOT facetimehd-dkms — that COPR
# does not exist; the correct one ships kmod-style pre-built modules per
# kernel version). Verified Fedora 44 builds: see
#   https://copr.fedorainfracloud.org/coprs/mulderje/facetimehd-kmod/
install_facetimehd() {
    log "Installing FaceTime HD camera driver…"
    warn "FaceTime HD setup is fragile. Manual route: https://github.com/patjak/facetimehd/wiki/Get-Started"

    # Secure Boot blocks unsigned kmod modules at load time with no visible
    # error in user-facing apps. Detect early and abort cleanly.
    if command -v mokutil &>/dev/null; then
        if mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled"; then
            warn "Secure Boot is ENABLED — the facetimehd kmod is unsigned and will NOT load."
            warn "Disable Secure Boot in your firmware settings, then re-run the script."
            return 0
        fi
    fi

    # Enable COPR. Don't redirect stderr — if the COPR doesn't exist or the
    # network fails, we want the actual error visible rather than a silent
    # "skipping" that the user can't debug.
    log "Enabling COPR mulderje/facetimehd-kmod…"
    if ! dnf copr enable -y mulderje/facetimehd-kmod; then
        warn "Could not enable mulderje/facetimehd-kmod COPR — skipping FaceTime HD."
        warn "Check the error above. Common causes: network, COPR outage, or unsupported Fedora release."
        return 0
    fi

    # The kmod package ships a pre-built module for the running kernel.
    # If the kmod hasn't been built yet for a brand-new kernel, this fails
    # and we surface that clearly.
    if ! dnf install -y facetimehd-firmware facetimehd-kmod; then
        warn "Camera package install failed — skipping FaceTime HD."
        warn "If your kernel is very new, the kmod may not be built yet."
        warn "Check: https://copr.fedorainfracloud.org/coprs/mulderje/facetimehd-kmod/builds/"
        return 0
    fi

    # The facetimehd-firmware %post scriptlet downloads firmware from Apple CDN.
    # It silently fails on network errors. Check for the file and retry via the
    # known extraction script paths if it is missing.
    local fw_path="/usr/lib/firmware/facetimehd/firmware.bin"
    if [ ! -f "$fw_path" ]; then
        local fw_script
        for fw_script in /usr/sbin/facetimehd_firmware_extract \
                         /usr/libexec/facetimehd_firmware_extract; do
            if [ -x "$fw_script" ]; then
                log "Re-running firmware extraction: $fw_script"
                "$fw_script" 2>/dev/null || true
                break
            fi
        done
    fi

    if [ -f "$fw_path" ]; then
        ok "FaceTime HD firmware present at $fw_path"
    else
        warn "Firmware not found at $fw_path — camera will not work."
        warn "After reboot, run: sudo /usr/sbin/facetimehd_firmware_extract"
        warn "Or follow: https://github.com/patjak/facetimehd/wiki/Get-Started#firmware"
    fi

    # Ensure the module loads on every boot, not just the current session.
    echo "facetimehd" > /etc/modules-load.d/facetimehd.conf

    # Load now and surface any errors rather than hiding them with 2>/dev/null.
    local modprobe_err
    if modprobe_err=$(modprobe facetimehd 2>&1); then
        if lsmod 2>/dev/null | grep -q "^facetimehd"; then
            ok "facetimehd module loaded — camera should be visible after reboot"
        fi
    else
        warn "facetimehd module not loadable now: $modprobe_err"
        warn "Should work after reboot if the kmod package matched your kernel."
    fi

    mark_reboot "FaceTime HD camera (kernel module + firmware)"
}
