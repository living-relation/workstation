#!/usr/bin/env bash
# Rebuild skills/<name>.zip for each skills/<name>/ that contains SKILL.md.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
exec python3 scripts/pack-skill-zips.py "$@"
