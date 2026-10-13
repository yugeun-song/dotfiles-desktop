#!/usr/bin/env bash
# Runs install.sh against a temporary HOME. Nothing reaches the real one or
# the running session: each case gets its own HOME, a copy of this checkout
# as its own repository (so a case can commit and the installer's git checks
# see it), stand-ins for Hyprland, hyprctl, qs, systemctl, sudo and fc-list,
# and DOTFILES_OS_RELEASE pointing at a file of its own. sudo always fails
# here, so root's files are only ever listed as left undone. Conflict prompts
# are answered through a pty.
# shellcheck disable=SC2016 # the stand-ins expand their own variables

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
    # The cursor builders read /usr/share/icons and take seconds; not what
    # is tested here.
    for f in tint-cursors.py pointer.py emphasise.py; do
        printf '#!/bin/sh\nexit 0\n' >"$T/repo/theme/cursor/$f"
    done
    git -C "$T/repo" init -q
    git -C "$T/repo" add -A
    git -C "$T/repo" -c user.name=test -c user.email=test@test commit -qm initial
    printf 'NAME="Arch Linux"\nID=arch\n' >"$T/os-release"
    : >"$T/session-env"
    # verify-config.sh reads Hyprland's verdict after its banner.
    cat >"$T/bin/Hyprland" <<EOF
#!/bin/sh
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
        DOTFILES_OS_RELEASE="$T/os-release" "${extra[@]}" "$@"
}
run() { out=$(installer -- setsid -w bash "$T/repo/install.sh" "$@" </dev/null 2>&1); code=$?; }
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
printf 'NAME="Debian GNU/Linux"\nID=debian\n' >"$T/os-release"
run; is "not Arch" "$code" 1
has "not Arch: why" "$out" "says ID=debian"
is "not Arch: nothing written" "$(entries)" ""
printf 'NAME="CachyOS"\nID=cachyos\nID_LIKE=arch\n' >"$T/os-release"
run --check
lacks "an Arch derivative meets the premise" "$out" "premise is not met"
setup
rm -f -- "$T/bin/qs"
TPATH=$T/bin:$WORK/noqs
run; is "no quickshell" "$code" 1
has "no quickshell: why and how" "$out" "pacman -S quickshell"
is "no quickshell: nothing written" "$(entries)" ""
setup
printf 'XDG_CONFIG_HOME=/elsewhere\n' >"$T/session-env"
run; is "XDG_CONFIG_HOME differs from the session's" "$code" 1
has "XDG mismatch: both values named" "$out" "but /elsewhere to the session's user manager"
is "XDG mismatch: nothing written" "$(entries)" ""
setup
: >"$T/config-broken"
run; is "a Hyprland config that does not load" "$code" 1
has "a config that does not load: why" "$out" "does not load"
is "a broken config: nothing written" "$(entries)" ""

# ---- fresh install, then again ----
setup
run; is "fresh install: root's files left, so 1" "$code" 1
has "fresh install: the bar" "$out" "installed $T/home/$C/quickshell/bar"
same "the bar's shell" "$T/home/$C/quickshell/bar/shell.qml" "$T/repo/quickshell/bar/shell.qml"
same "the Hyprland entry point" "$T/home/$C/hypr/hyprland.lua" "$T/repo/hypr/hyprland.lua"
same "a unit" "$T/home/$C/systemd/user/bar.service" "$T/repo/systemd/user/bar.service"
same "the camera switch's user copy" "$T/home/.local/bin/camera-switch" "$T/repo/camera/camera-switch.py"
runnable "bin/bar is executable" "$T/home/.local/bin/bar"
runnable "the hypr scripts are executable" "$T/home/$C/hypr/scripts/camera.sh"
present "the D-Bus service under XDG_DATA_HOME's default" "$T/home/.local/share/dbus-1/services/org.fcitx.Fcitx5.service"
present "the colour scheme under XDG_DATA_HOME's default" "$T/home/.local/share/color-schemes/SpaceduckDark.colors"
if [[ -s "$T/home/.local/state/dotfiles-desktop/installed" ]]; then pass; else fail "the manifest is written"; fi
has "root's files are listed with their command" "$out" "sudo install -D -o root -g root -m 755 '$T/repo/camera/camera-switch.py' /usr/local/bin/camera-switch"
has "the summary says what is left" "$out" "left undone"
lacks "no compositor is reloaded from a test" "$(cat "$T/calls")" "hyprctl reload"
run; has "a second run writes nothing" "$out" "(0 files written)"
lacks "a second run finds no conflict" "$out" "conflict"
run --check
lacks "--check after an install: no user file is behind" "$out" "$T/home"
has "--check after an install: root's files are" "$out" "/usr/local/bin/camera-switch"

# ---- conflicts ----
env_lua=$T/home/$C/hypr/config/env.lua
general_lua=$T/home/$C/hypr/config/general.lua
echo '-- changed by hand' >>"$env_lua"
cp -a "$env_lua" "$T/env.mine"
run --check; is "--check with a conflict" "$code" 1
has "--check names the conflict" "$out" "CONFLICT $env_lua is not what this repository installed"
same "--check leaves it" "$env_lua" "$T/env.mine"
run; is "a conflict without a terminal stops" "$code" 1
has "it says how to choose" "$out" "run ./install.sh in a terminal to choose, or with --force"
same "the file is kept" "$env_lua" "$T/env.mine"
answer n; is "n stops" "$code" 1
has "the diff names both sides" "$out" "--- $env_lua (installed)"
has "the diff numbers the line only the installed file has" "$out" "   94       │ --- changed by hand"
has "n keeps it and says so" "$out" "kept $env_lua as it is"
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
has "--force says what it forced" "$out" "forced $env_lua"
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
has "the removal is said" "$out" "removed stale $T/home/$C/quickshell/bar/modules/Extra.qml"
present "a file it never installed stays" "$T/home/$C/quickshell/bar/modules/Foreign.qml"
has "and is pointed out" "$out" "Foreign.qml: not from this repository"
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
