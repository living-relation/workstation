#Requires -Version 5.1
# One-time cleanup for a PC that still has the old local web UI, watcher, or shortcut links.
# -WhatIf prints every step and changes nothing.
# Backs up first and writes SHA256 hashes, then archives (does not delete) the old runtime folders.
# Does not stop the Desktop Commander phone remote and does not archive its state folder.
# An old cursor-worker folder (no instances directory) is still archived.
# A folder that has instances\ is the manual Cursor worker and is left in place.
# Does not touch MCP servers, plugins, handoff or memory hooks, statusLine, Desktop Commander's
# own config folders, or the PowerShell profile.
param(
    [switch]$WhatIf,
    [string]$UserHome,
    [string]$CloneRoot,
    [string]$StateDir
)
$ErrorActionPreference = 'Stop'
if (-not $UserHome) { $UserHome = $env:USERPROFILE }
if (-not $UserHome) { $UserHome = $HOME }
$UserHome = [IO.Path]::GetFullPath($UserHome).TrimEnd('\')
if (-not $CloneRoot) { $CloneRoot = $PSScriptRoot }
$CloneRoot = [IO.Path]::GetFullPath($CloneRoot).TrimEnd('\')
if (-not $StateDir) {
    $local = $env:LOCALAPPDATA
    if (-not $local) { $local = Join-Path $UserHome 'AppData\Local' }
    $StateDir = Join-Path $local 'Workstation'
}
$StateDir = [IO.Path]::GetFullPath($StateDir).TrimEnd('\')
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Archive = Join-Path $StateDir ("backups\cleanup-legacy-$Stamp")
$PrMergeRule = 'Merging pull requests in Daniel''s own GitHub repos (github.com/living-relation/*) is allowed without the user typing an explicit merge instruction, as long as the PR''s required checks have passed or are queued via gh pr merge --auto (via gh pr merge or the GitHub MCP merge tool). This does NOT allow --admin, bypassing branch protection or required checks, force-pushing, --no-verify, or deleting anything other than the merged PR''s own head branch.'

function Say([string]$Msg) { Write-Host $Msg }
function Hash-File([string]$Path) {
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLower() }
    catch { return $null }
}
function Get-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

$hashes = New-Object System.Collections.Generic.List[string]
function Add-TreeHashes([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    $files = @()
    if ($item.PSIsContainer) { $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue) }
    else { $files = @($item) }
    foreach ($f in $files) {
        $hash = Hash-File $f.FullName
        if (-not $hash) { Say "  skipped hash (file in use): $($f.FullName)"; continue }
        $hashes.Add(("{0}  {1}" -f $hash, $f.FullName))
    }
}

Say "cleanup-legacy"
Say "  clone: $CloneRoot"
Say "  state: $StateDir"
if ($WhatIf) { Say '  mode: WhatIf (no changes)' }

# 1. Stop the old local web server from this clone only. Never the phone remote.
# Windows PowerShell 5.1: Join-Path takes only two path arguments.
$dashScript = Join-Path $CloneRoot 'workstation\dashboard\server.py'
Say 'stop old local web server (this clone only)'
$dashProcs = $null
if ($env:WORKSTATION_FAKE_PROCS) {
    if ($env:WORKSTATION_FAKE_PROCS -eq 'none') { $dashProcs = @() }
    else { try { $parsed = $env:WORKSTATION_FAKE_PROCS | ConvertFrom-Json; $dashProcs = @($parsed | ForEach-Object { $_ }) } catch { $dashProcs = @() } }
} elseif (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
    $dashProcs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
}
$dashHits = @()
if ($null -ne $dashProcs) {
    $dashHits = @($dashProcs | Where-Object { "$($_.CommandLine)" -like "*$dashScript*" })
}
if ($null -eq $dashProcs) { Say '  process list not available; skipped' }
elseif (-not $dashHits.Count) { Say '  not running' }
else {
    foreach ($p in $dashHits) {
        if ($WhatIf) { Say "  WOULD stop pid $($p.ProcessId)"; continue }
        Say "  stopping pid $($p.ProcessId)"
        if (-not $env:WORKSTATION_FAKE_PROCS) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    }
}

# 2. Shortcut links this clone generated.
$linkRoot = Join-Path $CloneRoot 'shortcuts'
Say "shortcut links under $linkRoot"
$lnks = @()
if (Test-Path -LiteralPath $linkRoot) { $lnks = @(Get-ChildItem -LiteralPath $linkRoot -Recurse -Filter *.lnk -File -Force -ErrorAction SilentlyContinue) }
foreach ($l in $lnks) { Add-TreeHashes $l.FullName }
if ($WhatIf) { Say ("  WOULD archive {0} link file(s)" -f $lnks.Count) }
elseif ($lnks.Count) {
    New-Item -ItemType Directory -Path (Join-Path $Archive 'shortcuts') -Force | Out-Null
    foreach ($l in $lnks) {
        $dest = Join-Path (Join-Path $Archive 'shortcuts') $l.Name
        Move-Item -LiteralPath $l.FullName -Destination $dest -Force
        Say "  archived $($l.FullName)"
    }
} else { Say '  none' }

# 3. Tailscale serve, only when it points at 127.0.0.1:8791 and nothing else local.
Say 'tailscale serve'
$ts = Get-Command tailscale -ErrorAction SilentlyContinue
if (-not $ts) { Say '  tailscale not installed; left as is' }
else {
    $st = ''
    try { $st = (& tailscale serve status 2>&1 | Out-String) } catch { $st = '' }
    if ($st -notmatch '127\.0\.0\.1:8791') { Say '  does not point at 127.0.0.1:8791; left as is' }
    elseif ($st -match '127\.0\.0\.1:(?!8791\b)\d+') { Say '  also points at another local port; left as is' }
    elseif ($WhatIf) { Say '  WOULD turn serve off (it points at 127.0.0.1:8791 only)' }
    else {
        & tailscale serve reset
        Say '  serve turned off'
    }
}

# 4. Firewall rule. Admin only. Skip with a message otherwise.
Say 'firewall rule'
if (-not (Get-IsAdmin)) { Say "  skipped 'Workstation dashboard tailnet' (this window is not admin)" }
elseif (-not (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue)) { Say '  firewall cmdlets not available; skipped' }
else {
    $rule = Get-NetFirewallRule -DisplayName 'Workstation dashboard tailnet' -ErrorAction SilentlyContinue
    if (-not $rule) { Say '  rule not present' }
    elseif ($WhatIf) { Say "  WOULD remove firewall rule 'Workstation dashboard tailnet'" }
    else {
        Remove-NetFirewallRule -DisplayName 'Workstation dashboard tailnet' -ErrorAction Stop
        Say '  removed firewall rule'
    }
}

# 5. Registry key for the old session tracker.
Say 'registry'
$reg = 'HKCU:\Software\Workstation\Tracker'
if (-not (Test-Path -LiteralPath 'HKCU:\') -and -not (Get-PSDrive -Name HKCU -ErrorAction SilentlyContinue)) { Say '  HKCU not available; skipped' }
elseif (-not (Test-Path -LiteralPath $reg)) { Say '  key not present' }
elseif ($WhatIf) { Say "  WOULD delete $reg" }
else { Remove-Item -LiteralPath $reg -Recurse -Force; Say "  deleted $reg" }

# 6. Archive old runtime data. Never the phone-remote state folder.
$moves = @(
    (Join-Path $StateDir 'dashboard'),
    (Join-Path $StateDir 'tracker'),
    (Join-Path $StateDir 'cursor-worker'),
    (Join-Path $StateDir 'toggles.json'),
    (Join-Path $StateDir 'claude-remote-control.json')
)
Say 'archive old runtime files'
foreach ($p in $moves) {
    if (-not (Test-Path -LiteralPath $p)) { Say "  absent $p"; continue }
    if ((Split-Path -Leaf $p) -eq 'cursor-worker' -and (Test-Path -LiteralPath (Join-Path $p 'instances') -PathType Container)) {
        Say "  left in place (manual Cursor worker): $p"
        continue
    }
    Add-TreeHashes $p
    if ($WhatIf) { Say "  WOULD archive $p"; continue }
    New-Item -ItemType Directory -Path $Archive -Force | Out-Null
    $dest = Join-Path $Archive (Split-Path $p -Leaf)
    Move-Item -LiteralPath $p -Destination $dest -Force
    Say "  archived $p"
}
$dcState = Join-Path $StateDir 'desktop-commander-remote'
if (Test-Path -LiteralPath $dcState) { Say "  left in place (phone remote state): $dcState" }

# 7. Claude settings: one flag and one allow rule. Hooks, statusLine, and other keys stay.
$settingsPath = Join-Path $UserHome '.claude\settings.json'
Say 'Claude settings'
if (-not (Test-Path -LiteralPath $settingsPath)) { Say '  no settings.json' }
else {
    Add-TreeHashes $settingsPath
    $raw = [IO.File]::ReadAllText($settingsPath)
    $s = $raw | ConvertFrom-Json
    $changed = $false
    if ($s.PSObject.Properties['remoteControlAtStartup']) {
        $s.PSObject.Properties.Remove('remoteControlAtStartup')
        $changed = $true
        Say '  remove remoteControlAtStartup'
    }
    if ($s.PSObject.Properties['autoMode'] -and $s.autoMode -and $s.autoMode.PSObject.Properties['allow'] -and $null -ne $s.autoMode.allow) {
        $allow = New-Object System.Collections.Generic.List[string]
        foreach ($e in @($s.autoMode.allow)) { if ($null -ne $e) { [void]$allow.Add([string]$e) } }
        $before = $allow.Count
        for ($i = $allow.Count - 1; $i -ge 0; $i--) { if ($allow[$i] -ceq $PrMergeRule) { $allow.RemoveAt($i) } }
        if ($allow.Count -ne $before) { Say '  remove the living-relation pull-request merge allow rule'; $changed = $true }
        $onlyDefaults = ($allow.Count -eq 0) -or ($allow.Count -eq 1 -and $allow[0] -ceq '$defaults')
        if ($onlyDefaults -and $s.autoMode.PSObject.Properties['allow']) {
            $s.autoMode.PSObject.Properties.Remove('allow')
            Say '  drop autoMode.allow (only the defaults token would remain)'
            $changed = $true
        } elseif ($allow.Count -ne $before) {
            $s.autoMode.allow = [string[]]$allow.ToArray()
        }
    }
    if (-not $changed) { Say '  settings already clean' }
    elseif ($WhatIf) { Say '  WOULD update settings.json' }
    else {
        New-Item -ItemType Directory -Path $Archive -Force | Out-Null
        Copy-Item -LiteralPath $settingsPath -Destination (Join-Path $Archive 'settings.json') -Force
        $nl = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
        $json = ($s | ConvertTo-Json -Depth 20) + $nl
        [IO.File]::WriteAllText($settingsPath, $json)
        Say '  updated settings.json (hooks and statusLine left as they were)'
    }
}

if ($hashes.Count -and -not $WhatIf) {
    New-Item -ItemType Directory -Path $Archive -Force | Out-Null
    [IO.File]::WriteAllLines((Join-Path $Archive 'HASHES.txt'), [string[]]$hashes.ToArray())
    Say "hashes: $(Join-Path $Archive 'HASHES.txt')"
} elseif ($WhatIf) { Say '  WOULD write HASHES.txt in the backup folder before moving anything' }
Say 'done'
exit 0
