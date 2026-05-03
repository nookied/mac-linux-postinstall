#!/usr/bin/env bash
# ============================================================================
# targets/macbookair7_2-debian13/extras.sh
# ----------------------------------------------------------------------------
# OPTIONAL "universally-agreed must-haves" for MBA 2017 + Debian 13 (Trixie).
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
    "flathub|Full Flathub remote (apps repo)|on"
    "dev_tools|Developer tools (git, neovim, tmux, gcc, clang, etc.)|on"
    "gnome_tweaks|GNOME Tweaks + Extension Manager|on"
    "facetimehd|FaceTime HD camera driver (source build)|off"
)

# ---------------- 1. TLP ----------------------------------------------------
install_tlp() {
    log "Installing TLP (battery optimization)…"
    # Stop and mask power-profiles-daemon to avoid conflicts with TLP.
    # Debian doesn't ship tuned-ppd by default, so the Fedora-style RPM
    # file-conflict workaround isn't needed here.
    systemctl disable --now power-profiles-daemon.service 2>/dev/null || true
    systemctl mask power-profiles-daemon.service 2>/dev/null || true
    apt-get install -y tlp tlp-rdw
    systemctl enable --now tlp.service
}

# ---------------- 2. mbpfan -------------------------------------------------
# Not in Debian repos. Build from source — `linux-on-mac/mbpfan` is the
# maintained fork (the original `dgraziotin/mbpfan` is unmaintained).
install_mbpfan() {
    log "Setting up mbpfan (source build)…"
    if ! apt-get install -y git make gcc; then
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
}

# ---------------- 3. Flathub ------------------------------------------------
install_flathub() {
    log "Adding Flathub remote…"
    apt-get install -y flatpak
    flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
}

# ---------------- 4. Dev tools ----------------------------------------------
install_dev_tools() {
    log "Installing dev tools…"
    apt-get install -y \
        git neovim tmux htop curl wget \
        gcc clang make jq \
        ripgrep fd-find
}

# ---------------- 5. GNOME tweaks -------------------------------------------
# Debian 13 packages the extension manager as `gnome-shell-extension-manager`
# (different from Fedora's `gnome-extensions-app`).
install_gnome_tweaks() {
    log "Installing GNOME Tweaks + Extension Manager…"
    apt-get install -y gnome-tweaks gnome-shell-extension-manager
}

# ---------------- 6. FaceTime HD camera (fragile, off by default) -----------
# Debian doesn't have a COPR equivalent — we build patjak/facetimehd from
# source via DKMS. The firmware blob is extracted from Apple's CDN by
# patjak/facetimehd-firmware (separate Makefile).
#
# Debian 13 ships kernel 6.12 LTS, BEFORE the patjak/facetimehd issue #315
# regression on kernels 6.15+. So unlike the Fedora 44 target, the camera
# should actually stream live in Cheese/Snapshot here. We still warn if
# the running kernel is somehow 6.15+ (e.g. a backports kernel was installed)
# because that scenario reintroduces the freeze.
install_facetimehd() {
    log "Installing FaceTime HD camera driver (source build)…"
    warn "FaceTime HD setup is fragile. Manual route: https://github.com/patjak/facetimehd/wiki/Get-Started"

    # Warn if the running kernel is in the regression range.
    local _kmaj _kmin
    _kmaj=$(uname -r | awk -F'[.-]' '{print $1}')
    _kmin=$(uname -r | awk -F'[.-]' '{print $2}')
    if [ "${_kmaj:-0}" -gt 6 ] || { [ "${_kmaj:-0}" -eq 6 ] && [ "${_kmin:-0}" -ge 15 ]; }; then
        warn ""
        warn "KNOWN ISSUE on kernel $(uname -r):"
        warn "  patjak/facetimehd has an upstream regression on kernels 6.15+."
        warn "  Cheese, GNOME Snapshot, and other GStreamer/PipeWire apps will"
        warn "  capture one frame then freeze. See:"
        warn "    https://github.com/patjak/facetimehd/issues/315"
        warn "  Workaround: use a browser-based camera app instead."
        warn ""
    fi

    # Secure Boot blocks unsigned DKMS modules at load time with no visible
    # error in user-facing apps. Detect early and abort cleanly.
    if command -v mokutil &>/dev/null; then
        if mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled"; then
            warn "Secure Boot is ENABLED — the facetimehd module is unsigned and will NOT load."
            warn "Disable Secure Boot in your firmware settings, then re-run the script."
            return 0
        fi
    fi

    # Build deps for both the firmware extractor and the kernel module.
    if ! apt-get install -y git make gcc curl xz-utils cpio dkms; then
        warn "Could not install facetimehd build dependencies — skipping"
        return 0
    fi

    # ----- Firmware extraction (patjak/facetimehd-firmware) -----
    local tmpdir
    tmpdir=$(mktemp -d)
    log "Extracting FaceTime HD firmware (downloads from Apple CDN)…"
    if ! git clone --depth=1 https://github.com/patjak/facetimehd-firmware.git "$tmpdir/firmware"; then
        warn "Could not clone facetimehd-firmware repo — skipping"
        rm -rf "$tmpdir"
        return 0
    fi
    if ! ( cd "$tmpdir/firmware" && make && make install ); then
        warn "Firmware extraction failed — camera will not work."
        warn "Likely cause: network error reaching Apple's CDN."
        warn "Manual retry: cd $tmpdir/firmware && sudo make install"
        # Don't return — kernel module still useful for the next reboot.
    fi

    local fw_path="/usr/lib/firmware/facetimehd/firmware.bin"
    if [ -f "$fw_path" ]; then
        ok "FaceTime HD firmware present at $fw_path"
    else
        warn "Firmware not found at $fw_path — camera will not work until extracted."
    fi

    # ----- Kernel module via DKMS (patjak/facetimehd) -----
    log "Building facetimehd kernel module via DKMS…"
    local module_version="0.6.13"
    local src_dir="/usr/src/facetimehd-${module_version}"

    if [ -d "$src_dir" ]; then
        # Already present — make sure DKMS knows about it
        ok "facetimehd source already at $src_dir"
    else
        if ! git clone --depth=1 https://github.com/patjak/facetimehd.git "$src_dir"; then
            warn "Could not clone facetimehd module repo — skipping"
            rm -rf "$tmpdir"
            return 0
        fi
        # patjak/facetimehd ships a dkms.conf — verify it's there
        if [ ! -f "$src_dir/dkms.conf" ]; then
            warn "$src_dir/dkms.conf is missing — DKMS install will fail."
            warn "The patjak/facetimehd repo upstream has changed structure."
            rm -rf "$tmpdir"
            return 0
        fi
    fi

    # Add to DKMS and build for the running kernel. Capture output so a
    # build failure is visible rather than silently swallowed.
    dkms add -m facetimehd -v "$module_version" 2>/dev/null || true
    local dkms_out
    dkms_out=$(dkms autoinstall 2>&1) || true
    if ! dkms status 2>/dev/null | grep -q "facetimehd.*installed"; then
        warn "DKMS module did not install cleanly. DKMS output:"
        warn "$dkms_out"
        warn "To retry: sudo dkms autoinstall -k $(uname -r)"
    fi

    # Ensure the module loads on every boot, not just the current session.
    echo "facetimehd" > /etc/modules-load.d/facetimehd.conf

    # Load now and surface any errors rather than hiding them.
    local modprobe_err
    if modprobe_err=$(modprobe facetimehd 2>&1); then
        if lsmod 2>/dev/null | grep -q "^facetimehd"; then
            ok "facetimehd module loaded — camera should be visible after reboot"
        fi
    else
        warn "facetimehd module not loadable now: $modprobe_err"
        warn "Should work after reboot if DKMS built successfully."
    fi

    rm -rf "$tmpdir"
    mark_reboot "FaceTime HD camera (kernel module + firmware)"
}
