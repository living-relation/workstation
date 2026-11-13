# One lock per PC so only one agent drives Autodesk Fusion, or the harness.design desktop app.
# -Name defaults to fusion. Omitting it keeps Fusion behavior: same files, output and exit codes.
# Fusion lock file: %LOCALAPPDATA%\<StateFolder>\fusion.lock. Log: fusion-lock.log beside it.
# harness.design lock file: harness-design.lock. Log: harness-design-lock.log beside it.
# Rules: agents/projects-AGENTS.md section 5 (Fusion) and section 5b (harness.design).
# Windows PowerShell 5.1, ASCII only.
#
#   fusion-lock.ps1 [-Name fusion|harness-design] status
#   fusion-lock.ps1 [-Name fusion|harness-design] acquire -Holder <name> -Kind claude-code|cursor|remote [-Files a,b] [-StartPinger] [-ParentPid N]
#   fusion-lock.ps1 [-Name fusion|harness-design] checkin -Holder <name> [-Files a,b]
#   fusion-lock.ps1 [-Name fusion|harness-design] release -Holder <name>
#   fusion-lock.ps1 [-Name fusion|harness-design] check   [-StaleMinutes 15]     # stale check; never clears on time alone
#   fusion-lock.ps1 [-Name fusion|harness-design] pinger  -Holder <name> -ParentPid N [-IntervalSec 300]
#
# Exit codes: 0 ok / free, 1 held by someone (status/check), 2 refused (held by another holder),
#             3 stale and needs the owner (check), 4 bad usage.
[CmdletBinding()]
param(
    [Parameter(Position = 0)][ValidateSet('status', 'acquire', 'checkin', 'release', 'check', 'pinger')][string]$Command = 'status',
    [ValidateSet('fusion', 'harness-design')][string]$Name = 'fusion',
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
$LockDir = $WsStateDir
# Default (-Name fusion) keeps the original file names and mutex. harness-design is a second lock.
if ($Name -eq 'harness-design') {
    $LockPath  = Join-Path $LockDir 'harness-design.lock'
    $LogPath   = Join-Path $LockDir 'harness-design-lock.log'
    $MutexName = 'Local\WorkstationHarnessDesignLock'
} else {
    $LockPath  = Join-Path $LockDir 'fusion.lock'
    $LogPath   = Join-Path $LockDir 'fusion-lock.log'
    $MutexName = 'Local\WorkstationFusionLock'
}
$Self = $MyInvocation.MyCommand.Path
# harness document ids are often passed as one comma-separated string ("rBjB, QjYZ").
# Fusion paths are not split (a path may contain a comma). Default -Name fusion is unchanged.
if ($Name -eq 'harness-design' -and $Files) {
    $split = New-Object System.Collections.Generic.List[string]
    foreach ($f in @($Files)) {
        foreach ($part in ([string]$f -split ',')) {
            $part = $part.Trim()
            if ($part) { [void]$split.Add($part) }
        }
    }
    $Files = $split.ToArray()
}

function Now { (Get-Date).ToUniversalTime().ToString('o') }
function Write-Log([string]$Msg) {
    if (-not (Test-Path -LiteralPath $LockDir)) { New-Item -ItemType Directory -Path $LockDir -Force | Out-Null }
    Add-Content -LiteralPath $LogPath -Value ("{0} {1}" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz'), $Msg) -Encoding ASCII
}
# Named mutex around every read-modify-write, so two agents can't both win acquire.
function Invoke-Locked([scriptblock]$Body) {
    $m = New-Object System.Threading.Mutex($false, $MutexName)
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
    # Windows PowerShell has Get-CimInstance. If it is missing, the pid is not treated as our pinger.
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) { return $false }
    $c = Get-CimInstance Win32_Process -Filter "ProcessId=$P" -ErrorAction SilentlyContinue
    if (-not ($c -and $c.CommandLine -like '*fusion-lock.ps1*pinger*')) { return $false }
    # A harness.design pinger is the same script with -Name harness-design. Fusion pinges never pass -Name.
    if ($Name -eq 'harness-design') { return ($c.CommandLine -like '*-Name harness-design*') }
    return ($c.CommandLine -notlike '*-Name harness-design*')
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
# File name without extension, accepting both slash styles. On Windows this matches
# [IO.Path]::GetFileNameWithoutExtension for a normal path such as C:\x\Bracket.f3d.
function Get-FileBase([string]$Path) {
    if (-not $Path) { return '' }
    $leaf = [string]$Path
    $i = [Math]::Max($leaf.LastIndexOf('\'), $leaf.LastIndexOf('/'))
    if ($i -ge 0) { $leaf = $leaf.Substring($i + 1) }
    $dot = $leaf.LastIndexOf('.')
    if ($dot -gt 0) { return $leaf.Substring(0, $dot) }
    return $leaf
}
# A visible harness.design window title counts as an open editor unless it is only the app name.
# Windows title text is not published (macOS lists windows by harness name). Anything else is treated as a document.
function Test-HarnessDocTitle([string]$Title) {
    if ([string]::IsNullOrWhiteSpace($Title)) { return $false }
    $t = $Title.Trim().ToLowerInvariant()
    foreach ($shell in @('harness.design', 'harness.design desktop', 'harness design')) {
        if ($t -eq $shell) { return $false }
    }
    return $true
}
# @{ Known = $true/$false; Titles = string[] }. Known $false means the probe could not tell (ask the owner).
# Test seam: WORKSTATION_HARNESS_FAKE_WINDOWS = JSON title list, 'none' (app not running), or 'unknown'.
function Get-HarnessWindowTitles {
    if ($env:WORKSTATION_HARNESS_FAKE_WINDOWS) {
        $fake = [string]$env:WORKSTATION_HARNESS_FAKE_WINDOWS
        if ($fake -eq 'none') { return @{ Known = $true; Titles = @() } }
        if ($fake -eq 'unknown') { return @{ Known = $false; Titles = @() } }
        try { return @{ Known = $true; Titles = @($fake | ConvertFrom-Json) } } catch { return @{ Known = $false; Titles = @() } }
    }
    $exe = Join-Path $env:LOCALAPPDATA 'Programs\harness-design-desktop\harness.design.exe'
    $procs = @(Get-Process -Name 'harness.design' -ErrorAction SilentlyContinue)
    if (-not $procs -and (Test-Path -LiteralPath $exe)) {
        $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and ($_.Path -ieq $exe) })
    }
    if (-not $procs) { return @{ Known = $true; Titles = @() } }
    $pids = @($procs | ForEach-Object { [int]$_.Id })
    try { return @{ Known = $true; Titles = @(Get-HarnessVisibleTitles $pids) } }
    catch {
        $titles = @($procs | ForEach-Object { [string]$_.MainWindowTitle } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if (-not $titles.Count) { return @{ Known = $false; Titles = @() } }
        return @{ Known = $true; Titles = $titles }
    }
}
function Get-HarnessVisibleTitles([int[]]$ProcIds) {
    if (-not ('WsHarnessWindows' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class WsHarnessWindows {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  public static List<string> Titles(int[] pids) {
    var want = new HashSet<int>();
    if (pids != null) { foreach (int p in pids) want.Add(p); }
    var found = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      uint pid;
      GetWindowThreadProcessId(h, out pid);
      if (!want.Contains((int)pid) || !IsWindowVisible(h)) return true;
      var sb = new StringBuilder(512);
      GetWindowText(h, sb, sb.Capacity);
      found.Add(sb.ToString());
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
'@
    }
    return @([WsHarnessWindows]::Titles($ProcIds))
}
function Get-HarnessStaleReason {
    $info = Get-HarnessWindowTitles
    if (-not $info.Known) { return 'cannot read harness.design windows, cannot confirm no editor is open' }
    $busy = @($info.Titles | Where-Object { Test-HarnessDocTitle $_ })
    if ($busy.Count) { return ("harness.design editor open: " + (($busy | Select-Object -First 3) -join '; ') + " (any window title other than the app name counts as an editor; Windows title text was not confirmed)") }
    return $null
}

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
                    # Fusion (the default) keeps this argument string unchanged. harness-design adds -Name.
                    if ($Name -eq 'fusion') { $a = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Self`" pinger -Holder `"$Holder`" -ParentPid $pp -IntervalSec $IntervalSec" }
                    else { $a = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Self`" pinger -Name $Name -Holder `"$Holder`" -ParentPid $pp -IntervalSec $IntervalSec" }
                    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $a -WindowStyle Hidden -PassThru
                    Invoke-Locked { $L = Read-Lock; if ($L -and $L -ne 'corrupt' -and $L.holder -eq $Holder) { $L.pinger_pid = $p.Id; $L.parent_pid = $pp; Write-Lock $L } }
                    Write-Log "PINGER $Holder pid=$($p.Id) parent=$pp"
                }
            }
        }
        if ($Name -eq 'fusion') { & $Self status -Json:$Json; exit 0 }
        & $Self status -Name $Name -Json:$Json; exit 0
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
        # Stale by time. Time alone never clears it.
        $why = $null
        if ($Name -eq 'harness-design') {
            # Cloud autosave: unsaved work is not visible. Clear only when no editor window is open.
            $why = Get-HarnessStaleReason
        } else {
            # Fusion: look at open documents. This branch is the original check.
            $docs = Get-FusionDocs
            if ($null -eq $docs) { $why = 'Fusion add-in not reachable, cannot confirm nothing is open' }
            else {
                $dirty = @($docs | Where-Object { $_.modified })
                $open = @($docs | Where-Object { $n = $_.name; @($L.files) | Where-Object { $_ -and ($n -like "*$(Get-FileBase $_)*") } })
                if ($dirty.Count) { $why = "unsaved Fusion document(s): $(($dirty | ForEach-Object { $_.name }) -join '; ')" }
                elseif ($open.Count) { $why = "holder's file(s) still open: $(($open | ForEach-Object { $_.name }) -join '; ')" }
            }
        }
        if ($why) {
            Write-Log "STALE-FLAG $($L.holder) age=${age}m: $why"
            Out-Result ([ordered]@{ state = 'stale-needs-owner'; holder = $L.holder; minutes_since_checkin = $age; reason = $why; next = 'ask the owner before clearing' }) 3
        }
        $cleared = Invoke-Locked { $C = Read-Lock; if ($C -and $C -ne 'corrupt' -and $C.holder -eq $L.holder -and $C.last_checkin -eq $L.last_checkin) { Remove-Item -LiteralPath $LockPath -Force; return $true }; return $false }
        if ($cleared) {
            if (Test-Pinger ([int]$L.pinger_pid)) { Stop-Process -Id ([int]$L.pinger_pid) -Force -ErrorAction SilentlyContinue }
            if ($Name -eq 'harness-design') { Write-Log "CLEAR $($L.holder) age=${age}m (no harness.design editor open)" }
            else { Write-Log "CLEAR $($L.holder) age=${age}m (no holder files open, nothing unsaved)" }
            Out-Result ([ordered]@{ state = 'cleared'; holder = $L.holder; minutes_since_checkin = $age }) 0
        }
        Out-Result ([ordered]@{ state = 'held'; holder = $L.holder; note = 'lock changed during check' }) 1
    }
}
