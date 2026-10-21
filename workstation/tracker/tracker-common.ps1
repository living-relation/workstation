# Shared paths and helpers for the live task tracker (workstation repo: workstation\tracker).
$TrackerDir      = Join-Path $env:LOCALAPPDATA 'Workstation\tracker'
$TrackerFile     = Join-Path $TrackerDir 'tracker.json'
$TrackerBots     = Join-Path $TrackerDir 'bots.json'
$TrackerSettings = Join-Path $TrackerDir 'settings.json'
$TrackerWindowMutex = 'Local\WorkstationTrackerWindow'
$TrackerWatchMutex  = 'Local\WorkstationTrackerWatch'

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
  $ex = Join-Path $PSScriptRoot 'bots.example.json'
  if (-not (Test-Path -LiteralPath $TrackerBots) -and (Test-Path -LiteralPath $ex)) { Copy-Item -LiteralPath $ex $TrackerBots }
}

function Read-JsonFile([string]$Path) {
  for ($i = 0; $i -lt 5; $i++) {
    try { if (Test-Path -LiteralPath $Path) { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } else { return $null } }
    catch { Start-Sleep -Milliseconds 100 }
  }
  return $null
}

function Write-JsonAtomic([string]$Path, $Object) {
  $json = $Object | ConvertTo-Json -Depth 8
  $tmp = "$Path.$PID.tmp"
  [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding $false))
  if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($tmp, $Path, [NullString]::Value) } else { [IO.File]::Move($tmp, $Path) }
}
