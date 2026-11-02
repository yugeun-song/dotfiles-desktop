#!/usr/bin/env bash
# Runs hypr/scripts/lock.sh with stand-ins for hyprlock, hyprctl, qs and
# fcitx5-remote, in a temporary HOME and runtime directory. hyprlock must
# start with SIGUSR2 ignored: the bar's refresh of the lock screen's island
# (LockIsland.qml) once reached a hyprlock that had not set its handler yet,
# and the signal's default action ended it, so the lock key locked nothing
# (2026-11-02). The island's files of an earlier lock must be gone before
# hyprlock starts and after it ends.
# The stand-ins expand their own variables.
# shellcheck disable=SC2016

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-desktop-lock.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT

passed=0
failed=0
pass() { passed=$((passed + 1)); }
fail() { failed=$((failed + 1)); printf 'FAIL  lock: %s\n' "$*"; }

mkdir -p "$WORK/bin" "$WORK/run" "$WORK/config"
# The stand-in records what it inherited: the shell keeps a signal that was
# ignored on entry ignored.
cat >"$WORK/bin/hyprlock" <<EOF
#!/bin/sh
grep '^SigIgn:' /proc/\$\$/status >"$WORK/sigign"
ls "$WORK/run" >"$WORK/run-at-start"
EOF
printf '#!/bin/sh\necho 1\n' >"$WORK/bin/fcitx5-remote"
printf '#!/bin/sh\nexit 0\n' >"$WORK/bin/qs"
printf '#!/bin/sh\n[ "$1" = locked ] && { echo false; exit 0; }\nexit 1\n' >"$WORK/bin/hyprctl"
chmod +x "$WORK/bin/"*
for part in lead trail mark; do
    echo stale >"$WORK/run/hyprlock-island-$part"
done

env -i HOME="$WORK" PATH="$WORK/bin:/usr/bin" XDG_RUNTIME_DIR="$WORK/run" XDG_CONFIG_HOME="$WORK/config" \
    bash "$REPO/hypr/scripts/lock.sh" >/dev/null 2>&1
code=$?

if [[ $code -eq 0 ]]; then pass; else fail "lock.sh exited $code with a hyprlock that exits 0"; fi
if [[ -s "$WORK/sigign" ]]; then
    pass
    mask=$(awk '{print $2}' "$WORK/sigign")
    # SIGUSR2 is signal 12, bit 11 of the mask.
    if (( (16#$mask >> 11) & 1 )); then pass; else fail "hyprlock started with SIGUSR2 not ignored (SigIgn $mask)"; fi
else
    fail "the hyprlock stand-in never ran"
fi
if grep -q '^hyprlock-island-' "$WORK/run-at-start" 2>/dev/null; then
    fail "the island's files of an earlier lock were still there as hyprlock started"
else
    pass
fi
if compgen -G "$WORK/run/hyprlock-island-*" >/dev/null; then
    fail "the island's files outlived the lock"
else
    pass
fi

if (( failed )); then
    printf 'FAIL  lock: %d of %d checks failed\n' "$failed" "$((passed + failed))"
    exit 1
fi
printf 'PASS  lock: %d checks\n' "$passed"
