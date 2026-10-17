<#
.SYNOPSIS
  Admin part of the setup: registers the scheduled task(s). Run AFTER install.ps1.

.DESCRIPTION
  Open PowerShell with "Run as admin", go to the workstation repo clone (normally <Projects>\active\workstation), then:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install-admin.ps1
  1. Copies the memory sync scripts into <Projects>\_claude (if missing or changed) and runs
     <Projects>\_claude\register-memory-sync-task.ps1: task Claude-Memory-To-Cursor-Sync, every 15 minutes.
  2. Runs the toolkit's latch\register-ensure-grokbot-task.ps1 from this clone (PackageFolder in toolkit.psd1, e.g.
     <clone>\workstation\): task Latch-EnsureGrokBot (weekdays 8:30 and on unlock) running ensure-grokbot.ps1
     straight from the clone (no copy; its log stays in %USERPROFILE%\.grokbot\latch\), and adds the GrokBot
     startup entry if it is missing. Both use Register-ScheduledTask (an existing task is replaced). Safe to re-run.
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

# 3. Latch-EnsureGrokBot task + GrokBot startup entry (Latch's script; idempotent)
$latch = Join-Path (Join-Path $PkgRoot $TK.PackageFolder) $TK.LatchRegister
if (-not (Test-Path -LiteralPath $latch)) {
  $failed = $true
  Write-Host "Not found: $latch. Run this from the workstation repo clone." -ForegroundColor Red
} else {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $latch -NoPause
  if ($LASTEXITCODE -ne 0) { $failed = $true; Write-Host 'Latch-EnsureGrokBot was NOT registered (see the message above).' -ForegroundColor Red }
  else {
    $t = Get-ScheduledTask -TaskName 'Latch-EnsureGrokBot' -ErrorAction SilentlyContinue
    if ($t) { Write-Host "Verified: task Latch-EnsureGrokBot is $($t.State); runs $(@($t.Actions)[0].Arguments)" -ForegroundColor Green }
    else { $failed = $true; Write-Host 'Task Latch-EnsureGrokBot not found after registering.' -ForegroundColor Red }
    $run = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'GrokBot' -ErrorAction SilentlyContinue).GrokBot
    if ($run) { Write-Host "Verified: startup entry GrokBot = $run" -ForegroundColor Green }
    else { Write-Host 'Startup entry GrokBot is not set (Grok Bot not installed yet?). Install Grok Bot, then run this script again.' -ForegroundColor Yellow }
  }
}

if ($failed) { exit 1 }
Write-Host 'Admin setup done.' -ForegroundColor Green
exit 0
