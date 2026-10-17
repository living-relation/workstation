# Registers the scheduled task Claude-Memory-To-Cursor-Sync: runs run-hidden.vbs (which runs
# sync-claude-memory-to-cursor.ps1 with no window) every 15 minutes for the current user.
# Portable: run-hidden.vbs is found next to this script. Safe to re-run (-Force replaces the task).
# Run from an elevated PowerShell:
#   powershell -NoProfile -ExecutionPolicy Bypass -File "<Projects>\_claude\register-memory-sync-task.ps1"
$ErrorActionPreference = 'Stop'
$taskName = 'Claude-Memory-To-Cursor-Sync'

$isAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole((New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544'))  # built-in Admins group
if (-not $isAdmin) {
  Write-Host "NOT REGISTERED: this script must be run from an elevated (admin) PowerShell." -ForegroundColor Red
  Write-Host "Right-click Windows PowerShell, choose 'Run as admin...', then run this script again." -ForegroundColor Red
  exit 1
}

$claudeDir = $PSScriptRoot
if (-not $claudeDir) { $claudeDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$vbs = Join-Path $claudeDir 'run-hidden.vbs'
if (-not (Test-Path -LiteralPath $vbs -PathType Leaf)) {
  Write-Host "NOT REGISTERED: run-hidden.vbs was not found next to this script: $vbs" -ForegroundColor Red
  exit 1
}

try {
  $action   = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('//B //Nologo "' + $vbs + '"')
  $trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15)
  $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -Hidden
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
} catch {
  Write-Host ("NOT REGISTERED: " + $_.Exception.Message) -ForegroundColor Red
  exit 1
}
Write-Host "Registered scheduled task '$taskName': every 15 minutes, runs wscript.exe //B //Nologo `"$vbs`"" -ForegroundColor Green
exit 0
