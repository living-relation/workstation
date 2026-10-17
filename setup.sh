#!/usr/bin/env bash
# workstation setup for WSL/Linux (optional Python helpers). Safe to re-run.
# Touches only this repo, ~/.cache/uv,
# uv's Python store, and (unless --no-models) creates <Desktop>/models if it is missing.
#   bash setup.sh [--no-models]
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$PWD
UV_VERSION=0.13.0
UV_SHA=1468ebd5a5541121837c5a2817b9972ba6090fa6caa3d142620850a47fb75154  # uv-x86_64-unknown-linux-gnu.tar.gz
NO_MODELS=0
for a in "$@"; do case $a in --no-models) NO_MODELS=1;; *) echo "unknown option $a"; exit 2;; esac; done

# 1. pinned uv (use the one on PATH if it is the pinned version, else fetch into .tools/)
UV=$(command -v uv || true)
if [ -z "$UV" ] || [ "$("$UV" --version | awk '{print $2}')" != "$UV_VERSION" ]; then
  mkdir -p .tools; UV=$ROOT/.tools/uv
  if [ ! -x "$UV" ] || [ "$("$UV" --version | awk '{print $2}')" != "$UV_VERSION" ]; then
    curl -fsSL -o .tools/uv.tgz "https://github.com/astral-sh/uv/releases/download/$UV_VERSION/uv-x86_64-unknown-linux-gnu.tar.gz"
    echo "$UV_SHA  .tools/uv.tgz" | sha256sum -c -
    tar xzf .tools/uv.tgz -C .tools --strip-components=1; rm .tools/uv.tgz
  fi
fi
echo "uv: $("$UV" --version)"

# 2. pinned Python + .venv from uv.lock (never touches any other venv)
"$UV" python install "$(cat .python-version)"
"$UV" sync --frozen

# 3. hooks: pinned gitleaks + core.hooksPath so the hooks run on a fresh clone
sh scripts/fetch-gitleaks.sh
git config core.hooksPath .githooks

# 4. local settings
[ -f local.toml ] || cp local.toml.example local.toml

# 5. models folder (Desktop known folder; OneDrive Desktops work; never hard-coded)
desktop=""
if command -v powershell.exe >/dev/null 2>&1; then
  win=$(powershell.exe -NoProfile -Command "[Environment]::GetFolderPath('Desktop')" | tr -d '\r')
  [ -n "$win" ] && desktop=$(wslpath -u "$win")
fi
[ -z "$desktop" ] && desktop=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
MODELS="${MODELS_DIR:-$desktop/models}"
if [ "$NO_MODELS" = 1 ]; then echo "models folder: $MODELS (not created: --no-models)";
elif [ -d "$MODELS" ]; then echo "models folder: $MODELS (exists, left as is)";
else mkdir -p "$MODELS"; echo "models folder: created $MODELS"; fi

echo "Done. Optional: export MODELS_DIR=\"$MODELS\""
