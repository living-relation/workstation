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
# Claude Code catalog copy at the same commit as this clone's main (fake sha via WORKSTATION_FAKE_MAIN_SHA).
$sha = '0123456789abcdef0123456789abcdef01234567'
$install = Join-Path $userDir '.claude\plugins\cache\workstation-plugins\workstation-core\0123456789ab'
New-Item -ItemType Directory -Path (Join-Path $install 'hooks') -Force | Out-Null
Set-Content (Join-Path $install 'hooks\rules-inject.ps1') '# hook'
$installed = @{ version = 2; plugins = @{ 'workstation-core@workstation-plugins' = @(@{ scope = 'user'; installPath = $install; version = '0123456789ab'; gitCommitSha = $sha }) } }
($installed | ConvertTo-Json -Depth 8) | Set-Content (Join-Path $userDir '.claude\plugins\installed_plugins.json')
# Cursor local copy equal to this clone's tracked plugin files.
$cursorCopy = Join-Path $userDir '.cursor\plugins\local\workstation-core'
New-Item -ItemType Directory -Path $cursorCopy -Force | Out-Null
$tracked = @(& git -C $repo ls-files -- hooks skills rules memory/templates .cursor-plugin | Where-Object { $_ -and ($_ -notmatch '\.zip$') })
foreach ($rel in $tracked) {
    $src = Join-Path $repo $rel
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { continue }
    $dst = Join-Path $cursorCopy $rel
    New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
    Copy-Item -LiteralPath $src -Destination $dst -Force
}
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
$env:WORKSTATION_FAKE_MAIN_SHA = $sha
$env:WORKSTATION_FAKE_CURSOR_WORKER_STATE = Join-Path $root 'cursor-worker-state'
$env:WORKSTATION_LOCKCHECK_USERS = $users
$env:WORKSTATION_LOCKCHECK_SCRIPT = Join-Path $repo 'workstation\app-lock\app-lock.ps1'
$out = & pwsh -NoProfile -ExecutionPolicy Bypass -File $status -NoPause 2>&1
$code = $LASTEXITCODE
$text = $out -join "`n"
$bad = @($out | Where-Object { "$_" -match '\[(FAIL|WARN)\]' })
foreach ($want in '[ OK ] Claude Code: workstation-core@workstation-plugins 0123456', '[ OK ] Cursor: workstation-core copy matches', '[STOP] Cursor worker STOPPED', '[ -- ] claude.ai copy', '[ -- ] working-memory junction') {
    if (-not ($text.Contains($want))) { "missing line: $want"; $bad += $want }
}
if ($bad.Count -or $code -ne 0) {
    $text
    "FAILED exit $code warnings $($bad.Count)"
    exit 1
}
'ALL PASS'
exit 0
