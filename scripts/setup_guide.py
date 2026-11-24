#!/usr/bin/env python3
"""Print the PC setup guide, one numbered phase at a time in the output.

The agent follows this printout. It does not invent steps from SETUP-PROMPT.txt.
Record a finished phase with --complete so setup_verify.py can fail a missed one.

  python3 scripts/setup_guide.py
  python3 scripts/setup_guide.py --complete 6
  python3 scripts/setup_guide.py --complete 6 --log /tmp/setup-phases.json
"""
import argparse
import datetime
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import setup_phases  # noqa: E402


def print_guide():
    print("Workstation setup. Do these phases in order. Do not skip one.")
    print("SETUP-PROMPT.txt is only a pointer. This printout is the setup.")
    print("Record each finished phase, then run: python3 scripts/setup_verify.py")
    print("")
    for item in setup_phases.PHASES:
        print("Phase %s. %s" % (item["n"], item["title"]))
        print(item["body"])
        print("")
    print(setup_phases.ALWAYS.rstrip())
    print("")
    print("When a phase is done:")
    print("  python3 scripts/setup_guide.py --complete <number>")
    print("Setup is not finished until this exits 0:")
    print("  python3 scripts/setup_verify.py")


def complete(number, log_path):
    known = setup_phases.phase_ids()
    if number not in known:
        print("unknown phase %s (use one of %s)" % (number, ", ".join(known)), file=sys.stderr)
        return 2
    done = setup_phases.load_log(log_path)
    if number not in done:
        done[number] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        setup_phases.save_log(log_path, done)
    print("recorded phase %s in %s" % (number, log_path))
    missed = setup_phases.missing(done)
    if missed:
        print("still open: %s" % ", ".join(missed))
    else:
        print("all phases recorded; run setup_verify.py")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description="Print the workstation setup phases.")
    parser.add_argument("--complete", metavar="N", help="record phase N as done")
    parser.add_argument("--log", help="phase log path (default: a per-PC file outside the repo)")
    args = parser.parse_args(argv)
    if args.complete is None:
        print_guide()
        return 0
    log_path = Path(args.log) if args.log else setup_phases.default_log_path()
    return complete(str(args.complete), log_path)


if __name__ == "__main__":
    sys.exit(main())
