#!/usr/bin/env bash
# Read-only check of local git clones vs origin/main. Only runs `git fetch`.
# Usage: git-checker.sh [-d depth] [-m main] [-n(no fetch)] ROOT...
set -u
depth=2; mainopt=""; nofetch=0
while getopts "d:m:n" o; do case $o in d) depth=$OPTARG;; m) mainopt=$OPTARG;; n) nofetch=1;; esac; done
shift $((OPTIND-1)); [ $# -eq 0 ] && { echo "usage: $0 [-d N] [-m main] [-n] ROOT..."; exit 2; }
g(){ local d=$1; shift; git -C "$d" -c core.autocrlf=true -c core.safecrlf=false "$@" 2>/dev/null; }
mapfile -t repos < <(for r in "$@"; do find "$r" -maxdepth $((depth+1)) -name .git -not -path '*/node_modules/*' 2>/dev/null | xargs -r -n1 dirname; done | sort -u)
# Worktrees have a .git FILE ("gitdir: <repo>/.git/worktrees/<name>"). Name them after the
# main repo (repo@worktree) so they aren't mistaken for separate projects.
# (submodules also have a .git file, but their git-dir == common-dir, so they stay plain repos)
iswtree(){ local c gd; [ -f "$1/.git" ] || return 1; c=$(g "$1" rev-parse --path-format=absolute --git-common-dir); gd=$(g "$1" rev-parse --path-format=absolute --git-dir); [ -n "$c" ] && [ "$c" != "$gd" ]; }
label(){ local d=$1; if iswtree "$d"; then echo "$(basename "$(dirname "$(g "$d" rev-parse --path-format=absolute --git-common-dir)")")@$(basename "$d")"; else basename "$d"; fi; }
printf '%-20s %-14s %-7s %5s %4s %5s %5s %3s %-5s %s\n' Repo Branch A/B Dirty Untr Stash Unmrg WT Fetch Upstream
verdicts=()
for d in "${repos[@]}"; do
  n=$(label "$d"); fn=""; iswt=0; iswtree "$d" && iswt=1
  fe=skip; if [ $nofetch = 0 ]; then if g "$d" fetch --prune --quiet origin; then fe=ok; else fe=FAIL; fn=" (fetch failed)"; fi; fi
  if [ -n "$mainopt" ]; then main="origin/${mainopt#origin/}"; else main=$(g "$d" symbolic-ref --short refs/remotes/origin/HEAD); main=${main:-origin/main}; fi
  ms=${main#origin/}
  if g "$d" remote get-url origin >/dev/null && g "$d" rev-parse -q --verify "refs/remotes/$main" >/dev/null; then hasmain=1; else hasmain=0; fi
  br=$(g "$d" branch --show-current); br=${br:-"(detached)"}
  if ab=$(g "$d" rev-list --left-right --count "HEAD...$main"); then read -r ah be <<<"$ab"; else ah='?'; be='?'; fi
  st=$(g "$d" status --porcelain -uall)  # -uall: so a nested worktree shows as its own "?? path/" line
  # don't count this repo's own nested worktrees (e.g. .claude/worktrees/x/) as untracked files
  top=$(g "$d" rev-parse --show-toplevel)
  while IFS= read -r p; do r=${p#"$top"/}; [ -n "$p" ] && [ "$r" != "$p" ] && st=$(grep -vxF "?? $r/" <<<"$st"); done < <(g "$d" worktree list --porcelain | sed -n 's/^worktree //p')
  un=$(grep -c '^??' <<<"$st"); di=$(grep -v '^??' <<<"$st" | grep -c .)
  if [ "$di" -gt 0 ] && g "$d" diff --ignore-cr-at-eol --quiet && g "$d" diff --cached --ignore-cr-at-eol --quiet; then di=0; fi
  sa=$(g "$d" stash list | grep -c .)
  um=$(g "$d" branch --format='%(refname:short)' --no-merged "$main" | grep -vxF "$ms" | grep -c .)
  mg=$(g "$d" branch --format='%(refname:short)' --merged "$main" | grep -vxF "$ms" | grep -c .)
  wt=$(( $(g "$d" worktree list | grep -c .) - 1 )); [ $wt -lt 0 ] && wt=0
  pr=$(g "$d" worktree list --porcelain | grep -c '^prunable')
  up=$(g "$d" for-each-ref --format="%(upstream:short)" "refs/heads/$br"); up=${up:-NONE}
  printf '%-20s %-14s %-7s %5s %4s %5s %5s %3s %-5s %s\n' "$n" "$br" "$ah/$be" "$di" "$un" "$sa" "$um" "$wt" "$fe" "$up"
  if [ "$di$un$sa" != "000" ]; then v=DIRTY; m="$di changed, $un untracked, $sa stash. Suggest: review; commit on a branch + PR, or clean up by hand"
  elif [ $hasmain = 0 ]; then v=NO-REMOTE; m="no origin or no $main. Suggest: check git remote -v / default branch name (-m)"
  elif [ $iswt = 1 ]; then v=WORKTREE; m="worktree on $br ($ah/$be vs $main). Suggest: finish via PR; after merge remove it by hand (git worktree remove)"
  elif [ "$br" != "$ms" ] || [ "$up" = NONE ]; then v=OFF-MAIN; m="on $br, upstream $up. Suggest: finish via PR, then git switch $ms"; [ "$up" = NONE ] && m+="; git branch -u origin/$br"
  elif [ "$fe" = FAIL ]; then v=UNKNOWN; m="fetch failed, ahead/behind may be stale ($ah/$be). Suggest: check network/auth, re-run"
  elif [ "$ah" != 0 ] && [ "$be" != 0 ]; then v=DIVERGED; m="$ah ahead / $be behind $main. Suggest: move local commits to a branch + PR, then reset main by hand"
  elif [ "$ah" != 0 ]; then v=AHEAD; m="$ah unpushed commit(s) on $ms. Suggest: move them to a branch + PR (don't push to main)"
  elif [ "$be" != 0 ]; then v=BEHIND; m="$be behind $main. Suggest: git pull --ff-only"
  else v=OK; m="matches $main"; fi
  x=""; [ "$um" -gt 0 ] && x+="$um unmerged branch(es) "; [ "$mg" -gt 0 ] && x+="$mg merged branch(es) "; [ "$wt" -gt 0 ] && [ $iswt = 0 ] && x+="$wt extra worktree(s) "; [ "$pr" -gt 0 ] && [ $iswt = 0 ] && x+="$pr prunable (folder gone) worktree(s)"; [ -n "$x" ] && m+=" | note: $x"
  verdicts+=("$(printf '%-20s %-8s - %s%s' "$n" "$v" "$m" "$fn")")
done
echo; printf '%s\n' "${verdicts[@]}"
echo; echo "Read-only: nothing was changed. Apply fixes via safe-repo-preflight."
