# Shared git branch helpers for the status shortcuts. Dot-sourced. Read-only:
# nothing here switches branches, fetches, stashes, resets or commits. Windows PowerShell 5.1.

# Branch names that count as a "base" branch (no warning), besides origin's default branch.
$BaseBranchNames = @('main', 'master', 'dev', 'develop')

function Test-OriginBranch([string]$Path, [string]$Name) {
    if (-not $Name) { return $false }
    & git -C $Path rev-parse --verify --quiet "refs/remotes/origin/$Name" *> $null
    return ($LASTEXITCODE -eq 0)
}

# origin's default branch from refs/remotes/origin/HEAD. That ref can be missing or stale, so it is
# only trusted when the branch it names still exists locally as origin/<name>. Returns $null otherwise.
function Get-OriginDefaultBranch([string]$Path) {
    $ref = (& git -C $Path symbolic-ref --quiet refs/remotes/origin/HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $ref) { return $null }
    $name = "$ref".Trim() -replace '^refs/remotes/origin/', ''
    if (Test-OriginBranch $Path $name) { return $name }
    return $null
}

# Branch facts for one repo: current branch (or detached), origin default, the base to suggest
# (dev if origin/dev exists, else origin's default, else main) and whether the current branch is a base.
function Get-RepoBranchInfo([string]$Path) {
    $branch = (& git -C $Path symbolic-ref --quiet --short HEAD 2>$null)
    $detached = ($LASTEXITCODE -ne 0 -or -not $branch)
    $head = $null
    if ($detached) { $branch = $null; $head = (& git -C $Path rev-parse --short HEAD 2>$null) }
    $default = Get-OriginDefaultBranch $Path
    $suggest = if (Test-OriginBranch $Path 'dev') { 'dev' } elseif ($default) { $default } else { 'main' }
    $isBase = $false
    if (-not $detached) {
        $isBase = ($BaseBranchNames -contains "$branch".ToLower()) -or ($default -and "$branch" -eq $default)
    }
    [pscustomobject]@{
        Branch        = "$branch".Trim()
        Detached      = $detached
        Head          = "$head".Trim()
        OriginDefault = $default
        Base          = $suggest
        IsBase        = $isBase
    }
}

# "<repo>: on feature branch 'x', not 'dev'" / "<repo>: detached HEAD at abc123, not on 'dev'"
function Format-BranchWarning([string]$Name, $Info) {
    if ($Info.Detached) { return "${Name}: detached HEAD at $($Info.Head), not on a branch (base is '$($Info.Base)')" }
    return "${Name}: on feature branch '$($Info.Branch)', not '$($Info.Base)'"
}

# One-line reason for a failed fetch/pull, from git's own output.
function Get-PullFailureReason([string[]]$Output) {
    $t = ($Output | ForEach-Object { "$_" }) -join "`n"
    if ($t -match 'Authentication failed|could not read Username|Permission denied \(publickey\)|returned error: 40[13]|Repository not found|terminal prompts disabled') { return @{ Kind = 'auth';     Text = 'GitHub sign-in failed (credentials missing or expired, or no access to the repo)' } }
    if ($t -match 'Could not resolve host|unable to access|Failed to connect|Connection timed out|Connection refused|Could not read from remote repository|does not appear to be a git repository') { return @{ Kind = 'network';  Text = 'remote not reachable (network, VPN or remote URL problem)' } }
    if ($t -match 'There is no tracking information for the current branch|no upstream') { return @{ Kind = 'noupstream'; Text = 'no upstream branch set for the current branch' } }
    if ($t -match 'You are not currently on a branch') { return @{ Kind = 'detached'; Text = 'detached HEAD: not on a branch, so there is nothing to pull into' } }
    if ($t -match 'unmerged files|You have not concluded your merge|CONFLICT|fix conflicts') { return @{ Kind = 'conflict'; Text = 'unresolved conflicts or an unfinished merge/rebase in the working tree' } }
    if ($t -match 'would be overwritten by merge|Please commit your changes or stash them|You have unstaged changes|Your local changes') { return @{ Kind = 'dirty';    Text = 'uncommitted local changes block the pull' } }
    if ($t -match 'Not possible to fast-forward|diverg|non-fast-forward|have diverged') { return @{ Kind = 'diverged'; Text = 'diverged: the branch has local commits and the upstream has new commits (fast-forward impossible)' } }
    if ($t -match "couldn't find remote ref|no such ref was fetched") { return @{ Kind = 'goneupstream'; Text = 'the upstream branch no longer exists on the remote' } }
    $line = ($Output | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^(fatal|error):' } | Select-Object -First 1)
    if (-not $line) { $line = ($Output | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Select-Object -Last 1) }
    return @{ Kind = 'other'; Text = "git said: $line" }
}

# Manual fix suggestion. Never something the scripts do themselves.
function Get-PullFixHint([string]$Kind, [string]$Path, $Info) {
    $q = '"' + $Path + '"'
    $b = $Info.Branch
    $base = $Info.Base
    $switchCmd = "git -C $q switch $base, then pull that repo again (git pull --ff-only)"
    $onFeature = (-not $Info.IsBase)
    switch ($Kind) {
        'noupstream'   { if ($onFeature) { return "fix by hand: $switchCmd; or publish the branch: git -C $q push -u origin $b" } else { return "fix by hand: git -C $q branch --set-upstream-to=origin/$b, then pull that repo again (git pull --ff-only)" } }
        'diverged'     { if ($onFeature) { return "fix by hand: $switchCmd; or merge/rebase '$b' yourself (pulls only fast-forward)" } else { return "fix by hand: merge or rebase '$b' onto its upstream yourself (pulls only fast-forward)" } }
        'detached'     { return "fix by hand: $switchCmd" }
        'dirty'        { return "fix by hand: commit or stash your changes yourself, then pull that repo again (git pull --ff-only)" }
        'conflict'     { return "fix by hand: finish or abort the merge/rebase in $q (git status shows how), then pull that repo again (git pull --ff-only)" }
        'goneupstream' { if ($onFeature) { return "fix by hand: $switchCmd" } else { return "fix by hand: git -C $q branch --set-upstream-to=origin/<branch>" } }
        'auth'         { return 'fix by hand: sign in to GitHub again (Git Credential Manager or gh auth login), then pull that repo again (git pull --ff-only)' }
        'network'      { return 'fix by hand: check the network/VPN and the remote URL, then pull that repo again (git pull --ff-only)' }
        default        { if ($onFeature) { return "fix by hand: $switchCmd" } else { return "run git -C $q status for details" } }
    }
}

# Native git output (stdout strings and stderr ErrorRecords from 2>&1) as plain text lines.
function ConvertTo-GitLines {
    process {
        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            $m = $_.Exception.Message
            if ($m -eq 'System.Management.Automation.RemoteException') { $m = '' }
            $m
        } else { "$_" }
    }
}
