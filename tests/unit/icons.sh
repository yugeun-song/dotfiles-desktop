#!/usr/bin/env bash
# kde/icons/verify.py against a local stand-in for Lucide's repository, offline:
# what passes, what is wrong (status 2, which makes install.sh remove the
# theme) and what merely cannot be asked (status 3, which must not).

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-desktop-icons.XXXXXX")
trap 'rm -rf -- "$T"' EXIT
passed=0
failed=0
is() { if [[ $2 == "$3" ]]; then passed=$((passed + 1)); else failed=$((failed + 1)); printf 'FAIL  icons: %s: got [%s], want [%s]\n' "$1" "$2" "$3"; [[ -s "$T/err" ]] && sed 's/^/      /' "$T/err"; fi; }

up=$T/upstream
git init -q "$up"
g() { git -C "$up" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
python3 -I - "$REPO/kde/icons/build.py" "$up" <<'PY'
import importlib.util, pathlib, sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("b", sys.argv[1])
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)
up = pathlib.Path(sys.argv[2])
(up / "icons").mkdir()
for i, name in enumerate(b.MAP):
    (up / "icons" / f"{name}.svg").write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg"><path d="M{i} 1h2" /><circle cx="3" cy="3" r="1" /></svg>\n')
(up / "icons" / "not-used.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0" /></svg>\n')
(up / "LICENSE").write_text("ISC License, a stand-in\n")
PY
g add -A; g commit -q -m one; g tag 1.0
url="file://$up"
verify() { python3 -I "$REPO/kde/icons/verify.py" --lock "$T/lock" --theme "$T/theme" "$@" >"$T/out" 2>"$T/err"; echo $?; }

is "the theme and lock are written from a tag" "$(verify --update --tag 1.0 --repo "$url")" 0
is "and then pass" "$(verify)" 0
glyph=$T/theme/scalable/places/folder.svg
cp "$glyph" "$T/glyph"; cp "$T/lock" "$T/lock.good"

echo changed >>"$glyph"
is "a changed icon is wrong" "$(verify)" 2
cp "$T/glyph" "$glyph"
echo extra >"$T/theme/extra.svg"
is "a file the theme does not have is wrong" "$(verify)" 2
rm -f -- "$T/theme/extra.svg"
rm -f -- "$glyph"
is "a missing icon is wrong" "$(verify)" 2
cp "$T/glyph" "$glyph"
is "and back as it was it passes" "$(verify)" 0

# A lock changed to fit changed files still has to match upstream.
sed -i -E '0,/^file ([0-9a-f]{40}) ([0-9a-f]{64}) icons/s//file 0000000000000000000000000000000000000000 \2 icons/' "$T/lock"
is "a Git id the commit does not have is wrong" "$(verify)" 2
cp "$T/lock.good" "$T/lock"
sed -i -E '0,/^file ([0-9a-f]{40}) ([0-9a-f]{64}) icons/s//file \1 0000000000000000000000000000000000000000000000000000000000000000 icons/' "$T/lock"
is "a SHA-256 that is not the file's is wrong" "$(verify)" 2
cp "$T/lock.good" "$T/lock"
sed -i '0,/^file .*icons/{/^file .*icons/d}' "$T/lock"
is "a lock short of a file is wrong" "$(verify)" 2
cp "$T/lock.good" "$T/lock"

# The tag moved upstream: the pinned commit is no longer what it names.
echo '<svg xmlns="http://www.w3.org/2000/svg"><path d="M9 9" /></svg>' >"$up/icons/folder.svg"
g add -A; g commit -q -m two; g tag -f 1.0 >/dev/null
is "a tag moved upstream is wrong" "$(verify)" 2
sed -i 's/^tag .*/tag 9.9/' "$T/lock"
is "a tag upstream does not have is wrong" "$(verify)" 2
cp "$T/lock.good" "$T/lock"

# What only cannot be asked is not wrong.
sed -i "s|^repo .*|repo file://$T/nowhere|" "$T/lock"
is "a repository out of reach is no verdict" "$(verify)" 3
cp "$T/lock.good" "$T/lock"
g tag -f 1.0 HEAD~1 >/dev/null
is "the tag back on its commit passes" "$(verify)" 0
python3="$(command -v python3)"
PATH="$T/empty" "$python3" -I "$REPO/kde/icons/verify.py" --lock "$T/lock" --theme "$T/theme" >/dev/null 2>"$T/err"
is "no git is no verdict" "$?" 3

# An icon that is more than plain shapes never makes a theme.
echo '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>' >"$up/icons/folder.svg"
g add -A; g commit -q -m three; g tag 2.0
is "a script in an upstream icon stops an update" "$(verify --update --tag 2.0 --repo "$url")" 2
is "and writes no lock" "$(cmp -s "$T/lock" "$T/lock.good"; echo $?)" 0

# Reads the configuration of nobody: a rewrite in the user's would not count.
fake=$T/home
mkdir -p "$fake"
git -C "$fake" init -q 2>/dev/null
printf '[url "file://%s/nowhere"]\n\tinsteadOf = %s\n' "$T" "$url" >"$fake/.gitconfig"
HOME="$fake" verify >"$T/code"
is "the user's url.insteadOf does not reach it" "$(cat "$T/code")" 0

# ---- the file icons: no committed theme, a stand-in for Material's repository ----
fup=$T/files-upstream
git init -q "$fup"
fg() { git -C "$fup" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
python3 -I - "$REPO/kde/icons/files.py" "$fup" <<'PY'
import importlib.util, pathlib, sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("f", sys.argv[1])
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)
up = pathlib.Path(sys.argv[2])
for i, name in enumerate(f.MAP):
    path = up / "icons" / f"{name}.svg"
    path.parent.mkdir(exist_ok=True)
    path.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path fill="#123456" d="M{i} 1h2"/></svg>\n')
(up / "icons" / "not-used.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg"><script/></svg>\n')
gen = up / "src/core/generator"
gen.mkdir(parents=True)
(gen / "fileGenerator.ts").write_text("const fileIcon =\n    'M2 2h3v3z';\n")
(up / "LICENSE").write_text("MIT, a stand-in\n")
PY
fg add -A; fg commit -q -m one; fg tag 1.0
furl="file://$fup"
there() { if [[ -e "$1" ]]; then echo yes; else echo no; fi; }
fv() { python3 -I "$REPO/kde/icons/verify.py" --builder "$REPO/kde/icons/files.py" --lock "$T/flock" "$@" >"$T/out" 2>"$T/err"; echo $?; }
is "file icons: a lock is written from a tag" "$(fv --update --tag 1.0 --repo "$furl")" 0
is "and no theme with it" "$(there "$REPO/kde/icons/SpaceduckFiles")" no
is "and it passes" "$(fv --out "$T/ftheme")" 0
is "and writes the theme" "$(cmp -s "$T/ftheme/scalable/mimetypes/text-x-csrc.svg" "$fup/icons/c.svg"; echo $?)" 0
is "with upstream's licence beside it" "$(cmp -s "$T/ftheme/LICENSE" "$fup/LICENSE"; echo $?)" 0
is "over the line icons" "$(grep -c '^Inherits=SpaceduckLines,' "$T/ftheme/index.theme")" 1
is "the plain file is the generator's path" "$(grep -c 'M2 2h3v3z' "$T/ftheme/scalable/mimetypes/unknown.svg")" 1
is "no folder is coloured: the line theme draws them all" "$(find "$T/ftheme" \( -name '*folder*' -o -name 'inode-directory*' -o -name 'user-*' \) | wc -l)" 0
is "what the table does not name stays out" "$(grep -rl '<script' "$T/ftheme" | wc -l)" 0
rm -rf -- "$T/ftheme"
cp "$T/flock" "$T/flock.good"
sed -i -E '0,/^file ([0-9a-f]{40}) ([0-9a-f]{64}) icons/s//file 0000000000000000000000000000000000000000 \2 icons/' "$T/flock"
is "a Git id the commit does not have is wrong" "$(fv --out "$T/ftheme")" 2
is "and writes nothing" "$(there "$T/ftheme")" no
cp "$T/flock.good" "$T/flock"
sed -i "s|^repo .*|repo file://$T/nowhere|" "$T/flock"
is "a repository out of reach is no verdict" "$(fv --out "$T/ftheme")" 3
is "and writes nothing" "$(there "$T/ftheme")" no
cp "$T/flock.good" "$T/flock"
refused() { # a name for the case, the SVG
    printf '%s\n' "$2" >"$fup/icons/c.svg"
    fg add -A; fg commit -q -m "$1"; fg tag "$1"
    is "$1 stops an update" "$(fv --update --tag "$1" --repo "$furl")" 2
    is "and writes no lock" "$(cmp -s "$T/flock" "$T/flock.good"; echo $?)" 0
}
svg='<svg xmlns="http://www.w3.org/2000/svg"'
refused script "$svg><script>alert(1)</script></svg>"
refused image "$svg><image href=\"https://example.com/a.png\"/></svg>"
refused use-out "$svg><use href=\"https://example.com/a.svg#b\"/></svg>"
refused url-out "$svg><path d=\"M0 0\" fill=\"url(https://example.com/a)\"/></svg>"
refused style "$svg><style>path{fill:red}</style></svg>"
refused style-attr "$svg><path d=\"M0 0\" style=\"fill:red\"/></svg>"
refused event "$svg onload=\"alert(1)\"></svg>"
refused doctype "<!DOCTYPE svg [<!ENTITY a \"b\">]>$svg></svg>"
refused oversize "$svg><path d=\"M$(printf '0 %.0s' {1..40000})\"/></svg>"

# The families come from the machine's database.
db=$T/mime
mkdir -p "$db"
printf 'text/x-csrc\naudio/x-new\n' >"$db/types"
printf 'application/x-new-archive:package-x-generic\nno/slash/../x:package-x-generic\n' >"$db/generic-icons"
git -C "$fup" checkout -q 1.0 2>/dev/null
python3 -I -B "$REPO/kde/icons/files.py" --from "$fup" --out "$T/ftheme2" --mime "$db" >"$T/out" 2>"$T/err"
is "a family's new type takes its icon" "$(cmp -s "$T/ftheme2/scalable/mimetypes/audio-x-new.svg" "$fup/icons/audio.svg"; echo $?)" 0
is "by the database's generic icon too" "$(cmp -s "$T/ftheme2/scalable/mimetypes/application-x-new-archive.svg" "$fup/icons/zip.svg"; echo $?)" 0
is "a type named in the table keeps its own" "$(cmp -s "$T/ftheme2/scalable/mimetypes/text-x-csrc.svg" "$fup/icons/c.svg"; echo $?)" 0
is "a name that is not one writes nothing" "$(find "$T/ftheme2" -name '*..*' | wc -l)" 0

if (( failed )); then
    echo "FAIL  icons: $failed of $((passed + failed)) checks"
    exit 1
fi
echo "PASS  icons: $passed checks"
