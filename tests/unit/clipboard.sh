#!/usr/bin/env bash
# hypr/scripts/clipboard.sh expire against a cliphist history in a temporary
# directory: each run drops what was there at the run before.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
command -v cliphist >/dev/null 2>&1 || { echo "SKIP  clipboard: cliphist is not installed"; exit 0; }
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-desktop-clipboard.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT
export CLIPHIST_DB_PATH="$WORK/cliphist/db"

passed=0
failed=0
is() {
    if [[ $2 == "$3" ]]; then passed=$((passed + 1)); else failed=$((failed + 1)); printf 'FAIL  clipboard: %s: got [%s], want [%s]\n' "$1" "$2" "$3"; fi
}
store() { printf '%s\n' "$1" | cliphist store; }
held() { cliphist list 2>/dev/null | cut -f2 | tr '\n' ' '; }
expire() { bash "$REPO/hypr/scripts/clipboard.sh" expire; }

expire
is "nothing stored: nothing to do" "$(held)" ""
store one; store two
expire
is "the first run only marks" "$(held)" "two one "
store three
expire
is "the next drops what the first saw" "$(held)" "three "
expire
is "and the one after, the rest" "$(held)" ""
store four
store four
expire; expire
store four
is "a copy made again is new" "$(held)" "four "
rm -f -- "$CLIPHIST_DB_PATH"
store five
expire
is "a history that started over keeps its entries" "$(held)" "five "
expire
is "until the run after" "$(held)" ""

if (( failed )); then
    echo "FAIL  clipboard: $failed of $((passed + failed)) checks"
    exit 1
fi
echo "PASS  clipboard: $passed checks"
