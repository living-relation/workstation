# Shared rules for the Desktop Commander phone remote. Dot-source only.
# One remote per PC. It serves every chat and project. Manual start only.
# Windows PowerShell 5.1, ASCII only.
# On Windows one copy is a chain: cmd -> npx node -> cmd -> node remote.
# That chain is one copy. The wrappers are not extra copies.
# A copy is healthy when the remote's parent is alive AND its console is alive.
# Leave a working copy alone. Offer to stop a copy whose terminal is gone,
# or an extra copy when more than one remote is running (keep the newest).
# Stopping uses taskkill /T on that copy's own outer cmd, never on a wrapper
# of the copy we are keeping. Claude's Desktop Commander plugin (no remote
# argument) is not a copy.

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

function Get-DcProcIndex($Procs) {
    $byId = @{}
    $kids = @{}
    foreach ($p in @($Procs)) {
        $id = 0
        try { $id = [int]$p.ProcessId } catch { continue }
        if ($id -le 0) { continue }
        $byId["$id"] = $p
        $pp = 0
        try { $pp = [int]$p.ParentProcessId } catch { $pp = 0 }
        $pk = "$pp"
        if (-not $kids.ContainsKey($pk)) { $kids[$pk] = New-Object System.Collections.Generic.List[string] }
        [void]$kids[$pk].Add("$id")
    }
    return @{ ById = $byId; Kids = $kids }
}

# Descendant process ids (not including StartId). Keys are strings.
function Get-DcDescendantIds([int]$StartId, $Kids) {
    $seen = @{}
    $pending = New-Object System.Collections.Generic.List[string]
    [void]$pending.Add("$StartId")
    $i = 0
    $guard = 0
    while ($i -lt $pending.Count -and $guard -lt 10000) {
        $guard++
        $id = $pending[$i]
        $i++
        if (-not $Kids.ContainsKey($id)) { continue }
        foreach ($c in @($Kids[$id])) {
            $ck = "$c"
            if ($ck -eq "$StartId" -or $seen.ContainsKey($ck)) { continue }
            $seen[$ck] = $true
            [void]$pending.Add($ck)
        }
    }
    return $seen
}

# A candidate with another candidate under it is a wrapper, not its own copy.
function Get-DcLeafProcs($Candidates, $Index) {
    $ids = @($Candidates | ForEach-Object { "$([int]$_.ProcessId)" })
    $leaves = @()
    foreach ($c in @($Candidates)) {
        $id = "$([int]$c.ProcessId)"
        $desc = Get-DcDescendantIds ([int]$id) $Index.Kids
        $child = $false
        foreach ($other in $ids) {
            if ($other -ne $id -and $desc.ContainsKey($other)) { $child = $true; break }
        }
        if (-not $child) { $leaves += $c }
    }
    return @($leaves)
}

# Outer cmd of this copy only. Does not climb into another copy or into Claude.
function Get-DcChainRootId([int]$LeafId, $Index, [string[]]$LeafIds) {
    $root = $LeafId
    $cur = "$LeafId"
    for ($n = 0; $n -lt 8; $n++) {
        $proc = $Index.ById[$cur]
        if (-not $proc) { break }
        $pp = 0
        try { $pp = [int]$proc.ParentProcessId } catch { break }
        if ($pp -le 0 -or "$pp" -eq $cur) { break }
        $parent = $Index.ById["$pp"]
        if (-not $parent) { break }
        $pname = "$($parent.Name)"
        $isCmd = $pname -match '^(cmd|npx)(\.exe)?$'
        $isNode = $pname -match '^node(\.exe)?$'
        if (-not $isCmd -and -not $isNode) { break }
        if ($isNode -and -not (Test-DcRemoteCommand "$($parent.CommandLine)")) { break }
        $desc = Get-DcDescendantIds $pp $Index.Kids
        $foreign = $false
        foreach ($lid in @($LeafIds)) {
            if ($lid -and $lid -ne "$LeafId" -and $desc.ContainsKey($lid)) { $foreign = $true; break }
        }
        if ($foreign) { break }
        $root = $pp
        $cur = "$pp"
    }
    return [int]$root
}

function Get-DcRemoteRows {
    param($Procs)
    if ($null -eq $Procs) { $Procs = @(Get-TrackedProcesses) }
    $index = Get-DcProcIndex $Procs
    $cands = @($Procs | Where-Object { Test-DcRemoteCommand "$($_.CommandLine)" })
    $leaves = @(Get-DcLeafProcs $cands $index)
    $leafIds = @($leaves | ForEach-Object { "$([int]$_.ProcessId)" })
    $ordered = @($leaves | Sort-Object @{ Expression = { Get-ProcStartTime $_ } }, @{ Expression = { [int]$_.ProcessId } })
    $newestId = 0
    if ($ordered.Count) { $newestId = [int]$ordered[-1].ProcessId }
    $rows = @()
    foreach ($p in $ordered) {
        $parentOk = Test-ParentAlive $p $Procs
        $consoleOk = Test-ConsoleAlive $p $Procs
        $healthy = $parentOk -and $consoleOk
        $leafPid = [int]$p.ProcessId
        $rows += [pscustomobject]@{
            Pid          = $leafPid
            StopPid      = (Get-DcChainRootId $leafPid $index $leafIds)
            Name         = "$($p.Name)"
            CommandLine  = "$($p.CommandLine)"
            StartTime    = Get-ProcStartTime $p
            ParentAlive  = [bool]$parentOk
            ConsoleAlive = [bool]$consoleOk
            Healthy      = [bool]$healthy
            Newest       = ($leafPid -eq $newestId)
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

# taskkill /T target: the outer cmd of this copy, or the remote itself when it has no chain.
function Get-DcStopPid($Row) {
    if ($null -eq $Row) { return 0 }
    if ($Row.PSObject.Properties.Name -contains 'StopPid') {
        $n = 0
        try { $n = [int]$Row.StopPid } catch { $n = 0 }
        if ($n -gt 0) { return $n }
    }
    try { return [int]$Row.Pid } catch { return 0 }
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
