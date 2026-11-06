#!/usr/bin/env bash
# packages/: the lists name no package twice, nothing left out (excluded.txt)
# or tied to one machine's hardware or boot is listed, and apply.sh installs
# what is missing and nothing else: never with -y, the AUR after the
# repositories, yay in its review, a stop on any failure, nothing without a
# terminal. Stubs stand in for pacman, sudo, yay, makepkg and git; nothing
# reaches the system.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf -- "${WORK:?}"' EXIT

failed=0
passed=0
ok() {
    if [[ "$2" == "$3" ]]; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        printf 'FAIL  packages: %s: got [%s], want [%s]\n' "$1" "$2" "$3"
    fi
}

# ---------------------------------------------------------------- the lists --
names() { sed -E 's/#.*//; s/[[:space:]]+//g; /^$/d' -- "$@"; }
dupes=$(names "$REPO"/packages/{desktop,user,user-aur}.txt | sort | uniq -d | tr '\n' ' ')
ok "no package in two lists" "$dupes" ""
left=$(comm -12 <(names "$REPO"/packages/{desktop,user,user-aur}.txt | sort -u) <(names "$REPO/packages/excluded.txt" | sort -u) | tr '\n' ' ')
ok "nothing left out is listed" "$left" ""
bad=$(names "$REPO"/packages/*.txt | grep -v -E '^[a-z0-9@._+-]+$' | tr '\n' ' ')
ok "every name is a package name" "$bad" ""
machine=$(names "$REPO"/packages/{desktop,user,user-aur}.txt \
    | grep -E '^(linux(-lts|-zen|-hardened)?(-headers)?|linux-firmware.*|.*-ucode|grub.*|efibootmgr|mkinitcpio|.*-dkms|nvidia.*|vulkan-(intel|radeon)|xf86-video-.*|intel-media-driver|libva-intel-driver|sof-firmware)$' | tr '\n' ' ')
ok "nothing tied to the hardware or the boot is listed" "$machine" ""
ok "the AUR step's tools come first" "$(names "$REPO/packages/desktop.txt" | head -2 | tr '\n' ' ')" "base-devel git "

# ------------------------------------------------------------------- stubs --
S=$WORK/stub
mkdir -p "$WORK/bin" "$S" "$WORK/pk"
cp "$REPO/packages/apply.sh" "$WORK/pk/apply.sh"
printf 'base-devel\ngit\nalpha\nbravo\n' >"$WORK/pk/desktop.txt"
printf 'charlie # a note\n\ndelta\n' >"$WORK/pk/user.txt"
printf 'echo-bin\nyay-bin\n' >"$WORK/pk/user-aur.txt"
printf 'kernel\n' >"$WORK/pk/excluded.txt"

cat >"$WORK/bin/pacman" <<'EOF'
#!/usr/bin/env bash
S=$STUB
case $1 in
    -T) shift; [[ $1 == -- ]] && shift
        miss=0
        for p in "$@"; do grep -qxF -- "$p" "$S/missing" 2>/dev/null && { echo "$p"; miss=1; }; done
        (( miss )) && exit 127; exit 0 ;;
    -Si) shift; [[ $1 == -- ]] && shift
        bad=0
        for p in "$@"; do grep -qxF -- "$p" "$S/absent" 2>/dev/null && { echo "error: package '$p' was not found" >&2; bad=1; }; done
        exit "$bad" ;;
    -Qqe) cat "$S/explicit" 2>/dev/null; exit 0 ;;
    *) echo "pacman $*" >>"$S/log"
       # What it installs is installed from then on.
       for p in "$@"; do sed -i "/^$p\$/d" "$S/missing" 2>/dev/null; done
       exit "$(cat "$S/pacman_exit" 2>/dev/null || echo 0)" ;;
esac
EOF
cat >"$WORK/bin/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo $*" >>"$STUB/log"
exec "$@"
EOF
cat >"$WORK/yay" <<'EOF'
#!/usr/bin/env bash
echo "yay $*" >>"$STUB/log"
exit "$(cat "$STUB/yay_exit" 2>/dev/null || echo 0)"
EOF
cat >"$WORK/bin/makepkg" <<'EOF'
#!/usr/bin/env bash
echo "makepkg $* in ${PWD##*/}" >>"$STUB/log"
sed -i '/^yay-bin$/d' "$STUB/missing"
exit "$(cat "$STUB/makepkg_exit" 2>/dev/null || echo 0)"
EOF
cat >"$WORK/bin/git" <<'EOF'
#!/usr/bin/env bash
echo "git $*" >>"$STUB/log"
mkdir -p "${*: -1}" && echo "pkgname=yay-bin" >"${*: -1}/PKGBUILD"
EOF
chmod +x "$WORK/bin"/* "$WORK/yay"

# A terminal for the run: a pty, answering a [y/N] question with $1.
cat >"$WORK/pty.py" <<'EOF'
import os, pty, select, sys
answer = sys.argv[1].encode()
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[2], sys.argv[2:])
out, sent = b"", False
while True:
    ready, _, _ = select.select([fd], [], [], 20)
    if not ready:
        break
    try:
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    out += data
    if answer and not sent and b"[y/N]" in out:
        os.write(fd, answer + b"\n")
        sent = True
_, status = os.waitpid(pid, 0)
sys.stdout.write(out.decode(errors="replace"))
sys.exit(os.waitstatus_to_exitcode(status))
EOF

# $1: what is missing; $2: whether yay is installed.
setup() {
    local -a miss=()
    read -ra miss <<<"$1"
    rm -f -- "$S"/*
    printf '%s\n' "${miss[@]}" >"$S/missing"
    : >"$S/log"
    printf 'alpha\nbravo\nhand-made\nkernel\n' >"$S/explicit"
    if [[ $2 == yay ]]; then cp "$WORK/yay" "$WORK/bin/yay"; else rm -f "$WORK/bin/yay"; fi
}
# The runs see the stubs and a short list of real tools, never /usr/bin
# whole: a real yay found there once ran against the stubbed sudo.
mkdir -p "$WORK/sys"
for t in bash env setsid timeout python3 dirname sed sort comm mktemp cat rm grep mkdir ls; do
    ln -s -- "$(command -v "$t")" "$WORK/sys/$t" || { echo "FAIL  packages: no $t to run the tests with"; exit 1; }
done
env_run() { env -i HOME="$WORK" TMPDIR="$WORK" PATH="$WORK/bin:$WORK/sys" STUB="$S" NO_COLOR=1 "$@"; }
# Before any run: every tool that installs resolves to a stub, or to nothing.
cp "$WORK/yay" "$WORK/bin/yay"
for t in pacman sudo yay makepkg git; do
    where=$(env_run bash -c "command -v $t" 2>/dev/null)
    if [[ "$where" != "$WORK/bin/$t" ]]; then
        echo "FAIL  packages: $t resolves to ${where:-nothing}, not to its stub; no test was run"
        exit 1
    fi
done
rm -f "$WORK/bin/yay"
[[ -z "$(env_run bash -c 'command -v yay' 2>/dev/null)" ]] || { echo "FAIL  packages: a yay outside the stubs is reachable; no test was run"; exit 1; }
plain() { out=$(env_run timeout 30 setsid -w bash "$WORK/pk/apply.sh" "$@" </dev/null 2>&1); code=$?; }
tty() { local a=$1; shift; out=$(env_run timeout 30 python3 -I "$WORK/pty.py" "$a" bash "$WORK/pk/apply.sh" "$@" 2>&1); code=$?; }
log() { tr '\n' ';' <"$S/log"; }

setup "" yay
tty ""
ok "nothing missing: exit 0" "$code" 0
ok "nothing missing: no install" "$(log)" ""

setup "bravo delta" yay
tty ""
ok "missing ones only, --needed, no sync" "$(log)" "sudo pacman -S --needed -- bravo delta;pacman -S --needed -- bravo delta;"
ok "an install that went: exit 0" "$code" 0

setup "bravo delta" yay
printf 'delta\n' >"$S/absent"
tty ""
ok "one no repository carries is left" "$(log)" "sudo pacman -S --needed -- bravo;pacman -S --needed -- bravo;"
case $out in *"in no enabled repository: delta"*) ok "and said" 1 1 ;; *) ok "and said" "$out" "delta named" ;; esac

setup "bravo echo-bin" yay
tty ""
ok "the AUR after the repositories, with yay's review" "$(log)" \
    "sudo pacman -S --needed -- bravo;pacman -S --needed -- bravo;yay -S --needed --sudoloop --diffmenu -- echo-bin;"

setup "bravo echo-bin" yay
echo 1 >"$S/pacman_exit"
tty ""
ok "pacman failing stops the run: status" "$code" 1
ok "pacman failing stops the run: no yay" "$(log)" "sudo pacman -S --needed -- bravo;pacman -S --needed -- bravo;"

setup "echo-bin" yay
echo 1 >"$S/yay_exit"
tty ""
ok "yay failing stops the run" "$code" 1

setup "bravo echo-bin" yay
plain
ok "no terminal: exit 3" "$code" 3
ok "no terminal: nothing installed" "$(log)" ""

setup "bravo echo-bin" yay
plain --check
ok "--check with something missing: exit 1" "$code" 1
ok "--check installs nothing" "$(log)" ""
case $out in *"in no list"*hand-made*) ok "--check names a package no list has" 1 1 ;; *) ok "--check names a package no list has" "$out" "hand-made" ;; esac
case $out in *kernel*) ok "--check leaves out the excluded" "$out" "no kernel" ;; *) ok "--check leaves out the excluded" 1 1 ;; esac

setup "bravo" yay
plain --pending
ok "--pending without a terminal: nothing to do here" "$code" 1
tty "" --pending
ok "--pending in a terminal with one missing" "$code" 0
setup "" yay
tty "" --pending
ok "--pending with nothing missing" "$code" 1

setup "echo-bin yay-bin" none
tty "n"
ok "yay-bin declined: stops" "$code" 1
case $(log) in
    "git clone --quiet --depth 1 -- https://aur.archlinux.org/yay-bin.git $WORK/tmp."*"/yay-bin;") ok "yay-bin declined: cloned, not built" 1 1 ;;
    *) ok "yay-bin declined: cloned, not built" "$(log)" "the clone alone" ;;
esac
ok "yay-bin declined: its clone is gone" "$(ls -d "$WORK"/tmp.* 2>/dev/null)" ""
setup "echo-bin yay-bin" none
tty "y"
case $(log) in
    *"makepkg -si --needed in yay-bin"*) ok "yay-bin confirmed: built with makepkg -si --needed" 1 1 ;;
    *) ok "yay-bin confirmed: built with makepkg -si --needed" "$(log)" "makepkg -si --needed" ;;
esac

if grep -h -E '(^| )(sudo pacman|pacman|yay) [^;]*-S[a-z]*y' "$S/log" 2>/dev/null; then ok "no -y anywhere" "a sync" "none"; else ok "no -y anywhere" 1 1; fi

if (( failed )); then exit 1; fi
echo "PASS  packages: $passed checks"
