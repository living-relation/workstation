# Tests for agents-md-only-warn.ps1.
# Temp folders only. Does not delete or edit a real instruction file.
# Usage: pwsh -NoProfile -File hooks/tests/test-agents-md-only-warn.ps1
$ErrorActionPreference = 'Stop'
$rootDir = Join-Path $PSScriptRoot '..'
$hook = Join-Path $rootDir 'agents-md-only-warn.ps1'
$hooksJson = Join-Path $rootDir 'hooks.json'
$cursorJson = Join-Path $rootDir 'cursor-hooks.json'
. $hook
$fail = 0
function Check([string]$What, $Ok) {
  if ($Ok) { "PASS $What" } else { "FAIL $What"; $script:fail++ }
}
$shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }

function Invoke-HookRaw([string]$Stdin, [hashtable]$Env, [string]$WorkDir) {
  $psi = New-Object Diagnostics.ProcessStartInfo $shell, "-NoProfile -ExecutionPolicy Bypass -File `"$hook`""
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  if ($WorkDir) { $psi.WorkingDirectory = $WorkDir }
  foreach ($name in @('USERPROFILE', 'HOME')) {
    $psi.EnvironmentVariables.Remove($name)
  }
  if ($Env) {
    foreach ($k in $Env.Keys) {
      if ($null -eq $Env[$k]) { $psi.EnvironmentVariables.Remove([string]$k) }
      else { $psi.EnvironmentVariables[[string]$k] = [string]$Env[$k] }
    }
  }
  $p = [Diagnostics.Process]::Start($psi)
  if ($null -eq $Stdin) { $Stdin = '' }
  $p.StandardInput.Write($Stdin)
  $p.StandardInput.Close()
  $out = $p.StandardOutput.ReadToEnd()
  $err = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  return [pscustomobject]@{ Code = $p.ExitCode; Out = $out; Err = $err }
}

function Invoke-Hook($Payload, [hashtable]$Env, [string]$WorkDir) {
  $json = if ($null -eq $Payload) { '' } else { $Payload | ConvertTo-Json -Compress -Depth 6 }
  return (Invoke-HookRaw $json $Env $WorkDir)
}

function Listed([string]$Out) {
  $rows = New-Object 'System.Collections.Generic.List[string]'
  foreach ($line in @($Out -split "`r?`n")) {
    if ($line.StartsWith('- ')) { [void]$rows.Add($line.Substring(2).Trim()) }
  }
  return @($rows)
}

function FileSnap([string[]]$Paths) {
  # Hash only the instruction files under test. A pwsh process whose HOME is
  # the temp profile may create its own host files; those are not the hook.
  $rows = New-Object 'System.Collections.Generic.List[string]'
  foreach ($f in $Paths) {
    if (-not (Test-Path -LiteralPath $f)) { [void]$rows.Add($f + ' MISSING'); continue }
    $hash = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash
    $len = (Get-Item -LiteralPath $f).Length
    [void]$rows.Add($f + ' ' + $hash + ' ' + $len)
  }
  return ($rows -join "`n")
}

$rule = "Dan's rule: AGENTS.md is the only instruction file. Fold this file's content into AGENTS.md, then delete it (in a PR for repo files; files outside a repo: tell Dan)."
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("agents-md-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$profileHome = Join-Path $tmp 'home'
$proj = Join-Path $profileHome 'proj'
$sub = Join-Path $proj 'sub'
$side = Join-Path $profileHome 'side'
$clean = Join-Path $tmp 'clean'
New-Item -ItemType Directory -Force -Path $sub, (Join-Path $proj '.claude'), (Join-Path $profileHome '.claude'), $side, $clean | Out-Null

$subLocal = Join-Path $sub 'CLAUDE.local.md'
$projClaude = Join-Path $proj 'CLAUDE.md'
$projDot = Join-Path (Join-Path $proj '.claude') 'CLAUDE.md'
$homeClaude = Join-Path $profileHome 'CLAUDE.md'
$homeLocal = Join-Path $profileHome 'CLAUDE.local.md'
$homeDot = Join-Path (Join-Path $profileHome '.claude') 'CLAUDE.md'
$sideClaude = Join-Path $side 'CLAUDE.md'
$baseClaude = Join-Path $tmp 'CLAUDE.md'
$wrongCase = Join-Path $sub 'CLAUDE.MD'
foreach ($pair in @(
  @($subLocal, 'sub-local'),
  @($projClaude, 'proj-claude'),
  @($projDot, 'proj-dot'),
  @($homeClaude, 'home-claude'),
  @($homeLocal, 'home-local'),
  @($homeDot, 'home-dot-ignored'),
  @($sideClaude, 'side'),
  @($baseClaude, 'base')
)) {
  Set-Content -LiteralPath $pair[0] -Value $pair[1] -Encoding ascii
}
if ([IO.Path]::DirectorySeparatorChar -eq '/') {
  Set-Content -LiteralPath $wrongCase -Value 'wrong-case' -Encoding ascii
}

$hookText = Get-Content -LiteralPath $hook -Raw
$danger = '\b(Remove-Item|Set-Content|Add-Content|Clear-Content|Out-File|New-Item|Move-Item|Rename-Item|Copy-Item|del|erase|rmdir)\b'
Check 'hook script has no write or delete cmdlet' ($hookText -notmatch $danger)
Check 'hook script has no nonzero exit' ($hookText -notmatch 'exit\s+[1-9]')

$claudeHooks = Get-Content -LiteralPath $hooksJson -Raw | ConvertFrom-Json
$sessionCmd = [string]$claudeHooks.hooks.SessionStart[0].hooks[0].command
Check 'SessionStart uses CLAUDE_PLUGIN_ROOT' ($sessionCmd -match '\$\{CLAUDE_PLUGIN_ROOT\}/hooks/agents-md-only-warn\.ps1')
Check 'SessionStart runs through run-ps.sh (powershell, then pwsh, else silent)' ($sessionCmd -match '^sh "\$\{CLAUDE_PLUGIN_ROOT\}/hooks/run-ps\.sh" ' -and $sessionCmd -notmatch 'pwsh|powershell')
$cursorText = Get-Content -LiteralPath $cursorJson -Raw
Check 'cursor hooks have no agents-md-only-warn' ($cursorText -notmatch 'agents-md-only-warn')

$set = @{}
Add-HomeIgnoreKeys $set 'C:\Users\Dan'
Check 'windows home ignores C:\ form' (Test-InstructionIgnored 'C:\Users\Dan\.claude\CLAUDE.md' $set)
Check 'windows home ignores /mnt/c form' (Test-InstructionIgnored '/mnt/c/Users/Dan/.claude/CLAUDE.md' $set)
Check 'windows home ignores /c form' (Test-InstructionIgnored '/c/Users/Dan/.claude/CLAUDE.md' $set)
Check 'home CLAUDE.md is not the ignored file' (-not (Test-InstructionIgnored 'C:\Users\Dan\CLAUDE.md' $set))
Check 'home CLAUDE.local.md is not ignored' (-not (Test-InstructionIgnored 'C:\Users\Dan\CLAUDE.local.md' $set))
Check 'another profile is not ignored' (-not (Test-InstructionIgnored 'C:\Users\Other\.claude\CLAUDE.md' $set))
Check 'project .claude/CLAUDE.md is not ignored' (-not (Test-InstructionIgnored 'C:\Users\Dan\proj\.claude\CLAUDE.md' $set))

$chain = @(Get-DirectoryChain -Start $sub)
Check 'chain starts at the session directory' ($chain[0] -eq (Get-FullPathSafe $sub))
$rootPath = [IO.Path]::GetPathRoot((Get-FullPathSafe $sub))
Check 'chain ends at the drive root' ($chain[$chain.Count - 1] -eq (Get-FullPathSafe $rootPath))
Check 'chain includes a parent' (@($chain | Where-Object { $_ -eq (Get-FullPathSafe $proj) }).Count -eq 1)

$envMap = @{ USERPROFILE = $profileHome; HOME = $profileHome }
$watched = @($subLocal, $projClaude, $projDot, $homeClaude, $homeLocal, $homeDot, $sideClaude, $baseClaude)
if ([IO.Path]::DirectorySeparatorChar -eq '/') { $watched += $wrongCase }
$before = FileSnap $watched
$r = Invoke-Hook @{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $sub } $envMap $side
$after = FileSnap $watched
Check 'warn exits 0' ($r.Code -eq 0)
Check 'warn stderr is empty' ([string]::IsNullOrWhiteSpace($r.Err))
Check 'warn includes the rule' ($r.Out -match [regex]::Escape($rule))
Check 'warn says it did not change anything' ($r.Out -match 'did not delete, edit, or block')
Check 'warn is plain text' (-not $r.Out.TrimStart().StartsWith('{'))
Check 'warn does not deny or block' ($r.Out -notmatch '"permission"' -and $r.Out -notmatch '"decision"')
Check 'instruction files are unchanged' ($before -eq $after)

$listed = @(Listed $r.Out)
function Show([string]$Path) { return (Get-DisplayPath $Path) }
$want = @(
  (Show $subLocal),
  (Show $projClaude),
  (Show $projDot),
  (Show $homeClaude),
  (Show $homeLocal),
  (Show $baseClaude)
)
$sep = [IO.Path]::DirectorySeparatorChar
$inside = @($listed | Where-Object { $_.StartsWith((Get-FullPathSafe $tmp) + $sep, [StringComparison]::OrdinalIgnoreCase) -or $_ -eq (Get-FullPathSafe $tmp) })
Check 'lists each instruction file under the temp tree' ((Compare-Object $inside $want) -eq $null)
Check 'lists the deeper file before its parent' ([array]::IndexOf($listed, (Show $subLocal)) -ge 0 -and [array]::IndexOf($listed, (Show $projClaude)) -gt [array]::IndexOf($listed, (Show $subLocal)))
Check 'ignores ~/.claude/CLAUDE.md' ($listed -notcontains (Show $homeDot))
Check 'does not list a sibling directory' ($listed -notcontains (Show $sideClaude))
if ([IO.Path]::DirectorySeparatorChar -eq '/') {
  Check 'POSIX names are case-sensitive' ($listed -notcontains (Show $wrongCase))
} else {
  'SKIP POSIX case check (this host folds names)'
}
$startupOut = $r.Out

$r = Invoke-Hook @{ cwd = $proj } $envMap $side
$listed = @(Listed $r.Out)
Check 'cwd is the JSON cwd, not the process directory' ($r.Code -eq 0 -and ($listed -contains (Show $projClaude)) -and ($listed -notcontains (Show $sideClaude)) -and ($listed -notcontains (Show $subLocal)))
Check 'parent of cwd is still scanned' ($listed -contains (Show $homeClaude) -and $listed -contains (Show $baseClaude))
Check 'startup warning is plain text' (-not $startupOut.TrimStart().StartsWith('{'))

$r = Invoke-HookRaw 'not-json' $envMap $clean
Check 'bad JSON exits 0' ($r.Code -eq 0)
Check 'bad JSON prints nothing' ($r.Out.Trim() -eq '')
$r = Invoke-HookRaw '' $envMap $clean
Check 'empty stdin exits 0' ($r.Code -eq 0)
Check 'empty stdin prints nothing' ($r.Out.Trim() -eq '')
$r = Invoke-Hook @{ cwd = (Join-Path $clean 'missing\nope') } $envMap $clean
Check 'missing cwd exits 0' ($r.Code -eq 0)

$quiet = Invoke-Hook @{ cwd = $clean } $envMap $clean
$qListed = @(Listed $quiet.Out)
Check 'clean directory exits 0' ($quiet.Code -eq 0)
Check 'clean directory adds no file of its own' (@($qListed | Where-Object { $_.StartsWith((Get-FullPathSafe $clean) + $sep, [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0)
Check 'a clean directory still warns about a parent file' ($qListed -contains (Show $baseClaude))

$lonely = Join-Path ([IO.Path]::GetTempPath()) ("agents-md-quiet-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $lonely | Out-Null
$alone = Invoke-Hook @{ cwd = $lonely } $envMap $lonely
if ($alone.Code -ne 0) {
  Check 'directory with no instruction files exits 0' $false
} elseif ([string]::IsNullOrWhiteSpace($alone.Out)) {
  Check 'directory with no instruction files is silent' $true
} else {
  $hitInside = $false
  foreach ($p in @(Listed $alone.Out)) {
    if ($p.StartsWith((Get-FullPathSafe $lonely) + $sep, [StringComparison]::OrdinalIgnoreCase)) { $hitInside = $true }
  }
  if ($hitInside) { Check 'directory with no instruction files is silent' $false }
  else { 'SKIP silent directory (an ancestor outside the temp tree has an instruction file)' }
}
Remove-Item -LiteralPath $lonely -Recurse -Force

Remove-Item -LiteralPath $tmp -Recurse -Force
if ($fail) { exit 1 } else { 'ALL PASS' }
