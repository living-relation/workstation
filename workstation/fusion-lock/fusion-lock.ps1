# Fusion lock: one lock per PC so only one agent drives Autodesk Fusion at a time.
# Lock file: %LOCALAPPDATA%\<StateFolder>\fusion.lock (JSON). Log: fusion-lock.log beside it.
# Rules for agents: agents/projects-AGENTS.md, section "Fusion lock". Windows PowerShell 5.1, ASCII only.
#
#   fusion-lock.ps1 status
#   fusion-lock.ps1 acquire -Holder <name> -Kind claude-code|cursor|remote [-Files a,b] [-StartPinger] [-ParentPid N]
#   fusion-lock.ps1 checkin -Holder <name> [-Files a,b]
#   fusion-lock.ps1 release -Holder <name>
#   fusion-lock.ps1 check   [-StaleMinutes 15]     # stale check; never clears on time alone
#   fusion-lock.ps1 pinger  -Holder <name> -ParentPid N [-IntervalSec 300]   (started by acquire -StartPinger)
#
# Exit codes: 0 ok / free, 1 held by someone (status/check), 2 refused (held by another holder),
#             3 stale and needs the owner (check), 4 bad usage.
[CmdletBinding()]
param(
    [Parameter(Position = 0)][ValidateSet('status', 'acquire', 'checkin', 'release', 'check', 'pinger')][string]$Command = 'status',
    [string]$Holder,
    [ValidateSet('claude-code', 'cursor', 'remote')][string]$Kind = 'remote',
    [string[]]$Files = @(),
    [switch]$StartPinger,
    [int]$ParentPid = 0,
    [int]$IntervalSec = 300,
    [int]$StaleMinutes = 15,
    [string]$FusionUrl = $(if ($env:WORKSTATION_FUSION_MCP_URL) { $env:WORKSTATION_FUSION_MCP_URL } else { 'http://127.0.0.1:8765/mcp' }),
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'paths.ps1')
$LockDir  = $WsStateDir
$LockPath = Join-Path $LockDir 'fusion.lock'
$LogPath  = Join-Path $LockDir 'fusion-lock.log'
$Self     = $MyInvocation.MyCommand.Path

function Now { (Get-Date).ToUniversalTime().ToString('o') }
function Write-Log([string]$Msg) {
    if (-not (Test-Path -LiteralPath $LockDir)) { New-Item -ItemType Directory -Path $LockDir -Force | Out-Null }
    Add-Content -LiteralPath $LogPath -Value ("{0} {1}" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz'), $Msg) -Encoding ASCII
}
# Named mutex around every read-modify-write, so two agents can't both win acquire.
function Invoke-Locked([scriptblock]$Body) {
    $m = New-Object System.Threading.Mutex($false, 'Local\WorkstationFusionLock')
    try {
        try { [void]$m.WaitOne(10000) } catch [System.Threading.AbandonedMutexException] { }
        & $Body
    } finally { try { $m.ReleaseMutex() } catch { }; $m.Dispose() }
}
function Read-Lock {
    if (-not (Test-Path -LiteralPath $LockPath)) { return $null }
    try { return (Get-Content -LiteralPath $LockPath -Raw | ConvertFrom-Json) } catch { return 'corrupt' }
}
function Write-Lock($Obj) {
    if (-not (Test-Path -LiteralPath $LockDir)) { New-Item -ItemType Directory -Path $LockDir -Force | Out-Null }
    $tmp = "$LockPath.tmp"
    Set-Content -LiteralPath $tmp -Value ($Obj | ConvertTo-Json -Depth 4) -Encoding ASCII
    Move-Item -LiteralPath $tmp -Destination $LockPath -Force
}
function Get-AgeMinutes($L) {
    try { return [math]::Round(((Get-Date).ToUniversalTime() - ([datetime]$L.last_checkin).ToUniversalTime()).TotalMinutes, 1) } catch { return 99999 }
}
function Test-Pid([int]$P) { if ($P -le 0) { return $false }; return [bool](Get-Process -Id $P -ErrorAction SilentlyContinue) }
function Test-Pinger([int]$P) {
    if (-not (Test-Pid $P)) { return $false }
    $c = Get-CimInstance Win32_Process -Filter "ProcessId=$P" -ErrorAction SilentlyContinue
    return ($c -and $c.CommandLine -like '*fusion-lock.ps1*pinger*')
}
# Session process to tie the pinger to: first ancestor named claude / Cursor / Code (else the caller must pass -ParentPid).
function Find-SessionPid {
    $p = $PID
    for ($i = 0; $i -lt 15 -and $p -gt 0; $i++) {
        $c = Get-CimInstance Win32_Process -Filter "ProcessId=$p" -ErrorAction SilentlyContinue
        if (-not $c) { break }
        if ($i -gt 0 -and $c.Name -match '^(claude|Cursor|Code)(\.exe)?$') { return [int]$c.ProcessId }
        $p = [int]$c.ParentProcessId
    }
    return 0
}
function Out-Result($Obj, [int]$Code) {
    if ($Json) { $Obj | ConvertTo-Json -Depth 5 } else { $Obj.GetEnumerator() | ForEach-Object { '{0}: {1}' -f $_.Key, (($_.Value | ForEach-Object { "$_" }) -join ', ') } }
    exit $Code
}
# Open Fusion documents via the AutodeskFusionMCP add-in (read-only). Returns $null if Fusion/add-in can't be reached.
# Test seam: WORKSTATION_FUSION_FAKE_DOCS = JSON list of {name, modified}; 'none' = Fusion not running, 'unreachable' = add-in down.
function Get-FusionDocs {
    if ($env:WORKSTATION_FUSION_FAKE_DOCS) {
        if ($env:WORKSTATION_FUSION_FAKE_DOCS -eq 'none') { return @() }
        if ($env:WORKSTATION_FUSION_FAKE_DOCS -eq 'unreachable') { return $null }
        return @($env:WORKSTATION_FUSION_FAKE_DOCS | ConvertFrom-Json)
    }
    if (-not (Get-Process -Name 'Fusion360' -ErrorAction SilentlyContinue)) { return @() }   # not running: nothing unsaved
    $code = "import adsk.core, json`napp = adsk.core.Application.get()`nprint(json.dumps([{'name': d.name, 'modified': bool(d.isModified)} for d in app.documents]))"
    $body = @{ jsonrpc = '2.0'; id = 1; method = 'tools/call'; params = @{ name = 'execute_python'; arguments = @{ code = $code; persistent = $false } } } | ConvertTo-Json -Depth 6
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri $FusionUrl -Method Post -Body $body -ContentType 'application/json' -Headers @{ Accept = 'application/json, text/event-stream' } -TimeoutSec 30
        $line = ($r.Content -split "`n" | Where-Object { $_ -like 'data:*' } | Select-Object -First 1)
        if (-not $line) { $line = $r.Content } else { $line = $line.Substring(5) }
        $res = $line | ConvertFrom-Json
        if ($res.result.isError) { return $null }
        $inner = $res.result.content[0].text | ConvertFrom-Json
        if (-not $inner.success) { return $null }
        return @($inner.stdout.Trim() | ConvertFrom-Json)
    } catch { return $null }
}
function Need-Holder { if (-not $Holder) { Write-Host 'ERROR: -Holder <name> is required.'; exit 4 } }

switch ($Command) {
    'status' {
        $L = Read-Lock
        if (-not $L) { Out-Result ([ordered]@{ state = 'free'; lock = $LockPath }) 0 }
        if ($L -eq 'corrupt') { Out-Result ([ordered]@{ state = 'corrupt'; lock = $LockPath; next = 'ask the owner' }) 1 }
        Out-Result ([ordered]@{ state = 'held'; holder = $L.holder; kind = $L.kind; started = $L.started; last_checkin = $L.last_checkin
            minutes_since_checkin = (Get-AgeMinutes $L); files = @($L.files); pinger_pid = $L.pinger_pid; pinger_alive = (Test-Pinger ([int]$L.pinger_pid)) }) 1
    }
    'acquire' {
        Need-Holder
        $out = Invoke-Locked {
            $L = Read-Lock
            if ($L -eq 'corrupt') { return @{ ok = $false; why = 'lock file is unreadable; ask the owner' } }
            if ($L -and $L.holder -ne $Holder) { return @{ ok = $false; why = "held by $($L.holder) ($($L.kind)), last check-in $($L.last_checkin)" } }
            $new = [ordered]@{ holder = $Holder; kind = $Kind; started = $(if ($L) { $L.started } else { Now }); last_checkin = (Now)
                files = @($(if ($Files.Count) { $Files } elseif ($L) { @($L.files) } else { @() })); pinger_pid = $(if ($L) { [int]$L.pinger_pid } else { 0 }); parent_pid = 0; computer = $env:COMPUTERNAME }
            Write-Lock $new
            return @{ ok = $true; renewed = [bool]$L; lock = $new }
        }
        if (-not $out.ok) { Write-Host "REFUSED: $($out.why)"; exit 2 }
        if (-not $out.renewed) { Write-Log "ACQUIRE $Holder ($Kind) files=[$($out.lock.files -join '; ')]" }
        if ($StartPinger -and -not (Test-Pinger ([int]$out.lock.pinger_pid))) {
            if ($Kind -eq 'remote') { Write-Host 'NOTE: remote agents check in themselves; no pinger started.' }
            else {
                $pp = $(if ($ParentPid -gt 0) { $ParentPid } else { Find-SessionPid })
                if ($pp -le 0) { Write-Host 'WARN: no session process found; pass -ParentPid <pid>. No pinger started.' }
                else {
                    $a = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Self`" pinger -Holder `"$Holder`" -ParentPid $pp -IntervalSec $IntervalSec"
                    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $a -WindowStyle Hidden -PassThru
                    Invoke-Locked { $L = Read-Lock; if ($L -and $L -ne 'corrupt' -and $L.holder -eq $Holder) { $L.pinger_pid = $p.Id; $L.parent_pid = $pp; Write-Lock $L } }
                    Write-Log "PINGER $Holder pid=$($p.Id) parent=$pp"
                }
            }
        }
        & $Self status -Json:$Json; exit 0
    }
    'checkin' {
        Need-Holder
        $ok = Invoke-Locked {
            $L = Read-Lock
            if (-not $L -or $L -eq 'corrupt' -or $L.holder -ne $Holder) { return $false }
            $L.last_checkin = Now
            if ($Files.Count) { $L.files = @($Files) }
            Write-Lock $L; return $true
        }
        if (-not $ok) { Write-Host "REFUSED: $Holder does not hold the lock (run status)."; exit 2 }
        Write-Host "checked in: $Holder"; exit 0
    }
    'release' {
        Need-Holder
        $L = Invoke-Locked {
            $L = Read-Lock
            if (-not $L -or $L -eq 'corrupt' -or $L.holder -ne $Holder) { return $null }
            Remove-Item -LiteralPath $LockPath -Force; return $L
        }
        if (-not $L) { Write-Host "REFUSED: $Holder does not hold the lock (run status)."; exit 2 }
        if (Test-Pinger ([int]$L.pinger_pid)) { Stop-Process -Id ([int]$L.pinger_pid) -Force -ErrorAction SilentlyContinue }
        Write-Log "RELEASE $Holder"; Write-Host "released: $Holder"; exit 0
    }
    'pinger' {
        Need-Holder
        while ($true) {
            Start-Sleep -Seconds $IntervalSec
            if (-not (Test-Pid $ParentPid)) { Write-Log "PINGER-EXIT $Holder (session pid $ParentPid ended; lock left for check)"; exit 0 }
            $held = Invoke-Locked {
                $L = Read-Lock
                if (-not $L -or $L -eq 'corrupt' -or $L.holder -ne $Holder) { return $false }
                $L.last_checkin = Now; Write-Lock $L; return $true
            }
            if (-not $held) { exit 0 }
        }
    }
    'check' {
        $L = Read-Lock
        if (-not $L) { Out-Result ([ordered]@{ state = 'free' }) 0 }
        if ($L -eq 'corrupt') { Out-Result ([ordered]@{ state = 'corrupt'; next = 'ask the owner' }) 3 }
        $age = Get-AgeMinutes $L
        if ($age -lt $StaleMinutes) { Out-Result ([ordered]@{ state = 'held'; holder = $L.holder; minutes_since_checkin = $age }) 1 }
        # Stale by time. Time alone never clears it: look at Fusion.
        $docs = Get-FusionDocs
        $why = $null
        if ($null -eq $docs) { $why = 'Fusion add-in not reachable, cannot confirm nothing is open' }
        else {
            $dirty = @($docs | Where-Object { $_.modified })
            $open = @($docs | Where-Object { $n = $_.name; @($L.files) | Where-Object { $_ -and ($n -like "*$([IO.Path]::GetFileNameWithoutExtension($_))*") } })
            if ($dirty.Count) { $why = "unsaved Fusion document(s): $(($dirty | ForEach-Object { $_.name }) -join '; ')" }
            elseif ($open.Count) { $why = "holder's file(s) still open: $(($open | ForEach-Object { $_.name }) -join '; ')" }
        }
        if ($why) {
            Write-Log "STALE-FLAG $($L.holder) age=${age}m: $why"
            Out-Result ([ordered]@{ state = 'stale-needs-owner'; holder = $L.holder; minutes_since_checkin = $age; reason = $why; next = 'ask the owner before clearing' }) 3
        }
        $cleared = Invoke-Locked { $C = Read-Lock; if ($C -and $C -ne 'corrupt' -and $C.holder -eq $L.holder -and $C.last_checkin -eq $L.last_checkin) { Remove-Item -LiteralPath $LockPath -Force; return $true }; return $false }
        if ($cleared) {
            if (Test-Pinger ([int]$L.pinger_pid)) { Stop-Process -Id ([int]$L.pinger_pid) -Force -ErrorAction SilentlyContinue }
            Write-Log "CLEAR $($L.holder) age=${age}m (no holder files open, nothing unsaved)"
            Out-Result ([ordered]@{ state = 'cleared'; holder = $L.holder; minutes_since_checkin = $age }) 0
        }
        Out-Result ([ordered]@{ state = 'held'; holder = $L.holder; note = 'lock changed during check' }) 1
    }
}
