#!/usr/bin/env bash
# Compiles every shader here to the .qsb that Qt Quick loads, beside it:
#   shaders/build.sh            write them
#   shaders/build.sh --check    fail when one written here differs
# The .qsb files are kept in the repository, so the desktop never needs
# Qt's shader tools (qt6-shadertools) to run; tests/unit/qml.sh checks them
# with --check. A newer qsb may write different bytes for the same source:
# run this again then.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
QSB=$(command -v qsb 2>/dev/null || echo /usr/lib/qt6/bin/qsb)
[[ -x "$QSB" ]] || { echo "shaders: no qsb (qt6-shadertools)"; exit 2; }
check=0
[[ "${1:-}" == --check ]] && check=1
tmp=$(mktemp -d)
trap 'rm -rf -- "${tmp:?}"' EXIT
status=0
for src in "$HERE"/*.frag "$HERE"/*.vert; do
    [[ -e "$src" ]] || continue
    name=$(basename -- "$src")
    "$QSB" --glsl "100 es,120,150" -o "$tmp/$name.qsb" "$src"
    if (( check )); then
        cmp -s "$tmp/$name.qsb" "$HERE/$name.qsb" || { echo "shaders: $name.qsb is not what $name compiles to; run shaders/build.sh"; status=1; }
    else
        cp "$tmp/$name.qsb" "$HERE/$name.qsb"
    fi
done
exit "$status"
