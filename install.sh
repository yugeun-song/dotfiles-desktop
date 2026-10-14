#!/usr/bin/env bash
#
# Installs the desktop configuration from this checkout, and updates an
# installed one: run it again after a pull. Only files that differ are
# written, and only what they belong to is reloaded or rebuilt.
#
#   ./install.sh           install or update
#   ./install.sh --check   report what is behind or in conflict; writes nothing
#   ./install.sh --force   install, overwriting every conflict without asking
#
# Exit status: 0 everything is in place; 1 stopped (a premise is missing, a
# conflict was kept, a write failed) or finished with steps left undone,
# listed at the end; 2 usage.
#
# The premise, checked before anything is written: a distribution this
# script recognises (Arch is the one tested; Debian/Ubuntu, Fedora/RHEL,
# openSUSE, Gentoo, Void and Alpine are known by their package managers),
# booted with systemd, GNU coreutils, Hyprland 0.56 or later whose Lua config
# loads, and quickshell. Outside it the paths and units here would be applied
# wrongly, so nothing is applied at all.
#
# Files are copied, not linked: nothing edited here runs until this runs
# again. A file this repository did not write (another program changed it,
# or it was there first) is a conflict: the difference is shown and the
# choice is the user's. /etc/fonts/local.conf, /etc/tuigreet/config.toml,
# the camera switch and the key overlay's reader need sudo, asked for once,
# up front: printed as manual steps when it never ran.
#
# Test hooks: DOTFILES_OS_RELEASE replaces /etc/os-release, DOTFILES_SYSTEMD
# replaces /run/systemd/system, and DOTFILES_ROOT goes in front of root's
# files and greetd's config, so a test never reads this machine's.
#
set -euo pipefail
# Under a umask of 002 (Fedora's and Ubuntu's, for user private groups) the
# directories made here would be group-writable; nothing here should be.
umask 022

SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
ROOT=${DOTFILES_ROOT:-}
FONTCONF=$ROOT/etc/fonts/local.conf
GREETERCONF=$ROOT/etc/tuigreet/config.toml
# The camera switch (camera/): the helper pkexec runs as root, the polkit
# actions that let the seat's session turn cameras off without a password
# (and on with one), and the udev rule that turns off a camera appearing
# while the switch is off. Root's, with these modes: whatever pkexec runs as
# root must not be writable by the user it runs for. source:destination:mode
CAMERA_FILES=(
    "camera/camera-switch.py:$ROOT/usr/local/bin/camera-switch:755"
    "camera/io.github.yugeun-song.camera-switch.policy:$ROOT/usr/share/polkit-1/actions/io.github.yugeun-song.camera-switch.policy:644"
    "camera/70-camera-switch.rules:$ROOT/etc/udev/rules.d/70-camera-switch.rules:644"
)
# The key overlay's reader (keyfeed/), which pkexec runs as root once an
# administrator's password is given: then no group of the user's has to read
# the keyboards. Root's, as the camera switch's helper is, and for the same
# reason.
KEYFEED_FILES=(
    "keyfeed/keyfeed.py:$ROOT/usr/local/libexec/keyfeed:755"
    "keyfeed/io.github.yugeun-song.keyfeed.policy:$ROOT/usr/share/polkit-1/actions/io.github.yugeun-song.keyfeed.policy:644"
)
HYPRLAND_MIN=0.56

usage() {
    cat <<EOF
usage: ${0##*/} [--check | --force]
  (none)    install or update, asking before overwriting anything this repository did not install
  --check   report what is behind or in conflict; writes nothing, exit 1 if anything is
  --force   overwrite conflicts without asking
EOF
}
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

# Colour only for a terminal, and never when NO_COLOR asks for none. The
# glyphs (a check, a cross, tree lines) stay either way: they carry meaning.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RED=$'\e[31m' GREEN=$'\e[32m' YELLOW=$'\e[33m' CYAN=$'\e[36m' BOLD=$'\e[1m' DIM=$'\e[2m' RESET=$'\e[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' DIM='' RESET=''
fi

DRIFT=0
FINISHED=0
WRITTEN=0
UNCHANGED=0
CONFLICTED=0
LEFT=()
NOTES=()
PROBLEMS=()
SEEDS_DIFFER=0
SUDO_OK=0
SUDO_KEEPALIVE=
FAMILY="" PRETTY=""

# ------------------------------------------------------------------ output --

# $HOME as ~, so a line names the path a user would type.
tilde() {
    if [[ "$1" == "$HOME" || "$1" == "$HOME"/* ]]; then printf '~%s' "${1#"$HOME"}"; else printf '%s' "$1"; fi
}

# Each step is a tree: its label once there is something to say, one branch
# per change, and a last branch with the count. A step with nothing to say is
# one dim line, so an update that changed little prints little.
GROUP_LABEL="" GROUP_SHOWN=0 GROUP_WROTE=0 GROUP_SAME=0 GROUP_TODO=0 GROUP_OWNER=""
# $2 names what reloads the group's files: bar, compositor or units.
group_open() {
    GROUP_LABEL=$1 GROUP_OWNER=${2:-} GROUP_SHOWN=0 GROUP_WROTE=0 GROUP_SAME=0 GROUP_TODO=0
}
group_label() {
    (( GROUP_SHOWN )) && return 0
    printf '%s%s%s\n' "$BOLD" "$GROUP_LABEL" "$RESET"
    GROUP_SHOWN=1
}
branch() {
    group_label
    printf '%s├──%s %s\n' "$DIM" "$RESET" "$1"
}
group_close() {
    local tally
    if (( CHECK )); then
        if (( GROUP_TODO )); then tally="$GROUP_TODO to apply"; else tally=current; fi
    elif (( GROUP_WROTE )); then
        tally="$GROUP_WROTE written, $GROUP_SAME unchanged"
    elif (( GROUP_SAME )); then
        tally="$GROUP_SAME unchanged"
    else
        tally=unchanged
    fi
    if (( GROUP_SHOWN )); then
        printf '%s└── %s%s\n' "$DIM" "$tally" "$RESET"
    else
        printf '%s%s  %s%s\n' "$DIM" "$GROUP_LABEL" "$tally" "$RESET"
    fi
    GROUP_SHOWN=0
}
# A plain list as a tree under a heading already printed.
tree_lines() {
    local colour=$1 i n
    shift
    n=$#
    for (( i = 1; i <= n; i++ )); do
        if (( i < n )); then
            printf '%s├──%s %s%s%s\n' "$DIM" "$RESET" "$colour" "${!i}" "$RESET"
        else
            printf '%s└──%s %s%s%s\n' "$DIM" "$RESET" "$colour" "${!i}" "$RESET"
        fi
    done
}

same() { UNCHANGED=$((UNCHANGED + 1)); GROUP_SAME=$((GROUP_SAME + 1)); }

# A group whose files changed but whose owner was not reloaded (the run
# stopped in between, or the reload failed) leaves a mark before its first
# write, so a later run reloads it even when it writes nothing.
PENDING_DIR="$STATE/dotfiles-desktop"
mark_pending() {
    if (( CHECK )) || [[ -z "$GROUP_OWNER" || -e "$PENDING_DIR/pending-$GROUP_OWNER" ]]; then return 0; fi
    { mkdir -p -- "$PENDING_DIR" && : >"$PENDING_DIR/pending-$GROUP_OWNER"; } 2>/dev/null || :
}
pending() { [[ -e "$PENDING_DIR/pending-$1" ]]; }
settled() { rm -f -- "$PENDING_DIR/pending-$1"; }
todo() { GROUP_TODO=$((GROUP_TODO + 1)); DRIFT=1; branch "$1"; }
# A write or a removal, said in its group; one that followed a conflict is
# marked as such.
wrote() {
    WRITTEN=$((WRITTEN + 1))
    GROUP_WROTE=$((GROUP_WROTE + 1))
    if (( CONFLICTED )); then
        branch "${YELLOW}${2:-overwritten} after a conflict: $1$RESET"
    elif [[ -n "${2:-}" ]]; then
        branch "$GREEN✓$RESET $2 $1"
    else
        branch "$GREEN✓$RESET $1"
    fi
    CONFLICTED=0
}

# ------------------------------------------------------------- the premise --

os_release_field() {
    local key=$1 file=$2 line value=""
    # A last line without a newline still counts.
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "$key="* ]]; then
            value=${line#*=}
            value=${value#[\"\']}
            value=${value%[\"\']}
        fi
    done <"$file"
    printf '%s' "$value"
}

# The family names the package manager messages point at. ID first, then the
# ID_LIKE words, so a derivative is known by its parent.
distro_family() {
    local word
    for word in "$@"; do
        case "$word" in
            arch|manjaro|endeavouros|cachyos|garuda|artix) echo arch; return 0 ;;
            debian|ubuntu|linuxmint|pop|elementary|zorin|kali|raspbian) echo debian; return 0 ;;
            fedora|rhel|centos|rocky|almalinux|ol) echo fedora; return 0 ;;
            opensuse*|sles|suse) echo suse; return 0 ;;
            void) echo void; return 0 ;;
            gentoo) echo gentoo; return 0 ;;
            alpine) echo alpine; return 0 ;;
        esac
    done
    return 0
}

install_hint() {
    case "$FAMILY" in
        arch) echo "pacman -S $1" ;;
        debian) echo "apt install $1" ;;
        fedora) echo "dnf install $1" ;;
        suse) echo "zypper install $1" ;;
        void) echo "xbps-install -S $1" ;;
        gentoo) echo "emerge $1" ;;
        alpine) echo "apk add $1" ;;
        *) echo "your package manager ($1)" ;;
    esac
}

# Hyprland and quickshell are packaged by few distributions, and some ship a
# Hyprland too old for hyprland.lua.
desktop_hint() {
    if [[ "$FAMILY" == arch ]]; then install_hint "$1"; else echo "$(install_hint "$1"), or build it where the distribution's is missing or older"; fi
}

# The first dotted number on a program's --version line, or nothing.
version_of() {
    local out
    out=$("$@" 2>/dev/null | head -n 1) || :
    [[ "$out" =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]] && printf '%s' "${BASH_REMATCH[1]}"
    return 0
}

# $1 is $2 or later: the two, smaller first, are already in version order.
version_at_least() { printf '%s\n%s\n' "$2" "$1" | sort -V -C; }

# One variable of the user manager's environment. show-environment prints a
# value with spaces or specials as $'...'; read raw, that was taken for a
# relative path and ignored, and two equal settings were called different.
session_value() {
    local v
    v=$(sed -n "s/^$1=//p" <<<"$2")
    if [[ "$v" == "\$'"*"'" ]]; then
        v=${v:2:-1}
        v=${v//\\\'/\'}
        printf '%b' "$v"
    else
        printf '%s' "$v"
    fi
}

# Every unmet premise at once, before any write, each with its fix.
check_premise() {
    local os=${DOTFILES_OS_RELEASE:-} f id="" like="" help env name want have verify init
    local -a words=()
    if [[ -z "$os" ]]; then
        for f in /etc/os-release /usr/lib/os-release; do
            if [[ -r "$f" ]]; then os=$f; break; fi
        done
    fi
    if [[ -z "$os" || ! -r "$os" ]]; then
        PROBLEMS+=("no readable os-release, so the distribution is unknown")
    else
        id=$(os_release_field ID "$os")
        like=$(os_release_field ID_LIKE "$os")
        PRETTY=$(os_release_field PRETTY_NAME "$os")
        PRETTY=${PRETTY:-$(os_release_field NAME "$os")}
        PRETTY=${PRETTY:-${id:-an unknown system}}
        read -ra words <<<"$id $like"
        FAMILY=$(distro_family "${words[@]}")
        if [[ -z "$FAMILY" ]]; then
            PROBLEMS+=("$PRETTY is not a distribution this repository recognises (Arch, Debian/Ubuntu, Fedora/RHEL, openSUSE, Gentoo, Void, Alpine)")
        fi
    fi
    if [[ ! -d "${DOTFILES_SYSTEMD:-/run/systemd/system}" ]]; then
        case "$id" in
            void) init=" (Void Linux boots with runit)" ;;
            alpine) init=" (Alpine boots with OpenRC)" ;;
            artix) init=" (Artix boots without it)" ;;
            *) init="" ;;
        esac
        PROBLEMS+=("the session runs as systemd user units, and this system was not booted with systemd$init")
    fi
    # busybox's mv has no -T, and every write here is a rename with it.
    # Captured, not piped into grep -q: an early close would trip pipefail.
    help=$(mv --help 2>&1 || :)
    if [[ "$help" != *--no-target-directory* ]]; then
        PROBLEMS+=("mv lacks -T, so this is not GNU coreutils; $(install_hint coreutils)")
    fi
    if ! command -v Hyprland >/dev/null 2>&1 || ! command -v hyprctl >/dev/null 2>&1; then
        PROBLEMS+=("Hyprland is not installed; $(desktop_hint hyprland)")
    else
        HYPRLAND_VERSION=$(version_of Hyprland --version)
        if [[ -n "$HYPRLAND_VERSION" ]] && ! version_at_least "$HYPRLAND_VERSION" "$HYPRLAND_MIN"; then
            PROBLEMS+=("Hyprland $HYPRLAND_VERSION is older than $HYPRLAND_MIN, the first to read hyprland.lua; $(desktop_hint hyprland)")
        fi
    fi
    if ! command -v qs >/dev/null 2>&1 && ! command -v quickshell >/dev/null 2>&1; then
        PROBLEMS+=("quickshell, which draws the bar, is not installed; $(desktop_hint quickshell)")
    fi
    # Units and the session read these from the user manager's environment,
    # this script from the shell's: two answers put files where nothing reads.
    if env=$(systemctl --user show-environment 2>/dev/null); then
        for name in XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME; do
            case "$name" in
                XDG_CONFIG_HOME) want=$CONFIG; have=$(xdg "$(session_value "$name" "$env")" "$HOME/.config") ;;
                XDG_DATA_HOME) want=$DATA; have=$(xdg "$(session_value "$name" "$env")" "$HOME/.local/share") ;;
                *) want=$STATE; have=$(xdg "$(session_value "$name" "$env")" "$HOME/.local/state") ;;
            esac
            [[ "$want" == "$have" ]] \
                || PROBLEMS+=("$name means $(tilde "$want") here but $(tilde "$have") to the session's user manager; set it the same in both")
        done
    fi
    # Mirroring reloads the running compositor, and a module that throws sends
    # the session to emergency mode: a config that does not load stops here.
    if (( ${#PROBLEMS[@]} == 0 )); then
        verify=0
        # Through bash, as the cursor builders go through python3: an archive
        # or core.fileMode=false checkout has no executable bits.
        bash "$SRC/hypr/scripts/verify-config.sh" "$SRC/hypr" >/dev/null 2>"$STATE_TMP" || verify=$?
        case "$verify" in
            0) ;;
            1) PROBLEMS+=("the Hyprland configuration in this checkout does not load (hypr/scripts/verify-config.sh says why)") ;;
            *) PROBLEMS+=("the Hyprland configuration could not be checked: $(head -n 3 "$STATE_TMP" | tr '\n' ' ')") ;;
        esac
    fi
}

premise_line() {
    local line="premise: $PRETTY ($FAMILY family)" v
    v=$(systemctl --version 2>/dev/null | awk 'NR == 1 && $1 == "systemd" { print $2 }') || v=""
    line+=", systemd${v:+ $v}, Hyprland${HYPRLAND_VERSION:+ $HYPRLAND_VERSION}"
    v=$(version_of qs --version)
    [[ -n "$v" ]] || v=$(version_of quickshell --version)
    line+=", quickshell${v:+ $v}"
    printf '%s✓%s %s\n' "$GREEN" "$RESET" "$line"
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
        || echo "install: could not save $(tilde "$MANIFEST_FILE"); the next run asks about files it cannot place" >&2
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
        -v dim="$DIM" -v reset="$RESET" -v old_label="$3" -v new_label="$4" '
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
    local verb=$1 target answer
    target=$(tilde "$2")
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
            n|no)  exec 3<&-; stop "kept $target as it is" ;;
        esac
    done
}

# Before $1 is overwritten with $2 (named $3 in the diff), or removed when $2
# is empty. Returns only to go ahead, and marks the write that follows.
claim() {
    local to=$1 from=${2:-} label=${3:-}
    ours "$to" "$from" && return 0
    if [[ -d "$to" && ! -L "$to" ]]; then
        stop "$(tilde "$to") is a directory where this repository installs a file; move it away and run again"
    fi
    CONFLICTED=1
    (( FORCE_ALL )) && return 0
    group_label
    printf '\n%s✗ conflict%s  %s: not what this repository installed\n' "$BOLD$RED" "$RESET" "$(tilde "$to")"
    if [[ -n "$from" ]]; then
        show_diff "$to" "$from" "$(tilde "$to") (installed)" "$label (repository)"
        ask Overwrite "$to"
    else
        show_diff "$to" /dev/null "$(tilde "$to") (installed)" "/dev/null (removed from the repository)"
        ask Remove "$to"
    fi
}

# Write beside and rename over, then record it. bash reads a running script
# lazily, so overwriting session-watch.sh in place corrupts it mid-run; and
# Hyprland reloads on write and could read a half-copied module.
put() {
    local from=$1 to=$2 name=$3
    mark_pending
    mkdir -p -- "$(dirname -- "$to")" || stop "could not create $(tilde "$(dirname -- "$to")")"
    # Never writable by group or others, whatever the checkout's mode: a
    # clone under umask 002 gives 664, and the shells skip such drop-ins.
    if ! { cp -a -- "$from" "$to.new-$$" && chmod go-w -- "$to.new-$$" && mv -T -- "$to.new-$$" "$to"; }; then
        rm -f -- "$to.new-$$"
        stop "could not write $(tilde "$to")"
    fi
    record "$to"
    wrote "$name"
}

stop() {
    (( GROUP_SHOWN )) && printf '%s└── stopped here%s\n' "$DIM" "$RESET"
    printf '%s✗ stopped:%s %s\n' "$BOLD$RED" "$RESET" "$*" >&2
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
    if (( ! FINISHED && code == 1 && ! CHECK && WRITTEN )); then
        printf '%sthe %s files written before the stop stay; run ./install.sh again to go on%s\n' "$DIM" "$WRITTEN" "$RESET" >&2
    elif (( ! FINISHED && code != 0 && code != 1 && code != 2 )); then
        printf '%s✗ a command failed (status %s); what was written before it stays%s\n' "$BOLD$RED" "$code" "$RESET" >&2
    fi
    return 0
}
STATE_TMP=$(mktemp)
trap cleanup EXIT
trap 'stop "interrupted"' INT TERM

# ---------------------------------------------------------------- mirror, seed --

# For what this repository authors: overwritten on every run, unless what is
# there is not what this repository wrote (a conflict). Not symlinked, because
# a link resolves back into the working tree. $3 names it in its group.
mirror_file() {
    local from=$1 to=$2 name=${3:-}
    [[ -n "$name" ]] || name=$(tilde "$2")
    [[ -f "$from" ]] || stop "missing source: ${from#"$SRC"/}"
    if [[ -f "$to" && ! -L "$to" ]] && cmp -s -- "$from" "$to"; then
        if [[ -n "$(find "$to" -maxdepth 0 -perm /022 2>/dev/null)" ]]; then
            if (( CHECK )); then todo "${YELLOW}writable by others: $name$RESET"; return 0; fi
            chmod go-w -- "$to" || stop "could not change the mode of $(tilde "$to")"
            branch "$GREEN✓$RESET $name is no longer writable by others"
        fi
        (( CHECK )) || record "$to"
        same
        return 0
    fi
    if (( CHECK )); then
        if [[ ! -e "$to" && ! -L "$to" ]]; then todo "${YELLOW}missing $name$RESET"
        elif ours "$to" "$from"; then todo "${YELLOW}behind $name$RESET"
        else todo "$RED✗ conflict $name$RESET"
        fi
        return 0
    fi
    if [[ -e "$to" || -L "$to" ]]; then claim "$to" "$from" "${from#"$SRC"/}"; fi
    if [[ -L "$to" ]]; then rm -f -- "$to"; fi
    put "$from" "$to" "$name"
}

# Every path the repository had under a source directory, at any commit.
history_paths() {
    local rel=${1#"$SRC"/}
    (( GIT )) || return 0
    {
        git -C "$SRC" log --all --format= --name-only --no-renames -- "$rel" 2>/dev/null || :
        git -C "$SRC" ls-files -- "$rel" 2>/dev/null || :
    } | awk -v prefix="$rel/" 'index($0, prefix) == 1 { print substr($0, length(prefix) + 1) }'
}

# A directory is updated file by file, never swapped whole: quickshell
# crashes if its directory is replaced underneath it. New files go in before
# changed ones: quickshell reloads on every write, and a module updated to
# use a component that has not landed yet fails that reload. Only files that
# differ are written, since every write is a reload. Files the repository
# dropped are removed when it put them there; anything else is left. $3
# prefixes the names in the group's tree.
mirror_dir() {
    local from=$1 to=$2 prefix=${3:-} rel pass target
    local -a found=()
    local -A known=() fresh=()
    [[ -d "$from" ]] || stop "missing source: ${from#"$SRC"/}"
    while IFS= read -r rel; do
        known[$rel]=1
    done < <(history_paths "$from")
    if (( CHECK )); then
        # A link an older install made would compare the checkout with itself.
        if [[ -L "$to" ]]; then
            todo "${YELLOW}behind $(tilde "$to") (still a link from an older install)$RESET"
            return 0
        fi
        while IFS= read -r -d '' rel; do
            mirror_file "$from/${rel#./}" "$to/${rel#./}" "$prefix${rel#./}"
        done < <(cd -- "$from" && find . -mindepth 1 \( -type f -o -type l \) -print0 | LC_ALL=C sort -z)
        [[ -d "$to" ]] || return 0
        while IFS= read -r -d '' rel; do
            rel=${rel#./}
            [[ -e "$from/$rel" || -L "$from/$rel" ]] && continue
            if ours "$to/$rel"; then
                todo "${YELLOW}stale $prefix$rel (gone from the repository)$RESET"
            elif [[ -n "${MANIFEST[$to/$rel]:-}" || -n "${known[$rel]:-}" ]]; then
                todo "$RED✗ conflict $prefix$rel (gone from the repository and changed since)$RESET"
            else
                branch "${YELLOW}left $prefix$rel: not from this repository$RESET"
            fi
        done < <(cd -- "$to" && find . -mindepth 1 \( -type f -o -type l \) -print0 | LC_ALL=C sort -z)
        return 0
    fi

    [[ -L "$to" ]] && rm -f -- "$to"
    if [[ -e "$to" && ! -d "$to" ]]; then claim "$to"; rm -f -- "$to"; CONFLICTED=0; fi
    mkdir -p -- "$to" || stop "could not create $(tilde "$to")"
    for pass in new changed; do
        while IFS= read -r -d '' rel; do
            rel=${rel#./}
            target="$to/$rel"
            if [[ -d "$from/$rel" && ! -L "$from/$rel" ]]; then
                mkdir -p -- "$target" || stop "could not create $(tilde "$target")"
                continue
            fi
            if [[ "$pass" == new ]]; then
                [[ -e "$target" || -L "$target" ]] && continue
                fresh[$rel]=1
            else
                [[ -n "${fresh[$rel]:-}" ]] && continue
                [[ -e "$target" || -L "$target" ]] || continue
            fi
            mirror_file "$from/$rel" "$target" "$prefix$rel"
        done < <(cd -- "$from" && find . -mindepth 1 -print0 | LC_ALL=C sort -z)
    done
    while IFS= read -r -d '' rel; do
        found+=("${rel#./}")
    done < <(cd -- "$to" && find . -mindepth 1 \( -type f -o -type l \) -print0 | LC_ALL=C sort -z)
    for rel in "${found[@]}"; do
        target="$to/$rel"
        [[ -e "$from/$rel" || -L "$from/$rel" ]] && continue
        if ours "$target" || [[ -n "${MANIFEST[$target]:-}" || -n "${known[$rel]:-}" ]]; then
            claim "$target"
            mark_pending
            rm -f -- "$target" || stop "could not remove $(tilde "$target")"
            unset 'MANIFEST[$target]'
            MANIFEST_DIRTY=1
            wrote "$prefix$rel" removed
        else
            branch "${YELLOW}left $prefix$rel: not from this repository$RESET"
        fi
    done
    while IFS= read -r -d '' rel; do
        rel=${rel#./}
        [[ -e "$from/$rel" ]] && continue
        if rmdir -- "$to/$rel" 2>/dev/null; then branch "$GREEN✓$RESET removed $prefix$rel/"; fi
    done < <(cd -- "$to" && find . -mindepth 1 -depth -type d -print0)
    return 0
}

# A file the repository no longer installs, removed so that it cannot mislead.
retire() {
    local target=$1 name=$2
    [[ -e "$target" || -L "$target" ]] || return 0
    if (( CHECK )); then todo "${YELLOW}stale $name (no longer used)$RESET"; return 0; fi
    mark_pending
    rm -f -- "$target" || stop "could not remove $(tilde "$target")"
    wrote "$name" removed
}

# cp -a keeps the checkout's mode, and an archive or core.fileMode=false
# tree arrives at 644.
ensure_exec() {
    local f
    for f in "$@"; do
        [[ -f "$f" && ! -x "$f" ]] || continue
        if (( CHECK )); then todo "${YELLOW}not executable: $(tilde "$f")$RESET"; continue; fi
        chmod +x -- "$f" || stop "could not make $(tilde "$f") executable"
        branch "$GREEN✓$RESET made $(tilde "$f") executable"
    done
}

# For what a program owns: copied once, then left to the program. fcitx5, KDE
# and GTK save by rename() over the target, which replaces a symlink rather
# than following it. A newer version from here replaces an installed copy
# only while that copy is still one this repository wrote (an update that
# finds it untouched); one its program changed is left, counted for a note,
# and listed by --check. To keep such a change, copy it into the repository;
# to take this one, delete the installed file and run again. A directory is
# seeded file by file.
seed() {
    local from=$1 to=$2 rel
    [[ -e "$from" ]] || stop "missing source: ${from#"$SRC"/}"
    if [[ ! -d "$from" ]]; then
        seed_file "$from" "$to"
        return 0
    fi
    if [[ -L "$to" ]] && ours "$to"; then
        if (( CHECK )); then todo "${YELLOW}behind $(tilde "$to") (still a link from an older install)$RESET"; return 0; fi
        rm -f -- "$to" || stop "could not remove the old link $(tilde "$to")"
    fi
    while IFS= read -r -d '' rel; do
        seed_file "$from/${rel#./}" "$to/${rel#./}"
    done < <(cd -- "$from" && find . -type f -print0 | LC_ALL=C sort -z)
}

seed_file() {
    local from=$1 to=$2 name
    name=$(tilde "$to")
    if [[ -f "$to" && ! -L "$to" ]] && cmp -s -- "$from" "$to"; then
        (( CHECK )) || record "$to"
        same
        return 0
    fi
    if [[ -e "$to" || -L "$to" ]] && ! ours "$to"; then
        SEEDS_DIFFER=$((SEEDS_DIFFER + 1))
        (( CHECK )) && branch "${DIM}$name was changed after it was seeded; left alone$RESET"
        same
        return 0
    fi
    if (( CHECK )); then
        if [[ -L "$to" ]]; then todo "${YELLOW}behind $name (still a link from an older install)$RESET"
        elif [[ -e "$to" ]]; then todo "${YELLOW}behind $name (seeded, and untouched since)$RESET"
        else todo "${YELLOW}missing $name$RESET"
        fi
        return 0
    fi
    # A link from an older install becomes a real file.
    [[ -L "$to" ]] && rm -f -- "$to"
    put "$from" "$to" "$name"
}

# --------------------------------------------------------- system files, sudo --

# tuigreet/config.toml means nothing to another greeter, so it is installed
# only when greetd's command is tuigreet and tuigreet is installed.
greeter_is_tuigreet() {
    [[ -r "$ROOT/etc/greetd/config.toml" ]] || return 1
    grep -qE '^[[:space:]]*command[[:space:]]*=.*\btuigreet\b' "$ROOT/etc/greetd/config.toml" || return 1
    command -v tuigreet >/dev/null 2>&1
}

# source:destination:mode for every root-owned file this machine should have.
system_files() {
    printf '%s\n' "fontconfig/local.conf:$FONTCONF:644"
    greeter_is_tuigreet && printf '%s\n' "tuigreet/config.toml:$GREETERCONF:644"
    printf '%s\n' "${CAMERA_FILES[@]}" "${KEYFEED_FILES[@]}"
}

system_current() {
    cmp -s -- "$SRC/$1" "$2" && [[ "$(stat -c '%a %U' -- "$2" 2>/dev/null)" == "$3 root" ]]
}

# Where the content for a root's file comes from, as git sees it: the
# upstream branch as last fetched, a commit made here, or the work tree.
provenance() {
    local rel=$1 id up=""
    if (( ! GIT )); then echo "no git history to compare with"; return 0; fi
    id=$(git -C "$SRC" hash-object -- "$rel" 2>/dev/null) || { echo "unreadable"; return 0; }
    up=$(git -C "$SRC" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || up=""
    if [[ -n "$up" && "$(git -C "$SRC" rev-parse -q --verify "$up:$rel" 2>/dev/null)" == "$id" ]]; then
        echo "as on $up"
    elif [[ "$(git -C "$SRC" rev-parse -q --verify "HEAD:$rel" 2>/dev/null)" == "$id" ]]; then
        echo "committed${up:+, not on $up}"
    else
        echo "not committed"
    fi
}

# +added -removed between the installed copy and the source.
diffstat() {
    { diff -u -- "$1" "$2" 2>/dev/null || :; } \
        | awk 'NR > 2 && /^\+/ { a++ } NR > 2 && /^-/ { d++ } END { printf "+%d -%d", a, d }'
}

# Root's files are written only after the user has seen what goes into them.
# The content is this checkout's as it is now, which any program of the user's
# could have changed, and sudo would make it root's: so each file says where
# its content comes from, and one not as on the upstream branch (or replacing
# a copy this repository did not write) shows its diff at once; the rest show
# theirs on request. One question for all of them, before sudo asks for the
# password; without a terminal to ask on they wait, unless --force.
# $@: source:destination:mode of each file that differs. 0 to go ahead.
root_plan() {
    local entry src dst mode what from answer n=$# i=0 glyph foreign
    local -a shown=() later=()
    printf '%sroot'\''s files%s %s(written with sudo)%s\n' "$BOLD" "$RESET" "$DIM" "$RESET"
    for entry in "$@"; do
        IFS=: read -r src dst mode <<<"$entry"
        i=$((i + 1))
        from=$(provenance "$src")
        foreign=0
        if [[ ! -e "$dst" ]]; then
            what="new"
        elif cmp -s -- "$SRC/$src" "$dst"; then
            what="mode $mode, owner root"
        elif ! ours "$dst" "$SRC/$src"; then
            what="${RED}replaces a copy this repository did not write$RESET"
            foreign=1
        else
            what=$(diffstat "$dst" "$SRC/$src")
        fi
        if [[ -e "$dst" ]] && ! cmp -s -- "$SRC/$src" "$dst"; then
            if (( foreign )) || [[ "$from" != "as on "* ]]; then shown+=("$entry"); else later+=("$entry"); fi
        fi
        if (( i < n )); then glyph="├──"; else glyph="└──"; fi
        printf '%s%s%s %s  %s %s(%s, %s)%s\n' "$DIM" "$glyph" "$RESET" "$dst" "$what" "$DIM" "$src" "$from" "$RESET"
    done
    for entry in "${shown[@]}"; do
        IFS=: read -r src dst mode <<<"$entry"
        show_diff "$dst" "$SRC/$src" "$dst (installed)" "$src (this checkout, $(provenance "$src"))"
    done
    (( FORCE_ALL )) && return 0
    if ! { exec 3</dev/tty; } 2>/dev/null; then
        printf '%sroot'\''s files wait for a terminal to confirm them (or --force)%s\n' "$YELLOW" "$RESET"
        return 1
    fi
    while true; do
        printf 'Write them as root? [y] yes  [n] no, leave them  [d] every diff: ' >/dev/tty
        IFS= read -r answer <&3 || answer=n
        case "${answer,,}" in
            y|yes) exec 3<&-; return 0 ;;
            n|no)  exec 3<&-; return 1 ;;
            d)
                for entry in "${later[@]}"; do
                    IFS=: read -r src dst mode <<<"$entry"
                    show_diff "$dst" "$SRC/$src" "$dst (installed)" "$src (this checkout, $(provenance "$src"))"
                done
                (( ${#later[@]} )) || echo "(no other diffs)"
                ;;
        esac
    done
}

# Asked for before the first write, and only when a root's file differs: an
# update that leaves them alone never prompts.
acquire_sudo() {
    local src dst mode
    local -a want=()
    while IFS=: read -r src dst mode; do
        system_current "$src" "$dst" "$mode" || want+=("$src:$dst:$mode")
    done < <(system_files)
    (( ${#want[@]} )) || return 0
    command -v sudo >/dev/null 2>&1 || return 0
    if ! root_plan "${want[@]}"; then
        echo
        return 0
    fi
    if sudo -v 2>/dev/null; then
        SUDO_OK=1
        # Kept alive: a cold run can outlast sudo's timestamp. Without the
        # lock's descriptor, and only while this script lives: a sleep that
        # inherited fd 9 held the lock for 50 s after the run, and a killed
        # run left the loop renewing the timestamp.
        ( exec 9>&-
          trap 'kill "${nap:-}" 2>/dev/null; exit 0' TERM
          while kill -0 "$$" 2>/dev/null; do
              sudo -n true 2>/dev/null || exit 0
              sleep 50 & nap=$!
              wait "$nap" || :
          done ) &
        SUDO_KEEPALIVE=$!
    else
        printf '%sno sudo here, so root'\''s files are left for the end%s\n' "$YELLOW" "$RESET"
    fi
    echo
}

# One root-owned file; 0 when it was written. Content another hand wrote is a
# conflict, as in the home directory, and its previous copy is kept beside it
# as .bak-<time>.
system_file() {
    local rel=$1 dst=$2 mode=$3
    # sudo install follows a link: one in the checkout could copy any file
    # root can read into a root-owned, world-readable one.
    if [[ -L "$SRC/$rel" || ! -f "$SRC/$rel" ]]; then
        if (( CHECK )); then todo "$RED✗ $rel is not a regular file in the checkout$RESET"; return 1; fi
        stop "$rel is not a regular file in the checkout; root's files are installed from regular files only"
    fi
    if system_current "$rel" "$dst" "$mode"; then
        (( CHECK )) || record "$dst"
        same
        return 1
    fi
    if (( CHECK )); then
        if [[ ! -e "$dst" ]]; then
            todo "${YELLOW}missing $dst$RESET"
        elif ! cmp -s -- "$SRC/$rel" "$dst" && ! ours "$dst" "$SRC/$rel"; then
            todo "$RED✗ conflict $dst$RESET"
        else
            todo "${YELLOW}behind $dst$RESET"
        fi
        return 1
    fi
    if (( ! SUDO_OK )); then
        LEFT+=("sudo install -D -o root -g root -m $mode '$SRC/$rel' $dst")
        branch "${YELLOW}left for sudo: $dst$RESET"
        return 1
    fi
    if [[ -e "$dst" ]] && ! cmp -s -- "$SRC/$rel" "$dst"; then
        if ! ours "$dst" "$SRC/$rel"; then
            # Its diff was shown and confirmed with the others (root_plan).
            CONFLICTED=1
            sudo cp -a -- "$dst" "$dst.bak-$STAMP" && NOTES+=("the previous $dst is kept at $dst.bak-$STAMP")
        fi
    fi
    sudo install -D -o root -g root -m "$mode" -- "$SRC/$rel" "$dst" || stop "could not write $dst"
    record "$dst"
    wrote "$dst"
    return 0
}

# --------------------------------------------------------- the user manager --

# State changes only, each said: an update with nothing to change runs no
# systemctl verb that writes. A unit not installed is left alone; masking one
# would leave a link to /dev/null for nothing.
unit_state() { systemctl --user is-enabled "$1" 2>/dev/null || :; }

user_services() {
    local u state
    if (( CHECK )) && pending units; then
        todo "${YELLOW}the user manager was not reloaded after an earlier run changed its units$RESET"
    fi
    if (( ! CHECK )) && { (( UNITS_CHANGED )) || pending units; }; then
        if systemctl --user daemon-reload 2>/dev/null; then
            branch "$GREEN✓$RESET reloaded the user manager"
            settled units
        else
            LEFT+=("systemctl --user daemon-reload (it failed here; the units apply at the next login)")
            branch "${YELLOW}could not reload the user manager$RESET"
        fi
    fi
    # hypridle uses its packaged unit; enabling hooks it to graphical-session.target.
    state=$(unit_state hypridle.service)
    if [[ "$state" == disabled ]]; then
        if (( CHECK )); then
            todo "${YELLOW}hypridle.service is not enabled$RESET"
        elif systemctl --user enable hypridle.service >/dev/null 2>&1; then
            branch "$GREEN✓$RESET enabled hypridle.service"
        else
            LEFT+=("systemctl --user enable hypridle.service (it failed here; without it the screen does not lock before sleep)")
            branch "${YELLOW}could not enable hypridle.service$RESET"
        fi
    fi
    # Baloo off, second half (see kde/baloofilerc): the config key only fails
    # the unit's ExecCondition, so disable it to stop the start/stop at every
    # login.
    if [[ "$(unit_state kde-baloo.service)" == enabled ]]; then
        if (( CHECK )); then
            todo "${YELLOW}kde-baloo.service is enabled$RESET"
        elif systemctl --user disable kde-baloo.service >/dev/null 2>&1; then
            branch "$GREEN✓$RESET disabled kde-baloo.service"
        fi
    fi
    # drkonqi runs from a user unit with no Wayland display, so Qt aborts it,
    # and its own coredump launches it again (one crash left 1.1 GB of
    # cores): masked; coredumpctl still works.
    for u in drkonqi-coredump-launcher.socket drkonqi-coredump-pickup.service \
             drkonqi-coredump-cleanup.timer drkonqi-sentry-postman.path drkonqi-sentry-postman.timer; do
        state=$(unit_state "$u")
        case "$state" in ""|not-found|masked|masked-runtime) continue ;; esac
        if (( CHECK )); then
            todo "${YELLOW}$u is not masked$RESET"
            continue
        fi
        systemctl --user disable --now "$u" >/dev/null 2>&1 || :
        if systemctl --user mask "$u" >/dev/null 2>&1; then
            branch "$GREEN✓$RESET masked $u"
        fi
    done
}

# ------------------------------------------------------------- cursor theme --

# XCursor themes are bitmaps, so the colour is baked in at build time; the
# tint comes from pointer.py's FILL so the redrawn arrow and every other shape
# match. The build redraws every image, so it runs only when what it is built
# from changed (the three scripts, or the Oxygen_White files a package
# upgrade replaces) or the theme is gone. A failed build is not fatal: the
# previous pointer stays, and the next run tries again.
CURSOR_THEME=Spaceduck-Sky
CURSOR_STAMP="$STATE/dotfiles-desktop/cursor"

cursor_inputs() {
    local base dir=""
    local -a bases=("$DATA/icons" "$HOME/.icons") dirs=()
    IFS=: read -ra dirs <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    for base in "${dirs[@]}"; do [[ "$base" == /* ]] && bases+=("$base/icons"); done
    for base in "${bases[@]}"; do
        if [[ -d "$base/Oxygen_White/cursors" ]]; then dir=$base/Oxygen_White/cursors; break; fi
    done
    {
        cat -- "$SRC/theme/cursor/tint-cursors.py" "$SRC/theme/cursor/pointer.py" "$SRC/theme/cursor/emphasise.py"
        if [[ -n "$dir" ]]; then find "$dir" -printf '%P %s %T@\n' | LC_ALL=C sort; fi
    } | sha256sum | cut -d' ' -f1
}

cursor_theme() {
    local want have tint complete
    want=$(cursor_inputs)
    have=$(cat -- "$CURSOR_STAMP" 2>/dev/null) || have=""
    if [[ -f "$DATA/icons/$CURSOR_THEME/index.theme" && "$want" == "$have" ]]; then
        same
        return 0
    fi
    if (( CHECK )); then
        todo "${YELLOW}behind $CURSOR_THEME (what it is built from changed, or it is missing)$RESET"
        return 0
    fi
    tint=$(sed -n 's/^FILL = "\(#[0-9a-fA-F]\{6\}\)".*/\1/p' "$SRC/theme/cursor/pointer.py" | head -n 1)
    if [[ -z "$tint" ]]; then
        branch "${YELLOW}no FILL in theme/cursor/pointer.py, so $CURSOR_THEME was not built$RESET"
        return 0
    fi
    if ! python3 "$SRC/theme/cursor/tint-cursors.py" --from Oxygen_White --name "$CURSOR_THEME" --tint "$tint" \
            --comment "Oxygen_White recoloured to the drawn pointer's blue" >/dev/null 2>"$STATE_TMP"; then
        branch "${YELLOW}$CURSOR_THEME could not be built ($(head -n 1 "$STATE_TMP")); the pointer is unchanged$RESET"
        return 0
    fi
    complete=1
    if ! python3 "$SRC/theme/cursor/pointer.py" --theme "$CURSOR_THEME" >/dev/null 2>&1; then
        complete=0
        branch "${YELLOW}the arrow stayed as the tint left it; the next run draws it again$RESET"
    fi
    # Enlarges the drag shapes; reasoning in the script.
    if ! python3 "$SRC/theme/cursor/emphasise.py" --theme "$CURSOR_THEME" >/dev/null 2>&1; then
        complete=0
        branch "${YELLOW}the drag cursors were left at theme size; the next run tries again$RESET"
    fi
    # Only a whole build is stamped, so a step that failed (Pillow or
    # rsvg-convert missing) runs again next time.
    if (( complete )); then
        { mkdir -p -- "${CURSOR_STAMP%/*}" && printf '%s\n' "$want" >"$CURSOR_STAMP"; } || :
    fi
    wrote "built $CURSOR_THEME in $(tilde "$DATA/icons")"
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
        "rsvg-convert:the drawn arrow in the cursor theme"
    )
    for tool in "${tools[@]}"; do
        command -v "${tool%%:*}" >/dev/null 2>&1 || missing+=("${tool%%:*} (${tool#*:})")
    done
    if command -v python3 >/dev/null 2>&1 && ! python3 -c 'import PIL' 2>/dev/null; then
        missing+=("Pillow for python3 (the drawn arrow in the cursor theme)")
    fi
    if (( ${#missing[@]} == 0 )); then
        printf '%s✓%s doctor: every font and tool the desktop uses is present\n' "$GREEN" "$RESET"
        return 0
    fi
    printf '%sdoctor: missing%s\n' "$YELLOW" "$RESET"
    tree_lines "$YELLOW" "${missing[@]}"
}

finish() {
    local note
    FINISHED=1
    echo
    if (( ${#LEFT[@]} )); then
        printf '%sleft undone%s %s(%s written)%s\n' "$BOLD$YELLOW" "$RESET" "$DIM" "$WRITTEN" "$RESET"
        tree_lines "$YELLOW" "${LEFT[@]}"
    elif (( ! CHECK )); then
        printf '%s✓ everything is in place%s %s(%s written, %s unchanged)%s\n' \
            "$BOLD$GREEN" "$RESET" "$DIM" "$WRITTEN" "$UNCHANGED" "$RESET"
    fi
    if (( SEEDS_DIFFER == 1 && ! CHECK )); then
        NOTES+=("1 seeded file was changed after it was seeded and is left alone; --check names it")
    elif (( SEEDS_DIFFER > 1 && ! CHECK )); then
        NOTES+=("$SEEDS_DIFFER seeded files were changed after they were seeded and are left alone; --check lists them")
    fi
    for note in "${NOTES[@]}"; do printf '%snote: %s%s\n' "$DIM" "$note" "$RESET"; done
    if (( CHECK )); then
        if (( ${#PROBLEMS[@]} )); then
            printf '%s✗ the premise is not met, so ./install.sh stops until it is%s\n' "$RED" "$RESET"
        elif (( DRIFT )); then
            printf '%srun ./install.sh to apply%s\n' "$YELLOW" "$RESET"
        else
            printf '%s✓%s everything installed is current\n' "$GREEN" "$RESET"
        fi
    fi
    doctor
    # The script's last command, so this is its exit status.
    if (( ${#LEFT[@]} || (CHECK && (DRIFT || ${#PROBLEMS[@]})) )); then return 1; fi
    return 0
}

# ===================================================================== run ==

printf '%sdotfiles-desktop%s  %s%s %s%s\n' "$BOLD$CYAN" "$RESET" "$DIM" \
    "$( (( CHECK )) && echo checking || echo installing into)" "$(tilde "$HOME")" "$RESET"
HYPRLAND_VERSION=""
check_premise
if (( ${#PROBLEMS[@]} )); then
    if (( ! CHECK )); then
        printf '%s✗ the premise is not met; nothing was written%s\n' "$RED" "$RESET" >&2
        tree_lines "" "${PROBLEMS[@]}" >&2
        exit 1
    fi
    printf '%s✗ the premise is not met%s\n' "$RED" "$RESET"
    tree_lines "" "${PROBLEMS[@]}"
else
    premise_line
fi
echo

load_manifest
if (( ! CHECK )); then
    # Two runs at once would interleave their writes and their manifests.
    mkdir -p -- "${MANIFEST_FILE%/*}" || stop "could not create $(tilde "${MANIFEST_FILE%/*}")"
    exec 9>"${MANIFEST_FILE%/*}/lock"
    flock -n 9 || stop "another ./install.sh is running"
    acquire_sudo
fi

# Scripts first: the config and the bar call them, and the reloads below may
# run what they name.
group_open "$(tilde "$CONFIG/hypr/scripts")"
mirror_dir "$SRC/hypr/scripts" "$CONFIG/hypr/scripts"
ensure_exec "$CONFIG/hypr/scripts"/*.sh
group_close

group_open "$(tilde "$CONFIG/quickshell/bar")" bar
mirror_dir "$SRC/quickshell/bar" "$CONFIG/quickshell/bar"
ensure_exec "$CONFIG/quickshell/bar/scripts"/*.sh "$CONFIG/quickshell/bar/scripts"/*.py
# The reloads on write above can miss files: quickshell reads the whole tree
# when a reload starts and watches again only when it ends, and a file
# renamed over a watched one sometimes went unseen altogether. One more
# reload, asked for after the last file, reads the finished tree. A reload
# still under way builds the shell over several turns of its event loop, its
# IPC targets appearing one by one, so the "shell" target is looked for a few
# times before the bar is taken for one from before the call.
if (( CHECK )) && pending bar; then
    todo "${YELLOW}the running bar was not reloaded after an earlier run wrote to it$RESET"
fi
if (( ! CHECK )) && { (( GROUP_WROTE )) || pending bar; }; then
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
            if qs -p "$CONFIG/quickshell/bar" ipc call shell reload >/dev/null 2>&1; then
                branch "$GREEN✓$RESET reloaded the running bar"
                settled bar
            else
                LEFT+=("bar --restart (the running bar did not take the reload)")
                branch "${YELLOW}the running bar did not take the reload$RESET"
            fi ;;
        old)
            LEFT+=("bar --restart (the running bar could not be asked to reload)")
            branch "${YELLOW}the running bar cannot be asked to reload yet$RESET" ;;
        # Not running: it reads the files when it starts.
        *) settled bar ;;
    esac
    unset _bar_targets _bar_state
fi
group_close

# config/ before hyprland.lua, then an explicit reload, and only when one of
# them changed. Hyprland reloads on writes to files it has already loaded
# only, so a hyprland.lua that requires a not-yet-copied module leaves the
# session in emergency mode. The state dir is where monitors.lua caches
# output descriptions; the module cannot create it.
group_open "$(tilde "$CONFIG/hypr")" compositor
if (( ! CHECK )); then mkdir -p -- "$STATE/hypr" || stop "could not create $(tilde "$STATE/hypr")"; fi
mirror_dir "$SRC/hypr/config" "$CONFIG/hypr/config" config/
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
        todo "${YELLOW}monitor_settings.lua is a per-machine file from before the preset; install moves it to monitor_settings.local.lua$RESET"
    elif [[ -f "$_local_settings" ]]; then
        cp -a -- "$_old_settings" "$_local_settings.bak-$STAMP"
        branch "${YELLOW}kept the old monitor_settings.lua as monitor_settings.local.lua.bak-$STAMP (a local file already exists)$RESET"
    else
        mv -- "$_old_settings" "$_local_settings"
        branch "$GREEN✓$RESET moved the old monitor_settings.lua to monitor_settings.local.lua: its values still win over the preset"
    fi
fi
unset _old_settings _local_settings
mirror_file "$SRC/hypr/monitor_settings.lua" "$CONFIG/hypr/monitor_settings.lua" monitor_settings.lua
if [[ -f "$SRC/hypr/monitor_settings.local.lua" ]]; then
    mirror_file "$SRC/hypr/monitor_settings.local.lua" "$CONFIG/hypr/monitor_settings.local.lua" monitor_settings.local.lua
fi
mirror_file "$SRC/hypr/hyprland.lua" "$CONFIG/hypr/hyprland.lua" hyprland.lua
retire "$CONFIG/hypr/monitors.preset" monitors.preset
if (( CHECK )) && pending compositor; then
    todo "${YELLOW}the running compositor was not reloaded after an earlier run wrote to it$RESET"
fi
if (( ! CHECK )) && { (( GROUP_WROTE )) || pending compositor; }; then
    if ! hyprctl version >/dev/null 2>&1; then
        branch "${DIM}no compositor reachable from here; the next session reads it$RESET"
        settled compositor
    elif hyprctl reload >/dev/null 2>&1; then
        branch "$GREEN✓$RESET reloaded the running compositor"
        settled compositor
    else
        LEFT+=("hyprctl reload (it failed here)")
        branch "${YELLOW}could not reload the running compositor$RESET"
    fi
fi
group_close

# ~/.local/bin, not an XDG directory: the units and keybinds name these by
# that path, and the terminal configuration puts it on PATH.
group_open programs
mirror_file "$SRC/bin/bar" "$HOME/.local/bin/bar"
mirror_file "$SRC/bin/unlock" "$HOME/.local/bin/unlock"
# In ~ on purpose: typed from a text console where PATH may not be set up.
mirror_file "$SRC/bin/recover-desktop" "$HOME/recover-desktop"
# The camera switch's user copy: `camera-switch` from a terminal, and what
# the camera keys fall back to until the sudo step has installed the
# root-owned one; it works, but asks for an administrator password each time.
mirror_file "$SRC/camera/camera-switch.py" "$HOME/.local/bin/camera-switch"
ensure_exec "$HOME/.local/bin/bar" "$HOME/.local/bin/unlock" "$HOME/.local/bin/camera-switch" "$HOME/recover-desktop"
group_close

# Units are mirrored, then daemon-reload. Running units are not restarted
# (restarting fcitx5 drops every window's input context); the next login or
# session-start.sh picks them up. The unit directory is shared with other
# packages, so only units whose first line is the "# dotfiles-desktop" marker
# and whose source is gone are removed.
group_open "$(tilde "$CONFIG/systemd/user")" units
for _unit in "$SRC"/systemd/user/*; do
    # A drop-in directory (hypridle.service.d) is mirrored as one.
    if [[ -d "$_unit" ]]; then
        mirror_dir "$_unit" "$CONFIG/systemd/user/${_unit##*/}" "${_unit##*/}/"
    else
        mirror_file "$_unit" "$CONFIG/systemd/user/${_unit##*/}" "${_unit##*/}"
    fi
done
for _installed in "$CONFIG"/systemd/user/*.service "$CONFIG"/systemd/user/*.target "$CONFIG"/systemd/user/*.slice; do
    [[ -f "$_installed" ]] || continue
    [[ -e "$SRC/systemd/user/${_installed##*/}" ]] && continue
    [[ "$(head -n 1 "$_installed" 2>/dev/null)" == "# dotfiles-desktop" ]] || continue
    retire "$_installed" "${_installed##*/}"
done
unset _unit _installed
UNITS_CHANGED=$GROUP_WROTE
group_close

group_open "user services"
user_services
group_close

group_open "other files"
# Overrides /usr/share's fcitx5 D-Bus activation to start the unit instead.
mirror_file "$SRC/dbus/services/org.fcitx.Fcitx5.service" "$DATA/dbus-1/services/org.fcitx.Fcitx5.service"
# The REPL helpers for node and IEx (~/.config/node, profile.d/node.sh,
# ~/.iex.exs) are dotfiles-terminal's alone: a file mirrored from both
# repositories was whatever the last installer to run left there.
mirror_file "$SRC/spotify/spotify-launcher.conf" "$CONFIG/spotify-launcher.conf"
group_close

group_open "cursor theme"
cursor_theme
group_close

group_open "seeded once"
seed "$SRC/hypr/hypridle.conf" "$CONFIG/hypr/hypridle.conf"
seed "$SRC/hypr/hyprlock.conf" "$CONFIG/hypr/hyprlock.conf"
seed "$SRC/hypr/hyprpaper.conf" "$CONFIG/hypr/hyprpaper.conf"
seed "$SRC/fcitx5/config" "$CONFIG/fcitx5/config"
seed "$SRC/fcitx5/profile" "$CONFIG/fcitx5/profile"
seed "$SRC/fcitx5/conf" "$CONFIG/fcitx5/conf"
seed "$SRC/gtk/gtk-3.0-settings.ini" "$CONFIG/gtk-3.0/settings.ini"
seed "$SRC/gtk/gtk-4.0-settings.ini" "$CONFIG/gtk-4.0/settings.ini"
seed "$SRC/kde/kdeglobals" "$CONFIG/kdeglobals"
seed "$SRC/kde/kded5rc" "$CONFIG/kded5rc"
seed "$SRC/kde/baloofilerc" "$CONFIG/baloofilerc"
seed "$SRC/kde/SpaceduckDark.colors" "$DATA/color-schemes/SpaceduckDark.colors"
# Seeded by older versions under the name kded6 never reads; gone when it is
# still the copy this repository wrote.
if [[ -f "$CONFIG/kded6rc" ]] && ours "$CONFIG/kded6rc"; then
    retire "$CONFIG/kded6rc" "$(tilde "$CONFIG/kded6rc") (kded6 reads kded5rc)"
fi
group_close

# Root's files last: everything above works without them.
group_open "system files"
_fonts=0
_camera=0
while IFS=: read -r _src _dst _mode; do
    if system_file "$_src" "$_dst" "$_mode"; then
        [[ "$_dst" == "$FONTCONF" ]] && _fonts=1
        [[ "$_src" == camera/* ]] && _camera=1
    fi
done < <(system_files)
if (( _fonts )); then
    sudo fc-cache -f >/dev/null 2>&1 && branch "$GREEN✓$RESET rebuilt the font cache"
fi
# polkit watches its action directory; udev is told, so the rule holds from
# the next event on.
if (( _camera )); then
    sudo udevadm control --reload 2>/dev/null && branch "$GREEN✓$RESET reloaded the udev rules"
fi
if (( ! CHECK && ! SUDO_OK && ${#LEFT[@]} )) && [[ "${LEFT[*]}" == *"$SRC/camera/"* ]]; then
    LEFT+=("sudo udevadm control --reload")
fi
if (( CHECK )) && ! greeter_is_tuigreet; then
    branch "${DIM}the greeter is not tuigreet, so $GREETERCONF is left alone$RESET"
fi
# Said, not undone: the group may be there for something else, and leaving it
# takes a login. Captured first, as a pipe into grep -q could trip pipefail.
_groups=$(id -nG 2>/dev/null) || _groups=""
if [[ " $_groups " == *" input "* ]]; then
    NOTES+=("the key overlay no longer needs the input group, with which any program of yours can read the keyboards; sudo gpasswd -d $(id -un) input (from the next login)")
fi
unset _src _dst _mode _fonts _camera _groups
group_close

finish
