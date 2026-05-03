#!/usr/bin/env bash
# ============================================================================
# lib/pkg.sh — package manager abstraction
# ----------------------------------------------------------------------------
# Detects dnf vs apt and provides:
#   pkg_install <pkg> [<pkg>...]   — install if not already installed
#   install_tui                    — install whiptail (newt on Fedora)
#
# This is intentionally minimal. Targets do most of their package work
# directly with dnf/apt because the bootstrap is distro-aware by then.
# This abstraction exists for the bootstrap's pre-detection needs (whiptail).
# ============================================================================

[ -n "${_MACLIN_PKG_LOADED:-}" ] && return 0
_MACLIN_PKG_LOADED=1

# Source common.sh if not already loaded (we use die/log/warn/has_cmd)
if [ -z "${_MACLIN_COMMON_LOADED:-}" ]; then
    # shellcheck source=common.sh
    . "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# ---------------- Detect package manager ------------------------------------
# Sets PKG_MANAGER to one of: dnf, apt, unknown
detect_pkg_manager() {
    if has_cmd dnf; then
        PKG_MANAGER=dnf
    elif has_cmd apt-get; then
        PKG_MANAGER=apt
    else
        PKG_MANAGER=unknown
    fi
    export PKG_MANAGER
}

# ---------------- Generic install -------------------------------------------
# Idempotent: dnf and apt both no-op when packages are already installed.
# Caller is responsible for sudo (we don't sudo internally — that lets the
# bootstrap call this both pre- and post-escalation cleanly).
pkg_install() {
    [ -n "${PKG_MANAGER:-}" ] || detect_pkg_manager
    case "$PKG_MANAGER" in
        dnf)
            dnf install -y "$@"
            ;;
        apt)
            # apt-get is more script-friendly than apt
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
            ;;
        *)
            die "Unsupported package manager. Need dnf or apt-get."
            ;;
    esac
}

# Refresh package metadata. dnf does this implicitly on install; apt does not.
pkg_refresh() {
    [ -n "${PKG_MANAGER:-}" ] || detect_pkg_manager
    case "$PKG_MANAGER" in
        dnf)
            dnf check-update -y >/dev/null 2>&1 || true  # exits 100 when updates exist
            ;;
        apt)
            DEBIAN_FRONTEND=noninteractive apt-get update -y
            ;;
    esac
}

# ---------------- Whiptail/TUI install --------------------------------------
# Package name differs across families:
#   Fedora/RHEL:  newt   (provides /usr/bin/whiptail)
#   Debian/Ubuntu: whiptail
install_tui() {
    if has_cmd whiptail; then
        return 0
    fi
    [ -n "${PKG_MANAGER:-}" ] || detect_pkg_manager
    case "$PKG_MANAGER" in
        dnf) sudo dnf install -y newt ;;
        apt) sudo DEBIAN_FRONTEND=noninteractive apt-get install -y whiptail ;;
        *)   die "Cannot install whiptail: unsupported package manager." ;;
    esac
    has_cmd whiptail || die "whiptail install reported success but command not found."
}
