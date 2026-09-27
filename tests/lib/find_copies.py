#!/usr/bin/env python3
"""find_copies.py REPO CLONE [ALLOW...] - list files of REPO that are copies of dotfiles in CLONE/.files.

Requirement: the shared dotfiles are linked from the live system-bootstrap clone, never copied into this repo.
A copy is any git-tracked file of REPO whose content equals a git-tracked file under CLONE/.files, either
byte for byte or after normalising: comment lines (#, //, --, ;) and blank lines dropped, quotes removed,
whitespace collapsed. The normalised form is what catches a copy that was re-commented or re-quoted (the old
config/nerd-fonts/all.yaml). Files whose normalised content is empty are ignored.

ALLOW entries are REPO-relative paths that may match (a deliberate fork kept with a reason).
Prints "REPO_PATH<TAB>CLONE_PATH<TAB>exact|normalised" per copy; exit 1 when there is one, 2 on usage errors.
"""
import hashlib
import re
import subprocess
import sys

COMMENT = re.compile(r"^\s*(#|//|--|;)")


def tracked(repo, *paths):
    out = subprocess.run(["git", "-C", repo, "ls-files", "-z", *paths], check=True, capture_output=True).stdout
    return [p for p in out.decode().split("\0") if p]


def digests(path):
    try:
        with open(path, "rb") as fh:
            data = fh.read()
    except (IsADirectoryError, FileNotFoundError, PermissionError):
        return None, None
    exact = hashlib.sha256(data).hexdigest()
    try:
        text = data.decode()
    except UnicodeDecodeError:
        return exact, None
    lines = []
    for line in text.splitlines():
        if not line.strip() or COMMENT.match(line):
            continue
        line = re.sub(r"[\"']", "", line)
        lines.append(" ".join(line.split()))
    if not lines:
        return exact, None
    return exact, hashlib.sha256("\n".join(lines).encode()).hexdigest()


def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    repo, clone, allow = argv[1], argv[2], set(argv[3:])
    exact_idx, norm_idx = {}, {}
    for rel in tracked(clone, ".files"):
        exact, norm = digests(f"{clone}/{rel}")
        if exact:
            exact_idx.setdefault(exact, rel)
        if norm:
            norm_idx.setdefault(norm, rel)
    found = 0
    for rel in tracked(repo):
        if rel in allow:
            continue
        exact, norm = digests(f"{repo}/{rel}")
        if exact and exact in exact_idx and norm:
            print(f"{rel}\t{exact_idx[exact]}\texact")
            found += 1
        elif norm and norm in norm_idx:
            print(f"{rel}\t{norm_idx[norm]}\tnormalised")
            found += 1
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
