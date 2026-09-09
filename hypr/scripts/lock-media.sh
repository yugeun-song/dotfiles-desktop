#!/usr/bin/env bash
# lock-media.sh - what is playing, for the lock screen's labels and buttons.
#
#   --line | --playing | --art          readouts, polled by hyprlock
#   --toggle | --next | --previous      actions, spawned by onclick
#
# Every readout prints nothing when no player has a track, and a hyprlock
# label with no text draws nothing, so the widget disappears on its own.
#
# Cost matters: these are polled behind a lock screen that may be up for
# hours. Picking the player takes two playerctl calls whatever the mode and
# whatever the number of players, never one per player.

set -uo pipefail

MODE="${1:---line}"
command -v playerctl >/dev/null 2>&1 || exit 0

# Whatever is playing, or failing that whatever has a track. The same rule the
# bar and the island use, so the three never disagree. -a lists statuses in
# --list-all's order, which is what lets this be two calls.
player() {
    local names states i
    mapfile -t names < <(playerctl --list-all 2>/dev/null)
    (( ${#names[@]} )) || return 1
    mapfile -t states < <(playerctl -a status 2>/dev/null)
    for i in "${!names[@]}"; do
        [[ "${states[i]:-}" == "Playing" ]] && { printf '%s\n' "${names[i]}"; return 0; }
    done
    printf '%s\n' "${names[0]}"
}

PLAYER=$(player) || exit 0

# Pango markup is on for hyprlock labels, and a track title is set by the
# player -- for a browser, by the page. Escaped so a title carrying a tag is
# drawn as text instead of parsed as markup.
escape() {
    local s="$1"
    s=${s//&/&amp;}
    s=${s//</&lt;}
    s=${s//>/&gt;}
    printf '%s' "$s"
}

case "$MODE" in
    # Title and artist in one label rather than two, because two labels are
    # two polls and two processes for one line of text.
    --line)
        line=$(playerctl --player="$PLAYER" metadata --format '{{title}}||{{artist}}' 2>/dev/null) || exit 0
        title=${line%%||*}
        artist=${line#*||}
        [[ -n "$title" ]] || exit 0
        if [[ -n "$artist" && "$artist" != "$title" ]]; then
            printf '%s\n' "$(escape "$title")  <span alpha='60%%'>$(escape "$artist")</span>"
        else
            escape "$title"; printf '\n'
        fi
        ;;

    # Shows the action the button performs, not the state it is in. The two
    # code points are Theme.iconPause and Theme.iconPlay, which is where they
    # were rendered and checked; a glyph in the font's cmap is not necessarily
    # the glyph its name suggests.
    --playing)
        if [[ "$(playerctl --player="$PLAYER" status 2>/dev/null)" == "Playing" ]]; then
            printf '\U0000F04C'   # Theme.iconPause
        else
            printf '\U0000F04B'   # Theme.iconPlay
        fi
        ;;

    # Cover art. LOCAL FILES ONLY: mpris:artUrl is chosen by the player, and
    # for a browser that means by the page. Fetching it would give any open
    # tab a beacon that fires while the machine is locked and unattended, and
    # a way to reach the local network. Theme.localArt refuses the same.
    #
    # A file:// URL is still checked: resolved past symlinks, under a
    # directory a player would use, capped, and actually an image.
    --art)
        url=$(playerctl --player="$PLAYER" metadata mpris:artUrl 2>/dev/null) || exit 0
        [[ "$url" == file://* ]] || exit 0

        src=$(printf '%b' "${url#file://}")   # percent-decoding
        [[ "$src" == /* && "$src" != *$'\n'* ]] || exit 0
        real=$(realpath -e -- "$src" 2>/dev/null) || exit 0
        [[ -f "$real" && -r "$real" ]] || exit 0

        allowed=0
        for root in "$HOME" /tmp /var/tmp "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"; do
            [[ -n "$root" && "$real" == "$root"/* ]] && { allowed=1; break; }
        done
        (( allowed )) || exit 0

        size=$(stat -c %s -- "$real" 2>/dev/null) || exit 0
        (( size > 0 && size <= 16777216 )) || exit 0

        if command -v file >/dev/null 2>&1; then
            [[ "$(file -Lb --mime-type -- "$real" 2>/dev/null)" == image/* ]] || exit 0
        fi

        # A stable path with changing contents: hyprlock reloads from the path
        # its reload_cmd prints and would hold a texture per track otherwise.
        cache="${XDG_CACHE_HOME:-$HOME/.cache}/hyprlock"
        mkdir -p "$cache" || exit 0
        cp -- "$real" "$cache/art.new" 2>/dev/null || exit 0
        # Renamed over: hyprlock may be reading the file as the next track lands.
        mv -f -- "$cache/art.new" "$cache/art" 2>/dev/null || { rm -f -- "$cache/art.new"; exit 0; }
        printf '%s\n' "$cache/art"
        ;;

    --toggle)   playerctl --player="$PLAYER" play-pause 2>/dev/null ;;
    --next)     playerctl --player="$PLAYER" next 2>/dev/null ;;
    --previous) playerctl --player="$PLAYER" previous 2>/dev/null ;;

    *)
        printf 'usage: %s [--line|--playing|--art|--toggle|--next|--previous]\n' "${0##*/}" >&2
        exit 2
        ;;
esac
