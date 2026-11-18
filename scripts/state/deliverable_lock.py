#!/usr/bin/env python3
"""Lock verified deliverables by hash. Stdlib only.

The lock file is VERIFIED.lock at the repo root: JSON, repo-relative path -> sha256, plus one
reserved key "_history" (a list of lock / unlock events with their UTC date).
Usage: deliverable_lock.py [--repo DIR] lock PATH... | verify | unlock PATH --owner-phrase TEXT
  lock    record the current sha256 of each file
  verify  every locked file must still exist with its recorded hash
  unlock  remove one entry; TEXT is the owner's own words, typed by the owner in the chat, and is
          logged in _history. The tool prints and stores no token: the real gate is the
          PreToolUse guard, which routes every unlock command to "ask".
Hashing: a text file (no NUL byte in its first 8 KiB) is hashed with CRLF normalised to LF, so
a core.autocrlf checkout does not break a lock; a binary file is hashed raw.
Exit: 0 = OK, 2 = tampered / missing / refused, 1 = usage error (path outside the repo, no file).
"""
import argparse
import datetime
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import state_paths  # noqa: E402

LOCK_NAME = "VERIFIED.lock"
HISTORY_KEY = "_history"
BINARY_SNIFF_BYTES = 8192


def repo_root(repo):
    top = state_paths._git(repo, "rev-parse", "--show-toplevel")
    return Path(top).resolve() if top else Path(repo).resolve()


def sha256_of(path):
    data = Path(path).read_bytes()
    if b"\0" not in data[:BINARY_SNIFF_BYTES]:
        data = data.replace(b"\r\n", b"\n")
    return hashlib.sha256(data).hexdigest()


def load_lock(root):
    path = root / LOCK_NAME
    if not path.is_file():
        return None, []
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(data, dict):
        raise ValueError("%s must be a JSON object of path -> sha256" % path)
    history = data.pop(HISTORY_KEY, [])
    if not isinstance(history, list) or not all(isinstance(v, str) for v in data.values()):
        raise ValueError("%s must be a JSON object of path -> sha256" % path)
    return data, history


def save_lock(root, data, history):
    out = dict(sorted(data.items()))
    if history:
        out[HISTORY_KEY] = history
    with open(root / LOCK_NAME, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(out, indent=2) + "\n")


def history_entry(action, key, **extra):
    when = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    entry = {"date": when, "action": action, "path": key}
    entry.update(extra)
    return entry


def relative_key(root, raw):
    path = Path(raw)
    path = (path if path.is_absolute() else Path.cwd() / path).resolve()
    try:
        return path.relative_to(root).as_posix(), path
    except ValueError:
        return None, path


def cmd_lock(root, args):
    data, history = load_lock(root)
    data = data or {}
    for raw in args.paths:
        key, path = relative_key(root, raw)
        if key is None:
            print("deliverable_lock: %s is outside the repo %s" % (raw, root), file=sys.stderr)
            return 1
        if key == LOCK_NAME or key == HISTORY_KEY or not path.is_file():
            print("deliverable_lock: not a lockable file: %s" % raw, file=sys.stderr)
            return 1
        data[key] = sha256_of(path)
        history.append(history_entry("lock", key))
        print("locked %s" % key)
    save_lock(root, data, history)
    return 0


def cmd_verify(root, args):
    data, _ = load_lock(root)
    if data is None:
        print("deliverable_lock: no %s; nothing to verify" % LOCK_NAME)
        return 0
    bad = 0
    for key, recorded in sorted(data.items()):
        path = root / key
        if not path.is_file():
            print("MISSING %s" % key)
            bad += 1
        elif sha256_of(path) != recorded:
            print("CHANGED %s" % key)
            bad += 1
    if bad:
        print("deliverable_lock: %d of %d locked file(s) changed or missing" % (bad, len(data)))
        return 2
    print("deliverable_lock: OK (%d locked file(s))" % len(data))
    return 0


def cmd_unlock(root, args):
    data, history = load_lock(root)
    data = data or {}
    key, _ = relative_key(root, args.path)
    if key not in data:
        print("deliverable_lock: %s is not locked" % args.path, file=sys.stderr)
        return 1
    phrase = (args.owner_phrase or "").strip()
    if not phrase:
        print("deliverable_lock: REFUSED: unlock needs --owner-phrase with the owner's own words",
              file=sys.stderr)
        return 2
    del data[key]
    history.append(history_entry("unlock", key, owner_phrase=phrase))
    save_lock(root, data, history)
    print("unlocked %s" % key)
    return 0


def main(argv=None):
    state_paths.configure_output()
    parser = argparse.ArgumentParser(description="Lock verified deliverables by sha256.")
    parser.add_argument("--repo", default=".")
    sub = parser.add_subparsers(dest="command", required=True)
    lock = sub.add_parser("lock")
    lock.add_argument("paths", nargs="+")
    sub.add_parser("verify")
    unlock = sub.add_parser("unlock")
    unlock.add_argument("path")
    unlock.add_argument("--owner-phrase", dest="owner_phrase")
    args = parser.parse_args(argv)
    root = repo_root(args.repo)
    handlers = {"lock": cmd_lock, "verify": cmd_verify, "unlock": cmd_unlock}
    try:
        return handlers[args.command](root, args)
    except (OSError, ValueError) as error:
        print("deliverable_lock: %s" % error, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
