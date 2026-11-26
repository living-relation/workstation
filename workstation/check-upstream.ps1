#Requires -Version 5.1
# Manual. For each skill whose SKILL.md has metadata.upstream:
#   fetch upstream, show commits base..HEAD, three-way merge into this repo's copy
#   (git merge-file: keep his edits, mark conflicts), bump upstream-base,
#   and open a PR on a new branch.
# No schedule. No sign-in item. -WhatIf prints the plan and writes nothing.
# -NoPr writes the merge and commits it on a new branch, and does not push.
param(
    [string]$RepoRoot,
    [string]$SkillsRoot,
    [string]$CacheDir,
    [switch]$WhatIf,
    [switch]$NoPr
)
$ErrorActionPreference = 'Stop'
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $Global:PSNativeCommandUseErrorActionPreference = $false
}
if (-not $RepoRoot) {
    $RepoRoot = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null | Select-Object -First 1)
    if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }
}
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
if (-not $SkillsRoot) { $SkillsRoot = Join-Path $RepoRoot 'skills' }
if (-not $CacheDir) {
    $tmp = $env:TEMP
    if (-not $tmp) { $tmp = [IO.Path]::GetTempPath() }
    $CacheDir = Join-Path $tmp 'workstation-upstream'
}
$utf8 = New-Object System.Text.UTF8Encoding $false

function Say([string]$Msg) { Write-Host $Msg }
function Invoke-Git([string]$Cwd, [string[]]$GitArgs) {
    $out = & git -C $Cwd @GitArgs 2>&1
    $code = $LASTEXITCODE
    $text = @($out | ForEach-Object { "$_" }) -join "`n"
    return @{ Code = $code; Text = $text }
}
function Read-Text([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return [IO.File]::ReadAllText($Path)
}
function Write-Text([string]$Path, [string]$Text) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, $utf8)
}
function Get-FrontMatter([string]$Text) {
    if (-not $Text.StartsWith('---')) { return $null }
    $m = [regex]::Match($Text.Substring(3), '(?s)^\r?\n?(.*?)\r?\n---')
    if (-not $m.Success) { return $null }
    return $m.Groups[1].Value
}
function Get-UpstreamMeta([string]$Text) {
    $fm = Get-FrontMatter $Text
    if (-not $fm) { return $null }
    $in = $false
    $url = $null; $rel = $null; $base = $null
    foreach ($line in ($fm -split '\r?\n')) {
        if ($line -match '^metadata\s*:\s*$') { $in = $true; continue }
        if ($in -and $line -match '^\S') { $in = $false }
        if (-not $in) { continue }
        if ($line -match '^\s+upstream:\s*(.+)\s*$') { $url = $Matches[1].Trim().Trim('"').Trim("'") }
        elseif ($line -match '^\s+upstream-path:\s*(.+)\s*$') { $rel = $Matches[1].Trim().Trim('"').Trim("'").Trim('/') }
        elseif ($line -match '^\s+upstream-base:\s*([0-9a-fA-F]+)') { $base = $Matches[1] }
    }
    if (-not $url -or -not $base) { return $null }
    if (-not $rel) { $rel = '' }
    return @{ Url = $url; Rel = $rel; Base = $base }
}
function Resolve-Upstream([string]$Url) {
    if (Test-Path -LiteralPath $Url -PathType Container) {
        $p = (Resolve-Path -LiteralPath $Url).Path
        $gitDir = Join-Path $p '.git'
        if (Test-Path -LiteralPath $gitDir) { return $p }
    }
    if (-not (Test-Path -LiteralPath $CacheDir)) { New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null }
    $key = ($Url -replace '[^A-Za-z0-9._-]', '_')
    $dest = Join-Path $CacheDir $key
    if (Test-Path -LiteralPath (Join-Path $dest '.git')) {
        $f = Invoke-Git $dest @('fetch', '--prune', 'origin')
        if ($f.Code -ne 0) { throw "fetch failed for $Url`n$($f.Text)" }
        $h = Invoke-Git $dest @('remote', 'set-head', 'origin', '-a')
        if ($h.Code -ne 0) { throw "could not read upstream HEAD for $Url`n$($h.Text)" }
    } else {
        $c = Invoke-Git $CacheDir @('clone', '--origin', 'origin', $Url, $dest)
        if ($c.Code -ne 0) { throw "clone failed for $Url`n$($c.Text)" }
    }
    return $dest
}
function Get-Rev([string]$Repo, [string]$Rev) {
    $r = Invoke-Git $Repo @('rev-parse', $Rev)
    if ($r.Code -ne 0) { return $null }
    return ($r.Text.Trim())
}
function Get-TreeFiles([string]$Repo, [string]$Rev, [string]$Rel) {
    $args = @('ls-tree', '-r', '--name-only', $Rev)
    if ($Rel) { $args += '--'; $args += $Rel }
    $r = Invoke-Git $Repo $args
    if ($r.Code -ne 0) { return @() }
    $prefix = ''
    if ($Rel) { $prefix = ($Rel.Trim('/') + '/') }
    $out = @()
    foreach ($line in ($r.Text -split '\n')) {
        $line = $line.Trim()
        if (-not $line) { continue }
        if ($prefix -and $line.StartsWith($prefix)) { $line = $line.Substring($prefix.Length) }
        elseif ($prefix) { continue }
        if ($line) { $out += $line }
    }
    return $out
}
function Save-GitFile([string]$Repo, [string]$Rev, [string]$GitPath, [string]$Dest) {
    $r = Invoke-Git $Repo @('show', "${Rev}:${GitPath}")
    if ($r.Code -ne 0) { return $false }
    $text = $r.Text
    if ($text -and -not $text.EndsWith("`n")) { $text += "`n" }
    Write-Text $Dest $text
    return $true
}
function Normalize-File([string]$Path) {
    $t = Read-Text $Path
    $t = $t -replace "`r`n", "`n" -replace "`r", "`n"
    if (-not $t.EndsWith("`n")) { $t += "`n" }
    Write-Text $Path $t
}
function Merge-OneFile([string]$OursPath, [string]$BasePath, [string]$TheirsPath) {
    Normalize-File $OursPath
    Normalize-File $BasePath
    Normalize-File $TheirsPath
    $r = Invoke-Git $RepoRoot @('merge-file', '-p', '--diff3', '-L', 'ours', '-L', 'base', '-L', 'upstream', '--', $OursPath, $BasePath, $TheirsPath)
    $text = $r.Text
    if ($null -eq $text) { $text = '' }
    if ($text -and -not $text.EndsWith("`n")) { $text += "`n" }
    return @{ Text = $text; Conflicts = [int]($r.Code) }
}
function Set-UpstreamBase([string]$Text, [string]$Sha) {
    $pat = '(?m)^(?<ind>[ \t]+upstream-base:[ \t]+)[0-9a-fA-F]+[ \t]*$'
    return [regex]::Replace($Text, $pat, '${ind}' + $Sha)
}

Say 'check-upstream'
Say "  repo: $RepoRoot"
if ($WhatIf) { Say '  mode: WhatIf (no changes)' }

$skills = @()
foreach ($d in @(Get-ChildItem -LiteralPath $SkillsRoot -Directory -ErrorAction SilentlyContinue)) {
    $md = Join-Path $d.FullName 'SKILL.md'
    if (-not (Test-Path -LiteralPath $md -PathType Leaf)) { continue }
    $meta = Get-UpstreamMeta (Read-Text $md)
    if (-not $meta) { continue }
    $skills += [pscustomobject]@{ Name = $d.Name; Dir = $d.FullName; Meta = $meta }
}
if (-not $skills.Count) { Say 'no skill has metadata.upstream'; exit 0 }

$changed = @()
$conflictNotes = @()
foreach ($s in $skills) {
    Say ''
    Say "skill $($s.Name)"
    $upstream = Resolve-Upstream $s.Meta.Url
    $head = Get-Rev $upstream 'HEAD'
    if (-not $head) { $head = Get-Rev $upstream 'origin/HEAD' }
    if (-not $head) { throw "no HEAD in $upstream" }
    $baseFull = Get-Rev $upstream $s.Meta.Base
    if (-not $baseFull) { throw "upstream-base $($s.Meta.Base) is not in $upstream" }
    Say "  base $($s.Meta.Base)  head $head"
    $log = Invoke-Git $upstream @('log', '--oneline', "$baseFull..$head", '--', $s.Meta.Rel)
    if ($log.Text) { Say $log.Text } else { Say '  no commits on the skill path' }
    if ($baseFull -eq $head) { Say '  up to date'; continue }

    $baseFiles = @(Get-TreeFiles $upstream $baseFull $s.Meta.Rel)
    $headFiles = @(Get-TreeFiles $upstream $head $s.Meta.Rel)
    $names = @($baseFiles + $headFiles | Select-Object -Unique)
    $work = Join-Path ([IO.Path]::GetTempPath()) ("upmerge-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $skillConflicts = 0
    foreach ($rel in $names) {
        $gitRel = $rel
        if ($s.Meta.Rel) { $gitRel = ($s.Meta.Rel.Trim('/') + '/' + $rel) }
        $oursDisk = Join-Path $s.Dir ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
        $bFile = Join-Path $work ("b-" + ($rel -replace '[\\/]', '_'))
        $tFile = Join-Path $work ("t-" + ($rel -replace '[\\/]', '_'))
        $oFile = Join-Path $work ("o-" + ($rel -replace '[\\/]', '_'))
        $hasBase = Save-GitFile $upstream $baseFull $gitRel $bFile
        $hasTheirs = Save-GitFile $upstream $head $gitRel $tFile
        if (-not $hasBase) { Write-Text $bFile '' }
        if (-not $hasTheirs) { Write-Text $tFile '' }
        if (Test-Path -LiteralPath $oursDisk -PathType Leaf) { Write-Text $oFile (Read-Text $oursDisk) }
        else { Write-Text $oFile '' }
        $merged = Merge-OneFile $oFile $bFile $tFile
        if ($merged.Conflicts -gt 0) { $skillConflicts += $merged.Conflicts }
        $localRel = $rel -replace '/', [IO.Path]::DirectorySeparatorChar
        $dest = Join-Path $s.Dir $localRel
        if (-not $merged.Text) {
            if ((Test-Path -LiteralPath $dest) -and -not $WhatIf) { Remove-Item -LiteralPath $dest -Force }
            Say "  removed $rel"
            continue
        }
        if ($rel -eq 'SKILL.md') { $merged.Text = Set-UpstreamBase $merged.Text $head }
        if ($WhatIf) { Say "  WOULD merge $rel" }
        else { Write-Text $dest $merged.Text; Say "  merged $rel" }
    }
    $skillMd = Join-Path $s.Dir 'SKILL.md'
    if (-not $WhatIf -and (Test-Path -LiteralPath $skillMd)) {
        $bumped = Set-UpstreamBase (Read-Text $skillMd) $head
        Write-Text $skillMd $bumped
    }
    if ($skillConflicts) {
        $conflictNotes += "$($s.Name): $skillConflicts conflict(s)"
        Say "  CONFLICTS $skillConflicts (markers left in the files)"
    }
    $changed += $s.Name
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not $changed.Count) { Say 'done'; exit 0 }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$branch = "chore/upstream-$stamp"
$title = "Update skills from upstream"
$body = "Manual check-upstream run.`n`n" + (($changed | ForEach-Object { "- $_" }) -join "`n")
if ($conflictNotes.Count) { $body += "`n`nConflicts to resolve:`n" + (($conflictNotes | ForEach-Object { "- $_" }) -join "`n") }
$body += "`n`nThe repo owner merges."
if ($WhatIf) {
    Say ''
    Say "WOULD branch $branch"
    Say "WOULD commit $($changed -join ', ')"
    Say 'WOULD open a PR (no push in WhatIf)'
    Say 'done'
    exit 0
}

$co = Invoke-Git $RepoRoot @('checkout', '-b', $branch)
if ($co.Code -ne 0) { throw "could not create branch $branch`n$($co.Text)" }
foreach ($name in $changed) {
    $rel = 'skills/' + $name
    $a = Invoke-Git $RepoRoot @('add', '--', $rel)
    if ($a.Code -ne 0) { throw "git add failed for $rel`n$($a.Text)" }
}
$msg = "Update skills from upstream`n`n" + ($changed -join ', ')
$commit = Invoke-Git $RepoRoot @('commit', '-m', $msg)
if ($commit.Code -ne 0) { throw "commit failed`n$($commit.Text)" }
Say "committed on $branch"
if ($NoPr) { Say 'no push (-NoPr)'; Say 'done'; exit 0 }
$push = Invoke-Git $RepoRoot @('push', '-u', 'origin', $branch)
if ($push.Code -ne 0) { throw "push failed`n$($push.Text)" }
$pr = & gh pr create --base main --head $branch --title $title --body $body 2>&1
if ($LASTEXITCODE -ne 0) { throw "gh pr create failed`n$pr" }
Say $pr
Say 'done'
exit 0
