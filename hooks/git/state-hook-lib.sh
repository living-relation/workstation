# Shared by the state git hooks (pre-commit, post-checkout, post-merge). Sourced, never run.
# The state tools (workstation scripts/state) are found in this order:
#   $WORKSTATION_STATE_TOOLS, git config workstation.stateTools, <this folder>/../../scripts/state.
# No tools or no Python 3: the state steps are skipped (exit 0); the chained hook still runs.

find_state_tools() {
  for dir in "$WORKSTATION_STATE_TOOLS" "$(git config --get workstation.stateTools 2>/dev/null)" "$HOOK_DIR/../../scripts/state"; do
    if [ -n "$dir" ] && [ -f "$dir/state_paths.py" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
  done
  return 1
}

find_python() {
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 &&
      "$candidate" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
      PY_EXE=$candidate
      PY_ARGS=
      return 0
    fi
  done
  if command -v py >/dev/null 2>&1 && py -3 -c 'import sys' >/dev/null 2>&1; then
    PY_EXE=py
    PY_ARGS=-3
    return 0
  fi
  return 1
}

run_py() {
  # shellcheck disable=SC2086
  "$PY_EXE" $PY_ARGS "$@"
}

state_ready() {
  STATE_TOOLS=$(find_state_tools) || return 1
  find_python || return 1
  return 0
}

session_state_file() {
  run_py -c 'import sys; sys.path.insert(0, sys.argv[1]); import state_paths as p; i = p.resolve(sys.argv[2]); print(i["state_file"] if i["store_reachable"] and i["state_file"] else "")' "$STATE_TOOLS" "$1" 2>/dev/null
}

git_common_hooks_dir() {
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) ||
    common=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
  case "$common" in
    /* | [A-Za-z]:*) ;;
    *) common="$(pwd)/$common" ;;
  esac
  printf '%s\n' "$common/hooks"
}

# The folder whose hook of the same name runs after the pack's own steps:
#   git config workstation.chainHooksPath (for example .githooks), else, when core.hooksPath is unset
#   or points at this pack, the repo's own <git-common-dir>/hooks (so an existing .git/hooks setup,
#   such as the pre-commit framework, keeps running).
chain_dir() {
  chain=$(git config --get workstation.chainHooksPath 2>/dev/null)
  if [ -z "$chain" ]; then
    hooks_path=$(git config --get core.hooksPath 2>/dev/null)
    if [ -n "$hooks_path" ]; then
      case "$hooks_path" in
        /* | [A-Za-z]:*) ;;
        *) hooks_path="$(git rev-parse --show-toplevel)/$hooks_path" ;;
      esac
      [ "$(cd "$hooks_path" 2>/dev/null && pwd -P)" = "$(cd "$HOOK_DIR" && pwd -P)" ] || return 1
    fi
    chain=$(git_common_hooks_dir) || return 1
  fi
  case "$chain" in
    /* | [A-Za-z]:*) ;;
    *) chain="$(git rev-parse --show-toplevel)/$chain" ;;
  esac
  printf '%s\n' "$chain"
}

# Runs the repo's own hook of the same name from chain_dir, so this pack adds to a repo's hooks
# instead of replacing them. An executable hook runs directly (its own shebang); otherwise with sh.
chain_hook() {
  hook_name=$1
  shift
  chain=$(chain_dir) || return 0
  [ -f "$chain/$hook_name" ] || return 0
  if [ "$(cd "$chain" 2>/dev/null && pwd -P)" = "$(cd "$HOOK_DIR" && pwd -P)" ]; then
    return 0
  fi
  if [ -x "$chain/$hook_name" ]; then
    "$chain/$hook_name" "$@"
  else
    sh "$chain/$hook_name" "$@"
  fi
}
