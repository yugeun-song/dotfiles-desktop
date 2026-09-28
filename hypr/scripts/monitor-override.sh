#!/usr/bin/env bash
# Writes the per-output overrides that config/monitors.lua lays over its
# policy: which outputs are on, at what mode, scale and rotation, where the
# built-in panel sits, whether it mirrors. The bar's display panel calls this;
# it is also the way from a shell. The file is state, not configuration
# (XDG_STATE_HOME): neither installed nor tracked, and the policy runs without
# it. Validation lives here rather than in the widget so a hand-written file
# and a widget-written one meet the same rules.
#
#   monitor-override.sh show            print the current overrides
#   monitor-override.sh set  < lines    replace them with stdin (checked first)
#   monitor-override.sh clear           remove them: the policy alone decides
#   monitor-override.sh revert          swap the previous set back in
#
# One override per line, <selector> TAB <field> TAB <value>; blank lines and
# lines starting with # are kept but ignored.
#   selector   the output's description as `hyprctl monitors` prints it with
#              commas dropped (so it follows the display across connectors),
#              or name:<connector>, e.g. name:HDMI-A-1
#   enabled    true | false
#   mode       <W>x<H>@<R> (refresh with up to two decimals) | auto
#   scale      0.5 .. 3 | auto
#   transform  0 .. 7 (Hyprland's transform enum) | auto
#   side       left | right | above | below   panel only: its side of the
#                                             first external
#   mirror     true | false                   panel only: mirror the first
#                                             external
# One desk-wide line uses the selector "*":
#   workspaces dynamic | panel-first | blocks | auto   how workspaces are
#              spread over the outputs (auto: the preset decides)
# The policy keeps the last word: the panel off counts only beside a lit
# external, an external off is suspended while the lid is shut, so no set of
# overrides leaves every screen dark.
#
# revert swaps <file>.prev back; an empty .prev means there was no file. Exit
# codes: 0 ok, 1 could not write or reload, 2 usage or a line that does not
# parse (then nothing is written).

set -uo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
FILE="$STATE_DIR/monitor-overrides"
PREV="$FILE.prev"

say() { printf 'monitor-override: %s\n' "$*" >&2; }

usage() {
    say "usage: ${0##*/} show | set < lines | clear | revert"
    exit 2
}

# The compositor re-reads the file and acts on it. hyprctl exits non-zero and
# answers "error: ..." for a Lua failure; both are reported the same way.
reload() {
    local reply
    if ! command -v hyprctl >/dev/null 2>&1; then
        say "written, but hyprctl is not installed; run: hyprctl eval 'MONITORS.reload_overrides(\"override\")'"
        return 1
    fi
    if ! reply=$(hyprctl eval 'MONITORS.reload_overrides("override")' 2>&1) || [[ "$reply" == error* ]]; then
        say "written, but the compositor did not take it: ${reply:-no reply}"
        return 1
    fi
    return 0
}

# Every line, in order; a bad one names its number and nothing is written.
validate() {
    local -n lines_ref=$1
    local i line selector field value n rest ok
    for i in "${!lines_ref[@]}"; do
        line="${lines_ref[$i]}"
        n=$((i + 1))
        [[ -z "$line" || "$line" == \#* ]] && continue
        if [[ "$line" == *$'\r'* ]]; then
            say "line $n: carriage return; the file is plain newlines"
            return 2
        fi
        selector="${line%%$'\t'*}"
        rest="${line#*$'\t'}"
        if [[ "$rest" == "$line" ]]; then
            say "line $n: not <output><TAB><field><TAB><value>"
            return 2
        fi
        field="${rest%%$'\t'*}"
        value="${rest#*$'\t'}"
        if [[ "$field" == "$rest" || "$value" == *$'\t'* ]]; then
            say "line $n: not <output><TAB><field><TAB><value>"
            return 2
        fi
        if [[ -z "$selector" || "$selector" =~ [[:cntrl:]] ]]; then
            say "line $n: the output selector is empty or holds control characters"
            return 2
        fi
        if [[ "$selector" == name:* && ! "$selector" =~ ^name:[A-Za-z0-9._-]+$ ]]; then
            say "line $n: name: must be followed by a connector name such as HDMI-A-1"
            return 2
        fi
        # The desk-wide line: "*" carries workspaces and nothing else.
        if [[ "$selector" == "*" && "$field" != workspaces ]] || [[ "$selector" != "*" && "$field" == workspaces ]]; then
            say "line $n: workspaces goes with the selector *, other fields with an output"
            return 2
        fi
        ok=1
        case "$field" in
            workspaces)
                [[ "$value" =~ ^(dynamic|panel-first|blocks|auto)$ ]] || ok=0 ;;
            enabled|mirror)
                [[ "$value" =~ ^(true|false)$ ]] || ok=0 ;;
            mode)
                [[ "$value" == auto || "$value" =~ ^[0-9]+x[0-9]+@[0-9]+(\.[0-9]{1,2})?$ ]] || ok=0 ;;
            scale)
                if [[ "$value" != auto ]]; then
                    [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]] || ok=0
                    (( ok )) && awk -v s="$value" 'BEGIN { exit !(s >= 0.5 && s <= 3) }' || ok=0
                fi ;;
            transform)
                [[ "$value" =~ ^(auto|[0-7])$ ]] || ok=0 ;;
            side)
                [[ "$value" =~ ^(left|right|above|below)$ ]] || ok=0 ;;
            *)
                say "line $n: unknown field '$field' (enabled, mode, scale, transform, side, mirror, workspaces)"
                return 2 ;;
        esac
        if (( ! ok )); then
            say "line $n: '$value' is not a valid $field"
            return 2
        fi
    done
    return 0
}

# The content in place becomes .prev (empty when there was none), so revert
# always has something to swap back.
keep_previous() {
    mkdir -p -- "$STATE_DIR" || { say "cannot create $STATE_DIR"; return 1; }
    if [[ -f "$FILE" ]]; then
        cp -- "$FILE" "$PREV.new-$$" && mv -T -- "$PREV.new-$$" "$PREV"
    else
        : > "$PREV.new-$$" && mv -T -- "$PREV.new-$$" "$PREV"
    fi
}

# Temp and rename: the compositor may read the file at any moment.
write_lines() {
    local -n lines_ref=$1
    local tmp="$FILE.new-$$"
    mkdir -p -- "$STATE_DIR" || { say "cannot create $STATE_DIR"; return 1; }
    if (( ${#lines_ref[@]} == 0 )); then
        rm -f -- "$FILE"
        return 0
    fi
    { printf '%s\n' "${lines_ref[@]}" > "$tmp" && mv -T -- "$tmp" "$FILE"; } || {
        rm -f -- "$tmp"
        say "cannot write $FILE"
        return 1
    }
}

case "${1:-}" in
    show)
        [[ $# -eq 1 ]] || usage
        [[ -f "$FILE" ]] && cat -- "$FILE"
        exit 0
        ;;
    set)
        [[ $# -eq 1 ]] || usage
        if [[ -t 0 ]]; then
            say "set reads the new overrides from stdin"
            exit 2
        fi
        lines=()
        while IFS= read -r line || [[ -n "$line" ]]; do
            lines+=("$line")
        done
        validate lines || exit 2
        keep_previous || exit 1
        write_lines lines || exit 1
        reload || exit 1
        exit 0
        ;;
    clear)
        [[ $# -eq 1 ]] || usage
        keep_previous || exit 1
        rm -f -- "$FILE"
        reload || exit 1
        exit 0
        ;;
    revert)
        [[ $# -eq 1 ]] || usage
        if [[ ! -f "$PREV" ]]; then
            say "nothing to revert"
            exit 1
        fi
        # A swap, so a second revert undoes the first.
        if [[ -f "$FILE" ]]; then
            cp -- "$FILE" "$FILE.swap-$$" || { say "cannot read $FILE"; exit 1; }
        else
            : > "$FILE.swap-$$"
        fi
        if [[ -s "$PREV" ]]; then
            mv -T -- "$PREV" "$FILE" || { rm -f -- "$FILE.swap-$$"; say "cannot restore $FILE"; exit 1; }
        else
            rm -f -- "$FILE" "$PREV"
        fi
        mv -T -- "$FILE.swap-$$" "$PREV"
        reload || exit 1
        exit 0
        ;;
    *)
        usage
        ;;
esac
