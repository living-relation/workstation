#!/usr/bin/env python3
"""Fail if any setup phase was not recorded.

  python3 scripts/setup_verify.py
  python3 scripts/setup_verify.py --log /tmp/setup-phases.json

Exit 0 when every phase is recorded. Exit 1 and list the missed phase numbers otherwise.
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import setup_phases  # noqa: E402


def verify(log_path):
    done = setup_phases.load_log(log_path)
    missed = setup_phases.missing(done)
    if missed:
        print("setup verify: missed phases: %s" % ", ".join(missed))
        print("log: %s" % log_path)
        return 1
    print("setup verify: all %d phases recorded" % len(setup_phases.phase_ids()))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description="Fail when a setup phase was missed.")
    parser.add_argument("--log", help="phase log path (default: a per-PC file outside the repo)")
    args = parser.parse_args(argv)
    log_path = Path(args.log) if args.log else setup_phases.default_log_path()
    return verify(log_path)


if __name__ == "__main__":
    sys.exit(main())
