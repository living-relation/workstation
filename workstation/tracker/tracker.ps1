<#
.SYNOPSIS
  Update the live task tracker (%LOCALAPPDATA%\Workstation\tracker\tracker.json). Writes are atomic.
.EXAMPLE
  tracker.ps1 -Set -Path plan.json          # replace everything (or pipe JSON on stdin)
  tracker.ps1 -Add -Id t1 -Title 'Fix X' -Group 'Repo' [-Status pending] [-Owner 'Sidekick'] [-AgentId <id>]
  tracker.ps1 -Update -Id t1 -Status done -Note 'merged #12'
  tracker.ps1 -Title 'Today'                 # set the list title only
  tracker.ps1 -Clear
  tracker.ps1 -Show                          # open the window (or refresh + bring to front); combine with any of the above
#>
[CmdletBinding()]
param(
  [switch]$Set, [switch]$Update, [switch]$Add, [switch]$Clear, [switch]$Remove, [switch]$Show,
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
  $raw = if ($Path) { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 } else { [Console]::In.ReadToEnd() }
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
    if (-not $Id) { $Id = 't' + ($d.tasks.Count + 1) }
    if ($d.tasks | ? { $_.id -eq $Id }) { throw "Task id '$Id' already exists; use -Update." }
    $t = [ordered]@{ id = $Id; title = $Title; group = $(if ($Group) { $Group } else { 'General' }); status = $(if ($Status) { $Status } else { 'pending' }); note = $Note }
    if ($Owner) { $t.owner = $Owner }; if ($AgentId) { $t.agentId = $AgentId }
    $d.tasks = @($d.tasks) + [pscustomobject]$t
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
