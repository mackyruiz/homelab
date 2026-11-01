#!/usr/bin/env python3
"""Export a sanitized copy of a git repository, or sanitize text from stdin.

Exit codes: 0 OK, 1 leak found, 2 usage/config/input error.
"""
import argparse
import fnmatch
import re
import subprocess
import sys
import tomllib
from pathlib import Path, PurePosixPath

BUILTIN_DENY = [
    r"\$ANSIBLE[_]VAULT;",
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    r"ENC\[AES256[_]GCM,",
    r"BEGIN AGE ENCRYPTED[ ]FILE",
]
ALLOWED_KEYS = {"exclude", "deny", "replace"}


class Fail(Exception):
    def __init__(self, msg, code=2):
        super().__init__(msg)
        self.code = code


class Rules:
    def __init__(self, path):
        if not path.is_file():
            raise Fail(f"rules file not found: {path} (start from publish/rules.example.toml)")
        try:
            with open(path, "rb") as f:
                data = tomllib.load(f)
        except tomllib.TOMLDecodeError as e:
            raise Fail(f"invalid rules TOML: {e}")
        extra = set(data) - ALLOWED_KEYS
        if extra:
            raise Fail(f"unknown rules key(s): {', '.join(sorted(extra))}")
        self.exclude = data.get("exclude", [])
        if not isinstance(self.exclude, list) or not all(isinstance(x, str) for x in self.exclude):
            raise Fail("exclude must be a list of strings")
        deny = data.get("deny", [])
        if not isinstance(deny, list) or not all(isinstance(x, str) for x in deny):
            raise Fail("deny must be a list of strings")
        self.deny = []
        for p in deny + BUILTIN_DENY:
            try:
                self.deny.append((p, re.compile(p, re.IGNORECASE)))
            except re.error as e:
                raise Fail(f"invalid deny regex /{p}/: {e}")
        repl = data.get("replace", [])
        if not isinstance(repl, list):
            raise Fail("replace must be an array of tables")
        self.replace = []
        for i, r in enumerate(repl):
            if not isinstance(r, dict) or "pattern" not in r or "replacement" not in r:
                raise Fail(f"replace rule {i}: 'pattern' and 'replacement' are required")
            try:
                self.replace.append((re.compile(r["pattern"]), r["replacement"]))
            except re.error as e:
                raise Fail(f"replace rule {i}: invalid regex: {e}")

    def excluded(self, relpath):
        return any(fnmatch.fnmatchcase(relpath, p) for p in self.exclude)

    def apply(self, s):
        for rx, rep in self.replace:
            s = rx.sub(rep, s)
        return s

    def hits(self, s):
        return [p for p, rx in self.deny if rx.search(s)]


def cmd_text(rules):
    out = rules.apply(sys.stdin.read())
    hits = rules.hits(out)
    if hits:
        for p in hits:
            print(f"LEAK text: /{p}/", file=sys.stderr)
        return 1
    sys.stdout.write(out)
    return 0


def cmd_tree(rules, src, out):
    src, out = Path(src), Path(out)
    if out.exists():
        if not out.is_dir() or any(out.iterdir()):
            raise Fail(f"output directory not empty: {out}")
    else:
        out.mkdir(parents=True)
    try:
        res = subprocess.run(["git", "-C", str(src), "ls-files", "-z"], check=True, capture_output=True)
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        raise Fail(f"git ls-files failed for {src}: {getattr(e, 'stderr', b'').decode(errors='replace') or e}")
    paths = [p for p in res.stdout.decode("utf-8", "surrogateescape").split("\0") if p]

    excluded = rewritten = 0
    written = []
    seen = set()
    for rel in paths:
        if rules.excluded(rel):
            excluded += 1
            continue
        sp = src / rel
        if sp.is_symlink() or not sp.is_file():
            raise Fail(f"unsupported file type: {rel}")
        raw = sp.read_bytes()
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            raise Fail(f"non-UTF-8 file not excluded: {rel}")
        new_text = rules.apply(text)
        new_rel = rules.apply(rel)
        pp = PurePosixPath(new_rel)
        if not new_rel or pp.is_absolute() or ".." in pp.parts:
            raise Fail(f"unsafe rewritten path: {rel} -> {new_rel}")
        if new_rel in seen:
            raise Fail(f"path collision after rewrite: {new_rel}")
        seen.add(new_rel)
        dest = out / new_rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(new_text.encode("utf-8"))
        dest.chmod(0o755 if sp.stat().st_mode & 0o111 else 0o644)
        written.append(new_rel)
        if new_text != text or new_rel != rel:
            rewritten += 1

    leaks = 0
    for rel in written:
        for p in rules.hits(rel):
            print(f"LEAK {rel}:0: /{p}/", file=sys.stderr)
            leaks += 1
        with open(out / rel, encoding="utf-8", newline="") as f:
            for n, line in enumerate(f, 1):
                for p in rules.hits(line):
                    print(f"LEAK {rel}:{n}: /{p}/", file=sys.stderr)
                    leaks += 1
    if leaks:
        print(f"{leaks} leak(s); nothing published", file=sys.stderr)
        return 1
    print(f"exported {len(written)} files, excluded {excluded}, rewritten {rewritten}")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--rules", type=Path, default=Path(__file__).resolve().parent / "rules.toml")
    sub = ap.add_subparsers(dest="cmd", required=True)
    t = sub.add_parser("tree", help="export a sanitized copy of git repo SRC into OUT")
    t.add_argument("src")
    t.add_argument("out")
    sub.add_parser("text", help="sanitize stdin to stdout")
    args = ap.parse_args()
    try:
        rules = Rules(args.rules)
        return cmd_text(rules) if args.cmd == "text" else cmd_tree(rules, args.src, args.out)
    except Fail as e:
        print(str(e), file=sys.stderr)
        return e.code


if __name__ == "__main__":
    sys.exit(main())
