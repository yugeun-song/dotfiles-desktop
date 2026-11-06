#!/usr/bin/env bash
# Installs what the lists here name and this system lacks, and nothing else.
# install.sh runs it before it places a file, since the files run these.
#
#   packages/apply.sh            install what is missing (asks, in a terminal)
#   packages/apply.sh --check    say what is missing (exit 1 then); change nothing
#   packages/apply.sh --pending  exit 0 when it would install something
#
# Never a reinstall, which can rewrite a package's configuration: pacman -T
# names what no installed package satisfies (provides count), and only that
# goes to pacman -S --needed. Never -Sy: syncing without upgrading is a
# partial upgrade, which breaks Arch, so a database too old to fetch from
# stops this with the upgrade to run instead. The official packages go
# first, base-devel and git among them, since the AUR's build with them; the
# AUR's build with yay in its review prompts, and any failure there stops the
# run: a PKGBUILD that does not build, a sum or signature that does not
# match, a diff declined.

set -uo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
MODE=install
usage() { echo "usage: packages/apply.sh [--check | --pending]"; }
case ${1:-} in
    "") ;;
    --check) MODE=check ;;
    --pending) MODE=pending ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    BOLD=$'\e[1m' DIM=$'\e[2m' RED=$'\e[31m' GREEN=$'\e[32m' YELLOW=$'\e[33m' RESET=$'\e[0m'
else
    BOLD="" DIM="" RED="" GREEN="" YELLOW="" RESET=""
fi
say() { printf '%s\n' "$*"; }
fail() { printf '%s✗ packages:%s %s\n' "$BOLD$RED" "$RESET" "$*" >&2; exit 1; }

# A list: one name a line, a note after a #.
names() { sed -E 's/#.*//; s/[[:space:]]+//g; /^$/d' -- "$@" | LC_ALL=C sort -u; }
# What no installed package satisfies; pacman -T exits 127 when anything is.
unsatisfied() { (( $# )) || return 0; pacman -T -- "$@" 2>/dev/null; return 0; }
# A terminal to ask on: pacman, yay and makepkg all confirm on it.
terminal() { { : </dev/tty; } 2>/dev/null; }

if ! command -v pacman >/dev/null 2>&1; then
    [[ $MODE == pending ]] && exit 1
    say "${DIM}packages: no pacman here; the lists are Arch's, so none is installed${RESET}"
    exit 0
fi
(( EUID )) || fail "run as the user: yay and makepkg refuse root, and pacman goes through sudo"

mapfile -t official < <(names "$HERE/desktop.txt" "$HERE/user.txt")
mapfile -t aur < <(names "$HERE/user-aur.txt")
mapfile -t need < <(unsatisfied "${official[@]}")
mapfile -t need_aur < <(unsatisfied "${aur[@]}")

# Of the official ones, those no enabled repository carries (multilib
# switched off, a package dropped upstream): left out, and said.
absent=()
if (( ${#need[@]} )); then
    mapfile -t absent < <(pacman -Si -- "${need[@]}" 2>&1 >/dev/null \
        | sed -nE "s/^error: package '([^']+)' was not found$/\1/p")
fi
get=()
for p in "${need[@]}"; do
    [[ " ${absent[*]} " == *" $p "* ]] || get+=("$p")
done

if [[ $MODE == pending ]]; then
    (( ${#get[@]} || ${#need_aur[@]} )) && terminal && exit 0
    exit 1
fi

report() {
    (( ${#get[@]} )) && say "${YELLOW}missing, from the repositories (${#get[@]}):${RESET} ${get[*]}"
    (( ${#need_aur[@]} )) && say "${YELLOW}missing, from the AUR (${#need_aur[@]}):${RESET} ${need_aur[*]}"
    (( ${#absent[@]} )) && say "${YELLOW}missing, and in no enabled repository:${RESET} ${absent[*]}"
    return 0
}

if [[ $MODE == check ]]; then
    report
    # Installed by hand since the lists were written: neither listed nor left
    # out. dotfiles-terminal's list counts when install.sh names it.
    mapfile -t listed < <(names "$HERE"/*.txt ${TERMINAL_LIST:+"$TERMINAL_LIST"})
    mapfile -t extra < <(LC_ALL=C comm -23 <(pacman -Qqe | LC_ALL=C sort -u) <(printf '%s\n' "${listed[@]}"))
    (( ${#extra[@]} )) && say "${DIM}installed by hand and in no list (user.txt, user-aur.txt or excluded.txt): ${extra[*]}${RESET}"
    if (( ${#get[@]} || ${#need_aur[@]} )); then exit 1; fi
    say "${GREEN}✓${RESET} packages: every package the lists name is installed"
    exit 0
fi

if (( ! ${#get[@]} && ! ${#need_aur[@]} )); then
    report
    say "${GREEN}✓${RESET} packages: every package the lists name is installed"
    exit 0
fi
if ! terminal; then
    report
    say "${YELLOW}packages: none installed, with no terminal to confirm them in; run ./install.sh in one${RESET}"
    exit 3
fi
report

if (( ${#get[@]} )); then
    say "${BOLD}packages:${RESET} ${#get[@]} from the repositories; pacman shows the whole transaction and asks"
    # shellcheck disable=SC2024 # the terminal is read here, as pacman's answers
    sudo pacman -S --needed -- "${get[@]}" </dev/tty \
        || fail "pacman installed none of them (status $?); if it could not fetch, the database is older than the mirrors: run sudo pacman -Syu, then ./install.sh again"
fi

# yay-bin, the helper the AUR step runs, built with makepkg from its PKGBUILD
# once it has been read here and confirmed. makepkg checks each source
# against the PKGBUILD's sums and signatures; -s installs what it builds with
# through sudo pacman, without -y either.
bootstrap_yay() {
    local dir answer status
    dir=$(mktemp -d) || return 1
    say "${BOLD}packages:${RESET} yay is not installed; yay-bin's PKGBUILD from the AUR, to build it with:"
    if ! git clone --quiet --depth 1 -- https://aur.archlinux.org/yay-bin.git "$dir/yay-bin"; then
        rm -rf -- "${dir:?}"
        return 1
    fi
    # With its control characters shown, which could hide a line from this
    # review, the one check there is: the sums come from the same PKGBUILD. Its
    # install script too, since makepkg -i runs that as root.
    cat -v -- "$dir/yay-bin/PKGBUILD" "$dir"/yay-bin/*.install 2>/dev/null
    printf 'Build and install yay-bin from this PKGBUILD? [y/N] ' >/dev/tty
    IFS= read -r answer </dev/tty || answer=""
    case ${answer,,} in
        y|yes) ;;
        *) rm -rf -- "${dir:?}"; return 1 ;;
    esac
    ( cd -- "$dir/yay-bin" && makepkg -si --needed ) </dev/tty
    status=$?
    rm -rf -- "${dir:?}"
    return "$status"
}

if (( ${#need_aur[@]} )); then
    mapfile -t tools < <(unsatisfied base-devel git)
    (( ${#tools[@]} )) && fail "the AUR step builds with ${tools[*]}, which pacman did not install"
    if ! command -v yay >/dev/null 2>&1; then
        bootstrap_yay || fail "yay-bin was not built (declined, or makepkg failed); nothing from the AUR was installed"
        # yay-bin may have been the only one.
        mapfile -t need_aur < <(unsatisfied "${aur[@]}")
    fi
    if (( ${#need_aur[@]} )); then
        say "${BOLD}packages:${RESET} ${#need_aur[@]} from the AUR; read each PKGBUILD's diff when yay asks"
        # --diffmenu whatever yay's own configuration says; --sudoloop so a
        # long build does not outlast the password asked at the start.
        yay -S --needed --sudoloop --diffmenu -- "${need_aur[@]}" </dev/tty \
            || fail "yay stopped (status $?): a PKGBUILD that did not build, a sum or signature that did not match, or a diff declined; nothing after it ran"
    fi
fi
say "${GREEN}✓${RESET} packages: installed"
