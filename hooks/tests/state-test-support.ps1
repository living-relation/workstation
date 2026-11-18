# Dot-sourced by hooks/tests/test-state-*.ps1. Temp folders and a fake memory store only
# (WORKSTATION_MEMORY_STORE); never reads or writes the real store or the real profile.
# The state tools come from WORKSTATION_STATE_TOOLS, else this repo's scripts/state.
$ErrorActionPreference = 'Stop'
$script:fail = 0
$script:HooksDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:StateTools = $env:WORKSTATION_STATE_TOOLS
if (-not $script:StateTools) { $script:StateTools = Join-Path (Join-Path $script:HooksDir '..') 'scripts\state' }
if (-not (Test-Path -LiteralPath (Join-Path $script:StateTools 'state_lint.py'))) {
  "FAIL state tools not found at $($script:StateTools) (set WORKSTATION_STATE_TOOLS)"
  exit 1
}
$script:StateTools = (Resolve-Path -LiteralPath $script:StateTools).Path
$script:HookShell = if (Get-Command powershell -ErrorAction SilentlyContinue) { 'powershell' } else { 'pwsh' }

function Check([string]$What, $Ok) {
  if ($Ok) { "PASS $What" } else { "FAIL $What"; $script:fail++ }
}

function New-TestRoot([string]$Prefix) {
  $dir = Join-Path ([IO.Path]::GetTempPath()) ($Prefix + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  return (Resolve-Path -LiteralPath $dir).Path
}

function Invoke-Git {
  param([string]$Repo, [Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $out = & git -C $Repo -c commit.gpgsign=false -c user.name=state-test -c user.email=state-test@example.invalid @GitArgs 2>&1
    $code = $LASTEXITCODE
  } finally { $ErrorActionPreference = $old }
  return [pscustomobject]@{ Code = $code; Out = (@($out | ForEach-Object { "$_" }) -join "`n") }
}

function New-TestRepo([string]$Parent, [string]$Name, [string]$HooksPath) {
  $repo = Join-Path $Parent $Name
  New-Item -ItemType Directory -Force -Path $repo | Out-Null
  [void](Invoke-Git $repo init -q -b main)
  if (-not $HooksPath) { $HooksPath = Join-Path $Parent 'no-hooks' ; New-Item -ItemType Directory -Force -Path $HooksPath | Out-Null }
  [void](Invoke-Git $repo config core.hooksPath ($HooksPath -replace '\\', '/'))
  [void](Invoke-Git $repo config core.autocrlf false)
  [IO.File]::WriteAllText((Join-Path $repo 'README.md'), "test`n")
  [void](Invoke-Git $repo add README.md)
  [void](Invoke-Git $repo commit -q -m init)
  return (Resolve-Path -LiteralPath $repo).Path
}

function Get-TestSlug([string]$Text) { return (($Text.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')) }

function Get-GoodState([string]$Branch, [string]$Objective, [int]$ExtraLines) {
  $lines = @(
    '# STATE (max 30 lines, overwrite only)', 'Repo: test-repo', "Branch: $Branch", 'Last_Verified_SHA: none',
    'Updated: 2026-11-18 -- state-test', '', '## Current Goal', "- Objective: $Objective", '- Spec_Ref: none', '',
    '## Active Blocker', '- Status: NONE', '- Detail: none', '', '## Next Single Step', '- [NEXT] Do the one thing in README.md', '',
    '## Pointers', '- Branch_States: none', '- Backlog: BACKLOG.md', '- Latest_ADR: none'
  )
  for ($i = 0; $i -lt $ExtraLines; $i++) { $lines += "- note $i" }
  return (($lines -join "`n") + "`n")
}

function Write-TestFile([string]$Path, [string]$Text) {
  New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
  [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false))
}

function Invoke-StateHook {
  param([string]$Hook, $Payload, [hashtable]$Env, [string[]]$HookArgs)
  $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$Hook`""
  if ($HookArgs) { $argLine += ' ' + ($HookArgs -join ' ') }
  $psi = New-Object Diagnostics.ProcessStartInfo $script:HookShell, $argLine
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  foreach ($name in @('CURSOR_VERSION', 'CLAUDE_PLUGIN_ROOT', 'CURSOR_PLUGIN_ROOT', 'WORKSTATION_MEMORY_STORE')) {
    $psi.EnvironmentVariables.Remove($name)
  }
  $psi.EnvironmentVariables['WORKSTATION_STATE_TOOLS'] = $script:StateTools
  if ($Env) {
    foreach ($k in $Env.Keys) {
      if ($null -eq $Env[$k]) { $psi.EnvironmentVariables.Remove([string]$k) }
      else { $psi.EnvironmentVariables[[string]$k] = [string]$Env[$k] }
    }
  }
  $p = [Diagnostics.Process]::Start($psi)
  $json = if ($null -eq $Payload) { '' } else { $Payload | ConvertTo-Json -Compress -Depth 8 }
  $p.StandardInput.Write($json)
  $p.StandardInput.Close()
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  return [pscustomobject]@{ Code = $p.ExitCode; Out = $outTask.Result; Err = $errTask.Result }
}

function Get-OutLines([string]$Text) { return , @(($Text.Trim()) -split "`r?`n" | Where-Object { $_ -ne '' }) }

function Remove-TestRoot([string]$Dir) {
  if ($Dir -and (Test-Path -LiteralPath $Dir)) { Remove-Item -LiteralPath $Dir -Recurse -Force -ErrorAction SilentlyContinue }
}

function Complete-StateTest {
  if ($script:fail) { "FAILED: $($script:fail)"; exit 1 } else { 'ALL PASS' }
}
