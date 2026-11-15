# Shared rules for the Desktop Commander phone remote. Dot-source only.
# One remote per PC. It serves every chat and project. Manual start only.
# Windows PowerShell 5.1, ASCII only.
# A copy is healthy when its parent process is alive AND its console is alive.
# The copy we keep is the newest healthy one. Every other copy is a leftover
# (a duplicate, or a stale copy whose parent or console is gone).

function Get-TrackedProcesses {
    if ($env:WORKSTATION_FAKE_PROCS) {
        if ($env:WORKSTATION_FAKE_PROCS -eq 'none') { return @() }
        try { return @($env:WORKSTATION_FAKE_PROCS | ConvertFrom-Json) } catch { return @() }
    }
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) { return @() }
    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
}

function Test-DcRemoteCommand([string]$Cmd) {
    if (-not $Cmd) { return $false }
    # The launcher, status, and orphan tools mention the script names. They are not the remote.
    if ($Cmd -match 'start-dc-remote|stop-dc-remote|dc-remote-status|dc-remote-lib|kill-orphans') { return $false }
    if ($Cmd -notmatch 'desktop-commander') { return $false }
    # The Claude plugin's MCP server has no remote argument. Leave it alone.
    return [bool]($Cmd -match '(^|[\s''"=])remote([\s''"]|$)')
}

function Get-ProcStartTime($Proc) {
    $raw = $null
    foreach ($name in @('CreationDate', 'StartTime')) {
        if ($Proc.PSObject.Properties.Name -contains $name -and $Proc.$name) { $raw = $Proc.$name; break }
    }
    if (-not $raw) { return [datetime]::MinValue }
    try { return [datetime]$raw } catch { return [datetime]::MinValue }
}

function Test-ParentAlive($Proc, $Procs) {
    $pp = 0
    try { $pp = [int]$Proc.ParentProcessId } catch { return $false }
    if ($pp -le 0) { return $false }
    return [bool]@($Procs | Where-Object { [int]$_.ProcessId -eq $pp }).Count
}

function Test-ConsoleAlive($Proc, $Procs) {
    if ($Proc.PSObject.Properties.Name -contains 'HasConsole') { return [bool]$Proc.HasConsole }
    $id = [int]$Proc.ProcessId
    foreach ($p in @($Procs)) {
        if ([int]$p.ParentProcessId -eq $id -and "$($p.Name)" -match '^(conhost|OpenConsole)(\.exe)?$') { return $true }
    }
    $terminal = '^(conhost|OpenConsole|WindowsTerminal|wt|cmd|powershell|pwsh|claude|Claude)(\.exe)?$'
    $cur = $Proc
    for ($i = 0; $i -lt 8; $i++) {
        $pp = 0
        try { $pp = [int]$cur.ParentProcessId } catch { return $false }
        if ($pp -le 0 -or $pp -eq $id) { return $false }
        $parent = @($Procs | Where-Object { [int]$_.ProcessId -eq $pp }) | Select-Object -First 1
        if (-not $parent) { return $false }
        if ("$($parent.Name)" -match $terminal) { return $true }
        $cur = $parent
    }
    return $false
}

function Get-DcRemoteRows {
    param($Procs)
    if ($null -eq $Procs) { $Procs = @(Get-TrackedProcesses) }
    $raw = @($Procs | Where-Object { Test-DcRemoteCommand "$($_.CommandLine)" })
    $ordered = @($raw | Sort-Object @{ Expression = { Get-ProcStartTime $_ } }, @{ Expression = { [int]$_.ProcessId } })
    $newestId = 0
    if ($ordered.Count) { $newestId = [int]$ordered[-1].ProcessId }
    $rows = @()
    foreach ($p in $ordered) {
        $parentOk = Test-ParentAlive $p $Procs
        $consoleOk = Test-ConsoleAlive $p $Procs
        $healthy = $parentOk -and $consoleOk
        $rows += [pscustomobject]@{
            Pid          = [int]$p.ProcessId
            Name         = "$($p.Name)"
            CommandLine  = "$($p.CommandLine)"
            StartTime    = Get-ProcStartTime $p
            ParentAlive  = [bool]$parentOk
            ConsoleAlive = [bool]$consoleOk
            Healthy      = [bool]$healthy
            Newest       = ([int]$p.ProcessId -eq $newestId)
        }
    }
    $keepId = 0
    $healthyRows = @($rows | Where-Object { $_.Healthy })
    if ($healthyRows.Count) { $keepId = [int]$healthyRows[-1].Pid }
    foreach ($r in $rows) {
        $verdict = 'stale'
        if ($keepId -and $r.Pid -eq $keepId) { $verdict = 'online' }
        elseif ($r.Healthy) { $verdict = 'duplicate' }
        $r | Add-Member -NotePropertyName Keep -NotePropertyValue ($verdict -eq 'online') -Force
        $r | Add-Member -NotePropertyName Verdict -NotePropertyValue $verdict -Force
    }
    return @($rows)
}

function Get-DcRemoteKeep($Rows) {
    $hit = @($Rows | Where-Object { $_.Keep }) | Select-Object -First 1
    return $hit
}

# Leftovers Start will stop: every copy except the one healthy newest copy.
function Get-DcRemoteStopList($Rows) {
    return @($Rows | Where-Object { -not $_.Keep })
}

function Stop-TrackedPid([int]$ProcId) {
    if ($ProcId -le 0) { return $false }
    if ($env:WORKSTATION_FAKE_PROCS) { return $false }
    if (Get-Command taskkill.exe -ErrorAction SilentlyContinue) {
        & taskkill.exe /T /F /PID $ProcId 2>&1 | Out-Null
    }
    try { Stop-Process -Id $ProcId -Force -ErrorAction Stop; return $true } catch { return -not (Get-Process -Id $ProcId -ErrorAction SilentlyContinue) }
}
