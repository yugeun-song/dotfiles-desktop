#!/usr/bin/env bash
# Checks this repository before it is installed or committed:
#
#   tests/run.sh          static checks and unit tests; no display needed
#   tests/run.sh --e2e    and the end-to-end suite (tests/e2e/run.sh), in a
#                         nested headless Hyprland; needs a running session
#   tests/run.sh --vm     and the camera switch against a real kernel
#                         (tests/vm/camera.sh), in a virtual machine
#
# Nothing here touches the installed desktop: every test works on copies, in
# temporary directories, with stubs for anything that reaches the machine.
# A tool that is not installed skips its check rather than failing it.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO" || exit 2

E2E=0
VM=0
for arg in "$@"; do
    case "$arg" in
        --e2e) E2E=1 ;;
        --vm) VM=1 ;;
        *) echo "usage: tests/run.sh [--e2e] [--vm]" >&2; exit 2 ;;
    esac
done

failed=0
fail() { echo "FAIL  $*"; failed=1; }
have() { command -v "$1" >/dev/null 2>&1; }

# The working tree as install.sh would copy it: tracked files that are
# still there and new ones not yet added, ignored ones left out. Tracked
# alone, a file deleted but not yet committed failed the python check and a
# new script went unchecked.
tree_files() {
    git ls-files --cached --others --exclude-standard "$@" | sort -u | while read -r f; do
        [[ -f "$f" ]] && echo "$f"
    done
}

# Every shell script, by extension or by its first line.
shell_files() {
    tree_files | while read -r f; do
        case "$f" in
            *.sh) echo "$f" ;;
            *.*) ;;
            *) head -n 1 "$f" 2>/dev/null | grep -qE '^#!.*\b(ba)?sh\b' && echo "$f" ;;
        esac
    done
}

if have shellcheck; then
    mapfile -t files < <(shell_files)
    if out=$(shellcheck -x "${files[@]}" 2>&1); then
        echo "PASS  shellcheck: ${#files[@]} scripts"
    else
        fail "shellcheck:"
        echo "$out" | head -40
    fi
else
    echo "SKIP  shellcheck: not installed"
fi

luac=$(command -v luac5.4 || command -v luac || true)
if [[ -n "$luac" ]]; then
    bad=0
    while read -r f; do
        "$luac" -p "$f" || bad=1
    done < <(tree_files '*.lua')
    (( bad )) && fail "lua syntax" || echo "PASS  lua syntax"
else
    echo "SKIP  lua syntax: no luac"
fi

mapfile -t py < <(tree_files '*.py')
if python3 -m py_compile "${py[@]}" 2>&1; then
    if have pyflakes; then
        if out=$(pyflakes "${py[@]}" 2>&1); then echo "PASS  python: ${#py[@]} files"; else fail "pyflakes:"; echo "$out"; fi
    else
        echo "PASS  python: ${#py[@]} files compile (pyflakes not installed)"
    fi
else
    fail "python: a file does not compile"
fi
# py_compile leaves caches beside the sources.
find . -name __pycache__ -type d -not -path './.git/*' -exec rm -rf {} + 2>/dev/null

if have Hyprland; then
    if out=$(hypr/scripts/verify-config.sh 2>&1); then echo "PASS  hyprland config"; else fail "hyprland config:"; echo "$out" | tail -20; fi
else
    echo "SKIP  hyprland config: Hyprland is not installed"
fi

tests/unit/qml.sh || failed=1
tests/unit/bar.sh || failed=1
tests/unit/clipboard.sh || failed=1
tests/unit/monitor-override.sh || failed=1
tests/unit/recover.sh || failed=1
tests/unit/alarm.sh || failed=1
tests/unit/weather.sh || failed=1
tests/unit/camera.sh || failed=1
tests/unit/install.sh || failed=1
for name in keyfeed keyfeed_hold inputstate camera_switch lock_media lock_colours share_apps polkit_tty obs_auth; do
    if out=$(python3 -I "tests/unit/test_$name.py" 2>&1); then
        echo "PASS  $name: $(grep -oE '^Ran [0-9]+ tests' <<<"$out" | sed 's/^Ran //')"
    else
        fail "$name:"
        echo "$out" | tail -20
    fi
done

if (( E2E )); then
    tests/e2e/run.sh || failed=1
fi
if (( VM )); then
    tests/vm/camera.sh || failed=1
fi

if (( failed )); then
    echo "some checks failed"
    exit 1
fi
echo "all checks passed"
