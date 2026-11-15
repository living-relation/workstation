# Health check shortcut is manual, and an empty shortcuts\rc folder is removed.
# Usage: pwsh -NoProfile -File workstation/health/tests/test-manual-shortcuts.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$tk = Import-PowerShellDataFile -LiteralPath (Join-Path $repo 'toolkit.psd1')
$maker = Join-Path $repo 'workstation\make-shortcuts.ps1'
$fail = 0
function Check([string]$What, $Got, $Want) { if ("$Got" -eq "$Want") { "PASS $What" } else { "FAIL $What (got '$Got', want '$Want')"; $script:fail++ } }

$hc = @($tk.Shortcuts | Where-Object { $_.Name -eq 'Health check' })
Check 'one health shortcut' $hc.Count 1
Check 'health script path' $hc[0].Script 'health\workstation-status.ps1'
Check 'health script exists' (Test-Path -LiteralPath (Join-Path $repo ('workstation\' + $hc[0].Script))) True
$startup = 0
if ($tk.StartupLinks) { $startup = @($tk.StartupLinks).Count }
Check 'no startup links' $startup 0
Check 'no scheduled task in maker' ((Get-Content -LiteralPath $maker -Raw) -match 'Register-ScheduledTask|schtasks') False

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("sc-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $tmp 'rc') -Force | Out-Null
& pwsh -NoProfile -File $maker -LinkDir $tmp -NoPause | Out-Null
Check 'empty rc removed' (Test-Path -LiteralPath (Join-Path $tmp 'rc')) False

New-Item -ItemType Directory -Path (Join-Path $tmp 'rc') -Force | Out-Null
Set-Content (Join-Path $tmp 'rc\keep.txt') 'x'
& pwsh -NoProfile -File $maker -LinkDir $tmp -NoPause | Out-Null
Check 'rc with a file stays' (Test-Path -LiteralPath (Join-Path $tmp 'rc\keep.txt')) True
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue

if ($fail) { "FAILED: $fail"; exit 1 } else { 'ALL PASS'; exit 0 }
