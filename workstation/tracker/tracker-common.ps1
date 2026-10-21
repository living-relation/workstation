# Shared paths and helpers for the live task tracker (workstation repo: workstation\tracker).
# WORKSTATION_TRACKER_DIR overrides the data folder (testing against a temp copy).
$TrackerDir      = if ($env:WORKSTATION_TRACKER_DIR) { $env:WORKSTATION_TRACKER_DIR } else { Join-Path $env:LOCALAPPDATA 'Workstation\tracker' }
$TrackerFile     = Join-Path $TrackerDir 'tracker.json'
$TrackerBots     = Join-Path $TrackerDir 'bots.json'
$TrackerSettings = Join-Path $TrackerDir 'settings.json'
$TrackerWindowMutex = 'Local\WorkstationTrackerWindow' + $(if ($env:WORKSTATION_TRACKER_DIR) { '-' + [Math]::Abs($TrackerDir.ToLower().GetHashCode()) } else { '' })

function Initialize-TrackerDir {
  if (-not (Test-Path -LiteralPath $TrackerDir)) { New-Item -ItemType Directory -Force -Path $TrackerDir | Out-Null }
  $readme = Join-Path $TrackerDir 'README.txt'
  if (-not (Test-Path -LiteralPath $readme)) {
    @"
This folder belongs to the workstation repo (github.com/living-relation/workstation, tool: workstation\tracker).
It holds runtime state for the live task tracker window: tracker.json (tasks), bots.json (bot name -> agentId),
settings.json (pin state, window position). Safe to delete; the tracker recreates it. Schema: workstation\tracker\README.md.
"@ | Set-Content -LiteralPath $readme -Encoding UTF8
  }
  # Start empty; the example file in the repo is documentation only, never copied.
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
