#Requires -Version 5.1
# Registers (or replaces) the scheduled task Workstation-Watcher: every 15 minutes, while this user is
# signed in, runs toggles\watcher.py hidden (pythonw). It health-checks the dashboard toggles that are on,
# runs the process check and shows a Windows toast on problems. -Remove unregisters it.
param([switch]$Remove, [int]$Minutes = 15)
$ErrorActionPreference = 'Stop'
$name = 'Workstation-Watcher'
if ($Remove) {
    if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false
        Write-Host "removed task $name"
    } else { Write-Host "task $name was not registered" }
    exit 0
}
. (Join-Path $PSScriptRoot 'python.ps1')
$pyw = Find-Python313 -Windowless
if (-not $pyw) { Write-Host 'Python 3.13 was not found; Workstation-Watcher was NOT registered.' -ForegroundColor Red; exit 1 }
$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction -Execute $pyw -Argument "`"$(Join-Path $PSScriptRoot 'watcher.py')`"" -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes $Minutes)
$logon = New-ScheduledTaskTrigger -AtLogOn -User $me
$logon.Delay = 'PT5M'
$principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Limited
$set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $name -Action $action -Trigger @($trigger, $logon) -Principal $principal -Settings $set `
    -Description 'Workstation dashboard watcher: toggle health checks and process check, toast on problems.' -Force | Out-Null
Write-Host "registered task $name (every $Minutes min, as $me)"
exit 0
