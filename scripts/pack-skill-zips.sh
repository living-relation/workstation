#!/usr/bin/env bash
# Optional local rebuild of skills/<name>.zip for each skills/<name>/ that contains SKILL.md.
# The GitHub Action owns the committed zips; you do not need to run this.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
exec python3 scripts/pack-skill-zips.py "$@"
