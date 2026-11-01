# Test: Cursor vs Claude Code output. Under Cursor (CURSOR_VERSION set) a preToolUse run prints exactly
# one line {"permission":"allow"} (warnings go to stderr); under Claude Code allow paths stay silent
# and warnings print as before. Runs in a temp fake profile; touches nothing real. Usage: pwsh -File <this>
$ErrorActionPreference = 'Stop'
$hook = Join-Path $PSScriptRoot '..\memory-link-guard.ps1'
$t = Join-Path ([IO.Path]::GetTempPath()) ("mlg-cur-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$store = Join-Path $t 'Projects\_claude\mem'
New-Item -ItemType Directory -Force $store, (Join-Path $t '.claude\hooks') | Out-Null
Set-Content (Join-Path $store 'MEMORY.md') "# Memory Index`n`n## Projects`n" -Encoding ascii
$storeJson = ($store -replace '\\', '/')
'{"autoMemoryDirectory": "' + $storeJson + '"}' | Set-Content (Join-Path $t '.claude\settings.json') -Encoding ascii
'{"storePath": "' + $storeJson + '"}' | Set-Content (Join-Path $t '.claude\hooks\memory-link-guard.config.json') -Encoding ascii
$wm = Join-Path $t '.claude\working-memory'
New-Item -ItemType Junction -Path $wm -Target $store | Out-Null
$shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
function Invoke-Hook([hashtable]$Payload, [string]$CursorVersion) {
  $psi = New-Object Diagnostics.ProcessStartInfo $shell, "-NoProfile -ExecutionPolicy Bypass -File `"$hook`""
  $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.EnvironmentVariables['USERPROFILE'] = $t
  if (-not $psi.EnvironmentVariables['HOME']) { $psi.EnvironmentVariables['HOME'] = $t }
  $psi.EnvironmentVariables.Remove('CURSOR_VERSION')
  if ($CursorVersion) { $psi.EnvironmentVariables['CURSOR_VERSION'] = $CursorVersion }
  $p = [Diagnostics.Process]::Start($psi)
  $p.StandardInput.Write(($Payload | ConvertTo-Json -Compress -Depth 6)); $p.StandardInput.Close()
  $out = $p.StandardOutput.ReadToEnd()
  $err = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  return [pscustomobject]@{ Code = $p.ExitCode; Out = $out; Err = $err }
}
$fail = 0
function Check($what, $ok) { if ($ok) { "PASS $what" } else { "FAIL $what"; $script:fail++ } }
function P($ev, $path, $content) { @{ hook_event_name = $ev; tool_name = 'Write'; cwd = $t; tool_input = @{ file_path = $path; content = $content } } }
$allowLine = '{"permission":"allow"}'
$pref = Join-Path $store 'prefer_short_commits.md'
$prog = Join-Path $store 'next-steps.md'
$progText = "# Next steps`n`n- open PR #12`n"
# Claude Code (no CURSOR_VERSION)
$r = Invoke-Hook (P 'PreToolUse' $pref "Prefer short commits.") ''
Check 'claude: normal write prints nothing' ($r.Out.Trim() -eq '' -and $r.Code -eq 0)
$r = Invoke-Hook (P 'PreToolUse' $prog $progText) ''
Check 'claude: progress write warns on stdout' ($r.Out -match 'MEMORY WARNING' -and $r.Out -notmatch 'permission' -and $r.Code -eq 0)
$r = Invoke-Hook (P 'PreToolUse' (Join-Path $t 'other.txt') 'x') ''
Check 'claude: write outside store prints nothing' ($r.Out.Trim() -eq '')
# Cursor (CURSOR_VERSION set)
$r = Invoke-Hook (P 'preToolUse' $pref "Prefer short commits.") '1.7.0'
Check 'cursor: normal write prints exactly the allow line' ($r.Out.Trim() -eq $allowLine -and @($r.Out.Trim() -split "`r?`n").Count -eq 1 -and $r.Code -eq 0)
$r = Invoke-Hook (P 'preToolUse' $prog $progText) '1.7.0'
Check 'cursor: progress write stdout is only the allow line' ($r.Out.Trim() -eq $allowLine -and $r.Code -eq 0)
Check 'cursor: progress warning moved to stderr' ($r.Err -match 'MEMORY WARNING')
$r = Invoke-Hook (P 'preToolUse' (Join-Path $t 'other.txt') 'x') '1.7.0'
Check 'cursor: write outside store prints the allow line' ($r.Out.Trim() -eq $allowLine)
$r = Invoke-Hook (P 'PreToolUse' $pref "x") '1.7.0'
Check 'cursor: Claude-style event name also allowed' ($r.Out.Trim() -eq $allowLine)
$r = Invoke-Hook @{ hook_event_name = 'SessionStart'; cwd = $t } '1.7.0'
Check 'cursor: SessionStart prints no allow line' ($r.Out -notmatch 'permission')
[IO.Directory]::Delete($wm)
Remove-Item $t -Recurse -Force
if ($fail) { exit 1 } else { 'ALL PASS' }
