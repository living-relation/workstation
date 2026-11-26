# Leftover-process list shared by Health check and kill-orphans.ps1. Dot-source only.
# ASCII only. Does not stop anything.
# A Cursor worker this tool started is not listed. Stop that with Stop Cursor worker.
# Targets: the old local web server, the old watcher, and a Claude
# remote-control session whose parent process is gone.

function Get-TrackedProcesses {
    if ($env:WORKSTATION_FAKE_PROCS) {
        if ($env:WORKSTATION_FAKE_PROCS -eq 'none') { return @() }
        # Windows PowerShell 5.1 returns a JSON array as one object; the ForEach-Object unrolls it.
        try { $parsed = $env:WORKSTATION_FAKE_PROCS | ConvertFrom-Json; return @($parsed | ForEach-Object { $_ }) } catch { return @() }
    }
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) { return @() }
    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
}

function Test-ParentAlive($Proc, $Procs) {
    $pp = 0
    try { $pp = [int]$Proc.ParentProcessId } catch { return $false }
    if ($pp -le 0) { return $false }
    return [bool]@($Procs | Where-Object { [int]$_.ProcessId -eq $pp }).Count
}

function Stop-TrackedPid([int]$ProcId) {
    if ($ProcId -le 0) { return $false }
    if ($env:WORKSTATION_FAKE_PROCS) { return $false }
    if (Get-Command taskkill.exe -ErrorAction SilentlyContinue) {
        & taskkill.exe /T /F /PID $ProcId 2>&1 | Out-Null
    }
    try { Stop-Process -Id $ProcId -Force -ErrorAction Stop; return $true } catch { return -not (Get-Process -Id $ProcId -ErrorAction SilentlyContinue) }
}

function Test-SkippedProcessName([string]$Name) {
    return [bool]("$Name" -match '^(Cursor|Fusion360|Fusion|harness\.design)(\.exe)?$')
}

function Get-OrphanCandidates {
    param($Procs)
    if ($null -eq $Procs) { $Procs = @(Get-TrackedProcesses) }
    $out = @()
    foreach ($p in @($Procs)) {
        if (Test-SkippedProcessName "$($p.Name)") { continue }
        $cmd = "$($p.CommandLine)"
        if (-not $cmd) { continue }
        if ((Get-Command Test-OurWorkerCommand -ErrorAction SilentlyContinue) -and (Test-OurWorkerCommand $cmd)) { continue }
        $pidN = [int]$p.ProcessId
        if ($cmd -match 'dashboard[\\/]server\.py') {
            $out += [pscustomobject]@{ Pid = $pidN; Name = "$($p.Name)"; CommandLine = $cmd; Kind = 'old-web-server'; Why = 'old local web server' }
            continue
        }
        if ($cmd -match 'toggles[\\/]watcher\.(py|ps1)') {
            $out += [pscustomobject]@{ Pid = $pidN; Name = "$($p.Name)"; CommandLine = $cmd; Kind = 'old-watcher'; Why = 'old watcher' }
            continue
        }
        if ($cmd -match '(^|\s)--remote-control(=|\s|$)' -and -not (Test-ParentAlive $p $Procs)) {
            $out += [pscustomobject]@{ Pid = $pidN; Name = "$($p.Name)"; CommandLine = $cmd; Kind = 'claude-remote'; Why = 'Claude remote-control session whose parent is gone' }
        }
    }
    return @($out)
}

# Health check warnings: every leftover is a warning.
function Get-HealthOrphanWarnings {
    param($Procs)
    return @(Get-OrphanCandidates $Procs)
}
