<#
.SYNOPSIS
  Admin part of the setup: adds the dashboard firewall rule. Run AFTER install.ps1.

.DESCRIPTION
  Open PowerShell with "Run as admin", go to the workstation repo clone (normally <Projects>\active\workstation), then:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install-admin.ps1
  (No memory sync task any more: Cursor edits the live memory store. Older installs may still have
  task Claude-Memory-To-Cursor-Sync; preflight flags it as retired.)
  The watcher is not a scheduled task any more: it is off by default and runs only from the Watcher On
  shortcut (Watcher Off stops it).
  1. Adds the firewall rule that lets the tailnet reach the dashboard port (8791) on the Tailscale adapter only.
  This admin window must run as the same account that uses Claude / Cursor (checked below).

.PARAMETER ProjectsRoot
  Projects root folder. Default: the one in install.ps1's runtime config, else %USERPROFILE%\Projects,
  else C:\projects (the first that has a _claude folder).

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

if (-not $ProjectsRoot) {
  # Same root install.ps1 used: its runtime config first, then %USERPROFILE%\Projects, then C:\projects.
  $cfg = Join-Path (Join-Path $env:LOCALAPPDATA $(if ($TK.StateFolder) { $TK.StateFolder } else { 'Workstation' })) $(if ($TK.ConfigFile) { $TK.ConfigFile } else { 'workstation.json' })
  try { if (Test-Path -LiteralPath $cfg) { $ProjectsRoot = [string](Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json).projectsRoot } } catch { }
  if (-not $ProjectsRoot -or -not (Test-Path -LiteralPath (Join-Path $ProjectsRoot '_claude') -PathType Container)) {
    $ProjectsRoot = Join-Path $env:USERPROFILE 'Projects'
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectsRoot '_claude') -PathType Container) -and (Test-Path -LiteralPath 'C:\projects\_claude' -PathType Container)) { $ProjectsRoot = 'C:\projects' }
  }
}
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

# Retired: the old Workstation-Watcher task (the watcher is now the manual Watcher On / Off shortcuts).
if (Get-ScheduledTask -TaskName 'Workstation-Watcher' -ErrorAction SilentlyContinue) {
  Unregister-ScheduledTask -TaskName 'Workstation-Watcher' -Confirm:$false
  Write-Host 'Removed the retired task Workstation-Watcher (use the Watcher On shortcut instead).' -ForegroundColor Green
}

# 1. Dashboard tailnet firewall rule (Tailscale adapter only; never the public internet).
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
