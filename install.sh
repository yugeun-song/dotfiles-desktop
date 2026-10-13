#!/usr/bin/env bash
#
# Installs the desktop configuration from this checkout.
#
#   ./install.sh           install
#   ./install.sh --check   report what is behind or in conflict; writes nothing
#   ./install.sh --force   install, overwriting every conflict without asking
#
# Exit status: 0 everything is in place; 1 stopped (a premise is missing, a
# conflict was kept, a write failed) or finished with steps left undone,
# listed at the end; 2 usage.
#
# The premise, checked before anything is written: Arch Linux or a
# derivative, booted with systemd, Hyprland whose Lua config loads, and
# quickshell. Outside it the paths and units here would be applied wrongly,
# so nothing is applied at all.
#
# Files are copied, not linked: nothing edited here runs until this runs
# again. A file this repository did not write (another program changed it,
# or it was there first) is a conflict: the difference is shown and the
# choice is the user's. /etc/fonts/local.conf, /etc/tuigreet/config.toml and
# the camera switch need sudo, asked for once, up front: printed as manual
# steps they never ran.
#
set -euo pipefail

SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
FONTCONF=/etc/fonts/local.conf
GREETERCONF=/etc/tuigreet/config.toml
# The camera switch (camera/): the helper pkexec runs as root, the polkit
# action that lets the seat's session run it without a password, and the udev
# rule that turns off a camera appearing while the switch is off. Root's, with
# these modes: whatever pkexec runs as root must not be writable by the user
# it runs for. source:destination:mode
CAMERA_FILES=(
    "camera/camera-switch.py:/usr/local/bin/camera-switch:755"
    "camera/io.github.yugeun-song.camera-switch.policy:/usr/share/polkit-1/actions/io.github.yugeun-song.camera-switch.policy:644"
    "camera/70-camera-switch.rules:/etc/udev/rules.d/70-camera-switch.rules:644"
)

usage() { echo "usage: ${0##*/} [--check | --force]"; }
CHECK=0
FORCE_ALL=0
for arg in "$@"; do
    case "$arg" in
        --check) CHECK=1 ;;
        --force) FORCE_ALL=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
if (( CHECK && FORCE_ALL )); then
    echo "install: --check writes nothing, so there is nothing to --force" >&2
    exit 2
fi

# XDG base directories as the spec reads them: a relative value is ignored.
xdg() { if [[ "$1" == /* ]]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }
CONFIG=$(xdg "${XDG_CONFIG_HOME:-}" "$HOME/.config")
DATA=$(xdg "${XDG_DATA_HOME:-}" "$HOME/.local/share")
STATE=$(xdg "${XDG_STATE_HOME:-}" "$HOME/.local/state")

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RED=$'\e[31m' GREEN=$'\e[32m' CYAN=$'\e[36m' BOLD=$'\e[1m' DIM=$'\e[2m' OFF=$'\e[0m'
else
    RED='' GREEN='' CYAN='' BOLD='' DIM='' OFF=''
fi

DRIFT=0
FINISHED=0
WRITTEN=0
LEFT=()
SUDO_OK=0
SUDO_KEEPALIVE=

# ------------------------------------------------------------- the premise --

# Every unmet premise at once, before any write, each with its fix.
# DOTFILES_OS_RELEASE points the tests at another os-release.
preflight() {
    local os="${DOTFILES_OS_RELEASE:-/etc/os-release}" id="" like="" problems=() env name want have verify
    if [[ -r "$os" ]]; then
        id=$(sed -n '/^ID=/{s/^ID=//;s/"//g;p;q}' "$os")
        like=$(sed -n '/^ID_LIKE=/{s/^ID_LIKE=//;s/"//g;p;q}' "$os")
    fi
    case " $id $like " in
        *" arch "*) ;;
        *) problems+=("this desktop is built on Arch Linux's packages and paths; $os says ID=${id:-unknown}${like:+, ID_LIKE=$like}") ;;
    esac
    [[ -d /run/systemd/system ]] \
        || problems+=("the session runs as systemd user units, and this system was not booted with systemd")
    command -v Hyprland >/dev/null 2>&1 && command -v hyprctl >/dev/null 2>&1 \
        || problems+=("Hyprland is not installed: pacman -S hyprland")
    command -v qs >/dev/null 2>&1 || command -v quickshell >/dev/null 2>&1 \
        || problems+=("quickshell, which draws the bar, is not installed: pacman -S quickshell")
    # Units and the session read these from the user manager's environment,
    # this script from the shell's: two answers put files where nothing reads.
    if env=$(systemctl --user show-environment 2>/dev/null); then
        for name in XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME; do
            case "$name" in
                XDG_CONFIG_HOME) want=$CONFIG; have=$(xdg "$(sed -n "s/^$name=//p" <<<"$env")" "$HOME/.config") ;;
                XDG_DATA_HOME) want=$DATA; have=$(xdg "$(sed -n "s/^$name=//p" <<<"$env")" "$HOME/.local/share") ;;
                *) want=$STATE; have=$(xdg "$(sed -n "s/^$name=//p" <<<"$env")" "$HOME/.local/state") ;;
            esac
            [[ "$want" == "$have" ]] \
                || problems+=("$name means $want here but $have to the session's user manager; set it the same in both")
        done
    fi
    # Mirroring reloads the running compositor, and a module that throws sends
    # the session to emergency mode: a config that does not load stops here.
    if (( ${#problems[@]} == 0 )); then
        verify=0
        "$SRC/hypr/scripts/verify-config.sh" "$SRC/hypr" >/dev/null 2>"$STATE_TMP" || verify=$?
        case "$verify" in
            0) ;;
            1) problems+=("the Hyprland configuration in this checkout does not load ($SRC/hypr/scripts/verify-config.sh says why)") ;;
            *) problems+=("the Hyprland configuration could not be checked: $(head -n 3 "$STATE_TMP" | tr '\n' ' ')") ;;
        esac
    fi
    (( ${#problems[@]} == 0 )) && return 0
    printf '%sinstall: the premise is not met, so nothing was %s:%s\n' "$RED" "$( (( CHECK )) && echo checked || echo written)" "$OFF" >&2
    printf '  %s\n' "${problems[@]}" >&2
    exit 1
}

# ------------------------------------------------------- ownership, conflicts --

# What this repository wrote, path to content id, so that a file it wrote and
# nothing changed since is told from one that something else wrote. Kept
# outside the repository and the config: it is about this machine.
MANIFEST_FILE="$STATE/dotfiles-desktop/installed"
declare -A MANIFEST=()
# Written only once something was recorded: a run stopped by its premise
# leaves the home directory exactly as it was.
MANIFEST_DIRTY=0
GIT=0
if command -v git >/dev/null 2>&1 && git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
    GIT=1
fi

blob() {
    if command -v git >/dev/null 2>&1; then
        git hash-object -- "$1"
    else
        sha256sum -- "$1" | cut -d' ' -f1
    fi
}

load_manifest() {
    local id path
    [[ -r "$MANIFEST_FILE" ]] || return 0
    while IFS=$'\t' read -r id path; do
        [[ -n "$id" && -n "$path" ]] && MANIFEST[$path]=$id
    done < "$MANIFEST_FILE"
    return 0
}

save_manifest() {
    local path
    (( CHECK || ! MANIFEST_DIRTY )) && return 0
    mkdir -p -- "${MANIFEST_FILE%/*}" 2>/dev/null || return 0
    {
        for path in "${!MANIFEST[@]}"; do
            printf '%s\t%s\n' "${MANIFEST[$path]}" "$path"
        done | sort -t $'\t' -k2
    } > "$MANIFEST_FILE.new" 2>/dev/null && mv -f -- "$MANIFEST_FILE.new" "$MANIFEST_FILE" \
        || echo "install: could not save $MANIFEST_FILE; the next run asks about files it cannot place" >&2
    return 0
}

record() {
    local id
    MANIFEST_DIRTY=1
    if id=$(blob "$1" 2>/dev/null); then
        MANIFEST[$1]=$id
    else
        unset 'MANIFEST[$1]'
    fi
}

# This repository wrote what is at $1 now: the source's content ($2, when
# given), what the manifest recorded there, or any version committed here
# (an install from an older checkout, or from before the manifest existed).
# A link into this checkout is an older install's.
ours() {
    local to=$1 from=${2:-} id
    if [[ -L "$to" ]]; then
        [[ "$(readlink -f -- "$to")" == "$SRC"/* ]]
        return
    fi
    [[ -f "$to" ]] || return 1
    [[ -n "$from" ]] && cmp -s -- "$from" "$to" && return 0
    id=$(blob "$to") || return 1
    [[ "${MANIFEST[$to]:-}" == "$id" ]] && return 0
    (( GIT )) && git -C "$SRC" cat-file -e "$id^{blob}" 2>/dev/null
}

# diff -u with each line numbered on both sides, drawn as dotfiles-terminal
# draws it:
#   --- <target> (installed)
#   +++ <source> (repository)
#   @@ -12,3 +12,4 @@
#      12    12 │  kept
#      13       │ -removed
#            13 │ +added
show_diff() {
    { diff -u -- "$1" "$2" 2>&1 || :; } | awk -v red="$RED" -v green="$GREEN" -v cyan="$CYAN" \
        -v dim="$DIM" -v reset="$OFF" -v old_label="$3" -v new_label="$4" '
        NR == 1 && /^--- /    { printf "%s--- %s%s\n", red, old_label, reset; next }
        NR == 2 && /^\+\+\+ / { printf "%s+++ %s%s\n", green, new_label, reset; next }
        /^@@ / {
            split($2, o, ","); split($3, n, ",")
            old = substr(o[1], 2) + 0; new = substr(n[1], 2) + 0
            printf "%s%s%s\n", cyan, $0, reset; next
        }
        /^-/  { printf "%s%5s %5s │ %s%s\n", red, old, "", $0, reset; old++; next }
        /^\+/ { printf "%s%5s %5s │ %s%s\n", green, "", new, $0, reset; new++; next }
        /^ /  { printf "%5s %5s │ %s\n", old, new, $0; old++; new++; next }
        { printf "%s%s%s\n", dim, $0, reset }'
}

# The user's call on one conflict, from the terminal: y goes ahead, a goes
# ahead with this and every later one, n stops the install here. Without a
# terminal to ask on, n.
ask() {
    local verb=$1 target=$2 answer
    if ! { exec 3</dev/tty; } 2>/dev/null; then
        stop "$target is not what this repository installed; run ./install.sh in a terminal to choose, or with --force"
    fi
    while true; do
        printf '%s %s? [y] yes  [n] no, keep it and stop  [a] all, this and every later conflict: ' \
            "$verb" "$target" >/dev/tty
        IFS= read -r answer <&3 || answer=n
        case "${answer,,}" in
            y|yes) exec 3<&-; return 0 ;;
            a|all) FORCE_ALL=1; exec 3<&-; return 0 ;;
            n|no)  exec 3<&-; stop "kept $target as it is; nothing after it was installed" ;;
        esac
    done
}

# Before $1 is overwritten with $2 (shown as $3), or removed when $2 is
# empty. Returns only to go ahead.
claim() {
    local to=$1 from=${2:-} label=${3:-}
    ours "$to" "$from" && return 0
    if [[ -d "$to" && ! -L "$to" ]]; then
        stop "$to is a directory where this repository installs a file; move it away and run again"
    fi
    if (( FORCE_ALL )); then
        echo "forced $to"
        return 0
    fi
    printf '\n%sconflict%s  %s: not what this repository installed\n' "$BOLD$RED" "$OFF" "$to"
    if [[ -n "$from" ]]; then
        show_diff "$to" "$from" "$to (installed)" "$label (repository)"
        ask Overwrite "$to"
    else
        show_diff "$to" /dev/null "$to (installed)" "/dev/null (removed from the repository)"
        ask Remove "$to"
    fi
}

# Write beside and rename over, then record it. bash reads a running script
# lazily, so overwriting session-watch.sh in place corrupts it mid-run; and
# Hyprland reloads on write and could read a half-copied module.
put() {
    local from=$1 to=$2
    mkdir -p -- "$(dirname -- "$to")" || stop "could not create $(dirname -- "$to")"
    if ! { cp -a -- "$from" "$to.new-$$" && mv -T -- "$to.new-$$" "$to"; }; then
        rm -f -- "$to.new-$$"
        stop "could not write $to"
    fi
    record "$to"
    WRITTEN=$((WRITTEN + 1))
}

stop() {
    printf '%sinstall: %s%s\n' "$RED" "$*" "$OFF" >&2
    exit 1
}

# On every exit: the sudo keepalive goes, the manifest keeps what was
# written (a stopped run included), and a run cut short says so.
cleanup() {
    local code=$?
    [[ -n "$SUDO_KEEPALIVE" ]] && kill "$SUDO_KEEPALIVE" 2>/dev/null
    # The timestamp this run kept alive would let anything on this terminal
    # use sudo without a password for minutes more.
    (( SUDO_OK )) && sudo -k 2>/dev/null
    save_manifest
    rm -f -- "$STATE_TMP"
    if (( ! FINISHED && code == 1 && ! CHECK )); then
        echo "install: stopped; what was installed before this point stays (${WRITTEN} files written)" >&2
    elif (( ! FINISHED && code != 0 && code != 2 )); then
        echo "install: a command failed (status $code); what was installed before it stays" >&2
    fi
    return 0
}
STATE_TMP=$(mktemp)
trap cleanup EXIT
trap 'stop "interrupted"' INT TERM

# ---------------------------------------------------------------- mirror, seed --

# For what this repository authors: overwritten on every run, unless what is
# there is not what this repository wrote (a conflict). Not symlinked, because
# a link resolves back into the working tree.
mirror() {
    local from=$1 to=$2
    MIRROR_CHANGED=0
    [[ -e "$from" ]] || stop "missing source: $from"
    if [[ -d "$from" ]]; then
        mirror_dir "$from" "$to"
        return 0
    fi
    if [[ -f "$to" && ! -L "$to" ]] && cmp -s -- "$from" "$to"; then
        (( CHECK )) && return 0
        record "$to"
        echo "unchanged $to"
        return 0
    fi
    if (( CHECK )); then
        if [[ ! -e "$to" && ! -L "$to" ]]; then
            echo "DRIFT    $to is missing"
        elif ours "$to" "$from"; then
            echo "DRIFT    $to is behind $from"
        else
            echo "CONFLICT $to is not what this repository installed"
        fi
        DRIFT=1
        return 0
    fi
    [[ -e "$to" || -L "$to" ]] && claim "$to" "$from" "${from#"$SRC"/}"
    [[ -L "$to" ]] && rm -f -- "$to"
    put "$from" "$to"
    MIRROR_CHANGED=1
    echo "installed $to"
}

# A directory is updated file by file, never swapped whole: quickshell
# crashes if its directory is replaced underneath it. New files go in before
# changed ones: quickshell reloads on every write, and a module updated to
# use a component that has not landed yet fails that reload. Only files that
# differ are written, since every write is a reload. Files the repository
# dropped are removed when it put them there; anything else is left.
# Every path the repository had under a source directory, at any commit.
history_paths() {
    local rel=${1#"$SRC"/}
    (( GIT )) || return 0
    {
        git -C "$SRC" log --all --format= --name-only --no-renames -- "$rel" 2>/dev/null || :
        git -C "$SRC" ls-files -- "$rel" 2>/dev/null || :
    } | awk -v prefix="$rel/" 'index($0, prefix) == 1 { print substr($0, length(prefix) + 1) }'
}

mirror_dir() {
    local from=$1 to=$2 rel pass target label
    local -a found=()
    local -A known=()
    if (( CHECK )); then
        while IFS= read -r -d '' rel; do
            rel=${rel#./}
            [[ -d "$from/$rel" && ! -L "$from/$rel" ]] && continue
            target="$to/$rel"
            if [[ -f "$target" && ! -L "$target" ]] && cmp -s -- "$from/$rel" "$target"; then
                continue
            elif [[ ! -e "$target" && ! -L "$target" ]]; then
                echo "DRIFT    $target is missing"
            elif ours "$target" "$from/$rel"; then
                echo "DRIFT    $target is behind"
            else
                echo "CONFLICT $target is not what this repository installed"
            fi
            DRIFT=1
        done < <(cd -- "$from" && find . -mindepth 1 -print0)
        if [[ -d "$to" ]]; then
            while IFS= read -r -d '' rel; do
                rel=${rel#./}
                [[ -e "$from/$rel" || -L "$from/$rel" ]] && continue
                if ours "$to/$rel"; then
                    echo "DRIFT    $to/$rel is no longer in the repository"
                    DRIFT=1
                fi
            done < <(cd -- "$to" && find . -mindepth 1 \( -type f -o -type l \) -print0)
        fi
        return 0
    fi

    [[ -L "$to" ]] && rm -f -- "$to"
    [[ -e "$to" && ! -d "$to" ]] && claim "$to" && rm -f -- "$to"
    mkdir -p -- "$to"
    for pass in new changed; do
        while IFS= read -r -d '' rel; do
            rel=${rel#./}
            target="$to/$rel"
            if [[ -d "$from/$rel" && ! -L "$from/$rel" ]]; then
                mkdir -p -- "$target"
                continue
            fi
            if [[ "$pass" == new ]]; then
                [[ -e "$target" || -L "$target" ]] && continue
            else
                [[ -e "$target" || -L "$target" ]] || continue
                if [[ -f "$target" && ! -L "$target" ]] && cmp -s -- "$from/$rel" "$target"; then
                    record "$target"
                    continue
                fi
                label="${from#"$SRC"/}/$rel"
                claim "$target" "$from/$rel" "$label"
                [[ -L "$target" ]] && rm -f -- "$target"
            fi
            put "$from/$rel" "$target"
            MIRROR_CHANGED=1
        done < <(cd -- "$from" && find . -mindepth 1 -print0)
    done
    while IFS= read -r -d '' rel; do
        found+=("${rel#./}")
    done < <(cd -- "$to" && find . -mindepth 1 \( -type f -o -type l \) -print0)
    while IFS= read -r rel; do
        known[$rel]=1
    done < <(history_paths "$from")
    for rel in "${found[@]}"; do
        target="$to/$rel"
        [[ -e "$from/$rel" || -L "$from/$rel" ]] && continue
        if ours "$target" || [[ -n "${MANIFEST[$target]:-}" || -n "${known[$rel]:-}" ]]; then
            claim "$target"
            rm -f -- "$target"
            unset 'MANIFEST[$target]'
            MANIFEST_DIRTY=1
            echo "removed stale $target"
            MIRROR_CHANGED=1
        else
            echo "${DIM}left     $target: not from this repository${OFF}"
        fi
    done
    while IFS= read -r -d '' rel; do
        rel=${rel#./}
        [[ -e "$from/$rel" ]] && continue
        rmdir -- "$to/$rel" 2>/dev/null && echo "removed stale $to/$rel/"
    done < <(cd -- "$to" && find . -mindepth 1 -depth -type d -print0)
    if (( MIRROR_CHANGED )); then echo "installed $to"; else echo "unchanged $to"; fi
}

# For what a program owns: copied once, never overwritten. fcitx5, KDE and GTK
# save by rename() over the target, which replaces a symlink rather than
# following it. To take a change back, copy it into the repository; to push one
# out, delete the installed file and run again.
seed() {
    local from="$1" to="$2"
    [[ -e "$from" ]] || stop "missing source: $from"
    if (( CHECK )); then
        if [[ ! -e "$to" ]]; then
            echo "absent   $to would be seeded"
        elif ! diff -rq "$from" "$to" >/dev/null 2>&1; then
            echo "owned    $to differs; the program owns it, so $from is not what runs"
        fi
        return 0
    fi
    # A link from an older install becomes a real file.
    if [[ -L "$to" ]]; then
        rm -f -- "$to"
        mkdir -p -- "$(dirname -- "$to")"
        cp -a -- "$from" "$to" || stop "could not seed $to"
        echo "unlinked and seeded $to"
        return 0
    fi
    if [[ -e "$to" ]]; then
        if diff -rq "$from" "$to" >/dev/null 2>&1; then
            echo "already seeded $to"
        else
            echo "left $to alone: the program owns it; copy it back into $from to keep a change"
        fi
        return 0
    fi
    mkdir -p -- "$(dirname -- "$to")"
    cp -a -- "$from" "$to" || stop "could not seed $to"
    echo "seeded $to"
}

# --------------------------------------------------------- system files, sudo --

# tuigreet/config.toml means nothing to another greeter, so it is installed
# only when greetd's command is tuigreet and tuigreet is installed.
greeter_is_tuigreet() {
    [[ -r /etc/greetd/config.toml ]] || return 1
    grep -qE '^[[:space:]]*command[[:space:]]*=.*\btuigreet\b' /etc/greetd/config.toml || return 1
    command -v tuigreet >/dev/null 2>&1
}

# source:destination:mode for every root-owned file this machine should have.
system_files() {
    printf '%s\n' "fontconfig/local.conf:$FONTCONF:644"
    greeter_is_tuigreet && printf '%s\n' "tuigreet/config.toml:$GREETERCONF:644"
    printf '%s\n' "${CAMERA_FILES[@]}"
}

system_current() {
    cmp -s -- "$SRC/$1" "$2" && [[ "$(stat -c '%a %U' -- "$2" 2>/dev/null)" == "$3 root" ]]
}

acquire_sudo() {
    local src dst mode want=0
    while IFS=: read -r src dst mode; do
        system_current "$src" "$dst" "$mode" || want=1
    done < <(system_files)
    if (( ! want )); then
        echo "system files already installed"
        return 0
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        echo "install: sudo is not installed, so the system files are left for the end" >&2
        return 0
    fi
    if sudo -v 2>/dev/null; then
        SUDO_OK=1
        # Kept alive: a cold run can outlast sudo's timestamp.
        ( while true; do sudo -n true 2>/dev/null; sleep 50; done ) &
        SUDO_KEEPALIVE=$!
    else
        echo "install: no sudo here, so the system files are left for the end" >&2
    fi
}

# One root-owned file. Content another hand wrote is a conflict, as in the
# home directory, and its previous copy is kept beside it as .bak-<time>.
system_file() {
    local rel=$1 dst=$2 mode=$3
    if system_current "$rel" "$dst" "$mode"; then
        (( CHECK )) || record "$dst"
        return 1
    fi
    if (( CHECK )); then
        if [[ -e "$dst" ]] && ! cmp -s -- "$SRC/$rel" "$dst" && ! ours "$dst" "$SRC/$rel"; then
            echo "CONFLICT $dst is not what this repository installed"
        else
            echo "DRIFT    $dst is behind $SRC/$rel"
        fi
        DRIFT=1
        return 1
    fi
    if (( ! SUDO_OK )); then
        LEFT+=("sudo install -D -o root -g root -m $mode '$SRC/$rel' $dst")
        return 1
    fi
    if [[ -e "$dst" ]] && ! cmp -s -- "$SRC/$rel" "$dst"; then
        if ! ours "$dst" "$SRC/$rel"; then
            claim "$dst" "$SRC/$rel" "$rel"
            sudo cp -a -- "$dst" "$dst.bak-$STAMP" && echo "kept the previous $dst at $dst.bak-$STAMP"
        fi
    fi
    sudo install -D -o root -g root -m "$mode" -- "$SRC/$rel" "$dst" || stop "could not write $dst"
    record "$dst"
    echo "installed $dst"
    return 0
}

# ------------------------------------------------------------------- doctor --

# What this desktop uses beyond the premise, checked rather than assumed: the
# preset is one laptop's, the next one may lack a font or a tool, and every
# script degrades on its own but says so only when its key is pressed.
# Advisory: nothing here changes the exit status.
doctor() {
    local missing=() font tool families
    # Listed once: grep -q closing the pipe early would trip pipefail.
    families=$(fc-list : family 2>/dev/null || true)
    for font in "Inter" "Pretendard" "CaskaydiaCove Nerd Font"; do
        grep -qiF -- "$font" <<<"$families" || missing+=("font $font")
    done
    local tools=(
        "grim:screenshots" "slurp:region capture" "wl-copy:clipboard" "cliphist:clipboard history"
        "brightnessctl:brightness keys on the panel" "ddcutil:brightness on external displays"
        "playerctl:media keys" "wpctl:volume keys" "hyprlock:lock screen" "hypridle:lock before sleep"
        "hyprpaper:wallpaper" "fcitx5:Korean input" "jq:the Displays panel and every script that reads hyprctl"
        "python3:key overlay, input method indicator, camera switch and cursor theme" "pkexec:the camera keys"
        "udevadm:the camera indicator" "cava:visualiser" "notify-send:notifications from scripts"
        "kitty:terminal" "inotifywait:session watch (polls every 5 s without it)"
    )
    for tool in "${tools[@]}"; do
        command -v "${tool%%:*}" >/dev/null 2>&1 || missing+=("${tool%%:*} (${tool#*:})")
    done
    if (( ${#missing[@]} == 0 )); then
        echo "doctor: every font and tool the desktop uses is present"
        return 0
    fi
    printf 'doctor: missing %s\n' "${missing[@]}"
}

# ===================================================================== run ==

preflight
load_manifest
if (( ! CHECK )); then
    # Two runs at once would interleave their writes and their manifests.
    mkdir -p -- "${MANIFEST_FILE%/*}" || stop "could not create ${MANIFEST_FILE%/*}"
    exec 9>"${MANIFEST_FILE%/*}/lock"
    flock -n 9 || stop "another ./install.sh is running"
    acquire_sudo
fi

mirror "$SRC/quickshell/bar"         "$CONFIG/quickshell/bar"
# The reloads on write above can miss files: quickshell reads the whole tree
# when a reload starts and watches again only when it ends, and a file
# renamed over a watched one sometimes went unseen altogether. One more
# reload, asked for after the last file, reads the finished tree. A reload
# still under way builds the shell over several turns of its event loop, its
# IPC targets appearing one by one, so the "shell" target is looked for a few
# times before the bar is taken for one from before the call.
if (( ! CHECK && MIRROR_CHANGED )); then
    _bar_state=none
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        _bar_targets=$(qs -p "$CONFIG/quickshell/bar" ipc show 2>/dev/null) || { _bar_state=none; break; }
        if grep -qx "target shell" <<<"$_bar_targets"; then
            _bar_state=ready
            break
        fi
        _bar_state=old
        sleep 0.3
    done
    case "$_bar_state" in
        ready)
            qs -p "$CONFIG/quickshell/bar" ipc call shell reload >/dev/null 2>&1 \
                && echo "reloaded the running bar" ;;
        old)
            echo "install: the running bar cannot be asked to reload yet; run: bar --restart" >&2 ;;
    esac
    unset _bar_targets _bar_state
fi

# config/ before hyprland.lua, then an explicit reload. Hyprland reloads on
# writes to files it has already loaded only, so a hyprland.lua that requires a
# not-yet-copied module leaves the session in emergency mode. The state dir is
# where monitors.lua caches output descriptions; the module cannot create it.
(( CHECK )) || mkdir -p -- "$STATE/hypr"
mirror "$SRC/hypr/config"            "$CONFIG/hypr/config"
mirror "$SRC/hypr/scripts"           "$CONFIG/hypr/scripts"
# The tracked preset, and the untracked per-machine deviations if this
# checkout has any. Before the preset existed the installed
# monitor_settings.lua was one machine's own file: one that differs from the
# preset and from every committed version becomes the local file (which wins
# per field), so its values survive; an existing local file is kept and the
# old one backed up beside it.
_old_settings="$CONFIG/hypr/monitor_settings.lua"
_local_settings="$CONFIG/hypr/monitor_settings.local.lua"
if [[ -f "$_old_settings" ]] && ! ours "$_old_settings" "$SRC/hypr/monitor_settings.lua" \
   && [[ ! -f "$SRC/hypr/monitor_settings.local.lua" ]]; then
    if (( CHECK )); then
        echo "DRIFT    $_old_settings is a per-machine file from before the preset; install moves it to $_local_settings"; DRIFT=1
    elif [[ -f "$_local_settings" ]]; then
        cp -a -- "$_old_settings" "$_local_settings.bak-$STAMP"
        echo "kept the old $_old_settings as $_local_settings.bak-$STAMP (a local file already exists)"
    else
        mv -- "$_old_settings" "$_local_settings"
        echo "moved the old $_old_settings to $_local_settings: its values still win over the preset"
    fi
fi
unset _old_settings _local_settings
mirror "$SRC/hypr/monitor_settings.lua" "$CONFIG/hypr/monitor_settings.lua"
if [[ -f "$SRC/hypr/monitor_settings.local.lua" ]]; then
    mirror "$SRC/hypr/monitor_settings.local.lua" "$CONFIG/hypr/monitor_settings.local.lua"
fi
mirror "$SRC/hypr/hyprland.lua"      "$CONFIG/hypr/hyprland.lua"
# Installed by older versions; removed so they cannot mislead.
_retired_files=("$CONFIG/hypr/monitors.preset")
for _retired in "${_retired_files[@]}"; do
    [[ -e "$_retired" ]] || continue
    if (( CHECK )); then
        echo "DRIFT    $_retired is no longer used"; DRIFT=1
    else
        rm -f -- "$_retired" && echo "removed retired $_retired"
    fi
done
unset _retired _retired_files
if (( ! CHECK )); then
    if hyprctl version >/dev/null 2>&1; then
        if hyprctl reload >/dev/null 2>&1; then
            echo "reloaded the running compositor"
        else
            echo "install: could not reload the running compositor; run: hyprctl reload" >&2
        fi
    else
        echo "no compositor reachable from here; a running session picks this up at its next hyprctl reload"
    fi
fi
seed "$SRC/hypr/hypridle.conf"     "$CONFIG/hypr/hypridle.conf"
seed "$SRC/hypr/hyprlock.conf"     "$CONFIG/hypr/hyprlock.conf"
seed "$SRC/hypr/hyprpaper.conf"    "$CONFIG/hypr/hyprpaper.conf"
# ~/.local/bin, not an XDG directory: the units and keybinds name these by
# that path, and the terminal configuration puts it on PATH.
mirror "$SRC/bin/bar"               "$HOME/.local/bin/bar"
mirror "$SRC/bin/unlock"            "$HOME/.local/bin/unlock"
# In ~ on purpose: typed from a text console where PATH may not be set up.
mirror "$SRC/bin/recover-desktop"   "$HOME/recover-desktop"
# The camera switch's user copy: `camera-switch` from a terminal, and what
# the camera keys fall back to until the sudo step has installed the
# root-owned one; it works, but asks for an administrator password each time.
mirror "$SRC/camera/camera-switch.py" "$HOME/.local/bin/camera-switch"
# mirror() keeps the checkout's mode, and an archive or core.fileMode=false
# tree arrives at 644.
if (( ! CHECK )); then
    chmod +x "$HOME/.local/bin/bar" "$HOME/.local/bin/unlock" "$HOME/.local/bin/camera-switch" \
        "$HOME/recover-desktop" || stop "could not make the programs in ~/.local/bin executable"
fi

# Units are mirrored, then daemon-reload below. Running units are not
# restarted (restarting fcitx5 drops every window's input context); the next
# login or session-start.sh picks them up.
for _unit in "$SRC"/systemd/user/*; do
    mirror "$_unit" "$CONFIG/systemd/user/$(basename "$_unit")"
done
unset _unit
# The unit directory is shared with other packages, so only units whose first
# line is the "# dotfiles-desktop" marker and whose source is gone are removed.
for _installed in "$CONFIG"/systemd/user/*.service "$CONFIG"/systemd/user/*.target "$CONFIG"/systemd/user/*.slice; do
    [[ -f "$_installed" ]] || continue
    [[ -e "$SRC/systemd/user/$(basename "$_installed")" ]] && continue
    [[ "$(head -n 1 "$_installed" 2>/dev/null)" == "# dotfiles-desktop" ]] || continue
    if (( CHECK )); then
        echo "DRIFT    $_installed is no longer in the repository"; DRIFT=1
    else
        rm -f -- "$_installed" && echo "removed retired $_installed"
    fi
done
unset _installed

# Overrides /usr/share's fcitx5 D-Bus activation to start the unit instead.
mirror "$SRC/dbus/services/org.fcitx.Fcitx5.service" "$DATA/dbus-1/services/org.fcitx.Fcitx5.service"

# XCursor themes are bitmaps, so the colour is baked in at build time. The tint
# comes from pointer.py's FILL so the redrawn arrow and every other shape match.
# Failure is not fatal; the previous pointer stays.
if (( ! CHECK )); then
    cursor_tint=$(sed -n 's/^FILL = "\(#[0-9a-fA-F]\{6\}\)".*/\1/p' "$SRC/theme/cursor/pointer.py" | head -1)
    if [[ -z "$cursor_tint" ]]; then
        echo "install: no FILL in pointer.py; the cursor theme was not built" >&2
    elif "$SRC/theme/cursor/tint-cursors.py" --from Oxygen_White --name Spaceduck-Sky --tint "$cursor_tint" \
           --comment "Oxygen_White recoloured to the drawn pointer's blue"; then
        "$SRC/theme/cursor/pointer.py" --theme Spaceduck-Sky \
            || echo "install: the arrow stayed as the tint left it" >&2
        # Enlarges the drag shapes; reasoning in the script.
        "$SRC/theme/cursor/emphasise.py" --theme Spaceduck-Sky \
            || echo "install: the drag cursors were left at theme size" >&2
    else
        echo "install: could not build the cursor theme; the pointer is unchanged" >&2
    fi
    unset cursor_tint
fi
# The REPL helpers for node and IEx (~/.config/node, profile.d/node.sh,
# ~/.iex.exs) are dotfiles-terminal's alone: a file mirrored from both
# repositories was whatever the last installer to run left there.
mirror "$SRC/spotify/spotify-launcher.conf" "$CONFIG/spotify-launcher.conf"
seed "$SRC/fcitx5/config"          "$CONFIG/fcitx5/config"
seed "$SRC/fcitx5/profile"         "$CONFIG/fcitx5/profile"
seed "$SRC/fcitx5/conf"            "$CONFIG/fcitx5/conf"
seed "$SRC/gtk/gtk-3.0-settings.ini" "$CONFIG/gtk-3.0/settings.ini"
seed "$SRC/gtk/gtk-4.0-settings.ini" "$CONFIG/gtk-4.0/settings.ini"
seed "$SRC/kde/kdeglobals"        "$CONFIG/kdeglobals"
seed "$SRC/kde/kded5rc"           "$CONFIG/kded5rc"
seed "$SRC/kde/baloofilerc"       "$CONFIG/baloofilerc"
seed "$SRC/kde/SpaceduckDark.colors" "$DATA/color-schemes/SpaceduckDark.colors"

if (( ! CHECK )); then
    # Baloo off, second half (see kde/baloofilerc): the config key only fails
    # the unit's ExecCondition, so disable it to stop the start/stop at every
    # login. drkonqi runs from a user unit with no Wayland display, so Qt
    # aborts it, and its own coredump launches it again (one crash left 1.1 GB
    # of cores): masked; coredumpctl still works. No-ops where absent.
    systemctl --user disable kde-baloo.service >/dev/null 2>&1 || true
    for _u in drkonqi-coredump-launcher.socket drkonqi-coredump-pickup.service \
              drkonqi-coredump-cleanup.timer drkonqi-sentry-postman.path drkonqi-sentry-postman.timer; do
        systemctl --user disable --now "$_u" >/dev/null 2>&1 || true
        systemctl --user mask "$_u" >/dev/null 2>&1 || true
    done
    unset _u
    systemctl --user daemon-reload 2>/dev/null \
        || echo "install: could not reload the user manager; the units apply at the next login" >&2
    # hypridle uses its packaged unit; enabling hooks it to graphical-session.target.
    systemctl --user enable hypridle.service >/dev/null 2>&1 \
        || LEFT+=("systemctl --user enable hypridle.service (it failed here; without it the screen does not lock before sleep)")

    # cp -a keeps the checkout's mode, and an archive or core.fileMode=false
    # tree arrives at 644.
    for _f in "$CONFIG/quickshell/bar/scripts"/*.{sh,py} "$CONFIG/hypr/scripts"/*.sh; do
        [[ -f "$_f" ]] || continue
        chmod +x -- "$_f" || stop "could not make $_f executable"
    done
    unset _f
fi

# Root's files last: everything above works without them.
echo
_fonts=0
_camera=0
while IFS=: read -r _src _dst _mode; do
    if system_file "$_src" "$_dst" "$_mode"; then
        [[ "$_dst" == "$FONTCONF" ]] && _fonts=1
        [[ "$_src" == camera/* ]] && _camera=1
    fi
done < <(system_files)
if (( _fonts )); then
    sudo fc-cache -f >/dev/null 2>&1 && echo "font cache rebuilt"
fi
# polkit watches its action directory; udev is told, so the rule holds from
# the next event on.
if (( _camera )); then
    sudo udevadm control --reload 2>/dev/null && echo "udev rules reloaded"
fi
if (( ! CHECK && ! SUDO_OK && ${#LEFT[@]} )) && [[ "${LEFT[*]}" == *"$SRC/camera/"* ]]; then
    LEFT+=("sudo udevadm control --reload")
fi
greeter_is_tuigreet || echo "greeter: not tuigreet, so $GREETERCONF is left alone"
unset _src _dst _mode _fonts _camera

echo
doctor
FINISHED=1
if (( CHECK )); then
    if (( DRIFT )); then
        echo
        echo "run ./install.sh to apply"
        exit 1
    fi
    echo "everything installed is current"
    exit 0
fi
if (( ${#LEFT[@]} )); then
    echo
    echo "${BOLD}left undone${OFF} (${WRITTEN} files written):"
    printf '  %s\n' "${LEFT[@]}"
    exit 1
fi
echo "everything is in place (${WRITTEN} files written)"
