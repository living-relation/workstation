#Requires -Version 5.1
# Run any dashboard toggle without the dashboard, e.g. from a shortcut:
#   toggle.ps1 -Id remote -Action on|off|status|health
#   toggle.ps1 -Action process-check
# Same toggles.py the dashboard uses, so the dashboard and the shortcuts run the same commands.
param([string]$Id = '', [ValidateSet('on', 'off', 'status', 'health', 'list', 'process-check')][string]$Action = 'status', [switch]$NoPause)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'python.ps1')
$python = Find-Python313
if (-not $python) { Write-Host 'Python 3.13 was not found.' -ForegroundColor Red; if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }; exit 1 }
$argList = @((Join-Path $PSScriptRoot 'toggles.py'), $Action)
if ($Id) { $argList += $Id }
Write-Host "Toggle $Id $Action ..." -ForegroundColor Cyan
& $python @argList
$code = $LASTEXITCODE
if ($code -eq 0) { Write-Host 'Done: OK' -ForegroundColor Green } else { Write-Host "Done: problems found (exit $code)" -ForegroundColor Yellow }
if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
exit $code
