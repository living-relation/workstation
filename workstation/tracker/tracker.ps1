<#
.SYNOPSIS
  Update the live task tracker (%LOCALAPPDATA%\Workstation\tracker\tracker.json). Writes are atomic.
.EXAMPLE
  tracker.ps1 -Set -Path plan.json          # replace everything (or pipe JSON on stdin)
  tracker.ps1 -Add -Id t1 -Title 'Fix X' -Group 'Repo' [-Status pending] [-Owner 'Helper Bot'] [-AgentId <id>]
  tracker.ps1 -Update -Id t1 -Status done -Note 'merged #12'
  tracker.ps1 -ListTitle 'Today'             # set the list title only
  tracker.ps1 -AddSub -Job t1 -Id s1 -Title 'Step one' [-Status pending] [-Note ..]
  tracker.ps1 -UpdateSub -Job t1 -Id s1 -Status done [-Note ..]
  tracker.ps1 -Clear
  tracker.ps1 -Show                          # open the window (or refresh + bring to front); combine with any of the above
#>
[CmdletBinding()]
param(
  [switch]$Set, [switch]$Update, [switch]$Add, [switch]$Clear, [switch]$Remove, [switch]$Show, [switch]$AddSub, [switch]$UpdateSub, [string]$Job,
  [string]$Path, [string]$Id, [string]$Title, [string]$Group,
  [ValidateSet('pending','in_progress','done','blocked')][string]$Status,
  [string]$Note, [string]$Owner, [string]$AgentId, [string]$ListTitle
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tracker-common.ps1')
Initialize-TrackerDir
$now = (Get-Date).ToString('o')

function Get-Data {
  $d = Read-JsonFile $TrackerFile
  if (-not $d) { $d = [pscustomobject]@{ title = 'Tasks'; updated = $now; tasks = @() } }
  $d.tasks = @($d.tasks)
  $d
}

$bp = $PSBoundParameters   # the locked block below is a scriptblock with its own (empty) $PSBoundParameters
$out = Invoke-TrackerLocked {
if ($Set) {
  if ($Path) { $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 }
  elseif ([Console]::IsInputRedirected) {
    # Read stdin with a timeout (Console.In's async read is synchronous in Windows PowerShell, so use the raw stream).
    $in = [Console]::OpenStandardInput(); $ms = New-Object IO.MemoryStream; $buf = New-Object byte[] 65536
    $deadline = [DateTime]::UtcNow.AddSeconds(3)
    while ($true) {
      $rt = $in.ReadAsync($buf, 0, $buf.Length)
      $left = [int][Math]::Max(0, ($deadline - [DateTime]::UtcNow).TotalMilliseconds)
      if (-not $rt.Wait($left)) { throw '-Set did not get all piped input within 3 s; use -Path <file> or pipe JSON.' }
      if ($rt.Result -le 0) { break }; $ms.Write($buf, 0, $rt.Result)
    }
    $raw = (New-Object Text.UTF8Encoding $false).GetString($ms.ToArray()).TrimStart([char]0xFEFF)
  }
  else { throw '-Set needs -Path <file> or JSON piped on stdin.' }
  if (-not $raw -or -not $raw.Trim()) { throw '-Set got empty input.' }
  $d = $raw | ConvertFrom-Json
  if (-not $d.PSObject.Properties['title']) { $d | Add-Member title 'Tasks' }
  $d | Add-Member -Force updated $now
  $d.tasks = @($d.tasks)
} elseif ($Clear) {
  $d = [pscustomobject]@{ title = $(if ($ListTitle) { $ListTitle } else { 'Tasks' }); updated = $now; tasks = @() }
} else {
  $d = Get-Data
  if ($ListTitle) { $d.title = $ListTitle }
  if ($Add) {
    if (-not $Id) {
      $max = 0; foreach ($x in $d.tasks) { if ([string]$x.id -match '^t(\d+)$') { $max = [Math]::Max($max, [int]$Matches[1]) } }
      $Id = 't' + ($max + 1)
    }
    if ($d.tasks | ? { $_.id -eq $Id }) { throw "Task id '$Id' already exists; use -Update." }
    $t = [ordered]@{ id = $Id; title = $Title; group = $(if ($Group) { $Group } else { 'General' }); status = $(if ($Status) { $Status } else { 'pending' }); note = $Note }
    if ($Owner) { $t.owner = $Owner }; if ($AgentId) { $t.agentId = $AgentId }
    $d.tasks = @($d.tasks) + [pscustomobject]$t
  } elseif ($AddSub -or $UpdateSub) {
    $j = $d.tasks | ? { $_.id -eq $Job } | Select -First 1
    if (-not $j) { throw "No job with id '$Job'." }
    if (-not $j.PSObject.Properties['subtasks']) { $j | Add-Member subtasks @() }
    $subs = @($j.subtasks | ? { $_ })
    if ($AddSub) {
      if (-not $Id) { $max = 0; foreach ($x in $subs) { if ([string]$x.id -match '^s(\d+)$') { $max = [Math]::Max($max, [int]$Matches[1]) } }; $Id = 's' + ($max + 1) }
      if ($subs | ? { $_.id -eq $Id }) { throw "Subtask '$Id' already exists in '$Job'." }
      $subs += [pscustomobject][ordered]@{ id = $Id; title = $Title; status = $(if ($Status) { $Status } else { 'pending' }); note = $Note }
    } else {
      $st = $subs | ? { $_.id -eq $Id } | Select -First 1
      if (-not $st) { throw "No subtask '$Id' in '$Job'." }
      foreach ($k in 'Status','Note','Title') { if ($bp.ContainsKey($k)) { $st | Add-Member -Force $k.ToLower() $bp[$k] } }
    }
    $j.subtasks = @($subs)
  } elseif ($Update -or $Remove) {
    $t = $d.tasks | ? { $_.id -eq $Id } | Select -First 1
    if (-not $t) { throw "No task with id '$Id'." }
    if ($Remove) { $d.tasks = @($d.tasks | ? { $_.id -ne $Id }) }
    else {
      foreach ($k in 'Status','Note','Title','Group','Owner','AgentId') {
        if ($bp.ContainsKey($k)) { $n = $k.Substring(0,1).ToLower() + $k.Substring(1); $t | Add-Member -Force $n $bp[$k] }
      }
    }
  } elseif ($Show -and -not $ListTitle) { $d = $null
  } elseif (-not $ListTitle) { Get-Content -LiteralPath $TrackerFile -Raw -ErrorAction SilentlyContinue; return }
  if ($d) { $d | Add-Member -Force updated $now }
}
if ($d) {
  Write-JsonAtomic $TrackerFile $d
  $done = @($d.tasks | ? { $_ -and (Get-JobStatus $_) -eq 'done' }).Count
  "tracker: $done of $(@($d.tasks).Count) done"
}
}   # end of locked read-modify-write
if ($null -ne $out) { $out }
if ($Show) {
  function Test-WindowOpen { try { $w = [Threading.Mutex]::OpenExisting($TrackerWindowMutex); $w.Dispose(); $true } catch { $false } }
  $launch = -not (Test-WindowOpen)
  if (-not $launch) {
    # Already open: write a signal file; the window refreshes, cancels any auto-close, comes to the front
    # without taking focus, and deletes the file as its acknowledgement. If the window exits instead
    # (e.g. its 60 s 'All done' close fired at the same moment), start a fresh one so the -Show is not lost.
    [IO.File]::WriteAllText($TrackerShowSignal, $now)
    $launch = $true
    for ($i = 0; $i -lt 40; $i++) {
      Start-Sleep -Milliseconds 100
      if (-not (Test-Path -LiteralPath $TrackerShowSignal)) { $launch = $false; break }
      if (-not (Test-WindowOpen)) { break }
    }
    if ($launch -and (Test-WindowOpen)) { $launch = $false }   # window alive but slow: it will pick the signal up
  }
  if ($launch) {
    $win = Join-Path $PSScriptRoot 'tracker-window.ps1'
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-WindowStyle','Hidden','-File',"`"$win`"")
  }
}
