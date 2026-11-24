# A clean installed layout should print no [FAIL] and no [WARN].
# Usage: pwsh -NoProfile -File workstation/health/tests/test-health-clean.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$status = Join-Path (Split-Path -Parent $PSScriptRoot) 'workstation-status.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ("hc-" + [guid]::NewGuid().ToString('N'))
$userDir = Join-Path $root 'home'
$local = Join-Path $root 'local'
$projects = Join-Path $root 'Projects'
$users = Join-Path $root 'users'
New-Item -ItemType Directory -Path $userDir, $local, $projects, $users | Out-Null
$rule = "Acquire before use, check in at least every 10 min, and release when done. harness.design section 5b."
New-Item -ItemType Directory -Path (Join-Path $userDir '.claude\hooks') -Force | Out-Null
$mem = Join-Path $projects '_claude\Claude Projects\Working Memory\memory'
New-Item -ItemType Directory -Path $mem -Force | Out-Null
$hook = 'powershell -NoProfile -File "' + (Join-Path $userDir '.claude\hooks\memory-link-guard.ps1') + '"'
$ctx = 'powershell -NoProfile -File "' + (Join-Path $userDir '.claude\hooks\context-guard.ps1') + '" stop'
$pre = 'powershell -NoProfile -File "' + (Join-Path $userDir '.claude\hooks\context-guard.ps1') + '" precompact'
$nudge = 'powershell -NoProfile -File "' + (Join-Path $userDir '.claude\hooks\pr-closeout-nudge.ps1') + '"'
foreach ($name in 'memory-link-guard.ps1','context-guard.ps1','pr-closeout-nudge.ps1') {
    Set-Content (Join-Path $userDir ".claude\hooks\$name") 'exit 0'
}
$settings = @{
    autoMemoryDirectory = ($mem -replace '\\','/')
    hooks = @{
        SessionStart = @(@{ hooks = @(@{ command = $hook }) })
        PreToolUse = @(@{ hooks = @(@{ command = $hook }) })
        Stop = @(@{ hooks = @(@{ command = $ctx }) })
        PreCompact = @(@{ hooks = @(@{ command = $pre }) })
        PostToolUse = @(@{ hooks = @(@{ command = $nudge }) })
    }
    pluginConfigs = @{
        'cc-plugin-agents-md@builtin' = @{ options = @{ instructionFiles = 'claude-md-and-agents-md' } }
    }
    enabledPlugins = @{ 'workstation-core@synced' = $false }
}
($settings | ConvertTo-Json -Depth 8) | Set-Content (Join-Path $userDir '.claude\settings.json')
$state = Join-Path $local 'Workstation'
New-Item -ItemType Directory -Path $state | Out-Null
(@{ projectsRoot = $projects; toolkit = (Join-Path $repo 'workstation') } | ConvertTo-Json) | Set-Content (Join-Path $state 'workstation.json')
Set-Content (Join-Path $projects 'AGENTS.md') $rule
$profile = Join-Path $users 'danie'
New-Item -ItemType Directory -Path (Join-Path $profile '.claude') -Force | Out-Null
Set-Content (Join-Path $profile '.claude\CLAUDE.md') $rule
$pstate = Join-Path $profile 'AppData\Local\Workstation'
New-Item -ItemType Directory -Path $pstate -Force | Out-Null
(@{ projectsRoot = $projects } | ConvertTo-Json) | Set-Content (Join-Path $pstate 'workstation.json')
$syncedPlugin = Join-Path $userDir '.claude\plugins\synced\workstation-core\.claude-plugin'
New-Item -ItemType Directory -Path $syncedPlugin -Force | Out-Null
Set-Content (Join-Path $syncedPlugin 'plugin.json') '{"name":"workstation-core"}'
$dest = Join-Path $userDir '.claude\skills'
New-Item -ItemType Directory -Path $dest | Out-Null
$exclude = @()
$ex = Join-Path $repo 'skills\EXCLUDE.txt'
if (Test-Path $ex) { $exclude = @(Get-Content $ex | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }) }
Get-ChildItem (Join-Path $repo 'skills') -Directory | ForEach-Object {
    if ($exclude -contains $_.Name) { return }
    if (-not (Test-Path (Join-Path $_.FullName 'SKILL.md'))) { return }
    $text = Get-Content (Join-Path $_.FullName 'SKILL.md') -Raw
    if ($text -match '(?m)^source:\s*harness-design-app\s*$') { return }
    New-Item -ItemType Directory -Path (Join-Path $dest $_.Name) | Out-Null
}
$env:HOME = $userDir
$env:USERPROFILE = $userDir
$env:LOCALAPPDATA = $local
$env:WORKSTATION_FAKE_PROCS = 'none'
$env:WORKSTATION_FAKE_AUTOSTART = 'none'
$env:WORKSTATION_FAKE_RESTART = 'none'
$env:WORKSTATION_LOCKCHECK_USERS = $users
$env:WORKSTATION_LOCKCHECK_SCRIPT = Join-Path $repo 'workstation\app-lock\app-lock.ps1'
$out = & pwsh -NoProfile -ExecutionPolicy Bypass -File $status -NoPause 2>&1
$code = $LASTEXITCODE
$text = $out -join "`n"
$bad = @($out | Where-Object { "$_" -match '\[(FAIL|WARN)\]' })
$need = @(
    '[STOP] Desktop Commander remote is not running',
    '[ RUN ] Desktop Commander remote has no Windows startup entry',
    '[STOP] Cursor worker is not running',
    '[ RUN ] Cursor worker has no Windows startup entry',
    '[ -- ] working-memory junction is not checked',
    'claude.ai synced copy (Desktop/Cowork): last synced',
    'has rules-inject no',
    'Claude Code plugin copy is not enabled',
    'claude plugin update workstation-core@workstation-plugins',
    'Cursor local copy is not installed',
    'install-plugins.ps1'
)
$missing = @($need | Where-Object { $text.IndexOf($_) -lt 0 })
if ($bad.Count -or $code -ne 0 -or $missing.Count -or $text -match 'not added on claude.ai') {
    $text
    "FAILED exit $code warnings $($bad.Count) missing $($missing -join ' | ')"
    exit 1
}
$deadDir = Join-Path $local 'Workstation\cursor-worker\instances\deadone'
New-Item -ItemType Directory -Path $deadDir -Force | Out-Null
Set-Content (Join-Path $deadDir 'worker.json') '{"pid":4242,"folder":"widget"}'
Set-Content (Join-Path $deadDir 'worker.err.log') 'Authentication required for worker mode. Please run agent login'
$deadOut = & pwsh -NoProfile -ExecutionPolicy Bypass -File $status -NoPause 2>&1
$deadCode = $LASTEXITCODE
$deadText = $deadOut -join "`n"
if ($deadCode -ne 1 -or $deadText -notmatch '\[FAIL\].*agent login' -or $deadText -match 'sample-key-value|--api-key') {
    $deadText
    "FAILED dead-worker exit $deadCode"
    exit 1
}
'ALL PASS'
exit 0
