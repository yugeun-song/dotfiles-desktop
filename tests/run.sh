#!/usr/bin/env bash
# Checks this repository before it is installed or committed:
#
#   tests/run.sh          static checks and unit tests; no display needed
#   tests/run.sh --e2e    and the end-to-end suite (tests/e2e/run.sh), in a
#                         nested headless Hyprland; needs a running session
#
# Nothing here touches the installed desktop: every test works on copies, in
# temporary directories, with stubs for anything that reaches the machine.
# A tool that is not installed skips its check rather than failing it.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO" || exit 2

E2E=0
case "${1:-}" in
    "") ;;
    --e2e) E2E=1 ;;
    *) echo "usage: tests/run.sh [--e2e]" >&2; exit 2 ;;
esac

failed=0
fail() { echo "FAIL  $*"; failed=1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Every tracked shell script, by extension or by its first line.
shell_files() {
    git ls-files | while read -r f; do
        [[ -f "$f" ]] || continue
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
    done < <(git ls-files '*.lua')
    (( bad )) && fail "lua syntax" || echo "PASS  lua syntax"
else
    echo "SKIP  lua syntax: no luac"
fi

mapfile -t py < <(git ls-files '*.py')
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
tests/unit/monitor-override.sh || failed=1
tests/unit/alarm.sh || failed=1
for name in keyfeed inputmethod; do
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

if (( failed )); then
    echo "some checks failed"
    exit 1
fi
echo "all checks passed"
