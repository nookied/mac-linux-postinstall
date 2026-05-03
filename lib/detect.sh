#!/usr/bin/env bash
# ============================================================================
# lib/detect.sh — device + distro detection
# ----------------------------------------------------------------------------
# Exports (after detect_all):
#   DEVICE_PRODUCT      e.g. "MacBookAir7,2"
#   DEVICE_SLUG         e.g. "macbookair7_2"     (lowercased, ',' → '_')
#   DISTRO_ID           e.g. "fedora"            (from /etc/os-release ID=)
#   DISTRO_VERSION      e.g. "44"                (from VERSION_ID=)
#   DISTRO_LIKE         e.g. "debian ubuntu"     (from ID_LIKE=, may be empty)
#   TARGET              e.g. "macbookair7_2-fedora44"  (or "" if unsupported)
#
# detect_all returns 0 if TARGET is supported, 1 otherwise.
# ============================================================================

[ -n "${_MACLIN_DETECT_LOADED:-}" ] && return 0
_MACLIN_DETECT_LOADED=1

if [ -z "${_MACLIN_COMMON_LOADED:-}" ]; then
    # shellcheck source=common.sh
    . "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# ---------------- Device ----------------------------------------------------
# Read DMI product name. Prefer /sys (no sudo needed); fall back to dmidecode.

detect_device() {
    DEVICE_PRODUCT=""
    if [ -r /sys/class/dmi/id/product_name ]; then
        DEVICE_PRODUCT=$(tr -d '\n' < /sys/class/dmi/id/product_name)
    elif has_cmd dmidecode; then
        # dmidecode needs root, but it's a fallback
        DEVICE_PRODUCT=$(sudo -n dmidecode -s system-product-name 2>/dev/null | tr -d '\n' || echo "")
    fi
    [ -z "$DEVICE_PRODUCT" ] && DEVICE_PRODUCT="unknown"

    # Slug: lowercase, comma → underscore, spaces → underscore
    DEVICE_SLUG=$(printf '%s' "$DEVICE_PRODUCT" | tr '[:upper:]' '[:lower:]' | tr ', ' '__')

    export DEVICE_PRODUCT DEVICE_SLUG
}

# ---------------- Distro ----------------------------------------------------
# Parse /etc/os-release. This is a freedesktop standard and present on
# every modern Linux distro we care about.
detect_distro() {
    DISTRO_ID="unknown"; DISTRO_VERSION="unknown"; DISTRO_LIKE=""
    if [ -r /etc/os-release ]; then
        # Parse in a subshell so the many NAME/PRETTY_NAME/etc. variables from
        # os-release don't pollute the bootstrap's global scope.
        local _parsed
        # shellcheck disable=SC1091
        _parsed=$(. /etc/os-release && printf '%s\t%s\t%s' \
            "${ID:-unknown}" "${VERSION_ID:-unknown}" "${ID_LIKE:-}")
        IFS=$'\t' read -r DISTRO_ID DISTRO_VERSION DISTRO_LIKE <<< "$_parsed"
    fi
    export DISTRO_ID DISTRO_VERSION DISTRO_LIKE
}

# ---------------- Target resolution -----------------------------------------
# Map (device, distro, version) → target directory name.
#
# Adding a new target:
#   1. Add a case below (most-specific first)
#   2. Create targets/<name>/{essentials,extras}.sh
#   3. Update README support matrix
#   4. Add a CHANGELOG entry

resolve_target() {
    TARGET=""
    case "${DEVICE_SLUG}-${DISTRO_ID}-${DISTRO_VERSION}" in
        macbookair7_2-fedora-44)
            TARGET="macbookair7_2-fedora44"
            ;;
        # Future targets go here, e.g.:
        # macbookair7_2-ubuntu-24.04)
        #     TARGET="macbookair7_2-ubuntu2404"
        #     ;;
        *)
            TARGET=""
            ;;
    esac
    export TARGET
    [ -n "$TARGET" ]
}

# ---------------- Convenience -----------------------------------------------
detect_all() {
    detect_device
    detect_distro
    resolve_target
}

# Pretty-print what we detected (for the bootstrap banner)
print_detection() {
    printf '  %sDevice:%s  %s\n' "$_C_BOLD" "$_C_RESET" "$DEVICE_PRODUCT"
    printf '  %sDistro:%s  %s %s\n' "$_C_BOLD" "$_C_RESET" "$DISTRO_ID" "$DISTRO_VERSION"
    if [ -n "$TARGET" ]; then
        printf '  %sTarget:%s  %s%s%s\n' "$_C_BOLD" "$_C_RESET" "$_C_GREEN" "$TARGET" "$_C_RESET"
    else
        printf '  %sTarget:%s  %sunsupported%s\n' "$_C_BOLD" "$_C_RESET" "$_C_RED" "$_C_RESET"
    fi
}
