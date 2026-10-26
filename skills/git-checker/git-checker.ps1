<#
.SYNOPSIS  Read-only check of local git clones vs origin/main. Only runs `git fetch`.
.EXAMPLE   pwsh -File git-checker.ps1 -Roots 'C:\code' -Depth 2
#>
param(
  [Parameter(Mandatory)][string[]]$Roots,
  [int]$Depth = 2,
  [string]$MainBranch = '',
  [switch]$NoFetch
)
$ErrorActionPreference = 'Continue'
function G { param($d) $a = @('-C', $d, '-c', 'core.autocrlf=true', '-c', 'core.safecrlf=false', '-c', 'core.fsmonitor=false') + $args; & git @a 2>$null }

$repos = foreach ($r in $Roots) {
  if (-not (Test-Path $r)) { Write-Warning "Missing root: $r"; continue }
  Get-ChildItem -Path $r -Directory -Recurse -Depth $Depth -Force -Filter .git -ErrorAction SilentlyContinue |
    ForEach-Object { $_.Parent.FullName }
  # also catch worktree/submodule .git files
  Get-ChildItem -Path $r -File -Recurse -Depth $Depth -Force -Filter .git -ErrorAction SilentlyContinue |
    ForEach-Object { $_.Directory.FullName }
}
$repos = $repos | Sort-Object -Unique

$rows = @(); $lines = @()
foreach ($d in $repos) {
  $name = Split-Path $d -Leaf
  # Worktrees have a .git FILE; label them repo@worktree, not as their own project
  # (submodules also have a .git file, but their git-dir == common-dir, so they stay plain repos)
  $isWt = $false
  if (Test-Path -LiteralPath (Join-Path $d '.git') -PathType Leaf) {
    $c = G $d rev-parse --path-format=absolute --git-common-dir; $gd = G $d rev-parse --path-format=absolute --git-dir
    if ($c -and $c -ne $gd) { $isWt = $true; $name = (Split-Path (Split-Path $c -Parent) -Leaf) + '@' + $name }
  }
  # git refuses some repos outright (e.g. \\wsl$ paths owned by the WSL user: "dubious ownership").
  # Report that instead of a misleading NO-REMOTE.
  $probe = & git -C $d rev-parse --git-dir 2>&1
  if ($LASTEXITCODE) {
    $err = (@($probe) | Where-Object { $_ -match 'fatal|error' } | Select-Object -First 1) -replace '^fatal:\s*',''
    $rows += [pscustomobject]@{ Repo=$name; Branch='?'; 'A/B'='?/?'; Dirty='?'; Untr='?'; Stash='?'; Unmrg='?'; WT='?'; Fetch='skip'; Upstream='?' }
    $hint = if ($err -match 'dubious ownership') { "Suggest: run git-checker.sh inside WSL/Linux for this path, or add it with git config --global --add safe.directory" } else { 'Suggest: check the repo by hand' }
    $lines += ('{0,-20} {1,-8} - git refused: {2}. {3}' -f $name, 'GIT-ERROR', $err, $hint); continue
  }
  $fetchNote = ''; $fetch = 'skip'
  if (-not $NoFetch) { G $d fetch --prune --quiet origin | Out-Null; if ($LASTEXITCODE) { $fetch = 'FAIL'; $fetchNote = ' (fetch failed)' } else { $fetch = 'ok' } }
  $main = $MainBranch
  if (-not $main) { $h = G $d symbolic-ref --short refs/remotes/origin/HEAD; $main = if ($h) { $h } else { 'origin/main' } }
  elseif ($main -notlike 'origin/*') { $main = "origin/$main" }
  $mainShort = $main -replace '^origin/', ''
  G $d remote get-url origin | Out-Null; $hasOrigin = ($LASTEXITCODE -eq 0)
  G $d rev-parse -q --verify "refs/remotes/$main" | Out-Null; $hasMain = $hasOrigin -and ($LASTEXITCODE -eq 0)

  $branch = G $d branch --show-current; if (-not $branch) { $branch = '(detached)' }
  $ab = G $d rev-list --left-right --count "HEAD...$main"
  if ($ab) { $ahead, $behind = ($ab -split '\s+'); } else { $ahead = '?'; $behind = '?' }
  $st = @(G $d status --porcelain -uall)  # -uall: so a nested worktree shows as its own '?? path/' line
  # don't count this repo's own nested worktrees (e.g. .claude/worktrees/x/) as untracked files
  $wtPaths = @(G $d worktree list --porcelain | Where-Object { $_ -like 'worktree *' } | ForEach-Object { ($_.Substring(9) -replace '\\','/').TrimEnd('/') })
  $root = ((G $d rev-parse --show-toplevel) -replace '\\','/').TrimEnd('/')
  $nested = $wtPaths | Where-Object { $_ -like "$root/*" } | ForEach-Object { '?? ' + $_.Substring($root.Length + 1) + '/' }
  $st = @($st | Where-Object { $nested -notcontains $_ })
  $untr = @($st | Where-Object { $_.StartsWith('??') }).Count
  $dirty = @($st | Where-Object { $_ -and -not $_.StartsWith('??') }).Count
  if ($dirty -gt 0) {   # drop CRLF-only diffs
    G $d diff --ignore-cr-at-eol --quiet | Out-Null; $wt = $LASTEXITCODE
    G $d diff --cached --ignore-cr-at-eol --quiet | Out-Null; $ix = $LASTEXITCODE
    if ($wt -eq 0 -and $ix -eq 0) { $dirty = 0 }
  }
  $stash = @(G $d stash list).Count
  $unm = @(G $d branch --format='%(refname:short)' --no-merged $main | Where-Object { $_ -ne $mainShort }).Count
  $mrg = @(G $d branch --format='%(refname:short)' --merged $main | Where-Object { $_ -ne $mainShort }).Count
  $wts = [math]::Max(0, @(G $d worktree list).Count - 1)
  $prunable = @(G $d worktree list --porcelain | Where-Object { $_ -like 'prunable*' }).Count
  $up = G $d for-each-ref --format='%(upstream:short)' "refs/heads/$branch"; if (-not $up) { $up = 'NONE' }

  $rows += [pscustomobject]@{ Repo=$name; Branch=$branch; 'A/B'="$ahead/$behind"; Dirty=$dirty; Untr=$untr; Stash=$stash; Unmrg=$unm; WT=$wts; Fetch=$fetch; Upstream=$up }

  if ($dirty -or $untr -or $stash) { $v='DIRTY'; $msg="$dirty changed, $untr untracked, $stash stash. Suggest: review; commit on a branch + PR, or clean up by hand" }
  elseif (-not $hasMain) { $v='NO-REMOTE'; $msg="no origin or no $main. Suggest: check git remote -v / default branch name (-MainBranch)" }
  elseif ($isWt) { $v='WORKTREE'; $msg="worktree on $branch ($ahead/$behind vs $main). Suggest: finish via PR; after merge remove it by hand (git worktree remove)" }
  elseif ($branch -ne $mainShort -or $up -eq 'NONE') { $v='OFF-MAIN'; $msg="on $branch, upstream $up. Suggest: finish via PR, then git switch $mainShort" + $(if($up -eq 'NONE'){"; git branch -u origin/$branch"}else{''}) }
  elseif ($fetch -eq 'FAIL') { $v='UNKNOWN'; $msg="fetch failed, ahead/behind may be stale ($ahead/$behind). Suggest: check network/auth, re-run" }
  elseif ($ahead -ne '0' -and $behind -ne '0') { $v='DIVERGED'; $msg="$ahead ahead / $behind behind $main. Suggest: move local commits to a branch + PR, then reset main by hand" }
  elseif ($ahead -ne '0') { $v='AHEAD'; $msg="$ahead unpushed commit(s) on $mainShort. Suggest: move them to a branch + PR (don't push to main)" }
  elseif ($behind -ne '0') { $v='BEHIND'; $msg="$behind behind $main. Suggest: git pull --ff-only" }
  else { $v='OK'; $msg='matches ' + $main }
  $extra = @(); if ($unm) { $extra += "$unm unmerged branch(es)" }; if ($mrg) { $extra += "$mrg merged branch(es)" }; if ($wts -and -not $isWt) { $extra += "$wts extra worktree(s)" }; if ($prunable -and -not $isWt) { $extra += "$prunable prunable (folder gone) worktree(s)" }
  if ($extra) { $msg += ' | note: ' + ($extra -join ', ') }
  $lines += ('{0,-20} {1,-8} - {2}{3}' -f $name, $v, $msg, $fetchNote)
}
$rows | Format-Table -AutoSize
$lines
Write-Host "`nRead-only: nothing was changed. Apply fixes via safe-repo-preflight."
