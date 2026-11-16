# Body-only compare against a fake claude.ai synced folder.
# Usage: pwsh -NoProfile -File workstation/tests/test-skills-drift.ps1
$ErrorActionPreference = 'Stop'
$script = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills-drift.ps1'
$fail = 0
function Check([string]$What, $Got, $Want) {
    if ("$Got" -eq "$Want") { "PASS $What" } else { "FAIL $What (got '$Got', want '$Want')"; $script:fail++ }
}
function Write-Skill([string]$Path, [string]$Front, [string]$Body) {
    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($Path, ($Front + "`n" + $Body), $utf8)
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("sd-" + [guid]::NewGuid().ToString('N'))
$skills = Join-Path $root 'skills'
$synced = Join-Path $root 'synced'
$frontRepo = "---`nname: demo`ndescription: repo`n---"
$frontCloud = "---`nname: demo`ndescription: rewritten by claude.ai`nmetadata:`n  claude: 1`n---"
Write-Skill (Join-Path $skills 'same\SKILL.md') $frontRepo "`nbody one`n"
Write-Skill (Join-Path $synced 'acct-a\same\SKILL.md') $frontCloud "`nbody one`n"
Write-Skill (Join-Path $skills 'changed\SKILL.md') $frontRepo "`nbody repo`n"
Write-Skill (Join-Path $synced 'acct-a\changed\SKILL.md') $frontCloud "`nbody cloud`n"
Write-Skill (Join-Path $skills 'missing\SKILL.md') $frontRepo "`nbody`n"
Write-Skill (Join-Path $synced 'acct-b\same\SKILL.md') $frontCloud "`nbody one`n"
$out = & pwsh -NoProfile -File $script -SkillsRoot $skills -SyncedRoot $synced -NoPause 2>&1
$text = $out -join "`n"
Check 'drift exits 1 when something is missing' $LASTEXITCODE 1
Check 'frontmatter-only difference is ok' ($text -match 'OK same') True
Check 'body difference asks for the zip' ($text -match 'RE-UPLOAD skills/changed.zip') True
Check 'absent skill is not on claude.ai' ($text -match 'NOT ON CLAUDE.AI skills/missing.zip') True
Check 'second account without the changed skill is missing' ($text -match 'MISSING skills/changed.zip') True
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
if ($fail) { "FAILED: $fail"; exit 1 } else { 'ALL PASS'; exit 0 }
