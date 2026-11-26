# Three-way merge keeps Local edits, takes upstream additions, and marks conflicts.
# Usage: pwsh -NoProfile -File workstation/tests/test-check-upstream.ps1
$ErrorActionPreference = 'Stop'
$script = Join-Path (Split-Path -Parent $PSScriptRoot) 'check-upstream.ps1'
$fail = 0
function Check([string]$What, $Got, $Want) {
    if ("$Got" -eq "$Want") { "PASS $What" } else { "FAIL $What (got '$Got', want '$Want')"; $script:fail++ }
}
function Init-Repo([string]$Path) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    & git -C $Path init -b main | Out-Null
    & git -C $Path config user.email 'test@example.com'
    & git -C $Path config user.name 'test'
    & git -C $Path config commit.gpgsign false
    & git -C $Path config core.autocrlf false
}
function Commit-All([string]$Path, [string]$Msg) {
    & git -C $Path add -A
    & git -C $Path commit -m $Msg | Out-Null
    return (& git -C $Path rev-parse HEAD).Trim()
}
function Write-Utf8([string]$Path, [string]$Text) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($Path, $Text, $utf8)
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("up-" + [guid]::NewGuid().ToString('N'))
$up = Join-Path $root 'upstream'
$ws = Join-Path $root 'ws'
Init-Repo $up
$baseText = @"
---
name: wizard
description: long description from upstream
---
# Title

intro stays

middle stays

base line
"@
Write-Utf8 (Join-Path $up 'skill\SKILL.md') $baseText
$baseSha = Commit-All $up 'base'
$headText = $baseText.Replace('base line', "base line`nupstream line")
Write-Utf8 (Join-Path $up 'skill\SKILL.md') $headText
$headSha = Commit-All $up 'upstream line'
Init-Repo $ws
$local = @"
---
name: wizard
description: short
metadata:
  upstream: $up
  upstream-path: skill
  upstream-base: $baseSha
---
# Title

## When to use
Local section

intro stays

middle stays

base line
"@
Write-Utf8 (Join-Path $ws 'skills\wizard\SKILL.md') $local
Write-Utf8 (Join-Path $ws 'skills\wizard\UPSTREAM.md') "local notes`n"
Write-Utf8 (Join-Path $ws 'skills\mine\SKILL.md') "---`nname: mine`ndescription: x`n---`nbody`n"
Commit-All $ws 'local' | Out-Null
& pwsh -NoProfile -File $script -RepoRoot $ws -NoPr | Out-Null
Check 'merge exits 0' $LASTEXITCODE 0
$merged = [IO.File]::ReadAllText((Join-Path $ws 'skills\wizard\SKILL.md'))
Check 'keeps short description' ($merged -match 'description: short') True
Check 'keeps When to use' ($merged -match 'Local section') True
Check 'takes upstream line' ($merged -match 'upstream line') True
Check 'keeps base line' ($merged -match 'base line') True
Check 'bumps base' ($merged -match [regex]::Escape($headSha)) True
Check 'no conflict on clean merge' ($merged -match '<<<<<<<') False
Check 'local notes stay' ([IO.File]::ReadAllText((Join-Path $ws 'skills\wizard\UPSTREAM.md')) -match 'local notes') True
Check 'skill without upstream stays' (Test-Path (Join-Path $ws 'skills\mine\SKILL.md')) True
$branch = (& git -C $ws rev-parse --abbrev-ref HEAD).Trim()
Check 'new branch' ($branch -like 'chore/upstream-*') True

# Same line edited on both sides is a conflict, and Local other edits stay.
$up2 = Join-Path $root 'upstream2'
$ws2 = Join-Path $root 'ws2'
Init-Repo $up2
Write-Utf8 (Join-Path $up2 'skill\SKILL.md') $baseText
$b2 = Commit-All $up2 'base'
Write-Utf8 (Join-Path $up2 'skill\SKILL.md') ($baseText.Replace('base line', 'up line'))
Commit-All $up2 'theirs' | Out-Null
Init-Repo $ws2
$dan2 = @"
---
name: wizard
description: short
metadata:
  upstream: $up2
  upstream-path: skill
  upstream-base: $b2
---
# Title

## When to use
Local section

intro stays

middle stays

local line
"@
Write-Utf8 (Join-Path $ws2 'skills\wizard\SKILL.md') $dan2
Commit-All $ws2 'local' | Out-Null
& pwsh -NoProfile -File $script -RepoRoot $ws2 -NoPr | Out-Null
Check 'conflict run exits 0' $LASTEXITCODE 0
$conf = [IO.File]::ReadAllText((Join-Path $ws2 'skills\wizard\SKILL.md'))
Check 'conflict marked' ($conf -match '<<<<<<<') True
Check 'conflict keeps Local section' ($conf -match 'Local section') True

Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
if ($fail) { "FAILED: $fail"; exit 1 } else { 'ALL PASS'; exit 0 }
