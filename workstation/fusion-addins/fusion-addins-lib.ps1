#Requires -Version 5.1
# Fusion add-in clone update. Dot-source this file; it does not run an update by itself.
# Windows PowerShell 5.1 compatible. ASCII-only.
# Discovers directory junctions (and directory symlinks) in the Fusion AddIns folder,
# resolves each target to its git repo root, and fast-forwards only when the tree is
# clean, the branch is the remote default, and an upstream exists. Never discards
# local work. Untracked files stay, including a user_scripts folder. Does not start
# or stop Fusion.

function Get-FusionAddinTaskName { return 'Workstation-UpdateFusionAddins' }

function Get-FusionAddinLogDir {
    if ($env:WORKSTATION_FUSION_LOG_DIR) { return $env:WORKSTATION_FUSION_LOG_DIR }
    if (-not $env:LOCALAPPDATA) { return $null }
    return (Join-Path (Join-Path $env:LOCALAPPDATA 'Workstation') 'logs')
}

function Get-FusionAddInsFolder {
    if ($env:WORKSTATION_FUSION_ADDINS) { return $env:WORKSTATION_FUSION_ADDINS }
    if (-not $env:APPDATA) { return $null }
    return (Join-Path $env:APPDATA 'Autodesk\Autodesk Fusion 360\API\AddIns')
}

function ConvertTo-AddInDisplayName([string]$Name) {
    if (-not $Name) { return 'add-in' }
    $s = [regex]::Replace($Name, '([a-z0-9])([A-Z])', '$1 $2')
    $s = [regex]::Replace($s, '([A-Z]+)([A-Z][a-z])', '$1 $2')
    $words = @($s -split '\s+' | Where-Object { $_ })
    $out = foreach ($w in $words) {
        if ($w -match '^[A-Za-z]{1,3}$') { $w.ToUpper() } else { $w }
    }
    return ($out -join ' ')
}

function Get-FusionRepoPlan {
    param(
        [bool]$Dirty,
        [string]$Branch,
        [string]$DefaultBranch,
        [bool]$HasUpstream,
        [int]$Ahead = 0,
        [int]$Behind = 0,
        [bool]$Counted = $false
    )
    if ($Dirty) { return @{ Action = 'skip'; Reason = 'dirty' } }
    if (-not $DefaultBranch) { return @{ Action = 'skip'; Reason = 'default-branch-unknown' } }
    if ($Branch -ne $DefaultBranch) { return @{ Action = 'skip'; Reason = 'not-default-branch' } }
    if (-not $HasUpstream) { return @{ Action = 'skip'; Reason = 'no-upstream' } }
    if (-not $Counted) { return @{ Action = 'fetch'; Reason = 'eligible' } }
    if ($Ahead -gt 0 -and $Behind -gt 0) { return @{ Action = 'skip'; Reason = 'diverged' } }
    if ($Behind -gt 0 -and $Ahead -eq 0) { return @{ Action = 'pull'; Reason = 'behind' } }
    if ($Ahead -gt 0) { return @{ Action = 'none'; Reason = 'ahead' } }
    return @{ Action = 'none'; Reason = 'not-behind' }
}

function Write-FusionLine([string]$Message) {
    $line = '{0} {1}' -f (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'), $Message
    Write-Host $line
    $dir = Get-FusionAddinLogDir
    if (-not $dir) { return }
    try {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $path = Join-Path $dir 'fusion-addins-update.log'
        [IO.File]::AppendAllText($path, $line + "`r`n")
    } catch { }
}

function Save-FusionLast {
    param([int]$Code, [string]$Note, $Repos, [string[]]$Updated)
    $dir = Get-FusionAddinLogDir
    if (-not $dir) { return }
    try {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $path = Join-Path $dir 'fusion-addins-last.json'
        $repoCopy = @()
        foreach ($row in @($Repos)) { if ($null -ne $row) { $repoCopy += $row } }
        $nameCopy = @()
        foreach ($name in @($Updated)) { if ($name) { $nameCopy += [string]$name } }
        $obj = [pscustomobject]@{
            time     = (Get-Date).ToUniversalTime().ToString('o')
            exitCode = $Code
            note     = $Note
            updated  = $nameCopy
            repos    = $repoCopy
        }
        $json = ($obj | ConvertTo-Json -Depth 6) + "`n"
        [IO.File]::WriteAllText($path, $json, (New-Object Text.UTF8Encoding $false))
    } catch { }
}

function Read-FusionLast {
    $dir = Get-FusionAddinLogDir
    if (-not $dir) { return $null }
    $path = Join-Path $dir 'fusion-addins-last.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Get-FusionLinkTarget([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $null }
    $t = $null
    if ($item.Target) { $t = [string]@($item.Target)[0] }
    if (-not $t -and $item.PSObject.Properties['LinkTarget']) { $t = [string]$item.LinkTarget }
    if (-not $t) { return $null }
    if ($t.StartsWith('\\?\')) { $t = $t.Substring(4) }
    if ($t.StartsWith('\??\')) { $t = $t.Substring(4) }
    if (-not [IO.Path]::IsPathRooted($t)) {
        $t = Join-Path (Split-Path -Parent $Path) $t
    }
    try { return [IO.Path]::GetFullPath($t) } catch { return $t }
}

function Get-FusionAddInLinks([string]$Folder) {
    $found = @()
    $items = @(Get-ChildItem -LiteralPath $Folder -Force -ErrorAction SilentlyContinue)
    foreach ($item in $items) {
        if (-not $item.PSIsContainer) { continue }
        $kind = [string]$item.LinkType
        $reparse = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
        if ($kind -ne 'Junction' -and $kind -ne 'SymbolicLink' -and -not $reparse) { continue }
        $target = Get-FusionLinkTarget $item.FullName
        if (-not $target) { continue }
        $found += [pscustomobject]@{ Name = [string]$item.Name; Target = $target }
    }
    return @($found)
}

function Get-GitSubcommand([string[]]$GitArgs) {
    $i = 0
    while ($i -lt $GitArgs.Count) {
        $a = [string]$GitArgs[$i]
        if ($a -eq '-c' -or $a -eq '-C') { $i += 2; continue }
        if ($a.StartsWith('-')) { $i += 1; continue }
        return $a
    }
    return ''
}

function Invoke-FusionGit {
    param([string]$Root, [string[]]$GitArgs)
    $sub = Get-GitSubcommand $GitArgs
    $allowed = @('status', 'rev-parse', 'symbolic-ref', 'rev-list', 'fetch', 'pull')
    if ($allowed -notcontains $sub) { throw "refusing git $sub" }
    $banned = @('reset', 'stash', 'clean', 'push', 'rebase', 'checkout', 'switch', 'restore', 'commit', 'merge', '--hard', '--force', '-f', '--prune', '--autostash')
    foreach ($a in @($GitArgs)) {
        if ($banned -contains ([string]$a)) { throw "refusing git argument $a" }
    }
    if ($sub -eq 'pull') {
        if (@($GitArgs) -notcontains '--ff-only') { throw 'refusing pull without --ff-only' }
    }
    if ($sub -eq 'fetch' -or $sub -eq 'pull') {
        $i = 0
        while ($i -lt $GitArgs.Count) {
            if ([string]$GitArgs[$i] -eq '-c') {
                $val = [string]$GitArgs[$i + 1]
                if (@('pull.rebase=false', 'rebase.autoStash=false') -notcontains $val) { throw "refusing git -c $val" }
                $i += 2
                continue
            }
            $i += 1
        }
    }
    $out = & git -C $Root @GitArgs 2>&1
    $code = $LASTEXITCODE
    $text = (@($out) | ForEach-Object { "$_" }) -join "`n"
    return @{ Code = $code; Out = $text }
}

function Test-FusionRepoDirty([string]$Root) {
    $r = Invoke-FusionGit -Root $Root -GitArgs @('status', '--porcelain', '--untracked-files=normal')
    if ($r.Code -ne 0) { return $true }
    foreach ($line in @($r.Out -split "`n")) {
        if (-not $line) { continue }
        if ($line.StartsWith('??')) { continue }
        if ($line.StartsWith('!!')) { continue }
        return $true
    }
    return $false
}

function Get-FusionDefaultBranch([string]$Root) {
    $r = Invoke-FusionGit -Root $Root -GitArgs @('symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD')
    if ($r.Code -ne 0) { return $null }
    $sym = $r.Out.Trim()
    if (-not $sym) { return $null }
    $i = $sym.IndexOf('/')
    if ($i -lt 0 -or $i -ge ($sym.Length - 1)) { return $null }
    return $sym.Substring($i + 1)
}

function Get-FusionRepoGitState([string]$Root) {
    $dirty = Test-FusionRepoDirty $Root
    $branchR = Invoke-FusionGit -Root $Root -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD')
    $branch = ''
    if ($branchR.Code -eq 0) { $branch = $branchR.Out.Trim() }
    $default = Get-FusionDefaultBranch $Root
    $up = Invoke-FusionGit -Root $Root -GitArgs @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
    $has = ($up.Code -eq 0 -and [bool]$up.Out.Trim())
    $remote = $null
    if ($has) {
        $u = $up.Out.Trim()
        $slash = $u.IndexOf('/')
        if ($slash -gt 0) { $remote = $u.Substring(0, $slash) }
    }
    return @{ Dirty = [bool]$dirty; Branch = $branch; DefaultBranch = $default; HasUpstream = [bool]$has; UpstreamRemote = $remote }
}

function Get-FusionAheadBehind([string]$Root) {
    $r = Invoke-FusionGit -Root $Root -GitArgs @('rev-list', '--left-right', '--count', 'HEAD...@{u}')
    if ($r.Code -ne 0) { return $null }
    $parts = @($r.Out.Trim() -split '\s+' | Where-Object { $_ })
    if ($parts.Count -lt 2) { return $null }
    return @{ Ahead = [int]$parts[0]; Behind = [int]$parts[1] }
}

function Get-GitTopLevel([string]$Path) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $out = & git -C $Path rev-parse --show-toplevel 2>&1
    if ($LASTEXITCODE -ne 0) { return $null }
    $text = (@($out) | ForEach-Object { "$_" }) -join "`n"
    $text = $text.Trim()
    if (-not $text) { return $null }
    return $text
}

function Update-FusionOneRepo {
    param([string]$Root, [string[]]$Names)
    $label = (@($Names) -join ', ')
    if (-not $label) { $label = $Root }
    $state = Get-FusionRepoGitState $Root
    $plan = Get-FusionRepoPlan -Dirty $state.Dirty -Branch $state.Branch -DefaultBranch $state.DefaultBranch -HasUpstream $state.HasUpstream
    $ahead = 0
    $behind = 0
    if ($plan.Action -ne 'fetch') {
        Write-FusionLine ("skip {0}: {1}" -f $label, $plan.Reason)
        return [pscustomobject]@{ name = $label; root = $Root; action = 'skip'; reason = $plan.Reason; ahead = 0; behind = 0; updated = $false; error = $false }
    }
    $remote = [string]$state.UpstreamRemote
    if ($remote -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        Write-FusionLine ("error {0}: upstream remote is not a plain name" -f $label)
        return [pscustomobject]@{ name = $label; root = $Root; action = 'error'; reason = 'fetch-failed'; ahead = 0; behind = 0; updated = $false; error = $true }
    }
    $fetch = Invoke-FusionGit -Root $Root -GitArgs @('fetch', '--quiet', $remote)
    if ($fetch.Code -ne 0) {
        Write-FusionLine ("error {0}: fetch failed" -f $label)
        return [pscustomobject]@{ name = $label; root = $Root; action = 'error'; reason = 'fetch-failed'; ahead = 0; behind = 0; updated = $false; error = $true }
    }
    $counts = Get-FusionAheadBehind $Root
    if (-not $counts) {
        Write-FusionLine ("error {0}: could not count commits against upstream" -f $label)
        return [pscustomobject]@{ name = $label; root = $Root; action = 'error'; reason = 'fetch-failed'; ahead = 0; behind = 0; updated = $false; error = $true }
    }
    $ahead = [int]$counts.Ahead
    $behind = [int]$counts.Behind
    $plan2 = Get-FusionRepoPlan -Dirty $false -Branch $state.Branch -DefaultBranch $state.DefaultBranch -HasUpstream $true -Ahead $ahead -Behind $behind -Counted:$true
    if ($plan2.Action -eq 'skip') {
        Write-FusionLine ("skip {0}: {1} (ahead {2}, behind {3})" -f $label, $plan2.Reason, $ahead, $behind)
        return [pscustomobject]@{ name = $label; root = $Root; action = 'skip'; reason = $plan2.Reason; ahead = $ahead; behind = $behind; updated = $false; error = $false }
    }
    if ($plan2.Action -ne 'pull') {
        Write-FusionLine ("leave {0}: {1} (ahead {2}, behind {3})" -f $label, $plan2.Reason, $ahead, $behind)
        return [pscustomobject]@{ name = $label; root = $Root; action = 'none'; reason = $plan2.Reason; ahead = $ahead; behind = $behind; updated = $false; error = $false }
    }
    $beforeR = Invoke-FusionGit -Root $Root -GitArgs @('rev-parse', 'HEAD')
    $before = $beforeR.Out.Trim()
    $pull = Invoke-FusionGit -Root $Root -GitArgs @('-c', 'pull.rebase=false', '-c', 'rebase.autoStash=false', 'pull', '--ff-only', '--quiet')
    if ($pull.Code -ne 0) {
        Write-FusionLine ("error {0}: fast-forward pull failed (behind {1})" -f $label, $behind)
        return [pscustomobject]@{ name = $label; root = $Root; action = 'error'; reason = 'pull-failed'; ahead = $ahead; behind = $behind; updated = $false; error = $true }
    }
    $afterR = Invoke-FusionGit -Root $Root -GitArgs @('rev-parse', 'HEAD')
    $after = $afterR.Out.Trim()
    $did = ($before -and $after -and $before -ne $after)
    if ($did) { Write-FusionLine ("updated {0}" -f $label) }
    else { Write-FusionLine ("leave {0}: not-behind" -f $label) }
    return [pscustomobject]@{ name = $label; root = $Root; action = $(if ($did) { 'updated' } else { 'none' }); reason = $(if ($did) { 'behind' } else { 'not-behind' }); ahead = 0; behind = 0; updated = [bool]$did; error = $false }
}

function Show-FusionWinRtToast([string]$Text) {
    $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
    $safe = [System.Security.SecurityElement]::Escape($Text)
    $xmlText = '<toast><visual><binding template="ToastGeneric"><text>' + $safe + '</text></binding></visual></toast>'
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($xmlText)
    $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
    return $true
}

function Show-FusionBalloon([string]$Text) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $n = New-Object System.Windows.Forms.NotifyIcon
    $n.Icon = [System.Drawing.SystemIcons]::Information
    $n.Visible = $true
    $n.ShowBalloonTip(8000, 'Fusion add-ins', $Text, [System.Windows.Forms.ToolTipIcon]::Info)
    Start-Sleep -Seconds 3
    $n.Dispose()
}

function Show-FusionAddinToast {
    param([string[]]$Names)
    $list = @($Names | Where-Object { $_ } | Select-Object -Unique | Sort-Object)
    if ($list.Count -eq 0) { return }
    $text = 'Fusion add-ins updated: ' + ($list -join ', ') + '. Restart Fusion to load them.'
    if ($env:WORKSTATION_FUSION_TOAST_SINK) {
        $parent = Split-Path -Parent $env:WORKSTATION_FUSION_TOAST_SINK
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [IO.File]::WriteAllText($env:WORKSTATION_FUSION_TOAST_SINK, $text, (New-Object Text.UTF8Encoding $false))
        return
    }
    if ($env:OS -ne 'Windows_NT') { return }
    $shown = $false
    try { $shown = [bool](Show-FusionWinRtToast $text) } catch { $shown = $false }
    if (-not $shown) {
        try { Show-FusionBalloon $text } catch { Write-FusionLine ('toast failed: ' + $_.Exception.Message) }
    }
}

function Invoke-FusionAddinUpdate {
    if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
        $PSNativeCommandUseErrorActionPreference = $false
    }
    $env:GIT_TERMINAL_PROMPT = '0'
    $env:GCM_INTERACTIVE = 'Never'
    $updated = New-Object System.Collections.ArrayList
    $rows = New-Object System.Collections.ArrayList
    $exit = 0
    $note = ''
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $note = 'git not found; nothing to do'
        Write-FusionLine $note
        Save-FusionLast -Code 0 -Note $note -Repos @() -Updated @()
        return 0
    }
    $folder = Get-FusionAddInsFolder
    if (-not $folder -or -not (Test-Path -LiteralPath $folder -PathType Container)) {
        $note = 'AddIns folder not found; nothing to do'
        Write-FusionLine $note
        Save-FusionLast -Code 0 -Note $note -Repos @() -Updated @()
        return 0
    }
    $links = @(Get-FusionAddInLinks $folder)
    $groups = @{}
    foreach ($link in @($links)) {
        $display = ConvertTo-AddInDisplayName $link.Name
        if (-not (Test-Path -LiteralPath $link.Target)) {
            Write-FusionLine ("skip {0}: target missing" -f $display)
            [void]$rows.Add([pscustomobject]@{ name = $display; root = $link.Target; action = 'skip'; reason = 'target-missing'; ahead = 0; behind = 0 })
            continue
        }
        $top = Get-GitTopLevel $link.Target
        if (-not $top) {
            Write-FusionLine ("skip {0}: not a git work tree" -f $display)
            [void]$rows.Add([pscustomobject]@{ name = $display; root = $link.Target; action = 'skip'; reason = 'not-a-git-repo'; ahead = 0; behind = 0 })
            continue
        }
        $key = $top
        if ($env:OS -eq 'Windows_NT') { $key = $top.ToLower() }
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = @{ Root = $top; Names = (New-Object System.Collections.ArrayList) }
        }
        if (-not $groups[$key].Names.Contains($display)) { [void]$groups[$key].Names.Add($display) }
    }
    foreach ($key in @($groups.Keys | Sort-Object)) {
        $g = $groups[$key]
        $names = @($g.Names | Sort-Object)
        try {
            $row = Update-FusionOneRepo -Root $g.Root -Names $names
        } catch {
            Write-FusionLine ("error {0}: {1}" -f ($names -join ', '), $_.Exception.Message)
            $row = [pscustomobject]@{ name = ($names -join ', '); root = $g.Root; action = 'error'; reason = 'fetch-failed'; ahead = 0; behind = 0; updated = $false; error = $true }
        }
        [void]$rows.Add([pscustomobject]@{ name = [string]$row.name; root = [string]$row.root; action = [string]$row.action; reason = [string]$row.reason; ahead = [int]$row.ahead; behind = [int]$row.behind })
        if ($row.error) { $exit = 1 }
        if ($row.updated) {
            foreach ($n in @($names)) { [void]$updated.Add($n) }
        }
    }
    $note = ('repos {0}; updated {1}' -f $rows.Count, $updated.Count)
    Write-FusionLine $note
    if ($updated.Count -gt 0) { Show-FusionAddinToast -Names @($updated) }
    Save-FusionLast -Code $exit -Note $note -Repos @($rows) -Updated @($updated)
    return $exit
}

function Get-FusionAddinTaskStatus {
    $name = Get-FusionAddinTaskName
    if ($env:WORKSTATION_FUSION_FAKE_TASK) {
        if ($env:WORKSTATION_FUSION_FAKE_TASK -eq 'missing') {
            return @{ Present = $false; LastResult = $null; LastRun = $null; Unavailable = $false }
        }
        try {
            $j = $env:WORKSTATION_FUSION_FAKE_TASK | ConvertFrom-Json
            $code = $null
            if ($j.PSObject.Properties['lastResult'] -and $null -ne $j.lastResult) { $code = [int]$j.lastResult }
            $present = $false
            if ($j.PSObject.Properties['present']) { $present = [bool]$j.present }
            return @{ Present = $present; LastResult = $code; LastRun = [string]$j.lastRun; Unavailable = $false }
        } catch {
            return @{ Present = $false; LastResult = $null; LastRun = $null; Unavailable = $false }
        }
    }
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        return @{ Present = $false; LastResult = $null; LastRun = $null; Unavailable = $true }
    }
    $task = $null
    try { $task = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue } catch { $task = $null }
    if (-not $task) { return @{ Present = $false; LastResult = $null; LastRun = $null; Unavailable = $false } }
    $info = $null
    try { $info = Get-ScheduledTaskInfo -TaskName $name -ErrorAction SilentlyContinue } catch { $info = $null }
    $code = $null
    $when = $null
    if ($info) {
        try { $code = [int]$info.LastTaskResult } catch { $code = $null }
        try { $when = [string]$info.LastRunTime } catch { $when = $null }
    }
    return @{ Present = $true; LastResult = $code; LastRun = $when; Unavailable = $false }
}

function Get-FusionAddinHealthLines {
    $lines = New-Object System.Collections.ArrayList
    $task = Get-FusionAddinTaskStatus
    if ($task.Present) {
        $text = 'Fusion add-in updater starts on its own: scheduled task ' + (Get-FusionAddinTaskName) + '. The updater is manual only; install.ps1 or uninstall.ps1 removes the task.'
        [void]$lines.Add([pscustomobject]@{ Level = 'WARN'; Text = $text })
    } else {
        [void]$lines.Add([pscustomobject]@{ Level = 'OK'; Text = 'Fusion add-in updater is manual only (Update Fusion add-ins shortcut); no scheduled task' })
    }
    $last = Read-FusionLast
    $warned = $false
    $repoList = @()
    if ($last -and $last.PSObject.Properties['repos'] -and $null -ne $last.repos) { $repoList = @($last.repos) }
    foreach ($r in @($repoList)) {
        if (-not $r) { continue }
        $nm = [string]$r.name
        if (-not $nm) { $nm = [string]$r.root }
        $reason = [string]$r.reason
        $action = [string]$r.action
        $behind = 0
        try { $behind = [int]$r.behind } catch { $behind = 0 }
        if ($reason -eq 'dirty') {
            [void]$lines.Add([pscustomobject]@{ Level = 'WARN'; Text = "Fusion add-in repo skipped (dirty): $nm" })
            $warned = $true
        } elseif ($reason -eq 'diverged' -or ($action -eq 'error' -and $behind -gt 0)) {
            [void]$lines.Add([pscustomobject]@{ Level = 'WARN'; Text = "Fusion add-in repo left behind: $nm" })
            $warned = $true
        } elseif ($reason -eq 'not-default-branch') {
            [void]$lines.Add([pscustomobject]@{ Level = 'OK'; Text = "Fusion add-in repo skipped (not on the default branch): $nm" })
        } elseif ($reason -eq 'no-upstream') {
            [void]$lines.Add([pscustomobject]@{ Level = 'OK'; Text = "Fusion add-in repo skipped (no upstream): $nm" })
        }
    }
    if (-not $warned) {
        [void]$lines.Add([pscustomobject]@{ Level = 'OK'; Text = 'No Fusion add-in repo was skipped as dirty or left behind' })
    }
    $out = @()
    foreach ($line in $lines) { $out += $line }
    return $out
}

function Unregister-FusionAddinTask {
    param([switch]$WhatIf)
    $name = Get-FusionAddinTaskName
    if ($WhatIf) {
        return [pscustomobject]@{ Ok = $true; Missing = $false; Message = "WOULD remove per-user task $name (no admin)" }
    }
    if (-not (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Ok = $false; Missing = $false; Message = "scheduled tasks are not available in this session; task $name was left as it is" }
    }
    $existing = $null
    try { $existing = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue } catch { $existing = $null }
    if (-not $existing) {
        return [pscustomobject]@{ Ok = $true; Missing = $true; Message = "task $name was not registered" }
    }
    $act = (@($existing.Actions) | ForEach-Object { ("$($_.Execute) $($_.Arguments)").Trim() }) -join ' '
    if ($act -notmatch 'update-fusion-addins\.ps1') {
        return [pscustomobject]@{ Ok = $false; Missing = $false; Message = "task $name does not run update-fusion-addins.ps1; left alone" }
    }
    Unregister-ScheduledTask -TaskName $name -Confirm:$false
    return [pscustomobject]@{ Ok = $true; Missing = $false; Message = "removed per-user task $name" }
}
