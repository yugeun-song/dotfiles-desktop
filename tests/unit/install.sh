#!/usr/bin/env bash
# Runs install.sh against a temporary HOME. Nothing reaches the real one or
# the running session: each case gets its own HOME, a copy of this checkout
# as its own repository (so a case can commit and the installer's git checks
# see it), stand-ins for Hyprland, hyprctl, qs, systemctl, sudo, fc-list and
# the cursor builders, and DOTFILES_OS_RELEASE pointing at a file of its own.
# sudo always fails here, so root's files are only ever listed as left
# undone. Conflict prompts are answered through a pty. The stand-ins log
# their calls, which is how an update is seen to reload and rebuild only
# what changed.
# The stand-ins expand their own variables, and the installer prints ~ for HOME.
# shellcheck disable=SC2016,SC2088

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-desktop-install.XXXXXX")
trap 'chmod -R u+w -- "$WORK" 2>/dev/null; rm -rf -- "$WORK"' EXIT

passed=0
failed=0
pass() { passed=$((passed + 1)); }
fail() { failed=$((failed + 1)); printf 'FAIL  install: %s\n' "$*"; }
is() { if [[ $2 == "$3" ]]; then pass; else fail "$1: got [$2], want [$3]"; fi; }
has() { if grep -qF -- "$3" <<<"$2"; then pass; else fail "$1: no [$3] in:"; printf '%s\n' "$2" | tail -15 | sed 's/^/      /'; fi; }
lacks() { if grep -qF -- "$3" <<<"$2"; then fail "$1: unexpected [$3] in:"; printf '%s\n' "$2" | tail -15 | sed 's/^/      /'; else pass; fi; }
same() { if cmp -s -- "$2" "$3"; then pass; else fail "$1: $2 differs from $3"; fi; }
differs() { if cmp -s -- "$2" "$3"; then fail "$1: $2 equals $3"; else pass; fi; }
present() { if [[ -e "$2" ]]; then pass; else fail "$1: $2 is missing"; fi; }
absent() { if [[ -e "$2" ]]; then fail "$1: $2 is there"; else pass; fi; }
runnable() { if [[ -x "$2" ]]; then pass; else fail "$1: $2 is not executable"; fi; }

# A PATH without quickshell, for the missing-premise case.
mkdir -p "$WORK/noqs"
for f in /usr/bin/*; do
    case ${f##*/} in qs|quickshell) ;; *) ln -s "$f" "$WORK/noqs/${f##*/}" ;; esac
done

# Answers prompts on a pty: each answer is sent when the next prompt appears.
cat >"$WORK/answer.py" <<'EOF'
import os, pty, select, sys, time
answers, cmd = sys.argv[1], sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
out, sent, deadline = b"", 0, time.time() + 120
prompt = b"[a] all, this and every later conflict: "
while time.time() < deadline:
    if select.select([fd], [], [], 0.2)[0]:
        try:
            data = os.read(fd, 65536)
        except OSError:
            break
        if not data:
            break
        out += data
        while sent < min(out.count(prompt), len(answers)):
            os.write(fd, answers[sent].encode() + b"\n")
            sent += 1
else:
    os.kill(pid, 9)
_, status = os.waitpid(pid, 0)
sys.stdout.write(out.decode("utf-8", "replace").replace("\r\n", "\n"))
sys.exit(os.waitstatus_to_exitcode(status))
EOF

# One case: $T holds home/, repo/ and the stand-ins.
setup() {
    T=$(mktemp -d "$WORK/case.XXXXXX")
    mkdir -p "$T/home" "$T/bin" "$T/repo"
    (cd "$REPO" && git ls-files -z --cached --others --exclude-standard | xargs -0 cp -a --parents -t "$T/repo")
    # The cursor builders read /usr/share/icons and take seconds; stand-ins
    # log the build and leave the theme's index behind.
    cat >"$T/repo/theme/cursor/tint-cursors.py" <<EOF
#!/bin/sh
echo "tint-cursors" >>"$T/calls"
mkdir -p "\$HOME/.local/share/icons/Spaceduck-Sky" && : >"\$HOME/.local/share/icons/Spaceduck-Sky/index.theme"
EOF
    for f in pointer.py emphasise.py; do
        printf '#!/bin/sh\n# FILL = "#1d89e4"\nexit 0\n' >"$T/repo/theme/cursor/$f"
    done
    printf 'FILL = "#1d89e4"\n' >>"$T/repo/theme/cursor/pointer.py"
    git -C "$T/repo" init -q
    git -C "$T/repo" add -A
    git -C "$T/repo" -c user.name=test -c user.email=test@test commit -qm initial
    printf 'NAME="Arch Linux"\nID=arch\n' >"$T/os-release"
    : >"$T/session-env"
    # verify-config.sh reads Hyprland's verdict after its banner.
    cat >"$T/bin/Hyprland" <<EOF
#!/bin/sh
if [ "\$1" = --version ]; then echo "Hyprland \$(cat "$T/hyprland-version" 2>/dev/null || echo 0.56.2) built from branch"; exit 0; fi
echo "Config parsing result:"
if [ -e "$T/config-broken" ]; then echo "config/env.lua: an error"; else echo "config ok"; fi
EOF
    cat >"$T/bin/hyprctl" <<EOF
#!/bin/sh
echo "hyprctl \$*" >>"$T/calls"
exit 1
EOF
    cat >"$T/bin/qs" <<EOF
#!/bin/sh
echo "qs \$*" >>"$T/calls"
exit 255
EOF
    cat >"$T/bin/systemctl" <<EOF
#!/bin/sh
echo "systemctl \$*" >>"$T/calls"
[ "\$1 \$2" = "--user show-environment" ] && cat "$T/session-env"
exit 0
EOF
    printf '#!/bin/sh\nexit 1\n' >"$T/bin/sudo"
    printf '#!/bin/sh\nprintf "Inter\\nPretendard\\nCaskaydiaCove Nerd Font\\n"\n' >"$T/bin/fc-list"
    chmod +x "$T/bin/"*
    TPATH=$T/bin:/usr/bin
}

installer() {
    local -a extra=()
    while (( $# )) && [[ $1 != -- ]]; do extra+=("$1"); shift; done
    shift
    env -i HOME="$T/home" PATH="$TPATH" LANG=C.UTF-8 TMPDIR="$T" NO_COLOR=1 GIT_CONFIG_NOSYSTEM=1 \
        DOTFILES_OS_RELEASE="$T/os-release" DOTFILES_ROOT="$T/root" "${extra[@]}" "$@"
}
run() { out=$(installer -- setsid -w bash "$T/repo/install.sh" "$@" </dev/null 2>&1); code=$?; }
# On a pty and without NO_COLOR, as in a terminal.
coloured() { out=$(env -i HOME="$T/home" PATH="$TPATH" LANG=C.UTF-8 TMPDIR="$T" GIT_CONFIG_NOSYSTEM=1 \
    DOTFILES_OS_RELEASE="$T/os-release" DOTFILES_ROOT="$T/root" python3 -I "$WORK/answer.py" "" bash "$T/repo/install.sh" "$@" 2>&1); code=$?; }
calls() { cat "$T/calls" 2>/dev/null; }
answer() { local a=$1; shift; out=$(installer -- python3 -I "$WORK/answer.py" "$a" bash "$T/repo/install.sh" "$@" 2>&1); code=$?; }
commit() { git -C "$T/repo" add -A && git -C "$T/repo" -c user.name=test -c user.email=test@test commit -qm "$1"; }
entries() { find "$T/home" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort | tr '\n' ' '; }
C=.config

# ---- usage ----
setup
run --bogus; is "an unknown argument" "$code" 2
has "an unknown argument prints usage" "$out" "usage: install.sh [--check | --force]"
run --help; is "--help" "$code" 0
run --check --force; is "--check with --force" "$code" 2
is "usage errors write nothing" "$(entries)" ""

# ---- the premise ----
setup
printf 'PRETTY_NAME="NixOS 25.11"\nID=nixos\n' >"$T/os-release"
run; is "an unrecognised distribution" "$code" 1
has "an unrecognised distribution: why" "$out" "NixOS 25.11 is not a distribution this repository recognises"
is "an unrecognised distribution: nothing written" "$(entries)" ""
printf 'NAME="CachyOS"\nID=cachyos\nID_LIKE=arch\n' >"$T/os-release"
run --check
has "an Arch derivative is Arch's family" "$out" "✓ premise: CachyOS (arch family)"
printf 'PRETTY_NAME="Ubuntu 26.04 LTS"\nID=ubuntu\nID_LIKE=debian\n' >"$T/os-release"
run --check
has "Ubuntu is Debian's family" "$out" "✓ premise: Ubuntu 26.04 LTS (debian family), systemd, Hyprland 0.56.2"
printf 'PRETTY_NAME="Red Hat Enterprise Linux 10"\nID="rhel"\nID_LIKE="centos fedora"\n' >"$T/os-release"
run --check
has "RHEL is Fedora's family" "$out" "(fedora family)"
printf 'PRETTY_NAME="Void Linux"\nID="void"\n' >"$T/os-release"
out=$(installer DOTFILES_SYSTEMD="$T/no-systemd" -- setsid -w bash "$T/repo/install.sh" </dev/null 2>&1); code=$?
is "Void, without systemd" "$code" 1
has "Void: why" "$out" "not booted with systemd (Void Linux boots with runit)"
is "Void: nothing written" "$(entries)" ""
setup
echo 0.55.1 >"$T/hyprland-version"
run; is "a Hyprland too old for hyprland.lua" "$code" 1
has "an old Hyprland: why and how" "$out" "Hyprland 0.55.1 is older than 0.56, the first to read hyprland.lua; pacman -S hyprland"
is "an old Hyprland: nothing written" "$(entries)" ""
setup
rm -f -- "$T/bin/qs"
TPATH=$T/bin:$WORK/noqs
run; is "no quickshell" "$code" 1
has "no quickshell: why and how" "$out" "pacman -S quickshell"
is "no quickshell: nothing written" "$(entries)" ""
printf 'PRETTY_NAME="Debian GNU/Linux 14"\nID=debian\n' >"$T/os-release"
run
has "no quickshell on Debian: its package manager" "$out" "apt install quickshell, or build it where the distribution's is missing or older"
setup
printf 'XDG_CONFIG_HOME=/elsewhere\n' >"$T/session-env"
run; is "XDG_CONFIG_HOME differs from the session's" "$code" 1
has "XDG mismatch: both values named" "$out" "XDG_CONFIG_HOME means ~/.config here but /elsewhere to the session's user manager"
is "XDG mismatch: nothing written" "$(entries)" ""
setup
: >"$T/config-broken"
run; is "a Hyprland config that does not load" "$code" 1
has "a config that does not load: why" "$out" "does not load"
is "a broken config: nothing written" "$(entries)" ""

# ---- fresh install, then again ----
setup
run; is "fresh install: root's files left, so 1" "$code" 1
has "fresh install: the premise line" "$out" "✓ premise: Arch Linux (arch family), systemd, Hyprland 0.56.2, quickshell"
has "fresh install: the bar's group" "$out" "~/.config/quickshell/bar"
has "fresh install: a file of it" "$out" "├── ✓ shell.qml"
has "fresh install: the group's count" "$out" "written, 0 unchanged"
has "fresh install: a Hyprland module, named in its group" "$out" "├── ✓ config/env.lua"
has "fresh install: the cursor theme is built" "$(calls)" "tint-cursors"
has "fresh install: the user manager is reloaded" "$(calls)" "systemctl --user daemon-reload"
has "fresh install: no compositor to reload is said" "$out" "no compositor reachable from here"
same "the bar's shell" "$T/home/$C/quickshell/bar/shell.qml" "$T/repo/quickshell/bar/shell.qml"
same "the Hyprland entry point" "$T/home/$C/hypr/hyprland.lua" "$T/repo/hypr/hyprland.lua"
same "a unit" "$T/home/$C/systemd/user/bar.service" "$T/repo/systemd/user/bar.service"
same "the camera switch's user copy" "$T/home/.local/bin/camera-switch" "$T/repo/camera/camera-switch.py"
runnable "bin/bar is executable" "$T/home/.local/bin/bar"
runnable "the hypr scripts are executable" "$T/home/$C/hypr/scripts/camera.sh"
present "the D-Bus service under XDG_DATA_HOME's default" "$T/home/.local/share/dbus-1/services/org.fcitx.Fcitx5.service"
present "the colour scheme under XDG_DATA_HOME's default" "$T/home/.local/share/color-schemes/SpaceduckDark.colors"
if [[ -s "$T/home/.local/state/dotfiles-desktop/installed" ]]; then pass; else fail "the manifest is written"; fi
has "root's files are listed with their command" "$out" "sudo install -D -o root -g root -m 755 '$T/repo/camera/camera-switch.py' $T/root/usr/local/bin/camera-switch"
has "the summary says what is left" "$out" "left undone"
has "root's files are left in their group" "$out" "left for sudo: $T/root/etc/fonts/local.conf"
lacks "no compositor is reloaded from a test" "$(calls)" "hyprctl reload"
: >"$T/calls"
run; has "a second run writes nothing" "$out" "(0 written)"
lacks "a second run finds no conflict" "$out" "conflict"
has "an unchanged group is one line" "$out" "~/.config/quickshell/bar  "
lacks "an update with no Hyprland change asks no compositor" "$(calls)" "hyprctl"
lacks "an update with nothing new reloads no user manager" "$(calls)" "daemon-reload"
lacks "an update with unchanged inputs builds no cursor theme" "$(calls)" "tint-cursors"
run --check
is "--check after an install: only root's files are behind" \
    "$(grep -E '(missing|behind|conflict|stale|not executable) ' <<<"$out" | grep -cvF " $T/root/")" 0
has "--check after an install: root's files are" "$out" "missing $T/root/usr/local/bin/camera-switch"
# An update changes one thing at a time, and reloads only that thing's owner.
echo '-- a newer line' >>"$T/repo/hypr/config/rules.lua"
commit "newer rules"
: >"$T/calls"
run
has "a changed module is said" "$out" "├── ✓ config/rules.lua"
has "and the compositor is asked to reload" "$(calls)" "hyprctl version"
lacks "but not the user manager" "$(calls)" "daemon-reload"
printf '\n# a newer line\n' >>"$T/repo/systemd/user/bar.service"
commit "newer unit"
: >"$T/calls"
run
has "a changed unit reloads the user manager" "$(calls)" "systemctl --user daemon-reload"
lacks "and not the compositor" "$(calls)" "hyprctl"
printf '# a newer line\n' >>"$T/repo/theme/cursor/emphasise.py"
commit "newer cursor"
: >"$T/calls"
run --check
has "--check sees the cursor theme behind" "$out" "behind Spaceduck-Sky"
run
has "a changed cursor script rebuilds the theme" "$(calls)" "tint-cursors"
coloured --check
has "a terminal gets colour" "$out" $'\e[32m✓\e[0m premise:'
has "and tree lines" "$out" "└──"

# ---- conflicts ----
env_lua=$T/home/$C/hypr/config/env.lua
general_lua=$T/home/$C/hypr/config/general.lua
echo '-- changed by hand' >>"$env_lua"
cp -a "$env_lua" "$T/env.mine"
run --check; is "--check with a conflict" "$code" 1
has "--check names the conflict" "$out" "✗ conflict config/env.lua"
same "--check leaves it" "$env_lua" "$T/env.mine"
run; is "a conflict without a terminal stops" "$code" 1
has "it says how to choose" "$out" "run ./install.sh in a terminal to choose, or with --force"
same "the file is kept" "$env_lua" "$T/env.mine"
answer n; is "n stops" "$code" 1
has "the diff names both sides" "$out" "--- ~/$C/hypr/config/env.lua (installed)"
has "the diff numbers the line only the installed file has" "$out" \
    "$(printf '%5s %5s │ %s' "$(($(wc -l <"$T/repo/hypr/config/env.lua") + 1))" "" "--- changed by hand")"
has "n keeps it and says so" "$out" "kept ~/$C/hypr/config/env.lua as it is"
same "n leaves the file" "$env_lua" "$T/env.mine"
answer y; is "y goes on" "$code" 1
same "y overwrites" "$env_lua" "$T/repo/hypr/config/env.lua"
echo '-- one' >>"$env_lua"
echo '-- two' >>"$general_lua"
answer a; is "a goes on" "$code" 1
same "a overwrites the first" "$env_lua" "$T/repo/hypr/config/env.lua"
same "a overwrites the next without asking" "$general_lua" "$T/repo/hypr/config/general.lua"
is "a asks once" "$(grep -c 'every later conflict' <<<"$out")" 1
echo '-- three' >>"$env_lua"
run --force; is "--force goes on" "$code" 1
has "--force says what it forced" "$out" "overwritten after a conflict: config/env.lua"
same "--force overwrites" "$env_lua" "$T/repo/hypr/config/env.lua"

# A file there before the first install is not this repository's either.
setup
mkdir -p "$T/home/$C/hypr"
echo 'hl.config({})' >"$T/home/$C/hypr/hyprland.lua"
run; is "an existing hyprland.lua stops the install" "$code" 1
same "it stays" "$T/home/$C/hypr/hyprland.lua" <(echo 'hl.config({})')
present "what came before it is installed" "$T/home/$C/hypr/config/env.lua"
absent "nothing after the stop is installed" "$T/home/.local/bin/bar"

# ---- versions this repository installed ----
setup
run
# An older commit's file is this repository's: no conflict, just behind.
echo '-- a newer line' >>"$T/repo/hypr/config/rules.lua"
commit newer
run; lacks "an older commit's file is no conflict" "$out" "conflict"
same "it is brought up to date" "$T/home/$C/hypr/config/rules.lua" "$T/repo/hypr/config/rules.lua"
# An uncommitted edit, installed, then edited again: the manifest knows it.
echo '-- uncommitted one' >>"$T/repo/hypr/config/rules.lua"
run
echo '-- uncommitted two' >>"$T/repo/hypr/config/rules.lua"
run; lacks "an installed uncommitted edit is no conflict" "$out" "conflict"
same "it is replaced" "$T/home/$C/hypr/config/rules.lua" "$T/repo/hypr/config/rules.lua"

# ---- seeds ----
setup
run
printf '# a newer comment\n' >>"$T/repo/kde/kded5rc"
printf '# a newer comment\n' >>"$T/repo/kde/kdeglobals"
printf '[General]\nChangedByKDE=true\n' >>"$T/home/$C/kdeglobals"
cp -a "$T/home/$C/kdeglobals" "$T/kdeglobals.mine"
commit "newer seeds"
run --check
has "--check: an untouched seed is behind" "$out" "behind ~/$C/kded5rc (seeded, and untouched since)"
has "--check: a changed one is listed and left" "$out" "~/$C/kdeglobals was changed after it was seeded; left alone"
run
same "an untouched seed takes the newer version" "$T/home/$C/kded5rc" "$T/repo/kde/kded5rc"
same "a seed its program changed is left" "$T/home/$C/kdeglobals" "$T/kdeglobals.mine"
has "and the summary notes it" "$out" "note: 1 seeded file was changed after it was seeded and is left alone"
rm -f -- "$T/home/$C/fcitx5/conf/classicui.conf"
run
same "a file missing from a seeded directory is seeded again" "$T/home/$C/fcitx5/conf/classicui.conf" "$T/repo/fcitx5/conf/classicui.conf"

# The kded seed under its old name, which kded6 never read: removed when it
# is still this repository's copy, kept when something else wrote it.
setup
mkdir -p "$T/home/$C"
printf '[Module-gtkconfig]\nautoload=false\n' >"$T/repo/kde/kded6rc"
commit "the old name"
cp "$T/repo/kde/kded6rc" "$T/home/$C/kded6rc"
git -C "$T/repo" rm -q kde/kded6rc && commit "renamed"
run
absent "the old kded seed, ours, is removed" "$T/home/$C/kded6rc"
has "and said" "$out" "removed ~/$C/kded6rc (kded6 reads kded5rc)"
present "the new name is seeded" "$T/home/$C/kded5rc"
setup
mkdir -p "$T/home/$C"
printf '[Module-other]\nautoload=true\n' >"$T/home/$C/kded6rc"
run
present "a kded6rc something else wrote stays" "$T/home/$C/kded6rc"

# ---- prune ----
setup
echo '// extra' >"$T/repo/quickshell/bar/modules/Extra.qml"
commit extra
run
present "a new module is installed" "$T/home/$C/quickshell/bar/modules/Extra.qml"
git -C "$T/repo" rm -q quickshell/bar/modules/Extra.qml && commit "drop extra"
echo '// not ours' >"$T/home/$C/quickshell/bar/modules/Foreign.qml"
run
absent "a module the repository dropped is removed" "$T/home/$C/quickshell/bar/modules/Extra.qml"
has "the removal is said" "$out" "✓ removed modules/Extra.qml"
present "a file it never installed stays" "$T/home/$C/quickshell/bar/modules/Foreign.qml"
has "and is pointed out" "$out" "left modules/Foreign.qml: not from this repository"
# Dropped by the repository but changed by hand since: asked first.
echo '// extra' >"$T/repo/quickshell/bar/modules/Extra2.qml"
commit extra2
run
echo '// edited' >>"$T/home/$C/quickshell/bar/modules/Extra2.qml"
git -C "$T/repo" rm -q quickshell/bar/modules/Extra2.qml && commit "drop extra2"
run; is "a changed file the repository dropped stops without a terminal" "$code" 1
present "the changed file stays" "$T/home/$C/quickshell/bar/modules/Extra2.qml"
answer y
has "removal asks with a diff against nothing" "$out" "+++ /dev/null (removed from the repository)"
absent "y removes it" "$T/home/$C/quickshell/bar/modules/Extra2.qml"

# A path the repository once had, changed by hand, with no manifest to say
# who wrote it: the history still makes it the repository's to ask about.
setup
echo '// once' >"$T/repo/quickshell/bar/modules/Once.qml"
commit once
run
git -C "$T/repo" rm -q quickshell/bar/modules/Once.qml && commit "drop once"
echo '// edited' >>"$T/home/$C/quickshell/bar/modules/Once.qml"
rm -f -- "$T/home/.local/state/dotfiles-desktop/installed"
run; is "a changed file at a path from the history stops without a terminal" "$code" 1
present "and stays" "$T/home/$C/quickshell/bar/modules/Once.qml"

# Two runs at once would interleave their writes.
setup
run
mkdir -p "$T/home/.local/state/dotfiles-desktop"
flock "$T/home/.local/state/dotfiles-desktop/lock" sleep 5 &
holder=$!
sleep 0.3
run; is "a second run while one holds the lock" "$code" 1
has "it says why" "$out" "another ./install.sh is running"
kill "$holder" 2>/dev/null
wait "$holder" 2>/dev/null

# ---- monitor settings from before the preset ----
setup
mkdir -p "$T/home/$C/hypr"
echo 'return { scale = 2 }' >"$T/home/$C/hypr/monitor_settings.lua"
run
same "an old per-machine file becomes the local one" "$T/home/$C/hypr/monitor_settings.local.lua" <(echo 'return { scale = 2 }')
same "and the preset takes its place" "$T/home/$C/hypr/monitor_settings.lua" "$T/repo/hypr/monitor_settings.lua"

if (( failed )); then
    echo "FAIL  install: $failed of $((passed + failed)) checks"
    exit 1
fi
echo "PASS  install: $passed checks"
