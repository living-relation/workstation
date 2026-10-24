<#
.SYNOPSIS
  Admin part of the setup: registers the watcher task and the firewall rule. Run AFTER install.ps1.

.DESCRIPTION
  Open PowerShell with "Run as admin", go to the workstation repo clone (normally <Projects>\active\workstation), then:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install-admin.ps1
  (No memory sync task any more: Cursor reads the memory store read-only. Older installs may still have
  task Claude-Memory-To-Cursor-Sync; preflight flags it as retired.)
  1. Registers task Workstation-Watcher (workstation\toggles\register-watcher-task.ps1): every 15 minutes it
     health-checks the dashboard toggles that are on, runs the process check and shows a toast on problems.
  2. Adds the firewall rule that lets the tailnet reach the dashboard port (8791) on the Tailscale adapter only.
  The task is registered for the account this admin window runs as, so that must be the same
  account that uses Claude / Cursor (checked below).

.PARAMETER ProjectsRoot
  Projects root folder. Default: %USERPROFILE%\Projects

.PARAMETER Force
  Continue even when this admin window runs as a different account than the signed-in user.
#>
[CmdletBinding()]
param(
  [string]$ProjectsRoot,
  [switch]$Force
)
$ErrorActionPreference = 'Stop'
$PkgRoot = $PSScriptRoot
if (-not $PkgRoot) { $PkgRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
# Toolkit folder and script names come from ONE place: toolkit.psd1 next to this script.
$ToolkitDef = Join-Path $PkgRoot 'toolkit.psd1'
if (-not (Test-Path -LiteralPath $ToolkitDef)) { Write-Host "toolkit.psd1 not found next to this script: $ToolkitDef" -ForegroundColor Red; exit 1 }
$TK = Import-PowerShellDataFile -LiteralPath $ToolkitDef

$isAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole((New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544'))
if (-not $isAdmin) {
  Write-Host 'This script must run in an elevated (admin) PowerShell.' -ForegroundColor Red
  Write-Host 'Right-click Windows PowerShell, choose "Run as admin", go to this folder, and run it again.' -ForegroundColor Red
  exit 1
}

# Same account check: tasks are registered for the account running this window.
$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$console = $null
try { $console = (Get-CimInstance Win32_ComputerSystem).UserName } catch { }
if ($console -and ($console -ine $me)) {
  Write-Host "This admin window runs as '$me', but the signed-in user is '$console'." -ForegroundColor Yellow
  Write-Host "The task would be registered for '$me' and use that account's Projects folder." -ForegroundColor Yellow
  if (-not $Force) {
    Write-Host "Stopped. Run this from an admin window opened by '$console' (Run as admin, same account), or add -Force if '$me' is really the right account." -ForegroundColor Red
    exit 1
  }
}

if (-not $ProjectsRoot) { $ProjectsRoot = Join-Path $env:USERPROFILE 'Projects' }
$ProjectsRoot = [IO.Path]::GetFullPath($ProjectsRoot).TrimEnd('\')
$ClaudeDir = Join-Path $ProjectsRoot '_claude'
Write-Host "Projects root: $ProjectsRoot"
if (-not (Test-Path -LiteralPath $ClaudeDir -PathType Container)) {
  Write-Host "Not found: $ClaudeDir. Run install.ps1 (normal PowerShell) first." -ForegroundColor Red
  exit 1
}

$failed = $false

# Retired: the old memory sync task. Reported only; this script never removes it.
$oldSync = Get-ScheduledTask -TaskName 'Claude-Memory-To-Cursor-Sync' -ErrorAction SilentlyContinue
if ($oldSync -and "$($oldSync.State)" -eq 'Disabled') {
  Write-Host "Retired task Claude-Memory-To-Cursor-Sync is disabled (fine; nothing to do). Optional cleanup: Unregister-ScheduledTask -TaskName 'Claude-Memory-To-Cursor-Sync' -Confirm:`$false"
} elseif ($oldSync) {
  Write-Host "Retired task Claude-Memory-To-Cursor-Sync is still ENABLED (blocks preflight). Disable it: Disable-ScheduledTask -TaskName 'Claude-Memory-To-Cursor-Sync' (or remove it: Unregister-ScheduledTask -TaskName 'Claude-Memory-To-Cursor-Sync' -Confirm:`$false)" -ForegroundColor Yellow
}

# 1. Workstation-Watcher (every 15 minutes, toast on problems).
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PkgRoot "$($TK.PackageFolder)\toggles\register-watcher-task.ps1")
if ($LASTEXITCODE -ne 0) { $failed = $true; Write-Host 'Workstation-Watcher was NOT registered (see the message above).' -ForegroundColor Red }
elseif (Get-ScheduledTask -TaskName 'Workstation-Watcher' -ErrorAction SilentlyContinue) { Write-Host 'Verified: task Workstation-Watcher is registered.' -ForegroundColor Green }
else { $failed = $true; Write-Host 'Task Workstation-Watcher not found after registering.' -ForegroundColor Red }

# 2. Dashboard tailnet firewall rule (Tailscale adapter only; never the public internet).
$tsAlias = (Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Tailscale' -or $_.InterfaceDescription -match 'Tailscale' } | Select-Object -First 1).Name
if (-not $tsAlias) { Write-Host 'No Tailscale adapter: dashboard firewall rule skipped.' }
elseif (Get-NetFirewallRule -DisplayName 'Workstation dashboard tailnet' -ErrorAction SilentlyContinue) { Write-Host 'Dashboard firewall rule already there.' }
else {
  New-NetFirewallRule -DisplayName 'Workstation dashboard tailnet' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8791 -InterfaceAlias $tsAlias -Profile Any | Out-Null
  Write-Host "Firewall allows TCP 8791 on $tsAlias only." -ForegroundColor Green
}

if ($failed) { exit 1 }
Write-Host 'Admin setup done.' -ForegroundColor Green
exit 0
