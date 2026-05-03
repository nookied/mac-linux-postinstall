#!/usr/bin/env bash
# ============================================================================
# lib/common.sh — shared logging, error handling, and reboot tracking
# ----------------------------------------------------------------------------
# Sourced by docs/install.sh after the repo tarball is extracted.
# Safe to source multiple times (guard at top).
# ============================================================================

# Source guard — sourcing twice is harmless but wastes cycles
[ -n "${_MACLIN_COMMON_LOADED:-}" ] && return 0
_MACLIN_COMMON_LOADED=1

# ---------------- Colors ----------------------------------------------------
# Disable colors if stdout is not a TTY (e.g. piped to a log file)
if [ -t 1 ]; then
    _C_RESET=$'\033[0m'
    _C_BOLD=$'\033[1m'
    _C_BLUE=$'\033[1;34m'
    _C_YELLOW=$'\033[1;33m'
    _C_RED=$'\033[1;31m'
    _C_GREEN=$'\033[1;32m'
    _C_DIM=$'\033[2m'
else
    _C_RESET=''; _C_BOLD=''; _C_BLUE=''; _C_YELLOW=''; _C_RED=''; _C_GREEN=''; _C_DIM=''
fi

# ---------------- Logging helpers -------------------------------------------
# Use these instead of raw echo. Style mirrors brew.sh / oh-my-zsh.

log()  { printf '\n%s==>%s %s%s%s\n' "$_C_BLUE"   "$_C_RESET" "$_C_BOLD" "$*" "$_C_RESET"; }
ok()   { printf '%s✓%s %s\n'         "$_C_GREEN"  "$_C_RESET" "$*"; }
warn() { printf '%s[warn]%s %s\n'    "$_C_YELLOW" "$_C_RESET" "$*"; }
err()  { printf '%s[error]%s %s\n'   "$_C_RED"    "$_C_RESET" "$*" >&2; }
dim()  { printf '%s%s%s\n'           "$_C_DIM"    "$*"        "$_C_RESET"; }

# Fatal: print error and exit with given code (default 1)
die() {
    local code="${2:-1}"
    err "$1"
    exit "$code"
}

# ---------------- Reboot tracking -------------------------------------------
# Steps that need a reboot (kernel module, initramfs, etc.) call:
#     mark_reboot "reason"
# The reason is appended to $MACLIN_REBOOT_FILE (path exported by the
# bootstrap). The bootstrap then checks the file is non-empty after the
# install phase to decide whether to print the reboot reminder.
#
# File-based rather than env-variable because essentials.sh and extras.sh
# run in a child bash invocation under sudo — an exported variable set
# inside that child would not propagate back to the parent bootstrap.

mark_reboot() {
    local reason="${1:-unspecified}"
    if [ -n "${MACLIN_REBOOT_FILE:-}" ]; then
        printf '%s\n' "$reason" >> "$MACLIN_REBOOT_FILE"
    fi
}

reboot_reasons() {
    [ -f "${MACLIN_REBOOT_FILE:-}" ] && cat "$MACLIN_REBOOT_FILE"
}

reboot_needed() {
    [ -s "${MACLIN_REBOOT_FILE:-}" ]
}

# ---------------- Sudo helpers ----------------------------------------------
# require_root: fail if not running as root. Use at the top of scripts that
# expect to be sudo-execed by the bootstrap (essentials.sh, extras.sh).
require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        die "Must be run as root. The bootstrap should have escalated for you — this is a bug."
    fi
}

# require_user: fail if running as root. Use in the bootstrap pre-escalation
# phase (we want device detection and the whiptail menu to run as the user).
require_user() {
    if [ "$(id -u)" -eq 0 ]; then
        die "Run as your normal user, not as root. The script will ask for sudo when needed."
    fi
}

# ensure_sudo_cached: prompt for sudo password once, cache the credential.
# Returns non-zero if the user denies sudo. Subsequent sudo calls in the
# same shell session will not re-prompt for ~5 minutes (default sudoers
# timeout) — long enough for our install phase.
ensure_sudo_cached() {
    if ! sudo -v; then
        return 1
    fi
}

# ---------------- Network check ---------------------------------------------
# We call this in the bootstrap. Targets MAY re-check before steps that
# specifically need internet (e.g. RPM Fusion install).
have_internet() {
    # Try a few hosts, short timeout. Don't trust DNS-only checks — we want
    # actual connectivity. -W is BSD/Linux ping-compatible for whole-deadline.
    ping -c 1 -W 3 1.1.1.1            >/dev/null 2>&1 && return 0
    ping -c 1 -W 3 fedoraproject.org  >/dev/null 2>&1 && return 0
    ping -c 1 -W 3 deb.debian.org     >/dev/null 2>&1 && return 0
    return 1
}

# ---------------- Misc ------------------------------------------------------
# Run a command, print it dimmed first. Useful for "you can verify by running"
# style hints in summary output.
run_visible() {
    dim "  $ $*"
    "$@"
}

# Test if a command exists in PATH
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}
