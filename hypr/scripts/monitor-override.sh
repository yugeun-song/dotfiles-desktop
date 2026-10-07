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
#   monitor-override.sh try SECONDS < lines
#                                       set, as a trial: due for a revert
#                                       unless kept within SECONDS
#   monitor-override.sh keep            end a trial, keeping what it set
#   monitor-override.sh trial           print the seconds a trial has left
#                                       (0 or less: due); nothing if none
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
#
# A trial is the display panel's Apply: the panel counts down and reverts
# unless the user keeps the change. The countdown lived only in the running
# bar, so a reload, a crash or a forced power-off in those seconds (when a
# mode has gone wrong, say) left the untested set in force at every later
# login, and the next Apply overwrote .prev, the last state known to work.
# <file>.trial holds the deadline instead; a bar that starts reads it and
# resumes the countdown or reverts at once. Anything that settles the state
# (set, keep, clear, revert) ends the trial.

set -uo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
FILE="$STATE_DIR/monitor-overrides"
PREV="$FILE.prev"
TRIAL="$FILE.trial"

say() { printf 'monitor-override: %s\n' "$*" >&2; }

usage() {
    say "usage: ${0##*/} show | set < lines | try SECONDS < lines | keep | trial | clear | revert"
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

# The deadline goes in first: an Apply interrupted between the write and the
# marker must still come back as a trial.
start_trial() {
    local seconds="$1" tmp="$TRIAL.new-$$"
    mkdir -p -- "$STATE_DIR" || { say "cannot create $STATE_DIR"; return 1; }
    { printf '%s\n' "$(( $(date +%s) + seconds ))" > "$tmp" && mv -T -- "$tmp" "$TRIAL"; } || {
        rm -f -- "$tmp"
        say "cannot write $TRIAL"
        return 1
    }
}

case "${1:-}" in
    show)
        [[ $# -eq 1 ]] || usage
        [[ -f "$FILE" ]] && cat -- "$FILE"
        exit 0
        ;;
    set|try)
        if [[ "$1" == try ]]; then
            [[ $# -eq 2 && "$2" =~ ^[1-9][0-9]{0,3}$ ]] || usage
        else
            [[ $# -eq 1 ]] || usage
        fi
        if [[ -t 0 ]]; then
            say "$1 reads the new overrides from stdin"
            exit 2
        fi
        lines=()
        while IFS= read -r line || [[ -n "$line" ]]; do
            lines+=("$line")
        done
        validate lines || exit 2
        if [[ "$1" == try ]]; then
            start_trial "$2" || exit 1
        else
            rm -f -- "$TRIAL"
        fi
        # Nothing written, nothing to try: a marker left over would revert
        # to the state before the previous set.
        if ! keep_previous || ! write_lines lines; then
            rm -f -- "$TRIAL"
            exit 1
        fi
        reload || exit 1
        exit 0
        ;;
    keep)
        [[ $# -eq 1 ]] || usage
        rm -f -- "$TRIAL"
        exit 0
        ;;
    trial)
        [[ $# -eq 1 ]] || usage
        if [[ -f "$TRIAL" ]]; then
            deadline=$(head -n 1 -- "$TRIAL")
            # Unreadable counts as due: reverting is the safe side.
            [[ "$deadline" =~ ^[0-9]+$ ]] || deadline=0
            printf '%s\n' "$(( deadline - $(date +%s) ))"
        fi
        exit 0
        ;;
    clear)
        [[ $# -eq 1 ]] || usage
        rm -f -- "$TRIAL"
        keep_previous || exit 1
        rm -f -- "$FILE"
        reload || exit 1
        exit 0
        ;;
    revert)
        [[ $# -eq 1 ]] || usage
        # Over before the swap: a marker left behind by a failed reload
        # would revert again at the next start, and a second revert undoes
        # the first.
        rm -f -- "$TRIAL"
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
