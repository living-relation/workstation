# pack-skill-zips.ps1 - optional local rebuild of skills\<name>.zip for each skills\<name>\ with SKILL.md.
# The GitHub Action owns the committed zips; you do not need to run this.
# Usage (from the repo root, or any directory):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pack-skill-zips.ps1 [-Strict]
[CmdletBinding()]
param([switch]$Strict)
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$PyScript = Join-Path $PSScriptRoot 'pack-skill-zips.py'
$py = $null
foreach ($c in @('python3', 'python')) {
  $cmd = Get-Command $c -ErrorAction SilentlyContinue
  if ($cmd) { $py = $cmd.Source; break }
}
if (-not $py) {
  $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
  if ($pyLauncher) { $py = $pyLauncher.Source }
}
if (-not $py) { throw 'python3/python not found on PATH' }
$argList = @($PyScript)
if ($py.ToLower().EndsWith('\py.exe') -or $py.ToLower().EndsWith('/py')) { $argList = @('-3') + $argList }
if ($Strict) { $argList += '--strict' }
Push-Location $RepoRoot
try {
  & $py @argList
  exit $LASTEXITCODE
} finally { Pop-Location }
