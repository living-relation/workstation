# Leftover-process list shared by Health check and kill-orphans.ps1. Dot-source only.
# ASCII only. Does not stop anything.
# Desktop Commander remote leftovers come from dc-remote-lib.ps1.
# One cmd -> npx node -> cmd -> node chain is one copy. A working copy is never
# listed. A copy whose terminal is gone is listed. When more than one copy is
# running, the newest healthy copy stays and the extras are listed.
# Claude's Desktop Commander plugin is not listed.
# A Cursor worker this tool started is not listed. Stop that with Stop Cursor worker.
# Other targets: the old local web server, the old watcher, and a Claude
# remote-control session whose parent process is gone.

$__dcLib = Join-Path (Split-Path -Parent $PSScriptRoot) 'desktop-commander-remote\dc-remote-lib.ps1'
if (-not (Get-Command Get-DcRemoteRows -ErrorAction SilentlyContinue)) { . $__dcLib }

function Test-SkippedProcessName([string]$Name) {
    return [bool]("$Name" -match '^(Cursor|Fusion360|Fusion|harness\.design)(\.exe)?$')
}

function Get-OrphanCandidates {
    param($Procs)
    if ($null -eq $Procs) { $Procs = @(Get-TrackedProcesses) }
    $out = @()
    $rows = @(Get-DcRemoteRows $Procs)
    $newestId = 0
    $newest = @($rows | Where-Object { $_.Newest }) | Select-Object -First 1
    if ($newest) { $newestId = [int]$newest.Pid }
    foreach ($r in @(Get-DcRemoteStopList $rows)) {
        $why = "Desktop Commander remote $($r.Verdict)"
        if (-not $r.ParentAlive) { $why += ', parent gone' }
        if (-not $r.ConsoleAlive) { $why += ', console gone' }
        $stopAt = Get-DcStopPid $r
        $out += [pscustomobject]@{
            Pid = [int]$r.Pid; StopPid = [int]$stopAt; Name = $r.Name; CommandLine = $r.CommandLine
            Kind = 'dc-remote'; Why = $why; IsNewest = ($r.Pid -eq $newestId)
        }
    }
    foreach ($p in @($Procs)) {
        if (Test-SkippedProcessName "$($p.Name)") { continue }
        $cmd = "$($p.CommandLine)"
        if (-not $cmd) { continue }
        if ((Get-Command Test-OurWorkerCommand -ErrorAction SilentlyContinue) -and (Test-OurWorkerCommand $cmd)) { continue }
        $pidN = [int]$p.ProcessId
        if ($cmd -match 'dashboard[\\/]server\.py') {
            $out += [pscustomobject]@{ Pid = $pidN; Name = "$($p.Name)"; CommandLine = $cmd; Kind = 'old-web-server'; Why = 'old local web server'; IsNewest = $false }
            continue
        }
        if ($cmd -match 'toggles[\\/]watcher\.(py|ps1)') {
            $out += [pscustomobject]@{ Pid = $pidN; Name = "$($p.Name)"; CommandLine = $cmd; Kind = 'old-watcher'; Why = 'old watcher'; IsNewest = $false }
            continue
        }
        if ($cmd -match '(^|\s)--remote-control(=|\s|$)' -and -not (Test-ParentAlive $p $Procs)) {
            $out += [pscustomobject]@{ Pid = $pidN; Name = "$($p.Name)"; CommandLine = $cmd; Kind = 'claude-remote'; Why = 'Claude remote-control session whose parent is gone'; IsNewest = $false }
        }
    }
    return @($out)
}

# Health check warnings. A single Desktop Commander remote is never a warning.
function Get-HealthOrphanWarnings {
    param($Procs)
    if ($null -eq $Procs) { $Procs = @(Get-TrackedProcesses) }
    $rows = @(Get-DcRemoteRows $Procs)
    $cands = @(Get-OrphanCandidates $Procs)
    if ($rows.Count -eq 1) { return @($cands | Where-Object { $_.Kind -ne 'dc-remote' }) }
    return @($cands | Where-Object { $_.Kind -ne 'dc-remote' -or -not $_.IsNewest })
}
