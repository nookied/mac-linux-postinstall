#!/usr/bin/env bash
# ============================================================================
# lib/ui.sh — interactive UI primitives
# ----------------------------------------------------------------------------
# Two layers:
#   1. plain_*  — pure bash (no whiptail dependency). Used in the bootstrap
#                 BEFORE whiptail is installed (e.g. the initial confirmation).
#   2. tui_*    — whiptail-backed. Used after install_tui has run.
#
# After bootstrap installs whiptail, prefer the tui_* helpers — they look
# polished and handle terminal resize gracefully.
# ============================================================================

[ -n "${_MACLIN_UI_LOADED:-}" ] && return 0
_MACLIN_UI_LOADED=1

if [ -z "${_MACLIN_COMMON_LOADED:-}" ]; then
    # shellcheck source=common.sh
    . "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# ---------------- Plain (no-whiptail) prompts -------------------------------

# plain_confirm "Continue?"
# Returns 0 if user types y/yes (case-insensitive), non-zero otherwise.
# Default is NO unless second arg is "yes".
plain_confirm() {
    local prompt="$1"
    local default="${2:-no}"
    local hint reply
    if [ "$default" = "yes" ]; then
        hint="[Y/n]"
    else
        hint="[y/N]"
    fi
    # Read from /dev/tty to be safe even if stdin is weird (it shouldn't be
    # under `bash -c "$(curl …)"`, but belt and suspenders).
    printf '%s %s ' "$prompt" "$hint" >&2
    read -r reply </dev/tty || reply=""
    case "${reply,,}" in
        y|yes) return 0 ;;
        n|no)  return 1 ;;
        "")    [ "$default" = "yes" ] && return 0 || return 1 ;;
        *)     return 1 ;;
    esac
}

# plain_banner "Title"
# Prints a centered, bordered banner. Uses tput cols if available.
plain_banner() {
    local title="$1"
    local width
    width=$(tput cols 2>/dev/null || echo 60)
    [ "$width" -gt 80 ] && width=80
    local rule
    rule=$(printf '%*s' "$width" '' | tr ' ' '=')
    printf '\n%s%s%s\n' "$_C_BLUE" "$rule" "$_C_RESET"
    printf '%s%s  %s%s\n' "$_C_BOLD" "$_C_BLUE" "$title" "$_C_RESET"
    printf '%s%s%s\n\n' "$_C_BLUE" "$rule" "$_C_RESET"
}

# ---------------- Whiptail-backed prompts -----------------------------------
# All of these require whiptail to be installed (use install_tui from pkg.sh
# first). If whiptail is missing, they fall back to plain_* equivalents so
# scripts don't crash, but the experience is degraded.

# tui_msg "Title" "Body text"
tui_msg() {
    local title="$1" body="$2"
    if has_cmd whiptail; then
        whiptail --title "$title" --msgbox "$body" 12 70
    else
        log "$title"
        printf '%s\n' "$body"
    fi
}

# tui_yesno "Title" "Question?"  → 0 yes, 1 no
tui_yesno() {
    local title="$1" body="$2"
    if has_cmd whiptail; then
        whiptail --title "$title" --yesno "$body" 10 70
    else
        plain_confirm "$body"
    fi
}

# tui_checklist "Title" "Body" key1 desc1 default1 key2 desc2 default2 …
# Where defaultN is "on" or "off".
# Echoes selected keys, space-separated, on stdout. Returns whiptail's exit
# code (0 = OK, 1 = Cancel, 255 = Esc).
#
# Example:
#   selected=$(tui_checklist "Extras" "Pick optional installs:" \
#       tlp     "Better battery life"           on  \
#       mbpfan  "Sensible fan curves"           on  \
#       camera  "FaceTime HD (fragile)"         off)
tui_checklist() {
    local title="$1" body="$2"
    shift 2
    local items=()
    while [ $# -ge 3 ]; do
        items+=("$1" "$2" "$3")
        shift 3
    done
    if has_cmd whiptail; then
        # whiptail writes the selection to stderr (because stdout is for the UI),
        # so redirect 3>&1 1>&2 2>&3 to swap them.
        whiptail --title "$title" --checklist --separate-output \
            "$body" 20 76 12 "${items[@]}" 3>&1 1>&2 2>&3
    else
        # Fallback: ask each item individually
        warn "whiptail not available, falling back to plain prompts"
        local result=()
        local i=0
        while [ $i -lt ${#items[@]} ]; do
            local key="${items[$i]}"
            local desc="${items[$((i+1))]}"
            local default="${items[$((i+2))]}"
            if plain_confirm "  - $desc ($key)?" \
                    "$([ "$default" = "on" ] && echo yes || echo no)"; then
                result+=("$key")
            fi
            i=$((i+3))
        done
        printf '%s\n' "${result[@]}"
    fi
}
