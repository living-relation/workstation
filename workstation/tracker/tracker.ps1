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

if ($Set) {
  if ($Path) { $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 }
  elseif ([Console]::IsInputRedirected) {
    # Read stdin with a timeout (Console.In's async read is synchronous in Windows PowerShell, so use the raw stream).
    $in = [Console]::OpenStandardInput(); $ms = New-Object IO.MemoryStream; $buf = New-Object byte[] 65536
    while ($true) {
      $rt = $in.ReadAsync($buf, 0, $buf.Length)
      if (-not $rt.Wait(3000)) { throw '-Set got no piped input within 3 s; use -Path <file> or pipe JSON.' }
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
      foreach ($k in 'Status','Note','Title') { if ($PSBoundParameters.ContainsKey($k)) { $st | Add-Member -Force $k.ToLower() $PSBoundParameters[$k] } }
    }
    $j.subtasks = @($subs)
  } elseif ($Update -or $Remove) {
    $t = $d.tasks | ? { $_.id -eq $Id } | Select -First 1
    if (-not $t) { throw "No task with id '$Id'." }
    if ($Remove) { $d.tasks = @($d.tasks | ? { $_.id -ne $Id }) }
    else {
      foreach ($k in 'Status','Note','Title','Group','Owner','AgentId') {
        if ($PSBoundParameters.ContainsKey($k)) { $n = $k.Substring(0,1).ToLower() + $k.Substring(1); $t | Add-Member -Force $n $PSBoundParameters[$k] }
      }
    }
  } elseif ($Show -and -not $ListTitle) { $d = $null
  } elseif (-not $ListTitle) { Get-Content -LiteralPath $TrackerFile -Raw -ErrorAction SilentlyContinue; return }
  if ($d) { $d.updated = $now }
}
if ($d) {
  Write-JsonAtomic $TrackerFile $d
  $done = @($d.tasks | ? { $_.status -eq 'done' }).Count
  "tracker: $done of $(@($d.tasks).Count) done"
}
if ($Show) {
  $open = $false
  try { $w = [Threading.Mutex]::OpenExisting($TrackerWindowMutex); $w.Dispose(); $open = $true } catch { }
  if ($open) {
    # Already open: touch a signal file; the window refreshes and comes to the front without taking focus.
    [IO.File]::WriteAllText((Join-Path $TrackerDir 'show.signal'), $now)
  } else {
    $win = Join-Path $PSScriptRoot 'tracker-window.ps1'
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-WindowStyle','Hidden','-File',"`"$win`"")
  }
}
