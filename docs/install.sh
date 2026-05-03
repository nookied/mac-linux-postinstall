#!/usr/bin/env bash
# ============================================================================
# mac-linux-postinstall :: bootstrap
# ============================================================================
# This is the file users curl/wget. It must stand alone with NO local
# dependencies — everything else lives in the GitHub repo and is downloaded
# at runtime.
#
# Invoked via:
#   bash -c "$(curl -fsSL https://nookied.github.io/mac-linux-postinstall/install.sh)"
#   bash -c "$(wget -qO- https://nookied.github.io/mac-linux-postinstall/install.sh)"
#
# DO NOT change to `curl … | bash` — that detaches stdin and breaks whiptail.
#
# Flow:
#   1. Sanity checks (Linux, network, fetcher, tar)
#   2. Lightweight device + distro detection for the banner
#   3. Show banner, prompt user to continue (plain text, no whiptail yet)
#   4. Download repo tarball, extract to tempdir
#   5. Run full target detection; abort unsupported targets before sudo
#   6. Cache sudo credentials
#   7. Install whiptail (newt on Fedora, whiptail on Debian-family)
#   8. Show whiptail checklist of optional extras
#   9. Re-exec installer phase under sudo with selections
#  10. Print summary + reboot reminder
# ----------------------------------------------------------------------------
# Architecture notes for future agents: see CLAUDE.md
# ============================================================================

set -euo pipefail

# ---------------- Config ----------------------------------------------------
GH_USER="nookied"
GH_REPO="mac-linux-postinstall"
GH_BRANCH="main"   # pinned to main per project decision (see CLAUDE.md §8)

TARBALL_URL="https://codeload.github.com/${GH_USER}/${GH_REPO}/tar.gz/refs/heads/${GH_BRANCH}"
ISSUE_URL="https://github.com/${GH_USER}/${GH_REPO}/issues"

# ---------------- Inline helpers (before lib/ is downloaded) ----------------
# We can't use lib/common.sh yet — it's in the tarball. So define minimal
# versions inline. Once the tarball is extracted these are overridden by the
# proper lib/common.sh helpers (same names, fuller implementations).

if [ -t 1 ]; then
    _C_RESET=$'\033[0m'; _C_BOLD=$'\033[1m'
    _C_BLUE=$'\033[1;34m'; _C_YELLOW=$'\033[1;33m'
    _C_RED=$'\033[1;31m'; _C_GREEN=$'\033[1;32m'; _C_DIM=$'\033[2m'
else
    _C_RESET= _C_BOLD= _C_BLUE= _C_YELLOW= _C_RED= _C_GREEN= _C_DIM=
fi
log()  { printf '\n%s==>%s %s%s%s\n' "$_C_BLUE"   "$_C_RESET" "$_C_BOLD" "$*" "$_C_RESET"; }
ok()   { printf '%s✓%s %s\n'         "$_C_GREEN"  "$_C_RESET" "$*"; }
warn() { printf '%s[warn]%s %s\n'    "$_C_YELLOW" "$_C_RESET" "$*"; }
err()  { printf '%s[error]%s %s\n'   "$_C_RED"    "$_C_RESET" "$*" >&2; }
die()  { err "$1"; exit "${2:-1}"; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# ---------------- 1. Sanity checks ------------------------------------------
[ "$(uname -s)" = "Linux" ] || die "This script only runs on Linux (you're on $(uname -s))."

if [ "$(id -u)" -eq 0 ]; then
    die "Run as your normal user, not as root. The script will ask for sudo when it needs it."
fi

# Need at least one fetcher and tar to download the rest of the repo.
if has_cmd curl; then
    FETCHER="curl"
elif has_cmd wget; then
    FETCHER="wget"
else
    die "Need either curl or wget. Install one: 'sudo dnf install curl' or 'sudo apt install curl'."
fi
has_cmd tar  || die "Need tar (should be present on every Linux). Install with your package manager."
has_cmd bash || die "Need bash."

# ---------------- 2. Device + distro detection (lightweight, inline) --------
# We do a minimal version here just to show the banner. The full lib/detect.sh
# will run again after extraction with its full feature set (slug, etc.).

DEVICE_PRODUCT="unknown"
if [ -r /sys/class/dmi/id/product_name ]; then
    DEVICE_PRODUCT=$(tr -d '\n' < /sys/class/dmi/id/product_name)
fi

DISTRO_ID="unknown"; DISTRO_VERSION="unknown"
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_VERSION="${VERSION_ID:-unknown}"
fi

# Network: if we got here via curl/wget we likely have it, but check anyway.
if ! ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1 && ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
    warn "No network connectivity detected. The script needs internet to download packages."
    warn "If this is wrong (e.g. ICMP blocked), continue anyway."
fi

# ---------------- 3. Banner + initial confirmation --------------------------
clear || true
cat <<EOF

${_C_BLUE}${_C_BOLD}===============================================================${_C_RESET}
${_C_BLUE}${_C_BOLD}  mac-linux-postinstall${_C_RESET}
${_C_BLUE}${_C_BOLD}===============================================================${_C_RESET}

  ${_C_BOLD}Device:${_C_RESET}  $DEVICE_PRODUCT
  ${_C_BOLD}Distro:${_C_RESET}  $DISTRO_ID $DISTRO_VERSION

  This script will:
    1. Install critical drivers (WiFi, codecs, fn-key fix)
    2. Ask you to pick optional must-haves (TLP, mbpfan, dev tools, …)
    3. Run the install (will ask for sudo password)
    4. Tell you if a reboot is needed

  Source: https://github.com/${GH_USER}/${GH_REPO} (branch: ${GH_BRANCH})

EOF

read -r -p "Continue? [y/N] " reply </dev/tty || reply=""
case "${reply,,}" in
    y|yes) ;;
    *) die "Aborted." 0 ;;
esac

# ---------------- 4. Download the repo tarball ------------------------------
TMPDIR=$(mktemp -d -t maclin.XXXXXX)
SUDO_KEEPALIVE_PID=""
cleanup() {
    if [ -n "${SUDO_KEEPALIVE_PID:-}" ]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

log "Downloading repo tarball…"
TARBALL="$TMPDIR/repo.tar.gz"
if [ "$FETCHER" = "curl" ]; then
    curl -fsSL "$TARBALL_URL" -o "$TARBALL" \
        || die "Failed to download $TARBALL_URL"
else
    wget -q -O "$TARBALL" "$TARBALL_URL" \
        || die "Failed to download $TARBALL_URL"
fi

REPO_DIR="$TMPDIR/repo"
mkdir -p "$REPO_DIR"
# --strip-components=1 flattens the GitHub-prefixed top-level dir
# (mac-linux-postinstall-main/) so paths look like repo/lib/common.sh
tar -xzf "$TARBALL" -C "$REPO_DIR" --strip-components=1 \
    || die "Failed to extract tarball"

ok "Repo downloaded to $REPO_DIR"

# ---------------- 5. Source the full lib/ + resolve target ------------------
# shellcheck source=/dev/null
. "$REPO_DIR/lib/common.sh"
# shellcheck source=/dev/null
. "$REPO_DIR/lib/pkg.sh"
# shellcheck source=/dev/null
. "$REPO_DIR/lib/ui.sh"
# shellcheck source=/dev/null
. "$REPO_DIR/lib/detect.sh"

# Re-run detection with the full helpers (gets DEVICE_SLUG, TARGET, etc.)
detect_all || true   # may return non-zero for unsupported targets; we handle below

if [ -z "${TARGET:-}" ]; then
    err "Unsupported combination: $DEVICE_PRODUCT + $DISTRO_ID $DISTRO_VERSION"
    err ""
    err "MVP currently supports: MacBookAir7,2 + Fedora 44"
    err "Please open an issue at $ISSUE_URL with your detection results above"
    err "if you'd like this combination supported."
    exit 1
fi

TARGET_DIR="$REPO_DIR/targets/$TARGET"
[ -d "$TARGET_DIR" ] || die "Target dir missing: $TARGET_DIR (this is a bug — the target was resolved but its scripts aren't in the repo)"

# ---------------- 6. Sudo credential cache ----------------------------------
log "Caching sudo credentials (you'll be prompted once)…"
if ! sudo -v; then
    die "Sudo authentication failed. Aborting."
fi
# Keep the credential alive while we work. Background loop refreshes every
# minute; killed on exit.
( while true; do sudo -n true; sleep 60; kill -0 $$ 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!

# ---------------- 7. Install whiptail ---------------------------------------
detect_pkg_manager
log "Installing TUI dependency (for the menu)…"
install_tui

# ---------------- 8. Build + show the extras checklist ---------------------
# Source extras.sh in user context to read EXTRAS_MANIFEST. The functions
# defined there (install_*) are unused at this stage — we just need the
# manifest. Functions will be re-sourced under sudo later.
# shellcheck source=/dev/null
. "$TARGET_DIR/extras.sh"

# Build whiptail checklist args from EXTRAS_MANIFEST
CHECKLIST_ARGS=()
for entry in "${EXTRAS_MANIFEST[@]}"; do
    IFS='|' read -r key desc default <<< "$entry"
    CHECKLIST_ARGS+=("$key" "$desc" "$default")
done

log "Showing extras menu…"
SELECTED=$(tui_checklist "Optional extras for $TARGET" \
    "Critical drivers will be installed automatically.\nPick which optional extras you want:" \
    "${CHECKLIST_ARGS[@]}") || die "Aborted at extras selection." 0

# ---------------- 9. Write selections to env file ---------------------------
SELECTIONS_FILE="$TMPDIR/selections.env"
: > "$SELECTIONS_FILE"
for key in $SELECTED; do
    # Convert key to uppercase for env var name. SELECTED_TLP=true etc.
    upper=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')
    printf 'SELECTED_%s=true\n' "$upper" >> "$SELECTIONS_FILE"
done

# ---------------- 10. Build + run the install runner under sudo -------------
# Why a separate runner file: `sudo bash -c "<huge multi-line script>"` is
# fragile around quoting and signal handling. Writing a tiny runner script
# and sudo-execing it is robust.

REBOOT_FILE="$TMPDIR/reboot.reasons"
: > "$REBOOT_FILE"

RUNNER="$TMPDIR/run-install.sh"
cat > "$RUNNER" <<RUNNER_EOF
#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="\$1"
SELECTIONS_FILE="\$2"
export MACLIN_REBOOT_FILE="\$3"

# Source full lib + selections
. "\$REPO_DIR/lib/common.sh"
. "\$REPO_DIR/lib/pkg.sh"
# shellcheck source=/dev/null
[ -f "\$SELECTIONS_FILE" ] && . "\$SELECTIONS_FILE"

TARGET_DIR="\$REPO_DIR/targets/${TARGET}"

# Run essentials (always)
log "Running essentials for ${TARGET}…"
. "\$TARGET_DIR/essentials.sh"

# Run selected extras
log "Running selected extras…"
. "\$TARGET_DIR/extras.sh"
for entry in "\${EXTRAS_MANIFEST[@]}"; do
    IFS='|' read -r key desc default <<< "\$entry"
    upper=\$(printf '%s' "\$key" | tr '[:lower:]' '[:upper:]')
    var="SELECTED_\${upper}"
    if [ "\${!var:-}" = "true" ]; then
        if declare -F "install_\$key" >/dev/null; then
            "install_\$key"
        else
            warn "Selected extra '\$key' has no install function — skipping"
        fi
    fi
done
RUNNER_EOF
chmod +x "$RUNNER"

log "Starting install (running as root)…"
sudo bash "$RUNNER" "$REPO_DIR" "$SELECTIONS_FILE" "$REBOOT_FILE"

# ---------------- 11. Summary + reboot reminder -----------------------------
echo
log "Setup complete!"
echo

if [ -s "$REBOOT_FILE" ]; then
    warn "Reboot required to activate:"
    while IFS= read -r reason; do
        echo "    - $reason"
    done < "$REBOOT_FILE"
    echo
    echo "  Run: ${_C_BOLD}sudo reboot${_C_RESET}"
    echo
fi

echo "  After reboot, verify with:"
echo "    ${_C_DIM}lspci -k | grep -A 3 Network${_C_RESET}    # should show 'Kernel driver in use: wl'"
echo "    ${_C_DIM}sensors${_C_RESET}                          # should show fan RPMs + temps"
echo "    ${_C_DIM}upower -i \$(upower -e | grep BAT)${_C_RESET}"
echo
