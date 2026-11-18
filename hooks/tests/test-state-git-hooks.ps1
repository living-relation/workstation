# Tests the hooks/git state pack (pre-commit, post-checkout, post-merge) in a temp repo whose
# core.hooksPath points at hooks/git, with a fake store (WORKSTATION_MEMORY_STORE). Real git runs the hooks.
# Usage: powershell -NoProfile -File hooks/tests/test-state-git-hooks.ps1  (WORKSTATION_STATE_TOOLS = scripts/state)
. (Join-Path $PSScriptRoot 'state-test-support.ps1')
$pack = Join-Path $script:HooksDir 'git'
$t = New-TestRoot 'state-git'
$store = Join-Path $t 'store'
$saved = @{ store = $env:WORKSTATION_MEMORY_STORE; tools = $env:WORKSTATION_STATE_TOOLS }
$env:WORKSTATION_MEMORY_STORE = $store
$env:WORKSTATION_STATE_TOOLS = $script:StateTools
try {
  $repo = New-TestRepo $t 'pack-repo' $pack
  $project = Join-Path $store 'pack-repo'
  Write-TestFile (Join-Path $project 'STATE.md') (Get-GoodState 'main' 'GOAL' 0)
  Write-TestFile (Join-Path $project 'BACKLOG.md') "# BACKLOG`n"
  Write-TestFile (Join-Path $repo '.gitignore') "TASK.md`n"
  [void](Invoke-Git $repo add .gitignore)
  $c = Invoke-Git $repo commit -q -m ignore
  Check 'good STATE: commit on main passes' ($c.Code -eq 0)
  function Get-CommitCount { [int]((Invoke-Git $repo rev-list --count HEAD).Out.Trim()) }

  $rootState = Join-Path $project 'STATE.md'
  $rootBefore = [IO.File]::ReadAllText($rootState)
  $r = Invoke-Git $repo checkout -q -b feat/x
  $branchFile = Join-Path $project 'STATE-feat-x.md'
  Check 'post-checkout: git checkout -b creates STATE-feat-x.md' ($r.Code -eq 0 -and (Test-Path -LiteralPath $branchFile))
  Check 'post-checkout: root STATE.md is not written' ([IO.File]::ReadAllText($rootState) -ceq $rootBefore)
  Check 'post-checkout: new file passes the lint' ((Invoke-Git $repo status).Code -eq 0 -and ([IO.File]::ReadAllText($branchFile) -match '\[NEXT\]'))
  Write-TestFile (Join-Path $repo 'README.md') "changed`n"
  [void](Invoke-Git $repo checkout -q -- README.md)
  Check 'post-checkout: a file checkout makes no branch file' (@(Get-ChildItem -LiteralPath $project -Filter 'STATE-*.md').Count -eq 1)

  Write-TestFile $branchFile (Get-GoodState 'feat/x' 'GOAL' 10)
  $before = Get-CommitCount
  Write-TestFile (Join-Path $repo 'a.txt') "a`n"
  [void](Invoke-Git $repo add a.txt)
  $c = Invoke-Git $repo commit -q -m 'add a'
  Check 'pre-commit: a 31-line STATE blocks the commit' ($c.Code -ne 0 -and (Get-CommitCount) -eq $before)
  Check 'pre-commit: says why' ($c.Out -match '31 lines')
  [void](Invoke-Git $repo config workstation.stateLint warn)
  $c = Invoke-Git $repo commit -q -m 'add a (warn mode)'
  Check 'pre-commit: warn mode lets it through' ($c.Code -eq 0 -and (Get-CommitCount) -eq ($before + 1))
  [void](Invoke-Git $repo config --unset workstation.stateLint)
  Write-TestFile $branchFile (Get-GoodState 'feat/x' 'GOAL' 0)

  Write-TestFile (Join-Path $repo 'deliverable.txt') "v1`n"
  $py = (Get-Command python -CommandType Application | Select-Object -First 1).Source
  & $py (Join-Path $script:StateTools 'deliverable_lock.py') --repo $repo lock (Join-Path $repo 'deliverable.txt') | Out-Null
  [void](Invoke-Git $repo add deliverable.txt VERIFIED.lock)
  $c = Invoke-Git $repo commit -q -m 'lock deliverable'
  Check 'pre-commit: untouched locked file commits' ($c.Code -eq 0)
  Write-TestFile (Join-Path $repo 'deliverable.txt') "v2 tampered`n"
  [void](Invoke-Git $repo add deliverable.txt)
  $before = Get-CommitCount
  $c = Invoke-Git $repo commit -q -m 'tamper'
  Check 'pre-commit: a changed locked file blocks the commit' ($c.Code -ne 0 -and (Get-CommitCount) -eq $before -and $c.Out -match 'CHANGED')
  Write-TestFile (Join-Path $repo 'deliverable.txt') "v1`n"
  [void](Invoke-Git $repo add deliverable.txt)

  $own = Join-Path $repo '.githooks'
  Write-TestFile (Join-Path $own 'pre-commit') "#!/bin/sh`necho chained > `"`$(git rev-parse --show-toplevel)/chained.marker`"`nexit 0`n"
  [void](Invoke-Git $repo config workstation.chainHooksPath .githooks)
  Write-TestFile (Join-Path $repo 'b.txt') "b`n"
  [void](Invoke-Git $repo add b.txt)
  $c = Invoke-Git $repo commit -q -m 'chain'
  Check "pre-commit: chains to the repo's own hook" ($c.Code -eq 0 -and (Test-Path -LiteralPath (Join-Path $repo 'chained.marker')))
  Write-TestFile (Join-Path $own 'pre-commit') "#!/bin/sh`necho own-gate-failed >&2`nexit 1`n"
  Write-TestFile (Join-Path $repo 'c.txt') "c`n"
  [void](Invoke-Git $repo add c.txt)
  $c = Invoke-Git $repo commit -q -m 'chain fails'
  Check "pre-commit: the repo's own failing hook still blocks" ($c.Code -ne 0 -and $c.Out -match 'own-gate-failed')
  [void](Invoke-Git $repo config --unset workstation.chainHooksPath)
  $c = Invoke-Git $repo commit -q -m 'c'
  Check 'pre-commit: commit passes again' ($c.Code -eq 0)

  $gitHooks = Join-Path $repo '.git\hooks'
  Write-TestFile (Join-Path $gitHooks 'pre-commit') "#!/bin/sh`necho dotgit > `"`$(git rev-parse --show-toplevel)/dotgit.marker`"`nexit 0`n"
  Write-TestFile (Join-Path $repo 'e.txt') "e`n"
  [void](Invoke-Git $repo add e.txt)
  $c = Invoke-Git $repo commit -q -m 'dotgit chain'
  Check 'pre-commit: no chainHooksPath -> chains to .git/hooks' ($c.Code -eq 0 -and (Test-Path -LiteralPath (Join-Path $repo 'dotgit.marker')))
  Write-TestFile (Join-Path $gitHooks 'pre-commit') "#!/bin/sh`necho dotgit-gate-failed >&2`nexit 1`n"
  Write-TestFile (Join-Path $repo 'e.txt') "e2`n"
  [void](Invoke-Git $repo add e.txt)
  $c = Invoke-Git $repo commit -q -m 'dotgit chain fails'
  Check 'pre-commit: a failing .git/hooks pre-commit still blocks' ($c.Code -ne 0 -and $c.Out -match 'dotgit-gate-failed')
  Remove-Item -LiteralPath (Join-Path $gitHooks 'pre-commit') -Force
  Remove-Item -LiteralPath (Join-Path $repo 'dotgit.marker') -Force
  $c = Invoke-Git $repo commit -q -m 'e2'
  Check 'pre-commit: passes once the .git/hooks gate is gone' ($c.Code -eq 0)

  Write-TestFile (Join-Path $repo 'TASK.md') "- [ ] task`n"
  [void](Invoke-Git $repo checkout -q main)
  $m = Invoke-Git $repo merge --no-ff -q -m 'merge feat/x' feat/x
  $archived = @(Get-ChildItem -LiteralPath (Join-Path $project 'archives') -Filter 'STATE-feat-x-*.md' -ErrorAction SilentlyContinue)
  Check 'post-merge: STATE-feat-x.md archived' ($m.Code -eq 0 -and $archived.Count -eq 1 -and -not (Test-Path -LiteralPath $branchFile))
  Check 'post-merge: root STATE.md is not written' ([IO.File]::ReadAllText($rootState) -ceq $rootBefore)
  Check 'post-merge: TASK.md removed' (-not (Test-Path -LiteralPath (Join-Path $repo 'TASK.md')))

  [void](Invoke-Git $repo checkout -q -b feat/wt-base)
  $wt = Join-Path $t 'wt-z'
  [void](Invoke-Git $repo worktree add -q -b feat/z $wt)
  Check 'post-checkout: worktree add creates STATE-feat-z.md (main repo project)' (Test-Path -LiteralPath (Join-Path $project 'STATE-feat-z.md'))
  Write-TestFile (Join-Path $wt 'TASK.md') "- [ ] z`n"
  Write-TestFile (Join-Path $wt 'z.txt') "z`n"
  [void](Invoke-Git $wt add z.txt)
  $cz = Invoke-Git $wt commit -q -m z
  [void](Invoke-Git $repo checkout -q main)
  $m = Invoke-Git $repo merge --no-ff -q -m 'merge feat/z' feat/z
  Check "post-merge: removes TASK.md in the merged branch's worktree" ($cz.Code -eq 0 -and $m.Code -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $wt 'TASK.md')))

  [void](Invoke-Git $repo checkout -q -b feat/stack-base)
  [void](Invoke-Git $repo checkout -q -b feat/stack-top)
  Write-TestFile (Join-Path $repo 'TASK.md') "- [ ] top`n"
  Write-TestFile (Join-Path $repo 's.txt') "s`n"
  [void](Invoke-Git $repo add s.txt)
  [void](Invoke-Git $repo commit -q -m s)
  [void](Invoke-Git $repo checkout -q feat/stack-base)
  $m = Invoke-Git $repo merge --no-ff -q -m 'merge feat/stack-top' feat/stack-top
  Check 'post-merge into a feature branch: nothing archived' ($m.Code -eq 0 -and (Test-Path -LiteralPath (Join-Path $project 'STATE-feat-stack-top.md')))
  Check 'post-merge into a feature branch: TASK.md kept' (Test-Path -LiteralPath (Join-Path $repo 'TASK.md'))
  Remove-Item -LiteralPath (Join-Path $repo 'TASK.md') -Force
  [void](Invoke-Git $repo checkout -q main)

  $env:WORKSTATION_MEMORY_STORE = Join-Path $t 'no-such-store'
  $r = Invoke-Git $repo checkout -q -b feat/offline
  Check 'store unreachable: checkout works, nothing created' ($r.Code -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $t 'no-such-store')))
  Write-TestFile (Join-Path $repo 'd.txt') "d`n"
  [void](Invoke-Git $repo add d.txt)
  $c = Invoke-Git $repo commit -q -m 'offline'
  Check 'store unreachable: commit passes' ($c.Code -eq 0)
  [void](Invoke-Git $repo worktree remove --force $wt)
} finally {
  $env:WORKSTATION_MEMORY_STORE = $saved.store
  $env:WORKSTATION_STATE_TOOLS = $saved.tools
  Remove-TestRoot $t
}
Complete-StateTest
