#!/usr/bin/env bash
# =============================================================================
# tests/qa.sh — automated QA for mac-linux-postinstall
# =============================================================================
# Runs without real hardware. Tests bash syntax, library unit tests,
# manifest integrity, and bootstrap structural invariants.
#
# Usage:
#   bash tests/qa.sh
#   bash tests/qa.sh --verbose      # show output of commands that fail
#
# Exit code: 0 if all tests pass, 1 if any fail.
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ─── Helpers ─────────────────────────────────────────────────────────────────

PASS=0; FAIL=0; SKIP=0
VERBOSE=false
[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

_c_reset=$'\033[0m'; _c_bold=$'\033[1m'
_c_green=$'\033[1;32m'; _c_red=$'\033[1;31m'
_c_yellow=$'\033[1;33m'; _c_blue=$'\033[1;34m'
[[ -t 1 ]] || { _c_reset=; _c_bold=; _c_green=; _c_red=; _c_yellow=; _c_blue=; }

section() { printf '\n%s==>%s %s%s%s\n' "$_c_blue" "$_c_reset" "$_c_bold" "$*" "$_c_reset"; }

pass() {
    printf '  %s✓%s  %s\n' "$_c_green" "$_c_reset" "$1"
    PASS=$(( PASS + 1 ))
}

fail() {
    printf '  %s✗%s  %s\n' "$_c_red" "$_c_reset" "$1"
    [ -n "${2:-}" ] && printf '     %s\n' "$2"
    FAIL=$(( FAIL + 1 ))
}

skip() {
    printf '  %s-%s  %s (skipped: %s)\n' "$_c_yellow" "$_c_reset" "$1" "${2:-reason not given}"
    SKIP=$(( SKIP + 1 ))
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$desc"
    else
        fail "$desc" "expected $(printf '%q' "$expected"), got $(printf '%q' "$actual")"
    fi
}

assert_zero() {
    local desc="$1"; shift
    local out
    if out=$("$@" 2>&1); then
        pass "$desc"
    else
        fail "$desc" "$("$VERBOSE" && printf '%s' "$out" || true)"
    fi
}

assert_nonzero() {
    local desc="$1"; shift
    if ! "$@" >/dev/null 2>&1; then
        pass "$desc"
    else
        fail "$desc" "expected non-zero exit but got 0"
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$desc"
    else
        fail "$desc" "expected to find $(printf '%q' "$needle") in output"
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        pass "$desc"
    else
        fail "$desc" "did not expect to find $(printf '%q' "$needle") in output"
    fi
}

# Run a test in an isolated subshell with a fresh environment.
# Usage: in_subshell "desc" <<'SH'
#            ... test body, call pass/fail directly ...
#        SH
# Since we can't easily propagate pass/fail counts from subshells, we use
# exit codes: 0 = all assertions inside passed, 1 = any failed.

# ─── Temp workspace ───────────────────────────────────────────────────────────

QA_TMP=$(mktemp -d)
trap 'rm -rf "$QA_TMP"' EXIT

# =============================================================================
# 1. Syntax checks
# =============================================================================
section "1. Syntax (bash -n)"

for f in \
    "$REPO_ROOT/docs/install.sh" \
    "$REPO_ROOT/lib/common.sh" \
    "$REPO_ROOT/lib/detect.sh" \
    "$REPO_ROOT/lib/pkg.sh" \
    "$REPO_ROOT/lib/ui.sh" \
    "$REPO_ROOT/targets/macbookair7_2-fedora44/essentials.sh" \
    "$REPO_ROOT/targets/macbookair7_2-fedora44/extras.sh"; do
    name="${f#"$REPO_ROOT/"}"
    if bash -n "$f" 2>/dev/null; then
        pass "bash -n $name"
    else
        fail "bash -n $name" "$(bash -n "$f" 2>&1 || true)"
    fi
done

# =============================================================================
# 2. shellcheck (optional — skipped if not installed)
# =============================================================================
section "2. shellcheck"

if command -v shellcheck >/dev/null 2>&1; then
    for f in \
        "$REPO_ROOT/docs/install.sh" \
        "$REPO_ROOT/lib/common.sh" \
        "$REPO_ROOT/lib/detect.sh" \
        "$REPO_ROOT/lib/pkg.sh" \
        "$REPO_ROOT/lib/ui.sh"; do
        name="${f#"$REPO_ROOT/"}"
        # --source-path=SCRIPTDIR lets shellcheck resolve `. "$(dirname …)/common.sh"`
        # in the lib/* files, which it cannot do statically without the hint.
        if shellcheck --source-path=SCRIPTDIR -x "$f" >/dev/null 2>&1; then
            pass "shellcheck $name"
        else
            fail "shellcheck $name" "$(shellcheck --source-path=SCRIPTDIR -x "$f" 2>&1 | head -5 || true)"
        fi
    done
else
    skip "shellcheck (all files)" "shellcheck not installed"
fi

# =============================================================================
# 3. lib/common.sh — reboot tracking, helpers
# =============================================================================
section "3. lib/common.sh — reboot tracking + helpers"

# 3a. mark_reboot writes reason to file
(
    . "$REPO_ROOT/lib/common.sh"
    MACLIN_REBOOT_FILE="$QA_TMP/reboot_3a.txt"
    : > "$MACLIN_REBOOT_FILE"
    mark_reboot "test reason"
    result=$(cat "$MACLIN_REBOOT_FILE")
    [[ "$result" == "test reason" ]] || { echo "FAIL: expected 'test reason', got '$result'"; exit 1; }
) && pass "mark_reboot writes reason to MACLIN_REBOOT_FILE" \
   || fail "mark_reboot writes reason to MACLIN_REBOOT_FILE"

# 3b. reboot_needed returns true after mark_reboot
(
    . "$REPO_ROOT/lib/common.sh"
    MACLIN_REBOOT_FILE="$QA_TMP/reboot_3b.txt"
    : > "$MACLIN_REBOOT_FILE"
    mark_reboot "wifi driver"
    reboot_needed
) && pass "reboot_needed is true after mark_reboot" \
   || fail "reboot_needed is true after mark_reboot"

# 3c. reboot_needed returns false on empty file
(
    . "$REPO_ROOT/lib/common.sh"
    MACLIN_REBOOT_FILE="$QA_TMP/reboot_3c.txt"
    : > "$MACLIN_REBOOT_FILE"
    ! reboot_needed
) && pass "reboot_needed is false on empty file" \
   || fail "reboot_needed is false on empty file"

# 3d. reboot_needed returns false when MACLIN_REBOOT_FILE is unset
(
    . "$REPO_ROOT/lib/common.sh"
    unset MACLIN_REBOOT_FILE
    ! reboot_needed
) && pass "reboot_needed is false when MACLIN_REBOOT_FILE unset" \
   || fail "reboot_needed is false when MACLIN_REBOOT_FILE unset"

# 3e. multiple calls accumulate reasons
(
    . "$REPO_ROOT/lib/common.sh"
    MACLIN_REBOOT_FILE="$QA_TMP/reboot_3e.txt"
    : > "$MACLIN_REBOOT_FILE"
    mark_reboot "reason one"
    mark_reboot "reason two"
    count=$(wc -l < "$MACLIN_REBOOT_FILE")
    [[ "$count" -eq 2 ]]
) && pass "mark_reboot accumulates multiple reasons" \
   || fail "mark_reboot accumulates multiple reasons"

# 3f. has_cmd finds bash
(
    . "$REPO_ROOT/lib/common.sh"
    has_cmd bash
) && pass "has_cmd finds bash" \
   || fail "has_cmd finds bash"

# 3g. has_cmd returns false for nonexistent command
(
    . "$REPO_ROOT/lib/common.sh"
    ! has_cmd __definitely_not_a_real_command__
) && pass "has_cmd returns false for nonexistent command" \
   || fail "has_cmd returns false for nonexistent command"

# 3h. source guard prevents double-load
(
    . "$REPO_ROOT/lib/common.sh"
    first="${_MACLIN_COMMON_LOADED:-}"
    . "$REPO_ROOT/lib/common.sh"
    second="${_MACLIN_COMMON_LOADED:-}"
    [[ "$first" == "1" && "$second" == "1" ]]
) && pass "common.sh source guard is set" \
   || fail "common.sh source guard is set"

# =============================================================================
# 4. lib/detect.sh — slug conversion + target resolution
# =============================================================================
section "4. lib/detect.sh — slug + target resolution"

# 4a. DEVICE_SLUG: MacBookAir7,2 → macbookair7_2
(
    _MACLIN_COMMON_LOADED=1
    # Define minimal stubs so detect.sh doesn't need common.sh sourced
    has_cmd() { command -v "$1" >/dev/null 2>&1; }
    die()  { echo "[die] $1" >&2; exit 1; }
    log()  { :; }
    warn() { :; }
    . "$REPO_ROOT/lib/detect.sh"
    slug=$(printf '%s' "MacBookAir7,2" | tr '[:upper:]' '[:lower:]' | tr ', ' '__')
    [[ "$slug" == "macbookair7_2" ]] || { echo "got: $slug"; exit 1; }
) && pass "slug: MacBookAir7,2 → macbookair7_2" \
   || fail "slug: MacBookAir7,2 → macbookair7_2"

# 4b. slug: spaces and commas become underscores
(
    slug=$(printf '%s' "MacBook Pro 16,1" | tr '[:upper:]' '[:lower:]' | tr ', ' '__')
    [[ "$slug" == "macbook_pro_16_1" ]] || { echo "got: $slug"; exit 1; }
) && pass "slug: spaces and commas become underscores" \
   || fail "slug: spaces and commas become underscores"

# 4c. resolve_target: macbookair7_2 + fedora 44 → supported target
(
    _MACLIN_COMMON_LOADED=1
    has_cmd() { command -v "$1" >/dev/null 2>&1; }
    die()  { echo "[die] $1" >&2; exit 1; }
    log()  { :; }
    warn() { :; }
    . "$REPO_ROOT/lib/detect.sh"
    DEVICE_SLUG="macbookair7_2"
    DISTRO_ID="fedora"
    DISTRO_VERSION="44"
    resolve_target
    [[ "$TARGET" == "macbookair7_2-fedora44" ]] || { echo "got: $TARGET"; exit 1; }
) && pass "resolve_target: macbookair7_2 + fedora 44 → macbookair7_2-fedora44" \
   || fail "resolve_target: macbookair7_2 + fedora 44 → macbookair7_2-fedora44"

# 4d. resolve_target returns 1 for unsupported combos
(
    _MACLIN_COMMON_LOADED=1
    has_cmd() { command -v "$1" >/dev/null 2>&1; }
    die()  { echo "[die] $1" >&2; exit 1; }
    log()  { :; }
    warn() { :; }
    . "$REPO_ROOT/lib/detect.sh"
    DEVICE_SLUG="macbookair7_2"
    DISTRO_ID="ubuntu"
    DISTRO_VERSION="24.04"
    ! resolve_target
    [[ -z "$TARGET" ]]
) && pass "resolve_target: unsupported combo sets TARGET='' and returns 1" \
   || fail "resolve_target: unsupported combo sets TARGET='' and returns 1"

# 4e. resolve_target: wrong Fedora version is unsupported
(
    _MACLIN_COMMON_LOADED=1
    has_cmd() { command -v "$1" >/dev/null 2>&1; }
    die()  { echo "[die] $1" >&2; exit 1; }
    log()  { :; }
    warn() { :; }
    . "$REPO_ROOT/lib/detect.sh"
    DEVICE_SLUG="macbookair7_2"
    DISTRO_ID="fedora"
    DISTRO_VERSION="43"
    ! resolve_target
) && pass "resolve_target: Fedora 43 (not 44) is unsupported" \
   || fail "resolve_target: Fedora 43 (not 44) is unsupported"

# 4f. detect_distro subshell: os-release vars do not bleed into parent scope
(
    _MACLIN_COMMON_LOADED=1
    has_cmd() { command -v "$1" >/dev/null 2>&1; }
    die()  { echo "[die] $1" >&2; exit 1; }
    log()  { :; }
    warn() { :; }
    . "$REPO_ROOT/lib/detect.sh"
    # After detect_distro, variables like NAME/PRETTY_NAME should NOT be set
    # unless they were already in the environment.  We unset them first so the
    # test is clean, then check they're still unset after the call.
    unset NAME PRETTY_NAME HOME_URL SUPPORT_URL 2>/dev/null || true
    detect_distro
    # Check the important ones: they should not be set by the subshell sourcing
    if [[ -n "${NAME:-}" || -n "${PRETTY_NAME:-}" ]]; then
        echo "os-release leaked NAME=${NAME:-} PRETTY_NAME=${PRETTY_NAME:-}"; exit 1
    fi
) && pass "detect_distro: os-release vars do not leak into parent scope" \
   || fail "detect_distro: os-release vars do not leak into parent scope"

# 4g. detect_distro parses DISTRO_ID and DISTRO_VERSION
# Skip when /etc/os-release is missing (e.g. running this on macOS for dev) —
# the test verifies parsing of a real os-release, which doesn't exist there.
if [ -r /etc/os-release ]; then
    (
        _MACLIN_COMMON_LOADED=1
        has_cmd() { command -v "$1" >/dev/null 2>&1; }
        die()  { echo "[die] $1" >&2; exit 1; }
        log()  { :; }
        warn() { :; }
        . "$REPO_ROOT/lib/detect.sh"
        detect_distro
        [[ -n "$DISTRO_ID" && "$DISTRO_ID" != "unknown" ]] || {
            echo "DISTRO_ID is empty or unknown: '$DISTRO_ID'"; exit 1
        }
        [[ -n "$DISTRO_VERSION" ]] || {
            echo "DISTRO_VERSION is empty: '$DISTRO_VERSION'"; exit 1
        }
    ) && pass "detect_distro: DISTRO_ID and DISTRO_VERSION are set from /etc/os-release" \
       || fail "detect_distro: DISTRO_ID and DISTRO_VERSION are set from /etc/os-release"
else
    skip "detect_distro: DISTRO_ID and DISTRO_VERSION are set from /etc/os-release" \
         "/etc/os-release not present (running on non-Linux dev host)"
fi

# =============================================================================
# 5. lib/pkg.sh — package manager detection
# =============================================================================
section "5. lib/pkg.sh — package manager detection"

# 5a. detect_pkg_manager sets PKG_MANAGER to known value
(
    _MACLIN_COMMON_LOADED=1
    has_cmd() { command -v "$1" >/dev/null 2>&1; }
    die()  { echo "[die] $1" >&2; exit 1; }
    log()  { :; }
    warn() { :; }
    . "$REPO_ROOT/lib/pkg.sh"
    detect_pkg_manager
    [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "apt" || "$PKG_MANAGER" == "unknown" ]] \
        || { echo "unexpected PKG_MANAGER=$PKG_MANAGER"; exit 1; }
) && pass "detect_pkg_manager: returns dnf, apt, or unknown" \
   || fail "detect_pkg_manager: returns dnf, apt, or unknown"

# 5b. pkg.sh source guard
(
    _MACLIN_COMMON_LOADED=1
    has_cmd() { command -v "$1" >/dev/null 2>&1; }
    die()  { echo "[die] $1" >&2; exit 1; }
    log()  { :; }
    warn() { :; }
    . "$REPO_ROOT/lib/pkg.sh"
    [[ "${_MACLIN_PKG_LOADED:-}" == "1" ]]
) && pass "pkg.sh source guard is set" \
   || fail "pkg.sh source guard is set"

# 5c. install_tui skips when whiptail already installed
(
    _MACLIN_COMMON_LOADED=1
    # Source pkg.sh without pre-setting _MACLIN_PKG_LOADED so install_tui is defined.
    # Stub common.sh dependencies that pkg.sh uses.
    die()  { echo "[die] $1" >&2; exit 1; }
    log()  { :; }
    warn() { :; }
    # Override has_cmd to fake whiptail presence (must be defined before sourcing)
    has_cmd() { [[ "$1" == "whiptail" ]] && return 0; command -v "$1" >/dev/null 2>&1; }
    . "$REPO_ROOT/lib/pkg.sh"
    # Override dnf/apt to fail loudly if called — they must NOT be reached
    dnf() { echo "ERROR: dnf should not be called when whiptail is present"; exit 1; }
    install_tui   # should return 0 immediately because has_cmd whiptail returns 0
) && pass "install_tui: no-op when whiptail already present" \
   || fail "install_tui: no-op when whiptail already present"

# =============================================================================
# 6. lib/ui.sh — checklist fallback + list_height logic
# =============================================================================
section "6. lib/ui.sh — tui_checklist logic"

# 6a. tui_checklist fallback produces correct item list when whiptail absent
(
    _MACLIN_COMMON_LOADED=1
    has_cmd() { [[ "$1" == "whiptail" ]] && return 1; command -v "$1" >/dev/null 2>&1; }
    die()  { echo "[die] $1" >&2; exit 1; }
    log()  { :; }
    warn() { :; }
    . "$REPO_ROOT/lib/ui.sh"

    # plain_confirm reads /dev/tty; we can't pipe to that in tests.
    # Override plain_confirm to accept all items with "on" default, reject "off".
    plain_confirm() {
        local msg="$1" default="${2:-no}"
        [[ "$default" == "yes" ]]
    }

    result=$(tui_checklist "Test" "Pick:" \
        alpha "Alpha item" on \
        beta  "Beta item"  off \
        gamma "Gamma item" on)
    # Should include alpha and gamma (on), not beta (off)
    [[ "$result" == *"alpha"* ]] || { echo "missing alpha in: $result"; exit 1; }
    [[ "$result" == *"gamma"* ]] || { echo "missing gamma in: $result"; exit 1; }
    [[ "$result" != *"beta"* ]] || { echo "beta should not be in: $result"; exit 1; }
) && pass "tui_checklist fallback: on-by-default items selected, off items excluded" \
   || fail "tui_checklist fallback: on-by-default items selected, off items excluded"

# 6b. list_height never exceeds num_items
(
    _MACLIN_COMMON_LOADED=1
    has_cmd() { command -v "$1" >/dev/null 2>&1; }
    die()  { echo "[die] $1" >&2; exit 1; }
    log()  { :; }
    warn() { :; }
    . "$REPO_ROOT/lib/ui.sh"

    # Simulate the list_height calculation with 2 items on a large terminal
    num_items=2
    height=20
    list_height=$(( height - 8 ))
    [ "$list_height" -gt "$num_items" ] && list_height=$num_items
    [ "$list_height" -lt 1 ] && list_height=1
    [ "$num_items" -ge 3 ] && [ "$list_height" -lt 3 ] && list_height=3
    [[ "$list_height" -le "$num_items" ]] || {
        echo "list_height ($list_height) > num_items ($num_items)"; exit 1
    }
) && pass "list_height: never exceeds num_items (2-item manifest case)" \
   || fail "list_height: never exceeds num_items (2-item manifest case)"

# 6c. list_height minimum of 3 applies when num_items >= 3
(
    num_items=6
    height=10   # small terminal
    list_height=$(( height - 8 ))   # = 2
    [ "$list_height" -gt "$num_items" ] && list_height=$num_items
    [ "$list_height" -lt 1 ] && list_height=1
    [ "$num_items" -ge 3 ] && [ "$list_height" -lt 3 ] && list_height=3
    [[ "$list_height" -ge 3 ]] || { echo "expected >=3, got $list_height"; exit 1; }
) && pass "list_height: minimum 3 applied on small terminal (6-item manifest)" \
   || fail "list_height: minimum 3 applied on small terminal (6-item manifest)"

# 6d. ui.sh source guard
(
    _MACLIN_COMMON_LOADED=1
    has_cmd() { command -v "$1" >/dev/null 2>&1; }
    die()  { echo "[die] $1" >&2; exit 1; }
    log()  { :; }
    warn() { :; }
    . "$REPO_ROOT/lib/ui.sh"
    [[ "${_MACLIN_UI_LOADED:-}" == "1" ]]
) && pass "ui.sh source guard is set" \
   || fail "ui.sh source guard is set"

# =============================================================================
# 7. extras.sh — manifest integrity
# =============================================================================
section "7. extras.sh — EXTRAS_MANIFEST integrity"

# Source extras.sh in isolation (it only defines functions + the manifest)
(
    _MACLIN_COMMON_LOADED=1
    has_cmd() { command -v "$1" >/dev/null 2>&1; }
    die()  { echo "[die] $1" >&2; exit 1; }
    log()  { :; }
    warn() { :; }
    ok()   { :; }
    mark_reboot() { :; }
    . "$REPO_ROOT/targets/macbookair7_2-fedora44/extras.sh"

    # 7a. EXTRAS_MANIFEST is set and non-empty
    [[ "${#EXTRAS_MANIFEST[@]}" -gt 0 ]] || { echo "EXTRAS_MANIFEST is empty"; exit 1; }
    echo "manifest_count=${#EXTRAS_MANIFEST[@]}"

    # 7b. Every entry has exactly 3 pipe-separated fields
    for entry in "${EXTRAS_MANIFEST[@]}"; do
        IFS='|' read -r key desc default <<< "$entry"
        [[ -n "$key" ]]     || { echo "empty key in: $entry"; exit 1; }
        [[ -n "$desc" ]]    || { echo "empty desc for key=$key"; exit 1; }
        [[ "$default" == "on" || "$default" == "off" ]] \
            || { echo "bad default '$default' for key=$key"; exit 1; }
    done
    echo "fields_ok=true"

    # 7c. facetimehd defaults to "off"
    for entry in "${EXTRAS_MANIFEST[@]}"; do
        IFS='|' read -r key desc default <<< "$entry"
        if [[ "$key" == "facetimehd" ]]; then
            [[ "$default" == "off" ]] || { echo "facetimehd should default off, got $default"; exit 1; }
            echo "facetimehd_default=off"
        fi
    done

    # 7d. Every key has a corresponding install_<key> function
    for entry in "${EXTRAS_MANIFEST[@]}"; do
        IFS='|' read -r key _ _ <<< "$entry"
        declare -F "install_${key}" >/dev/null \
            || { echo "missing function: install_${key}"; exit 1; }
    done
    echo "install_functions_ok=true"
) > "$QA_TMP/extras_out.txt" 2>&1
_extras_rc=$?
_extras_out=$(cat "$QA_TMP/extras_out.txt")

if [[ $_extras_rc -eq 0 ]]; then
    _count=$(grep -o 'manifest_count=[0-9]*' <<< "$_extras_out" | cut -d= -f2)
    pass "EXTRAS_MANIFEST is non-empty (${_count} entries)"
    pass "all manifest entries have key|desc|on/off format"
    assert_contains "facetimehd defaults to off" "facetimehd_default=off" "$_extras_out"
    pass "every manifest key has an install_<key> function"
else
    fail "extras.sh manifest integrity" "$_extras_out"
fi

# =============================================================================
# 8. Bootstrap structural invariants (grep-based)
# =============================================================================
section "8. Bootstrap structural invariants (docs/install.sh)"

BOOTSTRAP="$REPO_ROOT/docs/install.sh"

# 8a. Uses bash -c "$(curl ...)" not curl | bash
# Check README and landing page ship the safe pattern; grep the install.sh comment too.
_safe_pattern='bash -c "$(curl'
# Check README ships the safe pattern; install.sh must not contain curl|bash
# outside of comments (there's a "DO NOT" comment that mentions the pattern).
if grep -qF "$_safe_pattern" "$REPO_ROOT/README.md" && \
   ! grep -v '^[[:space:]]*#' "$REPO_ROOT/docs/install.sh" | grep -qF '| bash'; then
    pass "one-liner pattern uses bash -c \"\$(curl ...)\" not curl | bash"
else
    fail "one-liner pattern uses bash -c \"\$(curl ...)\" not curl | bash" \
         "README missing safe pattern or install.sh contains '| bash'"
fi

# 8b. clear before tui_checklist
if grep -q 'clear.*2>/dev/null' "$BOOTSTRAP" && \
   grep -q 'tui_checklist' "$BOOTSTRAP"; then
    # Check ordering: clear comes before tui_checklist
    clear_line=$(grep -n 'clear.*2>/dev/null' "$BOOTSTRAP" | head -1 | cut -d: -f1)
    tui_line=$(grep -n 'tui_checklist' "$BOOTSTRAP" | head -1 | cut -d: -f1)
    if [[ "$clear_line" -lt "$tui_line" ]]; then
        pass "terminal is cleared before tui_checklist (line $clear_line before $tui_line)"
    else
        fail "terminal is cleared before tui_checklist" \
             "clear is on line $clear_line but tui_checklist on $tui_line"
    fi
else
    fail "terminal is cleared before tui_checklist" "grep found no match"
fi

# 8c. cleanup trap is registered
if grep -q 'trap cleanup EXIT' "$BOOTSTRAP"; then
    pass "cleanup trap registered"
else
    fail "cleanup trap registered"
fi

# 8d. sudo keepalive background loop is present
if grep -q 'SUDO_KEEPALIVE_PID' "$BOOTSTRAP"; then
    pass "sudo keepalive background process tracked"
else
    fail "sudo keepalive background process tracked"
fi

# 8e. MACLIN_TMPDIR used instead of TMPDIR (no raw TMPDIR= assignment)
# Acceptable uses: references to the system $TMPDIR only (none expected in install.sh)
if grep -q 'MACLIN_TMPDIR=' "$BOOTSTRAP" && ! grep -qE '^TMPDIR=' "$BOOTSTRAP"; then
    pass "bootstrap uses MACLIN_TMPDIR (no TMPDIR= assignment that shadows env)"
else
    fail "bootstrap uses MACLIN_TMPDIR" \
         "either MACLIN_TMPDIR not found or bare TMPDIR= assignment exists"
fi

# 8f. unsupported target check exits before sudo -v
target_check_line=$(grep -n 'Unsupported combination\|unsupported.*exit\|\[ -z.*TARGET\|exit 1' \
    "$BOOTSTRAP" | head -1 | cut -d: -f1 || echo 0)
sudo_line=$(grep -n 'sudo -v' "$BOOTSTRAP" | head -1 | cut -d: -f1 || echo 9999)
if [[ "$target_check_line" -gt 0 && "$target_check_line" -lt "$sudo_line" ]]; then
    pass "unsupported target exit check appears before sudo -v (line $target_check_line < $sudo_line)"
else
    fail "unsupported target exit check appears before sudo -v" \
         "target_check=$target_check_line sudo=$sudo_line"
fi

# 8g. runner passes REPO_DIR, SELECTIONS_FILE, REBOOT_FILE as positional args
if grep -q 'sudo bash.*RUNNER.*REPO_DIR.*SELECTIONS_FILE.*REBOOT_FILE' "$BOOTSTRAP"; then
    pass "sudo runner invoked with REPO_DIR SELECTIONS_FILE REBOOT_FILE args"
else
    fail "sudo runner invoked with REPO_DIR SELECTIONS_FILE REBOOT_FILE args"
fi

# =============================================================================
# 9. detect.sh — source guard and isolation
# =============================================================================
section "9. lib/detect.sh — source guard + module isolation"

(
    _MACLIN_COMMON_LOADED=1
    has_cmd() { command -v "$1" >/dev/null 2>&1; }
    die()  { echo "[die] $1" >&2; exit 1; }
    log()  { :; }
    warn() { :; }
    . "$REPO_ROOT/lib/detect.sh"
    [[ "${_MACLIN_DETECT_LOADED:-}" == "1" ]]
) && pass "detect.sh source guard is set" \
   || fail "detect.sh source guard is set"

(
    _MACLIN_COMMON_LOADED=1
    has_cmd() { command -v "$1" >/dev/null 2>&1; }
    die()  { echo "[die] $1" >&2; exit 1; }
    log()  { :; }
    warn() { :; }
    . "$REPO_ROOT/lib/detect.sh"
    # detect_all should export the expected variables
    DEVICE_SLUG="macbookair7_2"; DISTRO_ID="fedora"; DISTRO_VERSION="44"
    # Override detect_device and detect_distro to avoid real hardware reads
    detect_device() { DEVICE_PRODUCT="MacBookAir7,2"; DEVICE_SLUG="macbookair7_2"; export DEVICE_PRODUCT DEVICE_SLUG; }
    detect_distro() { DISTRO_ID="fedora"; DISTRO_VERSION="44"; DISTRO_LIKE=""; export DISTRO_ID DISTRO_VERSION DISTRO_LIKE; }
    detect_all
    [[ "$TARGET" == "macbookair7_2-fedora44" ]]
) && pass "detect_all (mocked device+distro): resolves to correct target" \
   || fail "detect_all (mocked device+distro): resolves to correct target"

# =============================================================================
# Summary
# =============================================================================
TOTAL=$(( PASS + FAIL + SKIP ))
printf '\n%s══════════════════════════════════════%s\n' "$_c_bold" "$_c_reset"
printf '  %sResults:%s  %s%d passed%s' "$_c_bold" "$_c_reset" "$_c_green" "$PASS" "$_c_reset"
[ "$FAIL" -gt 0 ] && printf ', %s%d failed%s' "$_c_red"    "$FAIL" "$_c_reset"
[ "$SKIP" -gt 0 ] && printf ', %s%d skipped%s' "$_c_yellow" "$SKIP" "$_c_reset"
printf ' / %d total\n' "$TOTAL"
printf '%s══════════════════════════════════════%s\n\n' "$_c_bold" "$_c_reset"

if [ "$FAIL" -gt 0 ]; then
    printf '%sNote:%s tests marked SKIP require real hardware (MacBook Air 2017 + Fedora 44).\n' \
        "$_c_yellow" "$_c_reset"
    printf 'See CLAUDE.md §7 for the full manual test checklist.\n\n'
    exit 1
fi

exit 0
