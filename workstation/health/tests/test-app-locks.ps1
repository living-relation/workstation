# Read-only app-lock doctor: fake Windows profiles, plus the write-rule decision.
# Usage: pwsh -NoProfile -File workstation/health/tests/test-app-locks.ps1
$ErrorActionPreference = 'Stop'
$status = Join-Path (Split-Path -Parent $PSScriptRoot) 'workstation-status.ps1'
$common = Join-Path (Split-Path -Parent $PSScriptRoot) 'workstation-common.ps1'
$fail = 0
$pwsh = @(Get-Command powershell, pwsh -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $pwsh) { 'FAIL powershell not found'; exit 1 }
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
$rule = "Acquire before use, check in at least every 10 min, and release when done. harness.design section 5b."
$bad = "Acquire before use, check in at least every 10 min, and release when done."
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
    $first = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $status -Locks 2>&1
    $firstText = $first -join "`n"
    Check 'doctor fails while a profile is missing harness.design' $LASTEXITCODE 1
    Check 'doctor names the bad profile' ($firstText -like '*FAIL*Administrator Claude Code*harness.design*') $true
    Check 'doctor passes the good profile' ($firstText -like '*PASS*danie Claude Code*') $true
    Check 'doctor skips desktop when not file-based' ($firstText -like '*SKIP*danie Claude Desktop*') $true
    Check 'doctor skips Grok' ($firstText -like '*SKIP*Grok Bot*') $true
    Check 'doctor passes shared rules' ($firstText -like '*PASS*projects AGENTS.md (shared rules)*') $true
    $adminClaude = Join-Path (Join-Path $users 'Administrator') '.claude'
    $stale = Join-Path $adminClaude 'plugins\cache-x'
    New-Item -ItemType Directory -Path $stale -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $stale 'rules-inject.ps1') -Value '# old cache copy'
    $staleRun = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $status -Locks 2>&1
    $staleText = $staleRun -join "`n"
    Check 'stale cache hook is not the enabled copy' ($staleText -notlike '*PASS*Administrator Claude Code gets the harness.design lock rule*') $true
    Check 'stale cache hook still fails' $LASTEXITCODE 1
    $enabledRoot = Join-Path $adminClaude 'plugins\cache\workstation-plugins\workstation-core\deadbeef'
    New-Item -ItemType Directory -Path (Join-Path $enabledRoot 'hooks') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $enabledRoot 'hooks\rules-inject.ps1') -Value '# enabled hook'
    $reg = @{
        version = 2
        plugins = @{
            'workstation-core@workstation-plugins' = @(@{
                scope = 'user'
                installPath = 'cache/workstation-plugins/workstation-core/deadbeef'
                version = 'deadbeef'
            })
        }
    }
    ($reg | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $adminClaude 'plugins\installed_plugins.json')
    '{"enabledPlugins":{"workstation-core@workstation-plugins":true}}' | Set-Content -LiteralPath (Join-Path $adminClaude 'settings.json')
    $viaHook = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $status -Locks 2>&1
    $viaHookText = $viaHook -join "`n"
    Check 'doctor passes the enabled plugin copy' ($viaHookText -like '*PASS*Administrator Claude Code gets the harness.design lock rule from the enabled workstation-core copy*deadbeef*') $true
    Check 'doctor does not pass the stale cache path' ($viaHookText -notlike '*cache-x*') $true
    Check 'doctor exit 0 with the enabled plugin hook' $LASTEXITCODE 0
    '{"enabledPlugins":{"workstation-core@workstation-plugins":false}}' | Set-Content -LiteralPath (Join-Path $adminClaude 'settings.json')
    $disabled = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $status -Locks 2>&1
    $disabledText = $disabled -join "`n"
    Check 'disabled plugin is not treated as the enabled hook' ($disabledText -notlike '*PASS*Administrator Claude Code gets the harness.design lock rule from the enabled*') $true
    Check 'disabled plugin still fails the lock rule' $LASTEXITCODE 1
    Set-Content -LiteralPath (Join-Path $adminClaude 'CLAUDE.md') -Value $rule
    $second = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $status -Locks 2>&1
    $secondText = $second -join "`n"
    Check 'doctor passes once every profile has the rule' $LASTEXITCODE 0
    Check 'doctor has no FAIL line' ($secondText -notmatch '(?m)^FAIL') $true
    Check 'doctor ends all pass' ($secondText -like '*PASS  all checked items*') $true

    $log = Join-Path $root 'lock-calls.txt'
    $fake = Join-Path $root 'fake-lock.ps1'
    @'
param(
    [Parameter(Position = 0)][string]$Command = '',
    [string]$Name = ''
)
$dest = $env:WORKSTATION_LOCKCHECK_LOG
if ($dest) { Add-Content -LiteralPath $dest -Value ($Command + '|' + $Name) }
$code = 0
if ($env:WORKSTATION_LOCKCHECK_EXIT -match '^\d+$') { $code = [int]$env:WORKSTATION_LOCKCHECK_EXIT }
exit $code
'@ | Set-Content -LiteralPath $fake
    $env:WORKSTATION_LOCKCHECK_SCRIPT = $fake
    $env:WORKSTATION_LOCKCHECK_LOG = $log
    $env:WORKSTATION_LOCKCHECK_EXIT = '1'
    Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
    $exit1 = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $status -Locks 2>&1
    $exit1Text = $exit1 -join "`n"
    $calls1 = @()
    if (Test-Path -LiteralPath $log) { $calls1 = @(Get-Content -LiteralPath $log) }
    Check 'status exit 1 is a fail' ($exit1Text -like '*FAIL*harness.design lock script status failed (exit 1)*') $true
    Check 'status exit 1 is not a pass' ($exit1Text -notlike '*PASS*harness.design lock script runs*') $true
    Check 'status exit 1 fails the doctor' $LASTEXITCODE 1
    Check 'flattened name is not h' (@($calls1 | Where-Object { $_ -eq 'status|h' }).Count) 0
    Check 'exit 1 used the full name once' (@($calls1 | Where-Object { $_ -eq 'status|harness-design' }).Count) 1
    $env:WORKSTATION_LOCKCHECK_EXIT = '0'
    Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
    $exit0 = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $status -Locks 2>&1
    $exit0Text = $exit0 -join "`n"
    $calls0 = @()
    if (Test-Path -LiteralPath $log) { $calls0 = @(Get-Content -LiteralPath $log) }
    Check 'status exit 0 is a pass' ($exit0Text -like '*PASS*harness.design lock script runs (status exit 0)*') $true
    Check 'status exit 0 doctor passes' $LASTEXITCODE 0
    Check 'exit 0 called status once' $calls0.Count 1
    Check 'exit 0 name is harness-design' $calls0[0] 'status|harness-design'
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
