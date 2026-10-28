#Requires -Version 5.1
# Helpers for the per-project Claude remote-control shortcuts.
# No live claude calls. Windows PowerShell 5.1. Keep this file ASCII-only.

# Every directory directly inside active\ is a project, git repo or not.
# A name that starts with a dot is tool metadata (.cursor), not a project.
function Get-RcProjectFolders([string]$ActiveDir) {
    if (-not $ActiveDir -or -not (Test-Path -LiteralPath $ActiveDir -PathType Container)) { return @() }
    @(Get-ChildItem -LiteralPath $ActiveDir -Force -Directory | Where-Object { $_.Name -and $_.Name -notlike '.*' } | Sort-Object Name)
}

function Get-RcSafeFilePart([string]$FolderName) {
    $part = ($FolderName -replace '[<>:"/\\|?*]', '-').Trim().Trim('.')
    if (-not $part) { $part = 'project' }
    return $part
}

# One token, stable across launches. --bg ignores --session-id and keeps --name.
function Get-RcSessionName([string]$FolderName) {
    $slug = ($FolderName -replace '[^\w.-]', '-').Trim('-')
    if (-not $slug) { $slug = 'project' }
    return "rc-$slug"
}

function Get-RcOpenLinkName([string]$FolderName) { "RC $(Get-RcSafeFilePart $FolderName).lnk" }
function Get-RcCloseLinkName([string]$FolderName) { "Close RC $(Get-RcSafeFilePart $FolderName).lnk" }

function Normalize-RcPath([string]$Path) {
    if (-not $Path) { return '' }
    $text = "$Path".Trim()
    try { return ([IO.Path]::GetFullPath($text)).TrimEnd('\', '/') } catch { return $text.TrimEnd('\', '/') }
}

# Defaults from this script's place in the clone, plus workstation.json when it exists.
# Pass ConfigPath '' to skip the config file (tests).
function Get-RcDefaults([string]$ScriptRoot, [string]$ConfigPath) {
    $toolkit = Split-Path -Parent $ScriptRoot
    $package = Split-Path -Parent $toolkit
    if ($null -eq $ConfigPath) { $ConfigPath = Join-Path $env:LOCALAPPDATA 'Workstation\workstation.json' }
    $projects = $null
    if ($ConfigPath -and (Test-Path -LiteralPath $ConfigPath)) {
        try {
            $root = [string](Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json).projectsRoot
            if ($root -and (Test-Path -LiteralPath $root)) { $projects = $root.TrimEnd('\') }
        } catch { }
    }
    if (-not $projects) {
        $up = Split-Path -Parent $package
        if ((Split-Path -Leaf $up) -ieq 'active') { $projects = Split-Path -Parent $up } else { $projects = $up }
        $projects = "$projects".TrimEnd('\')
    }
    return @{
        ActiveDir = [IO.Path]::Combine($projects, 'active')
        LinkDir   = [IO.Path]::Combine($package, 'shortcuts', 'rc')
    }
}

# claude agents --json is an array, or wrapped as { agents: [...] } / { sessions: [...] }.
# Extra text around the JSON is ignored. Windows PowerShell 5.1 returns a JSON array as one
# Object[], and @() around that nests it, so this walks the array in a foreach.
function ConvertFrom-RcAgentsJson([string]$Text) {
    $text = "$Text"
    if (-not $text.Trim()) { return @() }
    $startArr = $text.IndexOf('[')
    $startObj = $text.IndexOf('{')
    if ($startArr -ge 0 -and ($startObj -lt 0 -or $startArr -lt $startObj)) { $json = $text.Substring($startArr) }
    elseif ($startObj -ge 0) { $json = $text.Substring($startObj) }
    else { return @() }
    $end = [Math]::Max($json.LastIndexOf(']'), $json.LastIndexOf('}'))
    if ($end -ge 0) { $json = $json.Substring(0, $end + 1) }
    try { $parsed = $json | ConvertFrom-Json } catch { return @() }
    if ($null -eq $parsed) { return @() }
    $names = @($parsed.PSObject.Properties.Name)
    $items = New-Object System.Collections.Generic.List[object]
    if ($parsed -is [System.Array]) {
        foreach ($item in $parsed) { if ($null -ne $item) { $items.Add($item) } }
    } elseif (($names -contains 'agents') -and $null -ne $parsed.agents -and ($names -notcontains 'cwd')) {
        foreach ($item in $parsed.agents) { if ($null -ne $item) { $items.Add($item) } }
    } elseif (($names -contains 'sessions') -and $null -ne $parsed.sessions -and ($names -notcontains 'cwd')) {
        foreach ($item in $parsed.sessions) { if ($null -ne $item) { $items.Add($item) } }
    } else { $items.Add($parsed) }
    return $items.ToArray()
}

# Sessions for this folder and this shortcut's name. Stopped ones are already gone.
function Select-RcSessions($Sessions, [string]$RepoPath, [string]$SessionName) {
    $want = Normalize-RcPath $RepoPath
    if (-not $want -or -not $SessionName) { return @() }
    @($Sessions | Where-Object {
        $_ -and
        ((Normalize-RcPath "$($_.cwd)") -ieq $want) -and
        ("$($_.name)" -ieq $SessionName) -and
        ("$($_.state)" -notin @('stopped', 'done', 'failed'))
    })
}

# The short id `claude stop` takes. agents JSON uses `id`; fall back to sessionId.
function Get-RcStopId($Session) {
    if ($Session -and "$($Session.id)") { return "$($Session.id)".Trim() }
    if ($Session -and "$($Session.sessionId)") { return "$($Session.sessionId)".Trim() }
    return ''
}

# "backgrounded <sep> b4e02f32 <sep> rc-name" from claude --bg. The separator is not a stable character.
function Get-RcBackgroundId([string]$Text) {
    if ("$Text" -match 'backgrounded\s+\S+\s+([0-9a-fA-F]{6,})') { return $Matches[1] }
    return ''
}

# True only for this session's process: --remote-control and --name as its own argument.
# rc-foo does not match rc-foobar. The shared `claude.exe daemon run` does not match.
function Test-RcProcessCommandLine([string]$Cmd, [string]$SessionName) {
    if (-not $Cmd -or -not $SessionName) { return $false }
    if ($Cmd -notmatch '(^|\s)--remote-control(=|\s|$)') { return $false }
    $esc = [regex]::Escape($SessionName)
    return [bool]($Cmd -match "(^|\s)--name(?:=|\s+)$esc(?=\s|$)")
}

function Select-RcProcs($Procs, [string]$SessionName) {
    @($Procs | Where-Object {
        $_ -and $_.Name -in @('claude.exe', 'node.exe') -and (Test-RcProcessCommandLine "$($_.CommandLine)" $SessionName)
    })
}

# Of the matched processes, the ones whose parent is not also matched. taskkill /T on these ends the tree.
function Get-RcKillRoots($Procs) {
    $ids = @($Procs | ForEach-Object { [int]$_.ProcessId })
    @($Procs | Where-Object { $ids -notcontains [int]$_.ParentProcessId })
}

# Write one open link and one close link per project folder. Remove RC links whose folder is gone.
# Leaves any other file in LinkDir alone. Returns a hashtable: Ok, Projects, Created, Updated, Removed, Errors.
function Write-RcShortcuts {
    param(
        [Parameter(Mandatory = $true)][string]$ActiveDir,
        [Parameter(Mandatory = $true)][string]$LinkDir,
        [Parameter(Mandatory = $true)][string]$OpenScript,
        [Parameter(Mandatory = $true)][string]$CloseScript
    )
    $errors = New-Object System.Collections.Generic.List[string]
    $result = @{ Ok = $true; Projects = 0; Created = 0; Updated = 0; Removed = 0; Errors = @() }
    if (-not (Test-Path -LiteralPath $OpenScript -PathType Leaf)) { $errors.Add("missing $OpenScript") }
    if (-not (Test-Path -LiteralPath $CloseScript -PathType Leaf)) { $errors.Add("missing $CloseScript") }
    if (-not (Test-Path -LiteralPath $ActiveDir -PathType Container)) { $errors.Add("project folder not found: $ActiveDir") }
    if ($errors.Count) { $result.Ok = $false; $result.Errors = @($errors); return $result }

    if (-not (Test-Path -LiteralPath $LinkDir)) { New-Item -ItemType Directory -Path $LinkDir -Force | Out-Null }
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $shell32 = Join-Path $env:SystemRoot 'System32\shell32.dll'
    $wsh = New-Object -ComObject WScript.Shell
    $projects = @(Get-RcProjectFolders $ActiveDir)
    $result.Projects = $projects.Count
    $expected = @{}
    foreach ($p in $projects) {
        $pairs = @(
            @{ Link = (Get-RcOpenLinkName $p.Name); Script = $OpenScript; Icon = 137; Desc = "Start Claude remote control in $($p.Name)" },
            @{ Link = (Get-RcCloseLinkName $p.Name); Script = $CloseScript; Icon = 131; Desc = "Stop Claude remote control in $($p.Name)" }
        )
        foreach ($pair in $pairs) {
            $lnkPath = Join-Path $LinkDir $pair.Link
            $expected[$pair.Link.ToLower()] = $true
            $existed = Test-Path -LiteralPath $lnkPath
            try {
                $s = $wsh.CreateShortcut($lnkPath)
                $s.TargetPath = $psExe
                $s.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($pair.Script)`" -Repo `"$($p.FullName)`""
                $s.WorkingDirectory = $p.FullName
                $s.WindowStyle = 1
                $s.Description = $pair.Desc
                $s.IconLocation = "$shell32,$($pair.Icon)"
                $s.Save()
                $check = $wsh.CreateShortcut($lnkPath)
                $leaf = [IO.Path]::GetFileName($pair.Script)
                $ok = ($check.TargetPath -ieq $psExe) -and ($check.Arguments -like "*$leaf*") -and ($check.Arguments -like "*$($p.FullName)*") -and ($check.WorkingDirectory -ieq $p.FullName)
                if (-not $ok) { $errors.Add("read-back failed for $($pair.Link)"); continue }
                if ($existed) { $result.Updated++ } else { $result.Created++ }
            } catch { $errors.Add("$($pair.Link): $($_.Exception.Message)") }
        }
    }
    foreach ($f in @(Get-ChildItem -LiteralPath $LinkDir -Filter *.lnk -File -ErrorAction SilentlyContinue)) {
        if ($expected.ContainsKey($f.Name.ToLower())) { continue }
        if ($f.Name -notmatch '^(Close )?RC .+\.lnk$') { continue }
        Remove-Item -LiteralPath $f.FullName -Force
        $result.Removed++
    }
    if ($errors.Count) { $result.Ok = $false }
    $result.Errors = @($errors)
    return $result
}
