#!/usr/bin/env python3
"""The icon themes against their official Git repositories, by hash (the user,
2026-11-06: an install must check them against the official Git repository, and
what does not match must go).

    verify.py                   check; install.sh runs this on any new content
    verify.py --update --tag T  write upstream.lock and the theme from tag T

    verify.py --builder files.py --lock files.lock --out DIR
                                the same for a theme that is not committed
                                (files.py says why): check, then write it at DIR
    verify.py --builder files.py --lock files.lock --update --tag T
                                write that lock from tag T

A check fetches the commit upstream.lock pins, and passes only if all hold:
  - the lock's tag still names that commit in the repository. A commit alone
    would not do: GitHub serves a fork's commits through the original's URL;
  - each file the theme is made from (build.py's MAP and the LICENSE) has the
    Git object id in that commit and the SHA-256 the lock records, so neither
    a change upstream nor a change to the lock alone gets through;
  - build.py, from those files, writes the committed theme byte for byte (a
    theme that is not committed is written from those files and no others).

Exit status: 0 verified; 2 something differs (install.sh removes the theme);
3 the repository could not be asked (no network, no git), which says nothing
either way, so install.sh installs nothing new and removes nothing verified.

Blobless and shallow, so only the files named are fetched, into a temporary
directory; nothing goes out but the request for this public commit. Git runs
without the user's or the system's configuration, whose url.insteadOf could
point it elsewhere, and without credential helpers, so no keyring is touched.
"""

import argparse
import hashlib
import importlib.util
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
LOCK = HERE / "upstream.lock"
THEME = HERE / "SpaceduckLines"
OFFICIAL = "https://github.com/lucide-icons/lucide.git"
VERIFIED, WRONG, UNREACHED = 0, 2, 3
GIT_SECONDS = 180


class Wrong(Exception):
    pass


class Unreached(Exception):
    pass


def load_build(path=HERE / "build.py"):
    # By path: run with -I, the script's directory is not on sys.path. No
    # bytecode: an install must leave nothing beside the sources.
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("icons_build", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def git(cwd, *args):
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull, GIT_TERMINAL_PROMPT="0",
               HOME=str(cwd), LC_ALL="C")
    command = ["git", "-c", "credential.helper=", "-c", "core.hooksPath=/dev/null",
               "-c", "http.lowSpeedLimit=1024", "-c", "http.lowSpeedTime=30", *args]
    try:
        return subprocess.run(command, cwd=cwd, env=env, capture_output=True, timeout=GIT_SECONDS)
    except FileNotFoundError as e:
        raise Unreached("git is not installed") from e
    except subprocess.TimeoutExpired as e:
        raise Unreached(f"git {args[0]} took over {GIT_SECONDS} s") from e


def text_of(result):
    return result.stderr.decode(errors="replace").strip()


def read_lock(path):
    lock = {"files": {}}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as e:
        raise Wrong(f"no lock: {e}") from e
    for line in lines:
        fields = line.split()
        if not fields or line.startswith("#"):
            continue
        if fields[0] in ("repo", "tag", "commit") and len(fields) == 2:
            lock[fields[0]] = fields[1]
        elif fields[0] == "file" and len(fields) == 4:
            lock["files"][fields[3]] = (fields[1], fields[2])
        else:
            raise Wrong(f"the lock has a line it should not: {line}")
    for key in ("repo", "tag", "commit"):
        if key not in lock:
            raise Wrong(f"the lock names no {key}")
    return lock


def tag_commit(cwd, tag):
    """What the repository's tag names now, an annotated tag's commit included."""
    listed = git(cwd, "ls-remote", "origin", f"refs/tags/{tag}", f"refs/tags/{tag}^{{}}")
    if listed.returncode != 0:
        raise Unreached(text_of(listed).splitlines()[-1] if text_of(listed) else "ls-remote failed")
    refs = dict(reversed(row.split("\t")) for row in listed.stdout.decode().splitlines())
    return refs.get(f"refs/tags/{tag}^{{}}") or refs.get(f"refs/tags/{tag}")


def fetched(cwd, repo, tag, commit):
    """Set up `cwd` for `repo`, and return the commit: the given one, checked
    against the tag, or the tag's when none is given."""
    for args in (("init", "-q"), ("remote", "add", "origin", repo)):
        done = git(cwd, *args)
        if done.returncode != 0:
            raise Unreached(text_of(done))
    named = tag_commit(cwd, tag)
    if named is None:
        raise Wrong(f"{repo} has no tag {tag}")
    if commit is not None and named != commit:
        raise Wrong(f"tag {tag} names {named} in {repo}; the lock pins {commit}")
    done = git(cwd, "fetch", "-q", "--depth", "1", "--filter=blob:none", "origin", named)
    if done.returncode != 0:
        raise Unreached(text_of(done).splitlines()[-1] if text_of(done) else "fetch failed")
    return named


def sources(cwd, commit, paths):
    """The named files of the commit, as {path: bytes} with their Git ids."""
    listed = git(cwd, "ls-tree", "-r", commit, "--", *paths)
    if listed.returncode != 0:
        raise Unreached(text_of(listed))
    ids = {}
    for row in listed.stdout.decode().splitlines():
        meta, path = row.split("\t", 1)
        ids[path] = meta.split()[2]
    missing = sorted(set(paths) - set(ids))
    if missing:
        raise Wrong(f"not in commit {commit}: {' '.join(missing[:5])}")
    # Checked out only so that a blobless clone fetches them all in one go;
    # read back from Git, since upstream's .gitattributes may rewrite the
    # working files.
    for args in (("sparse-checkout", "set", "--no-cone", *[f"/{p}" for p in paths]),
                 ("checkout", "-q", "--detach", commit)):
        done = git(cwd, *args)
        if done.returncode != 0:
            raise Unreached(text_of(done))
    out = {}
    for path, oid in ids.items():
        blob = git(cwd, "cat-file", "blob", oid)
        if blob.returncode != 0:
            raise Unreached(text_of(blob))
        if blob_id(blob.stdout) != oid:
            raise Wrong(f"{path}: the bytes fetched are not object {oid}")
        out[path] = blob.stdout
    return out


def blob_id(data):
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def tree(root):
    return {str(p.relative_to(root)): p.read_bytes() for p in sorted(root.rglob("*")) if p.is_file() or p.is_symlink()}


def written_theme(build, files, work):
    source = work / "source"
    for path, data in files.items():
        target = source / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    out = work / "theme"
    try:
        build.write_theme(source, out)
    except SystemExit as e:
        raise Wrong(str(e)) from e
    return out


def needed(build):
    if hasattr(build, "needed"):
        return build.needed()
    return sorted(["LICENSE"] + [f"icons/{name}.svg" for name in build.MAP])


def check(lock_path, theme, build, out=None):
    """`theme` is the committed theme to compare with; None when there is none,
    and then `out`, if given, is where the theme goes once it has passed."""
    lock = read_lock(lock_path)
    paths = needed(build)
    if sorted(lock["files"]) != paths:
        raise Wrong("the lock's files are not the ones build.py's MAP needs")
    with tempfile.TemporaryDirectory(prefix="icons-verify.") as tmp:
        tmp = pathlib.Path(tmp)
        repo = tmp / "git"
        repo.mkdir()
        fetched(repo, lock["repo"], lock["tag"], lock["commit"])
        files = sources(repo, lock["commit"], paths)
        for path, data in files.items():
            oid, sha256 = lock["files"][path]
            if blob_id(data) != oid:
                raise Wrong(f"{path}: Git object {blob_id(data)} upstream, {oid} in the lock")
            if hashlib.sha256(data).hexdigest() != sha256:
                raise Wrong(f"{path}: its SHA-256 is not the lock's")
        built = written_theme(build, files, tmp)
        if theme is None:
            if out is not None:
                shutil.copytree(built, out)
            return lock, len(files)
        want = tree(built)
    have = tree(theme)
    differ = sorted(p for p in want.keys() | have.keys() if want.get(p) != have.get(p))
    if differ:
        raise Wrong(f"{len(differ)} files of the theme differ from what upstream builds: {' '.join(differ[:5])}")
    return lock, len(files)


def update(lock_path, theme, build, repo_url, tag):
    paths = needed(build)
    with tempfile.TemporaryDirectory(prefix="icons-verify.") as tmp:
        tmp = pathlib.Path(tmp)
        repo = tmp / "git"
        repo.mkdir()
        commit = fetched(repo, repo_url, tag, None)
        files = sources(repo, commit, paths)
        built = written_theme(build, files, tmp)
        if theme is not None:
            build.write_theme(built and tmp / "source", theme)
    what = "kde/icons/SpaceduckLines is built from: Lucide's" if theme is not None else \
        "install.sh builds SpaceduckFiles from: Material Icon Theme's"
    rows = [f"# What {what} official Git repository,",
            "# one tag and its commit, then each file's Git object id and SHA-256.",
            "# Written by verify.py --update; verify.py checks it. Do not edit by hand.",
            f"repo {repo_url}", f"tag {tag}", f"commit {commit}"]
    rows += [f"file {blob_id(files[p])} {hashlib.sha256(files[p]).hexdigest()} {p}" for p in paths]
    lock_path.write_text("\n".join(rows) + "\n", encoding="utf-8")
    return commit


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--lock", type=pathlib.Path, default=LOCK)
    parser.add_argument("--theme", type=pathlib.Path, default=THEME)
    parser.add_argument("--update", action="store_true", help="write the lock and the theme from --tag")
    parser.add_argument("--tag", help="with --update: the upstream tag")
    parser.add_argument("--repo", help="with --update: the repository, if not the builder's official one")
    parser.add_argument("--builder", type=pathlib.Path, help="a builder for a theme that is not committed")
    parser.add_argument("--out", type=pathlib.Path, help="with --builder: where the theme goes once it has passed")
    args = parser.parse_args()
    if args.out and not args.builder:
        parser.error("--out needs --builder")
    build = load_build(args.builder) if args.builder else load_build()
    theme = None if args.builder else args.theme
    try:
        if args.update:
            if not args.tag:
                parser.error("--update needs --tag")
            repo = args.repo or getattr(build, "OFFICIAL", OFFICIAL)
            commit = update(args.lock, theme, build, repo, args.tag)
            print(f"icons: {'lock' if theme is None else 'theme and lock'} written from {repo} {args.tag} ({commit})")
            return VERIFIED
        lock, count = check(args.lock, theme, build, args.out)
        print(f"icons: verified against {lock['repo']} {lock['tag']} ({lock['commit']}), {count} files")
        return VERIFIED
    except Wrong as e:
        print(f"icons: WRONG: {e}", file=sys.stderr)
        return WRONG
    except Unreached as e:
        print(f"icons: could not ask upstream: {e}", file=sys.stderr)
        return UNREACHED


if __name__ == "__main__":
    sys.exit(main())
