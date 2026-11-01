#Requires -Version 5.1
# Retire the old Cursor worker (removed 2026-10-31; Cursor's built-in Remote Control replaces it).
# Stops ONLY what the old Start Cursor workers / Phone access toggle started: the run-worker.ps1 supervisor tree,
# its hidden wscript launcher and the `agent worker` it ran. Deletes the old stop flag the toolkit wrote.
# The Cursor app, Cursor's own Remote Control worker and every Claude session are never touched.
# Run by install.ps1. -WhatIf only lists what it would stop. Prints one line per action:
#   STOPPED|<what>  WOULD|<what>  OK|<what>  WARN|<what>
param([switch]$WhatIf)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'workstation-common.ps1')

$procs = Get-ProcSnapshot
$sup = @(Get-SupervisorProcs $procs)
$supIds = @($sup | ForEach-Object { $_.ProcessId })
$agents = @(Get-AgentWorkerProcs $procs $supIds)
$launchers = @(Get-SupervisorLaunchers $procs)
if (-not ($sup -or $agents -or $launchers)) { Write-Output 'OK|old Cursor worker not running' }
elseif ($WhatIf) {
    Write-Output ("WOULD|stop the old Cursor worker (pid " + (Format-Pids (@($sup) + @($agents) + @($launchers))) + ')')
} else {
    foreach ($s in $sup) { & taskkill.exe /T /F /PID $s.ProcessId *> $null }
    Start-Sleep -Milliseconds 500
    foreach ($p in @($agents) + @($launchers)) {
        if ($p -and (Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue)) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    }
    Start-Sleep -Milliseconds 500
    $after = Get-ProcSnapshot
    $left = @(Get-SupervisorProcs $after) + @(Get-AgentWorkerProcs $after $supIds) + @(Get-SupervisorLaunchers $after)
    if ($left) { Write-Output ("WARN|old Cursor worker still running (pid " + (Format-Pids $left) + '); stop it in Task Manager') }
    else { Write-Output ("STOPPED|old Cursor worker (pid " + (Format-Pids (@($sup) + @($agents) + @($launchers))) + ')') }
}

# The stop flag only the old Stop Cursor workers wrote. Its logs folder ($RetiredWorkerRunDir) is kept.
$flag = Join-Path $WsStateDir 'workers-stopped.flag'
if (Test-Path -LiteralPath $flag) {
    if ($WhatIf) { Write-Output "WOULD|delete the old worker stop flag $flag" }
    else { Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue; Write-Output "STOPPED|deleted the old worker stop flag $flag" }
}
exit 0
