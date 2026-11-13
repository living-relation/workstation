# Read-only app-lock doctor: fake Windows profiles, plus the write-rule decision.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File workstation/shortcuts/tests/test-app-locks.ps1
$ErrorActionPreference = 'Stop'
$status = Join-Path (Split-Path -Parent $PSScriptRoot) 'workstation-status.ps1'
$common = Join-Path (Split-Path -Parent $PSScriptRoot) 'workstation-common.ps1'
$fail = 0
function Check([string]$What, $Got, $Want) { if ($Got -eq $Want) { "PASS $What" } else { "FAIL $What (got '$Got', want '$Want')"; $script:fail++ } }
$saved = @{
    LOCALAPPDATA = $env:LOCALAPPDATA
    USERS = $env:WORKSTATION_LOCKCHECK_USERS
    SCRIPT = $env:WORKSTATION_LOCKCHECK_SCRIPT
}
$root = Join-Path ([IO.Path]::GetTempPath()) ("al-test-" + [guid]::NewGuid().ToString('N'))
$users = Join-Path $root 'users'
$projects = Join-Path $root 'Projects'
$local = Join-Path $root 'local'
New-Item -ItemType Directory -Path $users, $projects, $local | Out-Null
$rule = "Acquire before use, check in at least every 10 min, and release when done. Fusion section 5. harness.design section 5b."
$bad = "Acquire before use, check in at least every 10 min, and release when done. Fusion section 5 only."
function New-Profile([string]$Name, [string]$ClaudeText, [switch]$Cursor, [switch]$Desktop) {
    $p = Join-Path $users $Name
    New-Item -ItemType Directory -Path (Join-Path $p '.claude') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $p '.claude\CLAUDE.md') -Value $ClaudeText
    $state = Join-Path (Join-Path (Join-Path $p 'AppData') 'Local') 'Workstation'
    New-Item -ItemType Directory -Path $state -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $state 'workstation.json') -Value (@{ projectsRoot = $projects } | ConvertTo-Json)
    if ($Cursor) {
        $rules = Join-Path (Join-Path $p '.cursor') 'rules'
        New-Item -ItemType Directory -Path $rules -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $rules 'repo-rules.mdc') -Value $rule
    }
    if ($Desktop) { New-Item -ItemType Directory -Path (Join-Path (Join-Path (Join-Path $p 'AppData') 'Roaming') 'Claude') -Force | Out-Null }
}
try {
    $env:LOCALAPPDATA = $local
    $env:WORKSTATION_LOCKCHECK_USERS = $users
    if (-not $env:USERPROFILE) { $env:USERPROFILE = $root }
    if (-not $env:APPDATA) { $env:APPDATA = Join-Path $root 'roaming' }
    if (-not $env:ProgramFiles) { $env:ProgramFiles = Join-Path $root 'pf' }
    Remove-Item Env:WORKSTATION_LOCKCHECK_SCRIPT -ErrorAction SilentlyContinue
    . $common
    $allow = [pscustomobject]@{ AccessControlType = 'Allow'; FileSystemRights = 'FullControl'; IdentityReference = 'PC\danie' }
    $read = [pscustomobject]@{ AccessControlType = 'Allow'; FileSystemRights = 'ReadAndExecute'; IdentityReference = 'PC\danie' }
    $usersRule = [pscustomobject]@{ AccessControlType = 'Allow'; FileSystemRights = 'Modify'; IdentityReference = 'BUILTIN\Users' }
    $deny = [pscustomobject]@{ AccessControlType = 'Deny'; FileSystemRights = 'Write'; IdentityReference = 'PC\danie' }
    Check 'acl allows profile user' (Test-AclAllowsWrite @($allow) 'danie' @()) $true
    Check 'acl read is not write' (Test-AclAllowsWrite @($read) 'danie' @()) $false
    Check 'acl allows Users' (Test-AclAllowsWrite @($usersRule) 'someone' @()) $true
    Check 'acl deny wins' (Test-AclAllowsWrite @($usersRule, $deny) 'danie' @()) $false
    Check 'rule text complete' (Test-LockRuleComplete $rule) $true
    Check 'rule text incomplete' (Test-LockRuleComplete $bad) $false

    Set-Content -LiteralPath (Join-Path $projects 'AGENTS.md') -Value $rule
    New-Item -ItemType Directory -Path (Join-Path $users 'emptyuser') | Out-Null
    New-Profile 'danie' $rule -Cursor -Desktop
    New-Profile 'Administrator' $bad
    $first = & powershell -NoProfile -ExecutionPolicy Bypass -File $status -Locks 2>&1
    $firstText = $first -join "`n"
    Check 'doctor fails while a profile is missing harness.design' $LASTEXITCODE 1
    Check 'doctor names the bad profile' ($firstText -like '*FAIL*Administrator Claude Code*harness.design*') $true
    Check 'doctor passes the good profile' ($firstText -like '*PASS*danie Claude Code*') $true
    Check 'doctor skips desktop when not file-based' ($firstText -like '*SKIP*danie Claude Desktop*') $true
    Check 'doctor skips Grok' ($firstText -like '*SKIP*Grok Bot*') $true
    Check 'doctor passes shared rules' ($firstText -like '*PASS*projects AGENTS.md (shared rules)*') $true
    Set-Content -LiteralPath (Join-Path (Join-Path $users 'Administrator') '.claude\CLAUDE.md') -Value $rule
    $second = & powershell -NoProfile -ExecutionPolicy Bypass -File $status -Locks 2>&1
    $secondText = $second -join "`n"
    Check 'doctor passes once every profile has the rule' $LASTEXITCODE 0
    Check 'doctor has no FAIL line' ($secondText -notmatch '(?m)^FAIL') $true
    Check 'doctor ends all pass' ($secondText -like '*PASS  all checked items*') $true
} catch {
    "FAIL exception: $($_.Exception.Message)"
    $fail++
} finally {
    if ($null -ne $saved.LOCALAPPDATA) { $env:LOCALAPPDATA = $saved.LOCALAPPDATA } else { Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue }
    if ($null -ne $saved.USERS) { $env:WORKSTATION_LOCKCHECK_USERS = $saved.USERS } else { Remove-Item Env:WORKSTATION_LOCKCHECK_USERS -ErrorAction SilentlyContinue }
    if ($null -ne $saved.SCRIPT) { $env:WORKSTATION_LOCKCHECK_SCRIPT = $saved.SCRIPT } else { Remove-Item Env:WORKSTATION_LOCKCHECK_SCRIPT -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
if ($fail) { "FAILED: $fail"; exit 1 } else { 'ALL PASS'; exit 0 }
