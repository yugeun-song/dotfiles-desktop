#!/usr/bin/env bash
# Clipboard history picker. cliphist has no UI: fuzzel if present (it is only
# a transitive dependency), else fzf in a terminal.
#   clipboard.sh          pick an entry
#   clipboard.sh expire   cliphist-expire.timer's run (see that unit)
set -uo pipefail

if ! command -v cliphist >/dev/null 2>&1; then
    echo "clipboard.sh: cliphist is not installed" >&2
    exit 1
fi

# Drops every entry stored before the last run: the newest id then is kept
# beside the history, and the ids grow. One whose id is below the mark was
# there an interval ago. A history that started over (ids below the mark)
# only moves the mark.
if [[ "${1:-}" == expire ]]; then
    [[ -n "${CLIPHIST_DB_PATH:-}" ]] || { echo "clipboard.sh: CLIPHIST_DB_PATH is not set" >&2; exit 1; }
    mark_file="$(dirname -- "$CLIPHIST_DB_PATH")/expire-mark"
    [[ -e "$CLIPHIST_DB_PATH" ]] || exit 0
    list=$(cliphist list 2>/dev/null) || list=""
    newest=$(awk -F'\t' 'NR == 1 { print $1 + 0 }' <<<"$list")
    mark=$(cat -- "$mark_file" 2>/dev/null) || mark=""
    [[ "$mark" =~ ^[0-9]+$ ]] || mark=""
    if [[ -n "$mark" && -n "$newest" ]] && (( newest >= mark )); then
        old=$(awk -F'\t' -v m="$mark" '$1 + 0 <= m' <<<"$list")
        [[ -n "$old" ]] && cliphist delete <<<"$old"
    fi
    printf '%s\n' "${newest:-0}" > "$mark_file"
    exit 0
fi

# Captured, not piped into grep -q: grep stops at the first line, cliphist
# dies of SIGPIPE on its next write, and pipefail read a long history as
# empty (35 times in 50 with 100 entries).
if ! grep -q . <<<"$(cliphist list 2>/dev/null)"; then
    command -v notify-send >/dev/null 2>&1 && \
        ( timeout 2 notify-send "Clipboard history" "nothing stored yet" >/dev/null 2>&1 & )
    exit 0
fi

if command -v fuzzel >/dev/null 2>&1; then
    cliphist list | fuzzel --match-mode fzf --dmenu | cliphist decode | wl-copy
    exit 0
fi

if command -v fzf >/dev/null 2>&1; then
    exec "$(dirname -- "${BASH_SOURCE[0]}")/terminal.sh" -e sh -c \
        'cliphist list | fzf --no-sort | cliphist decode | wl-copy'
fi

echo "clipboard.sh: no picker available (looked for fuzzel, fzf)" >&2
exit 1
