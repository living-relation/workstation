# One-way sync: Claude memory -> Cursor's copy (claude-memory\ only).
# Never writes back to Claude. Never touches cursor-notes\, claude-chat-summaries\ or README.md.
# Portable: every path is worked out from this script's own folder (<Projects>\_claude).
$ErrorActionPreference = 'Stop'
$claudeDir = $PSScriptRoot
if (-not $claudeDir) { $claudeDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$src = Join-Path $claudeDir 'Claude Projects\Working Memory\memory'
$dst = Join-Path $claudeDir 'Cursor Copy of Claude Memory\claude-memory'
$log = Join-Path $claudeDir 'sync-claude-memory-to-cursor.log'
$maxLines = 200

function Write-SyncLog([string]$msg) {
  $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $msg
  $lines = @()
  if (Test-Path -LiteralPath $log) { $lines = @(Get-Content -LiteralPath $log) }
  $lines += $line
  if ($lines.Count -gt $maxLines) { $lines = $lines[($lines.Count - $maxLines)..($lines.Count - 1)] }
  [IO.File]::WriteAllText($log, (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding $false))
}

try {
  # Safety: never mirror from a missing or empty source (that would wipe the copy).
  if (-not (Test-Path -LiteralPath $src -PathType Container)) { Write-SyncLog "SKIP: source folder missing: $src"; exit 0 }
  $count = @(Get-ChildItem -LiteralPath $src -Recurse -File -Force -ErrorAction Stop).Count
  if ($count -eq 0) { Write-SyncLog "SKIP: source folder is empty: $src"; exit 0 }
  # Safety: only ever mirror into the claude-memory folder.
  if ((Split-Path -Leaf $dst) -ne 'claude-memory') { Write-SyncLog "SKIP: unexpected target: $dst"; exit 0 }
  if (-not (Test-Path -LiteralPath $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }

  & robocopy.exe $src $dst /MIR /XJ /R:1 /W:1 /NP /NJH /NJS /NFL /NDL /NS /NC | Out-Null
  $rc = $LASTEXITCODE
  if ($rc -lt 8) {
    Write-SyncLog "OK: $count source files, robocopy code $rc"
    exit 0
  } else {
    Write-SyncLog "FAIL: robocopy code $rc"
    exit $rc
  }
} catch {
  Write-SyncLog ("FAIL: " + $_.Exception.Message)
  exit 1
}