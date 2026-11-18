# Tests memory/hooks/memory-link-guard.ps1 with the live-state files: progress written to
# STATE.md, STATE-*.md, BACKLOG.md or archives\ in a project folder is not flagged; progress in
# INDEX.md or another note still is. Temp fake profile and store only.
# Usage: powershell -NoProfile -File hooks/tests/test-state-memory-link-guard.ps1
. (Join-Path $PSScriptRoot 'state-test-support.ps1')
$hook = Join-Path $script:HooksDir '..\memory\hooks\memory-link-guard.ps1'
$t = New-TestRoot 'state-mlg'
$store = Join-Path $t 'Projects\_claude\mem'
New-Item -ItemType Directory -Force -Path $store, (Join-Path $t '.claude\hooks') | Out-Null
Write-TestFile (Join-Path $store 'MEMORY.md') "# Memory Index`n`n## Projects`n"
$storeJson = ($store -replace '\\', '/')
Write-TestFile (Join-Path $t '.claude\settings.json') ('{"autoMemoryDirectory": "' + $storeJson + '"}')
Write-TestFile (Join-Path $t '.claude\hooks\memory-link-guard.config.json') ('{"storePath": "' + $storeJson + '"}')
$profileEnv = @{ USERPROFILE = $t; HOME = $t }
$progress = "# STATE`n`nStatus: in progress. Next steps: open PR #12 on branch feat/x.`n"
function Write-Note([string]$Path, [string]$Text, [hashtable]$Env) {
  if (-not $Env) { $Env = $profileEnv }
  Invoke-StateHook $hook @{ hook_event_name = 'PreToolUse'; tool_name = 'Write'; cwd = $t; tool_input = @{ file_path = $Path; content = $Text } } $Env
}
function Test-Warns($Result) { return ($Result.Code -eq 0 -and $Result.Out -match 'looks like project progress') }
function Test-Quiet($Result) { return ($Result.Code -eq 0 -and $Result.Out -notmatch 'looks like project progress') }
$p = Join-Path $store 'widget'

Check 'STATE.md progress is not flagged' (Test-Quiet (Write-Note (Join-Path $p 'STATE.md') $progress))
Check 'STATE-feat-x.md progress is not flagged' (Test-Quiet (Write-Note (Join-Path $p 'STATE-feat-x.md') $progress))
Check 'BACKLOG.md progress is not flagged' (Test-Quiet (Write-Note (Join-Path $p 'BACKLOG.md') "- [BKLG] next steps: TODO later`n"))
Check 'archives\STATE-x-date.md is not flagged' (Test-Quiet (Write-Note (Join-Path $p 'archives\STATE-feat-x-20261118.md') $progress))
Check 'project INDEX.md with progress warns' (Test-Warns (Write-Note (Join-Path $p 'INDEX.md') $progress))
Check 'project INDEX.md with preferences only is quiet' (Test-Quiet (Write-Note (Join-Path $p 'INDEX.md') "# Index`n`n- Prefers dense tables.`n"))
Check 'other progress note still warns' (Test-Warns (Write-Note (Join-Path $p 'session-notes.md') $progress))
Check 'STATE.md at the store root (not a project folder) still warns' (Test-Warns (Write-Note (Join-Path $store 'STATE.md') $progress))
Check 'nested STATE.md below a project subfolder still warns' (Test-Warns (Write-Note (Join-Path $p 'notes\STATE.md') $progress))
Check 'warning names the STATE / BACKLOG homes' ((Write-Note (Join-Path $p 'INDEX.md') $progress).Out -match 'STATE-<branch-slug>\.md' )

$alt = Join-Path $t 'alt-store'
New-Item -ItemType Directory -Force -Path $alt | Out-Null
$envAlt = @{ USERPROFILE = $t; HOME = $t; WORKSTATION_MEMORY_STORE = $alt }
Check 'WORKSTATION_MEMORY_STORE: STATE.md in that store is quiet' (Test-Quiet (Write-Note (Join-Path $alt 'widget\STATE.md') $progress $envAlt))
Check 'WORKSTATION_MEMORY_STORE: INDEX.md progress in that store warns' (Test-Warns (Write-Note (Join-Path $alt 'widget\INDEX.md') $progress $envAlt))
Check 'WORKSTATION_MEMORY_STORE: the linked memory folder is left alone (not moved or re-linked)' ((Test-Path -LiteralPath (Join-Path $store 'MEMORY.md')) -and -not ((Get-Item -LiteralPath $store -Force).LinkType))

$r = Write-Note (Join-Path $p 'STATE.md') $progress @{ USERPROFILE = $t; HOME = $t; CURSOR_VERSION = '1.7.0' }
Check 'cursor: STATE.md write prints only the allow line' ($r.Out.Trim() -eq '{"permission":"allow"}')

Remove-TestRoot $t
Complete-StateTest
