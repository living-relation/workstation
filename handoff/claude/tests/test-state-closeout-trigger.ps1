# Test: the 80% triggers (context-guard.ps1 Stop, handoff-at-80.py Cursor stop) tell the agent to run
# state-closeout (closeout mode), not agent-handoff-pack; below the threshold they stay quiet; the
# PreCompact transcript backup still runs. Temp fake profile only. Usage: powershell -NoProfile -File <this>
$ErrorActionPreference = 'Stop'
$guard = Join-Path $PSScriptRoot '..\context-guard.ps1'
$cursorHook = Join-Path $PSScriptRoot '..\..\cursor\handoff-at-80.py'
$t = Join-Path ([IO.Path]::GetTempPath()) ("closeout-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $t | Out-Null
$fail = 0
function Check($what, $ok) { if ($ok) { "PASS $what" } else { "FAIL $what"; $script:fail++ } }
function Invoke-Tool([string]$Exe, [string]$ArgLine, [string]$Stdin) {
  $psi = New-Object Diagnostics.ProcessStartInfo $Exe, $ArgLine
  $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.EnvironmentVariables['USERPROFILE'] = $t
  $psi.EnvironmentVariables['HOME'] = $t
  $p = [Diagnostics.Process]::Start($psi)
  $p.StandardInput.Write($Stdin); $p.StandardInput.Close()
  $out = $p.StandardOutput.ReadToEnd(); $null = $p.StandardError.ReadToEnd(); $p.WaitForExit()
  return [pscustomobject]@{ Code = $p.ExitCode; Out = $out }
}
$shell = if (Get-Command powershell -ErrorAction SilentlyContinue) { 'powershell' } else { 'pwsh' }
function Invoke-Guard([string]$Mode, [string]$Json) { Invoke-Tool $shell "-NoProfile -ExecutionPolicy Bypass -File `"$guard`" -Mode $Mode" $Json }
$stateDir = Join-Path $t '.claude\compaction-backups\.state'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

Set-Content -LiteralPath (Join-Path $stateDir 'low.pct') -Value '50000,150000' -NoNewline
$r = Invoke-Guard 'stop' '{"session_id":"low"}'
Check 'context-guard: below the threshold stays quiet' ($r.Out.Trim() -eq '' -and $r.Code -eq 0)
Set-Content -LiteralPath (Join-Path $stateDir 'high.pct') -Value '160000,150000' -NoNewline
$r = Invoke-Guard 'stop' '{"session_id":"high"}'
$obj = $null; try { $obj = $r.Out | ConvertFrom-Json } catch { }
Check 'context-guard: at the threshold blocks once with state-closeout' ($obj.decision -eq 'block' -and $obj.reason -match 'state-closeout' -and $obj.reason -match 'closeout mode')
Check 'context-guard: no longer names agent-handoff-pack' ($r.Out -notmatch 'agent-handoff-pack')
$r = Invoke-Guard 'stop' '{"session_id":"high"}'
Check 'context-guard: fires only once' ($r.Out.Trim() -eq '')
$transcript = Join-Path $t 'transcript.jsonl'
Set-Content -LiteralPath $transcript -Value '{"x":1}'
$payload = @{ session_id = 'high'; trigger = 'auto'; transcript_path = $transcript; cwd = $t } | ConvertTo-Json -Compress
$r = Invoke-Guard 'precompact' $payload
$backups = @(Get-ChildItem -LiteralPath (Join-Path $t '.claude\compaction-backups') -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'transcript.jsonl') })
Check 'context-guard: PreCompact still backs up the transcript' ($r.Code -eq 0 -and $backups.Count -eq 1)

$py = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $py) { $py = Get-Command py -CommandType Application | Select-Object -First 1 }
$armed = Join-Path $t '.cursor\hooks\state\handoff-at-80\armed'
New-Item -ItemType Directory -Force -Path (Split-Path $armed) | Out-Null
Set-Content -LiteralPath $armed -Value ''
$r = Invoke-Tool $py.Source "`"$cursorHook`"" '{"hook_event_name":"stop","status":"completed","conversation_id":"c-low","context_usage_percent":50}'
Check 'handoff-at-80: below 80% prints {}' ($r.Out.Trim() -eq '{}')
$r = Invoke-Tool $py.Source "`"$cursorHook`"" '{"hook_event_name":"stop","status":"completed","conversation_id":"c-high","context_usage_percent":85}'
$obj = $null; try { $obj = $r.Out | ConvertFrom-Json } catch { }
Check 'handoff-at-80: at 80% the followup runs state-closeout' ($obj.followup_message -match 'state-closeout' -and $obj.followup_message -match 'closeout mode')
Check 'handoff-at-80: no longer names agent-handoff-pack' ($r.Out -notmatch 'agent-handoff-pack')

Remove-Item -LiteralPath $t -Recurse -Force
if ($fail) { exit 1 } else { 'ALL PASS' }
