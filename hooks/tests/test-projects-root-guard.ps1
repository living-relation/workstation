# Tests for projects-root-guard.ps1 and projects-root-report.ps1.
# Temp folders only. Does not read or write a real projects root.
# Usage: pwsh -NoProfile -File hooks/tests/test-projects-root-guard.ps1
$ErrorActionPreference = 'Stop'
$rootDir = Join-Path $PSScriptRoot '..'
$common = Join-Path $rootDir 'projects-root-common.ps1'
$guard = Join-Path $rootDir 'projects-root-guard.ps1'
$report = Join-Path $rootDir 'projects-root-report.ps1'
. $common
$fail = 0
function Check([string]$What, $Ok) {
  if ($Ok) { "PASS $What" } else { "FAIL $What"; $script:fail++ }
}
$shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }

function Invoke-Hook([string]$Hook, $Payload, [hashtable]$Env) {
  $psi = New-Object Diagnostics.ProcessStartInfo $shell, "-NoProfile -ExecutionPolicy Bypass -File `"$Hook`""
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  foreach ($name in @('WORKSTATION_PROJECTS_ROOT', 'WORKSTATION_PROJECTS_DENY_KEYWORDS', 'CURSOR_VERSION')) {
    $psi.EnvironmentVariables.Remove($name)
  }
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
  $out = $p.StandardOutput.ReadToEnd()
  $err = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  return [pscustomobject]@{ Code = $p.ExitCode; Out = $out; Err = $err }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("proj-root-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$rootA = Join-Path $tmp 'root-a'
$rootB = Join-Path $tmp 'root-b'
$profile = Join-Path $tmp 'profile'
$homeProjects = Join-Path $profile 'projects'
New-Item -ItemType Directory -Force -Path (Join-Path $rootA 'active'), (Join-Path $rootB 'active'), $homeProjects | Out-Null
$noSuch = Join-Path $tmp 'missing-root'

function Guard($Payload, $Env) { Invoke-Hook $guard $Payload $Env }
function Report($Payload, $Env) { Invoke-Hook $report $Payload $Env }

# --- path forms (no disk root required) ---
$reC = Get-ProjectsRootRegex 'C:\projects'
$reU = Get-ProjectsRootRegex 'C:\Users\Administrator\projects'
foreach ($sample in @(
  'C:\projects\nope',
  'C:/projects/nope',
  '/c/projects/nope',
  '/mnt/c/projects/nope'
)) {
  Check "C:\projects regex matches $sample" ([regex]::IsMatch($sample, $reC))
}
Check 'user-profile regex matches /mnt/c form' ([regex]::IsMatch('/mnt/c/Users/Administrator/projects/nope', $reU))
Check 'user-profile regex matches /c form' ([regex]::IsMatch('/c/Users/Administrator/projects/nope', $reU))
Check 'user-profile regex matches Windows form' ([regex]::IsMatch('C:\Users\Administrator\projects\nope', $reU))
Check 'user-profile regex does not match C:\projects' (-not [regex]::IsMatch('C:\projects\nope', $reU))
Check 'C:\projects regex does not match the user-profile root' (-not [regex]::IsMatch('C:\Users\Administrator\projects\nope', $reC))

$why = Find-ProjectsRootViolation -Root 'C:\projects' -Text '/mnt/c/projects/nope\file.txt' -Tool 'Write'
Check 'deny /mnt/c/projects bad entry' ($why -match 'not an allowed projects root entry')
$why = Find-ProjectsRootViolation -Root 'C:\projects' -Text '/c/projects/active/ok.txt' -Tool 'Write'
Check 'allow /c/projects/active' ([string]::IsNullOrEmpty($why))
$why = Find-ProjectsRootViolation -Root 'C:\Users\Administrator\projects' -Text '/mnt/c/Users/Administrator/projects/secret' -Tool 'Edit'
Check 'deny user-profile /mnt/c bad entry' ($why -match 'not an allowed')
$why = Find-ProjectsRootViolation -Root 'C:\Users\Administrator\projects' -Text 'C:\projects\secret' -Tool 'Write'
Check 'C:\projects text is not judged against the user-profile root' ([string]::IsNullOrEmpty($why))
$why = Find-ProjectsRootViolation -Root 'C:\projects' -Text 'C:\projects\notes.md' -Tool 'Write'
Check 'loose file name is not an allowed root entry' ($why -match 'not an allowed projects root entry')
$why = Find-ProjectsRootViolation -Root 'C:\projects' -Text 'C:\projects\AGENTS.md' -Tool 'Write'
Check 'root AGENTS.md is allowed' ([string]::IsNullOrEmpty($why))
$env:WORKSTATION_PROJECTS_DENY_KEYWORDS = ''
$why = Find-ProjectsRootViolation -Root 'C:\projects' -Text 'C:\projects\_scratch\blocked-name-notes.md' -Tool 'Write'
Check 'empty keyword default skips the keyword check' ([string]::IsNullOrEmpty($why))
$env:WORKSTATION_PROJECTS_DENY_KEYWORDS = 'blocked-name|other-name'
$why = Find-ProjectsRootViolation -Root 'C:\projects' -Text 'Set-Content C:\projects\_scratch\blocked-name-notes.md' -Tool 'PowerShell'
Check 'keyword env denies _scratch' ($why -match 'AGENTS.md' -and $why -notmatch 'blocked-name-notes')
Remove-Item Env:WORKSTATION_PROJECTS_DENY_KEYWORDS -ErrorAction SilentlyContinue
$why = Find-ProjectsRootViolation -Root 'C:\projects' -Text 'mkdir foo' -Cwd '/mnt/c/projects' -Tool 'Bash'
Check 'relative create in /mnt/c/projects cwd is denied' ($why -match 'projects root')
$why = Find-ProjectsRootViolation -Root 'C:\projects' -Text 'mkdir C:\projects\active\bar' -Cwd 'C:\projects' -Tool 'Bash'
Check 'absolute create under active is allowed' ([string]::IsNullOrEmpty($why))
$why = Find-ProjectsRootViolation -Root 'C:\Users\Administrator\projects' -Text 'mkdir stuff' -Cwd '/c/Users/Administrator/projects' -Tool 'Shell'
Check 'Shell relative create uses the user-profile root' ($why -match 'C:\\Users\\Administrator\\projects\\active')

# --- process: allow, deny, missing root, env override ---
$allowEnv = @{ WORKSTATION_PROJECTS_ROOT = $rootA; USERPROFILE = $profile }
$r = Guard @{ tool_name = 'Write'; cwd = $rootA; tool_input = @{ file_path = (Join-Path $rootA 'active\demo.txt') } } $allowEnv
Check 'allow write under active exits 0' ($r.Code -eq 0)
Check 'allow write under active is silent' ($r.Out.Trim() -eq '')

$r = Guard @{ tool_name = 'Write'; cwd = $rootA; tool_input = @{ file_path = (Join-Path $rootA 'active\demo.txt') } } @{ WORKSTATION_PROJECTS_ROOT = $rootA; CURSOR_VERSION = '1.7.0' }
Check 'cursor allow is the permission line' ($r.Out.Trim() -eq '{"permission":"allow"}' -and $r.Code -eq 0)

$r = Guard @{ tool_name = 'Edit'; cwd = $rootA; tool_input = @{ file_path = (Join-Path $rootA 'nope\demo.txt') } } $allowEnv
Check 'deny bad entry' ($r.Code -eq 0 -and $r.Out -match '"permission"\s*:\s*"deny"' -and $r.Out -match 'AGENTS.md')

$r = Guard @{ tool_name = 'NotebookEdit'; cwd = $rootA; tool_input = @{ notebook_path = (Join-Path $rootA 'active\book.ipynb') } } $allowEnv
Check 'allow notebook under active' ($r.Out.Trim() -eq '' -and $r.Code -eq 0)

$r = Guard @{ tool_name = 'Bash'; cwd = $rootA; tool_input = @{ command = 'git status' } } $allowEnv
Check 'bash without a create verb allows' ($r.Out.Trim() -eq '' -and $r.Code -eq 0)

$r = Guard @{ tool_name = 'Write'; cwd = $rootB; tool_input = @{ file_path = (Join-Path $rootB 'nope\x.txt') } } @{ WORKSTATION_PROJECTS_ROOT = $rootA; USERPROFILE = $profile }
Check 'env override ignores a different root' ($r.Out.Trim() -eq '' -and $r.Code -eq 0)

$r = Guard @{ tool_name = 'Write'; cwd = $tmp; tool_input = @{ file_path = (Join-Path $rootA 'nope\x.txt') } } @{ WORKSTATION_PROJECTS_ROOT = $noSuch; USERPROFILE = $profile }
Check 'missing override root allows' ($r.Out.Trim() -eq '' -and $r.Code -eq 0)

$r = Guard @{ tool_name = 'Write'; cwd = $tmp; tool_input = @{ file_path = 'C:\projects\nope\x.txt' } } @{ WORKSTATION_PROJECTS_ROOT = $noSuch; CURSOR_VERSION = '1.7.0' }
Check 'missing root still prints cursor allow' ($r.Out.Trim() -eq '{"permission":"allow"}')

$scratch = Join-Path $rootA '_scratch\blocked-name-notes.md'
$r = Guard @{ tool_name = 'PowerShell'; cwd = (Join-Path $rootA 'active'); tool_input = @{ command = "Set-Content '$scratch' x" } } $allowEnv
Check 'keyword default empty allows _scratch' ($r.Out.Trim() -eq '' -and $r.Code -eq 0)
$r = Guard @{ tool_name = 'PowerShell'; cwd = (Join-Path $rootA 'active'); tool_input = @{ command = "Set-Content '$scratch' x" } } @{
  WORKSTATION_PROJECTS_ROOT = $rootA
  WORKSTATION_PROJECTS_DENY_KEYWORDS = 'blocked-name|other-name'
}
Check 'keyword env denies and stays generic' ($r.Out -match 'deny' -and $r.Out -match 'AGENTS.md' -and $r.Out -notmatch 'blocked-name-notes')

if (Test-Path -LiteralPath 'C:\projects') {
  'SKIP userprofile fallback (C:\projects exists on this PC)'
} else {
  $r = Guard @{ tool_name = 'Write'; cwd = $homeProjects; tool_input = @{ file_path = (Join-Path $homeProjects 'nope\x.txt') } } @{ USERPROFILE = $profile }
  Check 'userprofile projects root denies a bad entry' ($r.Out -match 'deny' -and $r.Code -eq 0)
  $r = Guard @{ tool_name = 'Write'; cwd = $profile; tool_input = @{ file_path = 'C:\projects\nope\x.txt' } } @{ USERPROFILE = $profile }
  Check 'userprofile root does not special-case C:\projects' ($r.Out.Trim() -eq '')
}

# --- report ---
Set-Content -LiteralPath (Join-Path $rootA 'STRAY.txt') -Value 'x' -Encoding ascii
$r = Report @{ stop_hook_active = $false } @{ WORKSTATION_PROJECTS_ROOT = $rootA }
Check 'report blocks a stray entry' ($r.Code -eq 0 -and $r.Out -match '"decision"\s*:\s*"block"' -and $r.Out -match 'AGENTS.md' -and $r.Out -match 'STRAY.txt')
$r = Report @{ stop_hook_active = $false; cursor_version = '1.7.0' } @{ WORKSTATION_PROJECTS_ROOT = $rootA }
Check 'cursor report uses followup_message' ($r.Out -match 'followup_message' -and $r.Out -notmatch '"decision"' -and $r.Out -match 'AGENTS.md')
$r = Report @{ stop_hook_active = $true } @{ WORKSTATION_PROJECTS_ROOT = $rootA }
Check 'stop_hook_active is silent' ($r.Out.Trim() -eq '' -and $r.Code -eq 0)
$r = Report @{ loop_count = 1 } @{ WORKSTATION_PROJECTS_ROOT = $rootA; CURSOR_VERSION = '1.7.0' }
Check 'cursor loop_count 1 is silent' ($r.Out.Trim() -eq '' -and $r.Code -eq 0)
Remove-Item -LiteralPath (Join-Path $rootA 'STRAY.txt') -Force
$r = Report @{} @{ WORKSTATION_PROJECTS_ROOT = $rootA }
Check 'clean root report is silent' ($r.Out.Trim() -eq '' -and $r.Code -eq 0)
$r = Report @{} @{ WORKSTATION_PROJECTS_ROOT = $noSuch; USERPROFILE = $profile }
Check 'report missing root is silent' ($r.Out.Trim() -eq '' -and $r.Code -eq 0)

Remove-Item $tmp -Recurse -Force
if ($fail) { exit 1 } else { 'ALL PASS' }
