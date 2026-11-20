# harness.design lock: one lock per PC so only one agent drives the harness.design desktop app.
# -Name defaults to fusion. That name does not take a lock.
# Fusion work uses Autodesk's official, Autodesk-hosted MCP servers (nothing to install): Fusion Compute MCP `https://developer.api.autodesk.com/da/v3/mcp/fusion` (preferred, headless cloud Fusion, so local Fusion isn't interrupted); Fusion Data MCP `https://developer.api.autodesk.com/fusion/mcp`; Fusion Desktop MCP is built into Fusion (Preferences > General > API, local `http://127.0.0.1:27182/mcp`). Docs: https://help.autodesk.com/view/ADSKMCP/ENU/.
# harness.design lock file: %LOCALAPPDATA%\<StateFolder>\harness-design.lock. Log: harness-design-lock.log beside it.
# Rule: agents/projects-AGENTS.md section 5b.
# Windows PowerShell 5.1, ASCII only.
#
#   fusion-lock.ps1 -Name harness-design status
#   fusion-lock.ps1 -Name harness-design acquire -Holder <name> -Kind claude-code|cursor|remote [-Repo <repo path>] [-Files a,b] [-StartPinger] [-ParentPid N]
# -Repo is recorded and shown by status. It does not decide who is blocked. One lock per PC still blocks every other session.
#   fusion-lock.ps1 -Name harness-design checkin -Holder <name> [-Files a,b]
#   fusion-lock.ps1 -Name harness-design release -Holder <name>
#   fusion-lock.ps1 -Name harness-design check   [-StaleMinutes 15]     # stale check; never clears on time alone
#   fusion-lock.ps1 -Name harness-design pinger  -Holder <name> -ParentPid N [-IntervalSec 300]
#
# Exit codes: 0 ok / free, 1 held by someone (status/check), 2 refused (held by another holder),
#             3 stale and needs the owner (check), 4 bad usage.
[CmdletBinding()]
param(
    [Parameter(Position = 0)][ValidateSet('status', 'acquire', 'checkin', 'release', 'check', 'pinger')][string]$Command = 'status',
    [ValidateSet('fusion', 'harness-design')][string]$Name = 'fusion',
    [string]$Holder,
    [ValidateSet('claude-code', 'cursor', 'remote')][string]$Kind = 'remote',
    [string]$Repo = '',
    [string[]]$Files = @(),
    [switch]$StartPinger,
    [int]$ParentPid = 0,
    [int]$IntervalSec = 300,
    [int]$StaleMinutes = 15,
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
if ($Name -eq 'fusion') {
    Write-Host 'Fusion work uses Autodesk''s official, Autodesk-hosted MCP servers (nothing to install): Fusion Compute MCP `https://developer.api.autodesk.com/da/v3/mcp/fusion` (preferred, headless cloud Fusion, so local Fusion isn''t interrupted); Fusion Data MCP `https://developer.api.autodesk.com/fusion/mcp`; Fusion Desktop MCP is built into Fusion (Preferences > General > API, local `http://127.0.0.1:27182/mcp`). Docs: https://help.autodesk.com/view/ADSKMCP/ENU/.'
    exit 0
}
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'paths.ps1')
$LockDir = $WsStateDir
$LockPath  = Join-Path $LockDir 'harness-design.lock'
$LogPath   = Join-Path $LockDir 'harness-design-lock.log'
$MutexName = 'Local\WorkstationHarnessDesignLock'
$Self = $MyInvocation.MyCommand.Path
# harness document ids are often passed as one comma-separated string ("rBjB, QjYZ").
if ($Files) {
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
    return ($c.CommandLine -like '*-Name harness-design*')
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
function Need-Holder { if (-not $Holder) { Write-Host 'ERROR: -Holder <name> is required.'; exit 4 } }
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
        $repoShown = ''
        if ($L.PSObject.Properties['repo'] -and $null -ne $L.repo) { $repoShown = [string]$L.repo }
        Out-Result ([ordered]@{ state = 'held'; holder = $L.holder; kind = $L.kind; repo = $repoShown; started = $L.started; last_checkin = $L.last_checkin
            minutes_since_checkin = (Get-AgeMinutes $L); files = @($L.files); pinger_pid = $L.pinger_pid; pinger_alive = (Test-Pinger ([int]$L.pinger_pid)) }) 1
    }
    'acquire' {
        Need-Holder
        $out = Invoke-Locked {
            $L = Read-Lock
            if ($L -eq 'corrupt') { return @{ ok = $false; why = 'lock file is unreadable; ask the owner' } }
            # -Repo is informational only. A different repo does not take the lock from another holder.
            if ($L -and $L.holder -ne $Holder) { return @{ ok = $false; why = "held by $($L.holder) ($($L.kind)), last check-in $($L.last_checkin)" } }
            $repoValue = ''
            if ($Repo) { $repoValue = $Repo }
            elseif ($L -and $L.PSObject.Properties['repo'] -and $null -ne $L.repo) { $repoValue = [string]$L.repo }
            $new = [ordered]@{ holder = $Holder; kind = $Kind; repo = $repoValue; started = $(if ($L) { $L.started } else { Now }); last_checkin = (Now)
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
                    $onWindows = ($env:OS -eq 'Windows_NT')
                    $win = $(if ($onWindows) { '-WindowStyle Hidden ' } else { '' })
                    $a = "-NoProfile -ExecutionPolicy Bypass ${win}-File `"$Self`" pinger -Name $Name -Holder `"$Holder`" -ParentPid $pp -IntervalSec $IntervalSec"
                    $hostExe = 'powershell.exe'
                    if (-not $onWindows) { $hostExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName }
                    if ($onWindows) { $p = Start-Process -FilePath $hostExe -ArgumentList $a -WindowStyle Hidden -PassThru }
                    else {
                        # Detach so this PowerShell can exit without waiting for the pinger.
                        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Self, 'pinger', '-Name', $Name, '-Holder', $Holder, '-ParentPid', "$pp", '-IntervalSec', "$IntervalSec")
                        $q = ($argList | ForEach-Object { "'" + ($_ -replace "'", "'\''") + "'" }) -join ' '
                        $sh = "setsid -- $hostExe $q < /dev/null > /dev/null 2>&1 & echo `$!"
                        $psi = New-Object System.Diagnostics.ProcessStartInfo
                        $psi.FileName = 'bash'
                        $psi.UseShellExecute = $false
                        $psi.RedirectStandardOutput = $true
                        [void]$psi.ArgumentList.Add('-c')
                        [void]$psi.ArgumentList.Add($sh)
                        $bash = [Diagnostics.Process]::Start($psi)
                        $pidText = $bash.StandardOutput.ReadToEnd()
                        $bash.WaitForExit()
                        $p = [pscustomobject]@{ Id = [int]$pidText.Trim() }
                    }
                    Invoke-Locked { $L = Read-Lock; if ($L -and $L -ne 'corrupt' -and $L.holder -eq $Holder) { $L.pinger_pid = $p.Id; $L.parent_pid = $pp; Write-Lock $L } }
                    Write-Log "PINGER $Holder pid=$($p.Id) parent=$pp"
                }
            }
        }
        & $Self status -Name $Name -Json:$Json; exit 0
    }
    'checkin' {
        Need-Holder
        $ok = Invoke-Locked {
            $L = Read-Lock
            if (-not $L -or $L -eq 'corrupt' -or $L.holder -ne $Holder) { return $false }
            $L.last_checkin = Now
            if ($Files.Count) { $L.files = @($Files) }
            if ($Repo) {
                if ($L.PSObject.Properties['repo']) { $L.repo = $Repo } else { $L | Add-Member -NotePropertyName repo -NotePropertyValue $Repo }
            }
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
        # Cloud autosave: unsaved work is not visible. Clear only when no editor window is open.
        $why = Get-HarnessStaleReason
        if ($why) {
            Write-Log "STALE-FLAG $($L.holder) age=${age}m: $why"
            Out-Result ([ordered]@{ state = 'stale-needs-owner'; holder = $L.holder; minutes_since_checkin = $age; reason = $why; next = 'ask the owner before clearing' }) 3
        }
        $cleared = Invoke-Locked { $C = Read-Lock; if ($C -and $C -ne 'corrupt' -and $C.holder -eq $L.holder -and $C.last_checkin -eq $L.last_checkin) { Remove-Item -LiteralPath $LockPath -Force; return $true }; return $false }
        if ($cleared) {
            if (Test-Pinger ([int]$L.pinger_pid)) { Stop-Process -Id ([int]$L.pinger_pid) -Force -ErrorAction SilentlyContinue }
            Write-Log "CLEAR $($L.holder) age=${age}m (no harness.design editor open)"
            Out-Result ([ordered]@{ state = 'cleared'; holder = $L.holder; minutes_since_checkin = $age }) 0
        }
        Out-Result ([ordered]@{ state = 'held'; holder = $L.holder; note = 'lock changed during check' }) 1
    }
}
