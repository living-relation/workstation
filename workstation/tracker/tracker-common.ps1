# Shared paths and helpers for the live task tracker (workstation repo: workstation\tracker).
# WORKSTATION_TRACKER_DIR overrides the data folder (testing against a temp copy).
$TrackerDir      = if ($env:WORKSTATION_TRACKER_DIR) { $env:WORKSTATION_TRACKER_DIR } else { Join-Path $env:LOCALAPPDATA 'Workstation\tracker' }
$TrackerFile     = Join-Path $TrackerDir 'tracker.json'
$TrackerBots     = Join-Path $TrackerDir 'bots.json'
$TrackerSettings = Join-Path $TrackerDir 'settings.json'
# Per-data-folder suffix (empty for the default folder) so a test folder never talks to the live window.
$TrackerSuffix = if ($env:WORKSTATION_TRACKER_DIR) {
  $sha = [Security.Cryptography.SHA1]::Create()
  '-' + (-join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($TrackerDir.ToLower())) | % { $_.ToString('x2') }))
} else { '' }
$TrackerWindowMutex = 'Local\WorkstationTrackerWindow' + $TrackerSuffix
# -Show handshake: tracker.ps1 sets this auto-reset event; the open window waits on it (no files involved).
$TrackerShowEvent  = 'Local\WorkstationTrackerShow' + $TrackerSuffix
# Window state (pin, position, size, expanded jobs) lives in the registry; the window never writes files.
$TrackerRegKey     = 'HKCU:\Software\Workstation\Tracker' + $(if ($TrackerSuffix) { '\test' + $TrackerSuffix } else { '' })
# Every read-modify-write of tracker.json by tracker.ps1 holds this named mutex.
$TrackerWriteMutex = 'Local\WorkstationTrackerWrite' + $TrackerSuffix

# Runs $Body while holding the write mutex (waits up to $TimeoutSec; an abandoned mutex counts as acquired).
function Invoke-TrackerLocked([scriptblock]$Body, [int]$TimeoutSec = 10) {
  $m = New-Object Threading.Mutex($false, $TrackerWriteMutex)
  $got = $false
  try {
    try { $got = $m.WaitOne([TimeSpan]::FromSeconds($TimeoutSec)) } catch [Threading.AbandonedMutexException] { $got = $true }
    if (-not $got) { throw "tracker.json is locked by another writer (waited $TimeoutSec s)." }
    & $Body
  } finally { if ($got) { $m.ReleaseMutex() }; $m.Dispose() }
}

# Job status: an explicit 'blocked' on the job wins; otherwise derived from subtasks when it has any.
function Get-JobStatus($t) {
  if ([string]$t.status -eq 'blocked') { return 'blocked' }
  $subs = @($t.subtasks | ? { $_ })
  if (-not $subs.Count) { return [string]$t.status }
  $st = @($subs | % { [string]$_.status })
  if (@($st | ? { $_ -ne 'done' }).Count -eq 0) { return 'done' }
  if ($st -contains 'blocked') { return 'blocked' }
  if ($st -contains 'in_progress' -or $st -contains 'done') { return 'in_progress' }
  'pending'
}

function Initialize-TrackerDir {
  if (-not (Test-Path -LiteralPath $TrackerDir)) { New-Item -ItemType Directory -Force -Path $TrackerDir | Out-Null }
  $readme = Join-Path $TrackerDir 'README.txt'
  $text = @"
This folder belongs to the workstation repo (github.com/living-relation/workstation, tool: workstation\tracker).
It holds the live task tracker's data: tracker.json (tasks, written only by tracker.ps1) and bots.json
(optional owner name -> color). The tracker window is read-only and never writes here; its pin state, position, size and
expanded jobs are kept in the registry (HKCU\Software\Workstation\Tracker). A settings.json left from older
versions is read once for migration and otherwise ignored. Safe to delete; tracker.ps1 recreates it.
Schema: workstation\tracker\README.md.
"@
  # Rewritten when the text changes (tracker.ps1 only; the window never calls this).
  $cur = if (Test-Path -LiteralPath $readme) { (Get-Content -LiteralPath $readme -Raw).Trim() } else { '' }
  if ($cur -ne $text.Trim()) { $text | Set-Content -LiteralPath $readme -Encoding UTF8 }
  # Start empty (optional owner colors).
  if (-not (Test-Path -LiteralPath $TrackerBots)) { [IO.File]::WriteAllText($TrackerBots, '{}', (New-Object Text.UTF8Encoding $false)) }
}

function Read-JsonFile([string]$Path) {
  for ($i = 0; $i -lt 10; $i++) {
    try { if (Test-Path -LiteralPath $Path) { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } else { return $null } }
    catch { Start-Sleep -Milliseconds 100 }
  }
  return $null
}

function Write-JsonAtomic([string]$Path, $Object) {
  $json = $Object | ConvertTo-Json -Depth 8
  $tmp = "$Path.$PID.tmp"
  [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding $false))
  for ($i = 1; ; $i++) {
    try {
      if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($tmp, $Path, [NullString]::Value) } else { [IO.File]::Move($tmp, $Path) }
      return
    } catch {
      if ($i -ge 10) { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue; throw }
      Start-Sleep -Milliseconds 100
    }
  }
}
