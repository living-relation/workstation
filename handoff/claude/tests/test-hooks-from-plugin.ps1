# Test: the plugin copies (-FromPlugin / --from-plugin) of context-guard.ps1, pr-closeout-nudge.ps1,
# memory-link-guard.ps1 and handoff-at-80.py (decision D-2026-11-26-hooks-in-plugin):
# - each stays quiet when the user config still wires an older copy for that event (no double run);
# - context-guard Stop works with no statusLine, from the transcript's token usage;
# - memory-link-guard stays silent on a PC with no shared memory setup;
# - the Cursor handoff is armed by default unless the disarmed file exists.
# Temp fake profiles only. Usage: powershell -NoProfile -ExecutionPolicy Bypass -File <this>
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$ctx = Join-Path $here '..\context-guard.ps1'
$nudge = Join-Path $here '..\pr-closeout-nudge.ps1'
$guard = Join-Path $here '..\..\..\memory\hooks\memory-link-guard.ps1'
$cursorHook = Join-Path $here '..\..\cursor\handoff-at-80.py'
$launcher = Join-Path $here '..\..\cursor\run-handoff-at-80.ps1'
$fail = 0
function Check($what, $ok) { if ($ok) { "PASS $what" } else { "FAIL $what"; $script:fail++ } }
function New-Profile([string]$Name) {
  $d = Join-Path ([IO.Path]::GetTempPath()) ("plugin-$Name-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path (Join-Path $d '.claude') | Out-Null
  return $d
}
function Write-Utf8([string]$Path, [string]$Text) {
  New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
  [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false))
}
function Invoke-Tool([string]$Exe, [string]$ArgLine, [string]$Stdin, [string]$Home_, [hashtable]$Extra) {
  $psi = New-Object Diagnostics.ProcessStartInfo $Exe, $ArgLine
  $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.EnvironmentVariables['USERPROFILE'] = $Home_
  $psi.EnvironmentVariables['HOME'] = $Home_
  foreach ($k in @('WORKSTATION_MEMORY_STORE', 'CURSOR_VERSION', 'CLAUDE_CODE_AUTO_COMPACT_WINDOW')) { if ($psi.EnvironmentVariables.ContainsKey($k)) { $psi.EnvironmentVariables.Remove($k) } }
  if ($Extra) { foreach ($k in $Extra.Keys) { $psi.EnvironmentVariables[$k] = [string]$Extra[$k] } }
  $p = [Diagnostics.Process]::Start($psi)
  $p.StandardInput.Write($Stdin); $p.StandardInput.Close()
  $out = $p.StandardOutput.ReadToEnd(); $null = $p.StandardError.ReadToEnd(); $p.WaitForExit()
  return [pscustomobject]@{ Code = $p.ExitCode; Out = $out }
}
$shell = if (Get-Command powershell -ErrorAction SilentlyContinue) { 'powershell' } else { 'pwsh' }
function Invoke-Ps([string]$Script, [string]$ArgsText, [string]$Json, [string]$Home_, [hashtable]$Extra) {
  Invoke-Tool $shell "-NoProfile -ExecutionPolicy Bypass -File `"$Script`" $ArgsText" $Json $Home_ $Extra
}
$made = New-Object Collections.Generic.List[string]

# --- context-guard: Stop from the transcript, no statusLine
$h = New-Profile 'ctx'; $made.Add($h)
$tr = Join-Path $h 'high.jsonl'
Write-Utf8 $tr ('{"type":"user","message":{"content":"hi"}}' + "`n" + '{"type":"assistant","message":{"usage":{"input_tokens":5000,"cache_creation_input_tokens":20000,"cache_read_input_tokens":140000,"output_tokens":300}}}' + "`n")
$r = Invoke-Ps $ctx '-Mode stop -FromPlugin' (@{ session_id = 'tr-high'; transcript_path = $tr } | ConvertTo-Json -Compress) $h
$obj = $null; try { $obj = $r.Out | ConvertFrom-Json } catch { }
Check 'context-guard plugin: no statusLine, transcript past the trigger blocks once with state-closeout' ($obj.decision -eq 'block' -and $obj.reason -match 'state-closeout')
$r = Invoke-Ps $ctx '-Mode stop -FromPlugin' (@{ session_id = 'tr-high'; transcript_path = $tr } | ConvertTo-Json -Compress) $h
Check 'context-guard plugin: fires only once per session' ($r.Out.Trim() -eq '')
$trLow = Join-Path $h 'low.jsonl'
Write-Utf8 $trLow ('{"type":"assistant","message":{"usage":{"input_tokens":3000,"cache_creation_input_tokens":1000,"cache_read_input_tokens":40000}}}' + "`n")
$r = Invoke-Ps $ctx '-Mode stop -FromPlugin' (@{ session_id = 'tr-low'; transcript_path = $trLow } | ConvertTo-Json -Compress) $h
Check 'context-guard plugin: transcript below the trigger stays quiet' ($r.Code -eq 0 -and $r.Out.Trim() -eq '')
$r = Invoke-Ps $ctx '-Mode stop -FromPlugin' (@{ session_id = 'tr-none' } | ConvertTo-Json -Compress) $h
Check 'context-guard plugin: no transcript and no statusline file stays quiet' ($r.Code -eq 0 -and $r.Out.Trim() -eq '')
$r = Invoke-Ps $ctx '-Mode stop -FromPlugin' (@{ session_id = 'tr-acw'; transcript_path = $trLow } | ConvertTo-Json -Compress) $h @{ CLAUDE_CODE_AUTO_COMPACT_WINDOW = '60000' }
$obj = $null; try { $obj = $r.Out | ConvertFrom-Json } catch { }
Check 'context-guard plugin: CLAUDE_CODE_AUTO_COMPACT_WINDOW sets the compaction point' ($obj.decision -eq 'block')
# Older copy wired in settings.json: the plugin copy stays quiet for that event only.
$hw = New-Profile 'ctxwired'; $made.Add($hw)
Write-Utf8 (Join-Path $hw '.claude\settings.json') '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"powershell -File \"C:/x/.claude/hooks/context-guard.ps1\" stop"}]}]}}'
$r = Invoke-Ps $ctx '-Mode stop -FromPlugin' (@{ session_id = 'w-high'; transcript_path = $tr } | ConvertTo-Json -Compress) $hw
Check 'context-guard plugin: quiet on Stop while an older copy is wired for Stop' ($r.Code -eq 0 -and $r.Out.Trim() -eq '')
$r = Invoke-Ps $ctx '-Mode stop' (@{ session_id = 'w-high2'; transcript_path = $tr } | ConvertTo-Json -Compress) $hw
$obj = $null; try { $obj = $r.Out | ConvertFrom-Json } catch { }
Check 'context-guard older copy (no -FromPlugin) still fires' ($obj.decision -eq 'block')
$trc = Join-Path $hw 'pc.jsonl'; Write-Utf8 $trc '{"x":1}'
$r = Invoke-Ps $ctx '-Mode precompact -FromPlugin' (@{ session_id = 'w-pc'; trigger = 'auto'; transcript_path = $trc; cwd = $hw } | ConvertTo-Json -Compress) $hw
$bk = @(Get-ChildItem -LiteralPath (Join-Path $hw '.claude\compaction-backups') -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'transcript.jsonl') })
Check 'context-guard plugin: PreCompact still backs up when only Stop is wired elsewhere' ($r.Code -eq 0 -and $bk.Count -eq 1)

# --- pr-closeout-nudge
$hn = New-Profile 'nudge'; $made.Add($hn)
$prPayload = @{ hook_event_name = 'PostToolUse'; tool_name = 'Bash'; tool_input = @{ command = 'gh pr create --fill' }; tool_response = @{ stdout = 'https://github.com/o/r/pull/7' } } | ConvertTo-Json -Compress -Depth 6
$r = Invoke-Ps $nudge '-FromPlugin' $prPayload $hn
Check 'nudge plugin: nudges after gh pr create' ($r.Out -match 'pr-closeout' -and $r.Out -match 'pull/7')
Write-Utf8 (Join-Path $hn '.claude\settings.json') '{"hooks":{"PostToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"powershell -File C:/x/.claude/hooks/pr-closeout-nudge.ps1"}]}]}}'
$r = Invoke-Ps $nudge '-FromPlugin' $prPayload $hn
Check 'nudge plugin: prints {} while an older copy is wired' ($r.Out.Trim() -eq '{}')

# --- memory-link-guard
$hg = New-Profile 'guard'; $made.Add($hg)
$r = Invoke-Ps $guard '-FromPlugin' (@{ hook_event_name = 'SessionStart'; cwd = $hg } | ConvertTo-Json -Compress) $hg
Check 'guard plugin: silent on a PC with no memory setup' ($r.Code -eq 0 -and $r.Out.Trim() -eq '')
$r = Invoke-Ps $guard '-FromPlugin' (@{ hook_event_name = 'preToolUse'; tool_name = 'Write'; tool_input = @{ file_path = (Join-Path $hg 'x.md'); content = 'x' } } | ConvertTo-Json -Compress) $hg @{ CURSOR_VERSION = '3.0' }
Check 'guard plugin: Cursor preToolUse with no memory setup prints only the allow line' ($r.Out.Trim() -eq '{"permission":"allow"}')
$store = Join-Path $hg 'Projects\_claude\mem'
New-Item -ItemType Directory -Force -Path $store | Out-Null
Write-Utf8 (Join-Path $store 'MEMORY.md') "# Memory Index`n"
$storeJson = ($store -replace '\\', '/')
Write-Utf8 (Join-Path $hg '.claude\settings.json') ('{"autoMemoryDirectory": "' + $storeJson + '"}')
# An older install's guard config (still read); a new install relies on the junction target instead.
Write-Utf8 (Join-Path $hg '.claude\hooks\memory-link-guard.config.json') ('{"storePath": "' + $storeJson + '"}')
$progress = "# Notes`n`nStatus: in progress. Next steps: open PR #12 on branch feat/x.`n"
$wr = @{ hook_event_name = 'PreToolUse'; tool_name = 'Write'; cwd = $hg; tool_input = @{ file_path = (Join-Path $store 'widget\INDEX.md'); content = $progress } } | ConvertTo-Json -Compress
$r = Invoke-Ps $guard '-FromPlugin' $wr $hg
Check 'guard plugin: with autoMemoryDirectory set it warns about progress in the store' ($r.Out -match 'looks like project progress')
Write-Utf8 (Join-Path $hg '.claude\settings.json') ('{"autoMemoryDirectory": "' + $storeJson + '", "hooks": {"PreToolUse": [{"matcher": "Write|Edit", "hooks": [{"type": "command", "command": "powershell -File C:/x/.claude/hooks/memory-link-guard.ps1"}]}]}}')
$r = Invoke-Ps $guard '-FromPlugin' $wr $hg
Check 'guard plugin: quiet on PreToolUse while an older copy is wired for PreToolUse' ($r.Code -eq 0 -and $r.Out.Trim() -eq '')
$r = Invoke-Ps $guard '' $wr $hg
Check 'guard older copy (no -FromPlugin) still warns' ($r.Out -match 'looks like project progress')

# --- handoff-at-80 (Cursor)
$py = $null
foreach ($name in @('python', 'python3', 'py')) {
  $py = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Where-Object { $_.Source -notmatch 'WindowsApps' } | Select-Object -First 1
  if ($py) { break }
}
if (-not $py) { throw 'python, python3, or py is required for this test' }
$hc = New-Profile 'cursor'; $made.Add($hc)
$high = '{"hook_event_name":"stop","status":"completed","conversation_id":"c-high","context_usage_percent":85}'
$r = Invoke-Tool $py.Source "`"$cursorHook`" --from-plugin" $high $hc
$obj = $null; try { $obj = $r.Out | ConvertFrom-Json } catch { }
Check 'handoff-at-80 plugin: armed by default (no armed file) and runs state-closeout' ($obj.followup_message -match 'state-closeout')
$r = Invoke-Tool $py.Source "`"$cursorHook`"" ($high -replace 'c-high', 'c-old') $hc
Check 'handoff-at-80 older copy: still needs the armed file' ($r.Out.Trim() -eq '{}')
Write-Utf8 (Join-Path $hc '.cursor\hooks\state\handoff-at-80\disarmed') ''
$r = Invoke-Tool $py.Source "`"$cursorHook`" --from-plugin" ($high -replace 'c-high', 'c-dis') $hc
Check 'handoff-at-80 plugin: the disarmed file turns it off' ($r.Out.Trim() -eq '{}')
$hc2 = New-Profile 'cursor2'; $made.Add($hc2)
Write-Utf8 (Join-Path $hc2 '.cursor\hooks.json') '{"version":1,"hooks":{"stop":[{"command":"py -3 C:/x/.cursor/hooks/handoff-at-80.py"}]}}'
$r = Invoke-Tool $py.Source "`"$cursorHook`" --from-plugin" $high $hc2
Check 'handoff-at-80 plugin: prints {} while ~/.cursor/hooks.json wires an older copy' ($r.Out.Trim() -eq '{}')
$hc3 = New-Profile 'cursor3'; $made.Add($hc3)
$r = Invoke-Ps $launcher '' $high $hc3
$obj = $null; try { $obj = $r.Out | ConvertFrom-Json } catch { }
Check 'run-handoff-at-80.ps1: runs the plugin copy and passes the payload through' ($obj.followup_message -match 'state-closeout')
$r = Invoke-Ps $launcher '' '{"hook_event_name":"stop","status":"completed","conversation_id":"c-low","context_usage_percent":10}' $hc3
Check 'run-handoff-at-80.ps1: below 80% prints {}' ($r.Out.Trim() -eq '{}')

foreach ($d in $made) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
if ($fail) { "$fail FAILED"; exit 1 } else { 'ALL PASS'; exit 0 }
