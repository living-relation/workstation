# Test: progress-like writes warn; preference notes do not. Never blocks, moves or deletes.
# Runs in a temp fake profile; touches nothing real. Usage: pwsh -File <this>
$ErrorActionPreference = 'Stop'
$hook = Join-Path $PSScriptRoot '..\memory-link-guard.ps1'
$t = Join-Path ([IO.Path]::GetTempPath()) ("mlg-prog-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$store = Join-Path $t 'Projects\_claude\mem'
New-Item -ItemType Directory -Force $store, (Join-Path $t '.claude\hooks') | Out-Null
Set-Content (Join-Path $store 'MEMORY.md') "# Memory Index`n`n## Projects`n" -Encoding ascii
$storeJson = ($store -replace '\\', '/')
'{"autoMemoryDirectory": "' + $storeJson + '"}' | Set-Content (Join-Path $t '.claude\settings.json') -Encoding ascii
'{"storePath": "' + $storeJson + '"}' | Set-Content (Join-Path $t '.claude\hooks\memory-link-guard.config.json') -Encoding ascii
$pref = Join-Path $store 'prefer_short_commits.md'
$prog = Join-Path $store 'next-steps.md'
$projectProg = Join-Path $store 'project_widget.md'
$projectPref = Join-Path $store 'project_widget_style.md'
Set-Content $pref "# Prefer short commits`n`nWhy: easier to review.`nHow to apply: one change per commit.`n" -Encoding ascii
Set-Content $prog "# Next steps`n`n- open PR #12`n- current branch: feat/x`n" -Encoding ascii
Set-Content $projectProg "# Widget`n`nStatus: in progress. Next steps: land the PR.`n" -Encoding ascii
Set-Content $projectPref "# Widget style`n`nPrefer dense tables. Never duplicate this fact.`n" -Encoding ascii
$shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
function Invoke-Hook([hashtable]$Payload) {
  $psi = New-Object Diagnostics.ProcessStartInfo $shell, "-NoProfile -ExecutionPolicy Bypass -File `"$hook`""
  $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.EnvironmentVariables['USERPROFILE'] = $t
  if (-not $psi.EnvironmentVariables['HOME']) { $psi.EnvironmentVariables['HOME'] = $t }
  $p = [Diagnostics.Process]::Start($psi)
  $p.StandardInput.Write(($Payload | ConvertTo-Json -Compress -Depth 6)); $p.StandardInput.Close()
  $out = $p.StandardOutput.ReadToEnd()
  $null = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  return [pscustomobject]@{ Code = $p.ExitCode; Out = $out }
}
$fail = 0
function Check($what, $ok) { if ($ok) { "PASS $what" } else { "FAIL $what"; $script:fail++ } }
function Write-Payload($path, $content) {
  return @{
    hook_event_name = 'PreToolUse'
    tool_name = 'Write'
    cwd = $t
    tool_input = @{ file_path = $path; content = $content }
  }
}
$r1 = Invoke-Hook (Write-Payload $prog (Get-Content $prog -Raw))
Check 'progress filename warns' ($r1.Out -match 'MEMORY WARNING' -and $r1.Out -match 'state file')
Check 'progress write exit 0' ($r1.Code -eq 0)
Check 'progress file left in place' (Test-Path $prog)
$r2 = Invoke-Hook (Write-Payload $pref (Get-Content $pref -Raw))
Check 'preference note silent' ($r2.Out -notmatch 'looks like project progress')
Check 'preference write exit 0' ($r2.Code -eq 0)
Check 'preference file left in place' (Test-Path $pref)
$r3 = Invoke-Hook (Write-Payload $projectProg (Get-Content $projectProg -Raw))
Check 'project_* with progress warns' ($r3.Out -match 'MEMORY WARNING')
Check 'project_* progress file left' (Test-Path $projectProg)
$r4 = Invoke-Hook (Write-Payload $projectPref (Get-Content $projectPref -Raw))
Check 'project_* preference silent' ($r4.Out -notmatch 'looks like project progress')
Check 'project_* preference file left' (Test-Path $projectPref)
Check 'store files not deleted' (@(Get-ChildItem $store -File).Count -ge 5)
Remove-Item $t -Recurse -Force
if ($fail) { exit 1 } else { 'ALL PASS' }
