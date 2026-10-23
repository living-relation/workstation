<#
.SYNOPSIS
  Admin part of the setup: registers the scheduled task. Run AFTER install.ps1.

.DESCRIPTION
  Open PowerShell with "Run as admin", go to the workstation repo clone (normally <Projects>\active\workstation), then:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install-admin.ps1
  1. Copies the memory sync scripts into <Projects>\_claude (if missing or changed) and runs
     <Projects>\_claude\register-memory-sync-task.ps1: task Claude-Memory-To-Cursor-Sync, every 15 minutes.
     It uses Register-ScheduledTask (an existing task is replaced). Safe to re-run.
  2. Registers task Workstation-Watcher (workstation\toggles\register-watcher-task.ps1): every 15 minutes it
     health-checks the dashboard toggles that are on, runs the process check and shows a toast on problems.
  3. Adds the firewall rule that lets the tailnet reach the dashboard port (8791) on the Tailscale adapter only.
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

# 1. Make sure the _claude scripts are in place (normally install.ps1 already copied them).
foreach ($f in 'sync-claude-memory-to-cursor.ps1', 'run-hidden.vbs', 'register-memory-sync-task.ps1') {
  $src = Join-Path $PkgRoot "memory\_claude\$f"
  $dst = Join-Path $ClaudeDir $f
  if (-not (Test-Path -LiteralPath $dst)) { Copy-Item -LiteralPath $src -Destination $dst; Write-Host "copied $dst" }
  elseif ((Get-FileHash -LiteralPath $dst).Hash -ne (Get-FileHash -LiteralPath $src).Hash) {
    Copy-Item -LiteralPath $dst -Destination "$dst.bak-$Stamp" -Force
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "updated $dst (old copy kept as .bak-$Stamp)"
  } else { Write-Host "up to date: $dst" }
}

$failed = $false

# 2. Claude-Memory-To-Cursor-Sync (every 15 minutes). The script uses Register-ScheduledTask.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ClaudeDir 'register-memory-sync-task.ps1')
if ($LASTEXITCODE -ne 0) { $failed = $true; Write-Host 'Claude-Memory-To-Cursor-Sync was NOT registered (see the message above).' -ForegroundColor Red }
else {
  $t = Get-ScheduledTask -TaskName 'Claude-Memory-To-Cursor-Sync' -ErrorAction SilentlyContinue
  if ($t) {
    Write-Host "Verified: task Claude-Memory-To-Cursor-Sync is $($t.State)." -ForegroundColor Green
    Start-ScheduledTask -TaskName 'Claude-Memory-To-Cursor-Sync'
    Write-Host 'Started one sync run now. Its result goes to <Projects>\_claude\sync-claude-memory-to-cursor.log.'
  } else { $failed = $true; Write-Host 'Task Claude-Memory-To-Cursor-Sync not found after registering.' -ForegroundColor Red }
}

# 3. Workstation-Watcher (every 15 minutes, toast on problems).
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PkgRoot "$($TK.PackageFolder)\toggles\register-watcher-task.ps1")
if ($LASTEXITCODE -ne 0) { $failed = $true; Write-Host 'Workstation-Watcher was NOT registered (see the message above).' -ForegroundColor Red }
elseif (Get-ScheduledTask -TaskName 'Workstation-Watcher' -ErrorAction SilentlyContinue) { Write-Host 'Verified: task Workstation-Watcher is registered.' -ForegroundColor Green }
else { $failed = $true; Write-Host 'Task Workstation-Watcher not found after registering.' -ForegroundColor Red }

# 4. Dashboard tailnet firewall rule (Tailscale adapter only; never the public internet).
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
