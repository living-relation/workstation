#!/usr/bin/env bash
# Stage only skills/<name>.zip and commit if they changed.
# Prints COMMITTED or UNCHANGED. Exit 2 if a non-zip path would be committed.
# Runs the repo staged guard before commit; gitleaks when PACK_SKILL_ZIPS_GITLEAKS=1.
# Optional: used by the GitHub Action; humans can ignore this.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
here=$(cd "$(dirname "$0")" && pwd)
cd "$root"
shopt -s nullglob
zips=(skills/*.zip)
if ((${#zips[@]})); then git add --force -- "${zips[@]}"; fi
deleted=$(git diff --name-only --diff-filter=D -- skills | grep -E '^skills/[^/]+\.zip$' || true)
if [ -n "$deleted" ]; then printf '%s\n' "$deleted" | xargs git add --; fi
if git diff --cached --quiet; then
  echo UNCHANGED
  exit 0
fi
bad=$(git diff --cached --name-only | grep -vE '^skills/[^/]+\.zip$' || true)
if [ -n "$bad" ]; then
  echo "refusing to commit non-zip paths:" >&2
  echo "$bad" >&2
  exit 2
fi
sh "$here/guard-staged.sh"
if [ "${PACK_SKILL_ZIPS_GITLEAKS:-}" = "1" ]; then
  sh "$here/run-gitleaks.sh"
fi
git commit -m "$(printf 'chore(skills): rebuild Claude-importable zips\n\n[skip ci]')"
echo COMMITTED
exit 0
