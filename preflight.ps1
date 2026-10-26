<#
.SYNOPSIS
  Read-only check before installing the workstation setup: finds what is already installed, duplicates and conflicts.

.DESCRIPTION
  Never changes anything. The only file it writes is its report:
    preflight-report-<yyyyMMdd-HHmmss>.txt  (in -ReportDir, else %TEMP%; never next to this script,
                                              so it stays out of the repo)
  Each finding is one of:
    OK                 nothing to do, or install.ps1 will add it
    ALREADY-INSTALLED  the same thing is already in place; install.ps1 skips it
    WARN               look at it; install.ps1 continues
    CONFLICT           duplicate or retired item; install.ps1 stops until it is resolved
                       (or it is run with -AcceptConflicts after you reviewed the report)
  install.ps1 runs this first, also with -WhatIf. Run it alone:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\preflight.ps1 [-ProjectsRoot <path>]
  Exit code: 0 = no conflicts, 2 = conflicts found.

.PARAMETER ProjectsRoot   Projects root. Default: %USERPROFILE%\Projects
.PARAMETER UserHome       Testing only: use this folder instead of %USERPROFILE% (same as install.ps1 -UserHome).
.PARAMETER StartupFolder  Testing only: user Startup folder to check. Default: the real one (test mode: under -UserHome).
.PARAMETER ReportDir      Folder for the report file.
.PARAMETER PassThru       Return the results as an object (used by install.ps1).
#>
[CmdletBinding()]
param(
  [string]$ProjectsRoot,
  [string]$UserHome,
  [string]$StartupFolder,
  [string]$ReportDir,
  [switch]$PassThru
)
$ErrorActionPreference = 'Continue'
$PkgRoot = $PSScriptRoot
if (-not $PkgRoot) { $PkgRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
# Toolkit folder and script names come from ONE place: toolkit.psd1 next to this script.
$ToolkitDef = Join-Path $PkgRoot 'toolkit.psd1'
if (-not (Test-Path -LiteralPath $ToolkitDef)) { Write-Host "toolkit.psd1 not found next to this script: $ToolkitDef" -ForegroundColor Red; exit 1 }
$TK = Import-PowerShellDataFile -LiteralPath $ToolkitDef

# ---------------------------------------------------------------- paths (same rules as install.ps1)
$realHome = $env:USERPROFILE
if (-not $realHome) { $realHome = $HOME }
$testMode = [bool]$UserHome
if (-not $UserHome) { $UserHome = $realHome }
$UserHome = [IO.Path]::GetFullPath($UserHome).TrimEnd('\')
if (-not $ProjectsRoot) { $ProjectsRoot = Join-Path $UserHome 'Projects' }
$ProjectsRoot = [IO.Path]::GetFullPath($ProjectsRoot).TrimEnd('\')
if ($testMode) {
  $LocalAppData = Join-Path $UserHome 'AppData\Local'
  $RoamingAppData = Join-Path $UserHome 'AppData\Roaming'
  $DesktopDir = Join-Path $UserHome 'Desktop'
  if (-not $StartupFolder) { $StartupFolder = Join-Path $UserHome 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup' }
} else {
  # Fall back to the standard folders when a variable is missing (some pwsh 7 hosts / remote sessions).
  $LocalAppData = $env:LOCALAPPDATA; if (-not $LocalAppData) { $LocalAppData = Join-Path $UserHome 'AppData\Local' }
  $RoamingAppData = $env:APPDATA; if (-not $RoamingAppData) { $RoamingAppData = Join-Path $UserHome 'AppData\Roaming' }
  $DesktopDir = [Environment]::GetFolderPath('Desktop'); if (-not $DesktopDir) { $DesktopDir = Join-Path $UserHome 'Desktop' }
  if (-not $StartupFolder) { $StartupFolder = [Environment]::GetFolderPath('Startup') }
  if (-not $StartupFolder) { $StartupFolder = Join-Path $RoamingAppData 'Microsoft\Windows\Start Menu\Programs\Startup' }
}
$StartupFolder = [IO.Path]::GetFullPath($StartupFolder).TrimEnd('\')
$CommonStartup = [Environment]::GetFolderPath('CommonStartup')

$ProjectKey = $ProjectsRoot -replace '[^A-Za-z0-9]', '-'
$ClaudeDir  = Join-Path $ProjectsRoot '_claude'
$Store      = Join-Path $ClaudeDir 'Claude Projects\Working Memory\memory'
$CursorNotes = Join-Path $ClaudeDir 'Cursor Notes'   # legacy folder (retired); Cursor now edits $Store
$OldCursorCopy = Join-Path $ClaudeDir 'Cursor Copy of Claude Memory'   # retired frozen mirror (older installs); never a store to merge
# The toolkit runs straight from this package (the workstation repo clone); nothing is copied under <Projects>.
$BridgeDir  = Join-Path $PkgRoot $TK.PackageFolder
# Shortcut folder inside this package (the repo clone); install.ps1 resolves it the same way.
$ScDir      = [IO.Path]::GetFullPath((Join-Path $PkgRoot $TK.ShortcutFolder)).TrimEnd('\')
# Old installed toolkit copies under <Projects> (_bridge, _workstation).
$LegacyDirs = @($TK.LegacyFolders | Where-Object { $_ } | ForEach-Object { Join-Path $ProjectsRoot $_ })
$DotClaude  = Join-Path $UserHome '.claude'
$DotCursor  = Join-Path $UserHome '.cursor'
$LinkPath   = Join-Path $DotClaude "projects\$ProjectKey\memory"
$WmLink     = Join-Path $DotClaude 'working-memory'
$SettingsPath = Join-Path $DotClaude 'settings.json'
$CursorHooksJson = Join-Path $DotCursor 'hooks.json'
$Expected = @{
  'context-guard.ps1'     = (Join-Path $DotClaude 'hooks\context-guard.ps1')
  'memory-link-guard.ps1' = (Join-Path $DotClaude 'hooks\memory-link-guard.ps1')
  'handoff-at-80.py'      = (Join-Path $DotCursor 'hooks\handoff-at-80.py')
}
$ArmedPath = Join-Path $DotCursor 'hooks\state\handoff-at-80\armed'
if ($testMode) { $AutoMemValue = ($LinkPath -replace '\\', '/') } else { $AutoMemValue = "~/.claude/projects/$ProjectKey/memory" }

# Script names this package ships or retired. Used to spot duplicates of our jobs anywhere.
# Toolkit script names are read from the package's toolkit folder (plus legacy names from toolkit.psd1).
$pkgToolkit = Join-Path $PkgRoot $TK.PackageFolder
$toolkitLeaves = @(Get-ChildItem -LiteralPath $pkgToolkit -Recurse -File -Filter *.ps1 -ErrorAction SilentlyContinue | ForEach-Object Name | Where-Object { @('config.ps1', 'install-shortcuts.ps1', 'repair-sqlite.ps1', 'health-check.ps1', 'run-worker.ps1') -notcontains $_ })
$legacyLeaves = @($TK.LegacyScripts | Where-Object { $toolkitLeaves -notcontains $_ })
$OurLeaves = @('memory-link-guard.ps1', 'context-guard.ps1', 'handoff-at-80.py') + $toolkitLeaves + $legacyLeaves | Select-Object -Unique
$OurScriptRx  = '(?i)(^|[\\/"\s])(' + (($OurLeaves | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')'
$RetiredRx    = '(?i)sync-claude-memory-to-cursor|_claude\\run-hidden\.vbs|watch-pull|cursor-worker|run-worker\.ps1|ClaudeCode-?RemoteControl|watcher\.py'
$RetiredNameRx = '(?i)Claude-Memory-To-Cursor-Sync|watch-?pull|cursor-?worker|ClaudeCode-?RemoteControl|Workstation-Watcher'
$SimilarNameRx = '(?i)memory.?sync|sync.?memory|sync-?pull|sync-?push|handoff|context-?guard|remote-?control'
$CursorExeRx  = '(?i)(^|[\\/"\s])cursor\.exe\b'

# ---------------------------------------------------------------- helpers
$Findings = New-Object System.Collections.Generic.List[object]
function Add-Finding([string]$Class, [string]$Area, [string]$Item, [string]$Detail) {
  $Findings.Add([pscustomobject]@{ Class = $Class; Area = $Area; Item = $Item; Detail = $Detail })
}
function Expand-UserPath([string]$P) {
  if (-not $P) { return $null }
  $P = ([Environment]::ExpandEnvironmentVariables($P.Trim().Trim('"')) -replace '/', '\') -replace '^\\\?\?\\', ''
  if ($P -eq '~') { $P = $UserHome } elseif ($P.StartsWith('~\')) { $P = Join-Path $UserHome $P.Substring(2) }
  try { $P = [IO.Path]::GetFullPath($P) } catch { }
  return $P.TrimEnd('\')
}
function Test-Under([string]$Path, [string]$Root) {
  if (-not $Path -or -not $Root) { return $false }
  $p = $Path.TrimEnd('\').ToLower(); $r = $Root.TrimEnd('\').ToLower()
  return ($p -eq $r -or $p.StartsWith($r + '\'))
}
# Full path of the first file in a command line whose leaf is $Leaf (quoted or not); $null if none.
function Get-ScriptPath([string]$Cmd, [string]$Leaf) {
  if (-not $Cmd) { return $null }
  $e = [regex]::Escape($Leaf)
  $m = [regex]::Match($Cmd, '(?i)"([^"]*?' + $e + ')"')
  if (-not $m.Success) { $m = [regex]::Match($Cmd, '(?i)(\S*' + $e + ')') }
  if ($m.Success) { return (Expand-UserPath $m.Groups[1].Value) }
  return $null
}
function Get-ExePath([string]$Cmd) {
  if (-not $Cmd) { return $null }
  $m = [regex]::Match($Cmd, '^\s*"([^"]+)"')
  if (-not $m.Success) { $m = [regex]::Match($Cmd, '(?i)^\s*(.+?\.exe)\b') }
  if ($m.Success) { return (Expand-UserPath $m.Groups[1].Value) }
  return $null
}
function Read-JsonFile([string]$Path) {
  $r = [pscustomobject]@{ Exists = $false; Ok = $false; Obj = $null; Err = $null }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $r }
  $r.Exists = $true
  try {
    $raw = [IO.File]::ReadAllText($Path)
    if ($raw.Trim()) { $r.Obj = $raw | ConvertFrom-Json } else { $r.Obj = New-Object psobject }
    $r.Ok = $true
  } catch { $r.Err = $_.Exception.Message }
  return $r
}
# Claude settings: every hook command as {Event; Command}.
function Get-ClaudeHooks($S) {
  $out = @()
  if ($S -and $S.PSObject.Properties['hooks'] -and $S.hooks) {
    foreach ($ev in $S.hooks.PSObject.Properties) {
      foreach ($entry in @($ev.Value)) {
        if (-not $entry -or -not $entry.PSObject.Properties['hooks']) { continue }
        foreach ($h in @($entry.hooks)) { if ($h -and $h.PSObject.Properties['command']) { $out += [pscustomobject]@{ Event = $ev.Name; Command = [string]$h.command } } }
      }
    }
  }
  return $out
}
# Cursor hooks.json: every hook command as {Event; Command}.
function Get-CursorHooks($J) {
  $out = @()
  if ($J -and $J.PSObject.Properties['hooks'] -and $J.hooks) {
    foreach ($ev in $J.hooks.PSObject.Properties) {
      foreach ($h in @($ev.Value)) { if ($h -and $h.PSObject.Properties['command']) { $out += [pscustomobject]@{ Event = $ev.Name; Command = [string]$h.command } } }
    }
  }
  return $out
}
$script:Wsh = $null
try { $script:Wsh = New-Object -ComObject WScript.Shell } catch { }
function Get-Lnk([string]$Path) {
  $r = [pscustomobject]@{ Target = ''; Args = ''; Ok = $false }
  if (-not $script:Wsh) { return $r }
  try { $s = $script:Wsh.CreateShortcut($Path); $r.Target = [string]$s.TargetPath; $r.Args = [string]$s.Arguments; $r.Ok = $true } catch { }
  return $r
}
# Startup Apps toggle (read only). StartupApproved value: first byte even = on, odd = off; no value = never toggled = on.
function Get-StartupToggle([string]$Hive, [string]$Kind, [string]$Name) {
  $k = "$Hive\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\$Kind"
  try { $b = (Get-ItemProperty -LiteralPath $k -Name $Name -ErrorAction Stop).$Name } catch { return 'on (never toggled)' }
  if ($b -and $b.Length -gt 0) { if (($b[0] % 2) -eq 1) { return 'OFF in Startup apps' } else { return 'on' } }
  return 'on (never toggled)'
}
function Get-FileHashes([string]$Dir) {
  $h = @{}
  if (Test-Path -LiteralPath $Dir -PathType Container) {
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Recurse -File -Force -ErrorAction SilentlyContinue)) {
      $h[$f.FullName.Substring($Dir.Length).TrimStart('\').ToLower()] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    }
  }
  return $h
}
function Test-SameTree([string]$A, [string]$B) {
  $ha = Get-FileHashes $A; $hb = Get-FileHashes $B
  if ($ha.Count -ne $hb.Count -or $ha.Count -eq 0) { return $false }
  foreach ($k in $ha.Keys) { if ($hb[$k] -ne $ha[$k]) { return $false } }
  return $true
}
function Get-LinkTarget($Item) { if ($Item -and $Item.LinkType) { return (@($Item.Target) | ForEach-Object { ($_ -replace '^\\\?\?\\', '').TrimEnd('\') } | Select-Object -First 1) } return $null }

# ---------------------------------------------------------------- 1. prerequisites
$ps = $PSVersionTable.PSVersion
if ($ps.Major -gt 5 -or ($ps.Major -eq 5 -and $ps.Minor -ge 1)) { Add-Finding 'OK' 'prereq' 'PowerShell' "version $ps" }
else { Add-Finding 'CONFLICT' 'prereq' 'PowerShell' "version $ps; 5.1 or newer is needed" }
$git = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1
if ($git) { Add-Finding 'OK' 'prereq' 'git' $git.Source } else { Add-Finding 'WARN' 'prereq' 'git' 'not found. git is recommended for per-repo work (one repo at a time; no batch pull/push).' }
$PyOk = $false; $pyVer = $null
$pyCmd = Get-Command py -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pyCmd) {
  try { $pyVer = (& py -3 -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null | Select-Object -First 1) } catch { }
  if ($pyVer -match '^3\.(\d+)$' -and [int]$Matches[1] -ge 7) { $PyOk = $true }
}
if ($PyOk) { Add-Finding 'OK' 'prereq' 'py launcher' "py -3 = Python $pyVer" }
else { Add-Finding 'WARN' 'prereq' 'py launcher' ("py -3 (Python 3.7+) not available" + $(if ($pyVer) { " (got $pyVer)" } else { '' }) + '. install.ps1 skips the Cursor 80% handoff hook until Python is installed.') }
# Claude Code version: AGENTS.md loading needs 2.1.281+; the read-both option's plugin id changed in 2.1.285.
$ClaudeVer = $null
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue | Select-Object -First 1
if ($claudeCmd) {
  try { $cvOut = [string](& $claudeCmd.Source --version 2>$null | Select-Object -First 1); if ($cvOut -match '(\d+)\.(\d+)\.(\d+)') { $ClaudeVer = [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])" } } catch { }
}
$AgentsPlugin = if ($ClaudeVer -and $ClaudeVer -lt [version]'2.1.285') { 'agents-md@builtin' } else { 'cc-plugin-agents-md@builtin' }
if (-not $ClaudeVer) { Add-Finding 'WARN' 'prereq' 'Claude Code' ("not found" + $(if ($claudeCmd) { " (claude --version gave no version)" } else { '' }) + ". AGENTS.md loading needs Claude Code 2.1.281 or newer.") }
elseif ($ClaudeVer -lt [version]'2.1.281') { Add-Finding 'WARN' 'prereq' 'Claude Code' "version $ClaudeVer is older than 2.1.281 and may not load AGENTS.md. Update Claude Code." }
else { Add-Finding 'OK' 'prereq' 'Claude Code' "version $ClaudeVer (AGENTS.md loading needs 2.1.281+; read-both option plugin id: $AgentsPlugin)" }
function Get-InstructionFiles($S, [string]$Plugin) {
  if (-not $S -or -not $S.PSObject.Properties['pluginConfigs'] -or -not $S.pluginConfigs) { return $null }
  $p = $S.pluginConfigs.PSObject.Properties[$Plugin]; if (-not $p -or -not $p.Value) { return $null }
  $o = $p.Value.PSObject.Properties['options']; if (-not $o -or -not $o.Value) { return $null }
  $f = $o.Value.PSObject.Properties['instructionFiles']; if (-not $f) { return $null }
  return [string]$f.Value
}
$isAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole((New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544'))
if ($isAdmin) { Add-Finding 'WARN' 'prereq' 'elevation' 'this window is elevated. install.ps1 is meant for a normal PowerShell window.' }
else { Add-Finding 'OK' 'prereq' 'elevation' 'normal window (right for install.ps1). install-admin.ps1 needs an elevated PowerShell afterwards (you run that one).' }

# ---------------------------------------------------------------- 2. scheduled tasks
# No memory sync task any more (Claude-Memory-To-Cursor-Sync is retired; see $RetiredNameRx).
$knownTasks = @{}
$tasks = $null
try { $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' }) }
catch { Add-Finding 'WARN' 'tasks' 'scheduled tasks' "could not list them: $($_.Exception.Message)" }
if ($null -ne $tasks) {
  $seen = @{}
  foreach ($t in $tasks) {
    $name = $t.TaskName
    $act = (@($t.Actions) | ForEach-Object { ("$($_.Execute) $($_.Arguments)").Trim() }) -join ' ; '
    $label = "$($t.TaskPath)$name"
    if ($knownTasks.ContainsKey($name)) {
      $seen[$name] = $true
      $want = $knownTasks[$name]
      $hit = $false
      $actX = ([Environment]::ExpandEnvironmentVariables($act) -replace '/', '\').ToLower()
      foreach ($w in $want) { if ($actX.Contains($w.ToLower())) { $hit = $true } }
      if ($hit) { Add-Finding 'ALREADY-INSTALLED' 'tasks' $label "state $($t.State); runs $act" }
      else { Add-Finding 'WARN' 'tasks' $label "runs '$act', not this install's script ($($want -join ' or ')). install-admin.ps1 re-registers it under the same name." }
    } elseif ($name -eq 'Claude-Memory-To-Cursor-Sync' -and "$($t.State)" -eq 'Disabled') {
      Add-Finding 'OK' 'tasks' $label "retired memory sync task, disabled (fine; nothing to do). Optional cleanup in an admin PowerShell: Unregister-ScheduledTask -TaskName '$name' -Confirm:`$false"
    } elseif ($name -eq 'Claude-Memory-To-Cursor-Sync') {
      Add-Finding 'CONFLICT' 'tasks' $label "retired memory sync task is still ENABLED (state $($t.State)). Disable it in an admin PowerShell: Disable-ScheduledTask -TaskName '$name' (or remove it: Unregister-ScheduledTask -TaskName '$name' -Confirm:`$false)"
    } elseif ($name -match $RetiredNameRx -or $act -match $RetiredRx) {
      Add-Finding 'CONFLICT' 'tasks' $label "retired item, should be gone (runs '$act'). Remove it in an admin PowerShell: Unregister-ScheduledTask -TaskName '$name' -Confirm:`$false"
    } elseif ($act -match $OurScriptRx) {
      Add-Finding 'CONFLICT' 'tasks' $label "runs one of this package's scripts under another name (duplicate job): '$act'"
    } elseif ($name -match $SimilarNameRx -or $act -match $SimilarNameRx) {
      Add-Finding 'WARN' 'tasks' $label "similar name or purpose; check it is not a duplicate: '$act'"
    }
  }
  foreach ($k in $knownTasks.Keys) { if (-not $seen[$k]) { Add-Finding 'OK' 'tasks' $k 'not registered yet (install-admin.ps1 adds it)' } }
}

# ---------------------------------------------------------------- 3. Run / RunOnce / Startup folders
$runKeys = @(
  @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';                 Hive = 'HKCU:'; Kind = 'Run' },
  @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce';             Hive = 'HKCU:'; Kind = '' },
  @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run';                 Hive = 'HKLM:'; Kind = 'Run' },
  @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce';             Hive = 'HKLM:'; Kind = '' },
  @{ Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run';     Hive = 'HKLM:'; Kind = 'Run32' },
  @{ Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'; Hive = 'HKLM:'; Kind = '' }
)
$autostarts = @()   # every entry: Where, Name, Command, Toggle
foreach ($rk in $runKeys) {
  $props = $null
  try { $props = Get-ItemProperty -LiteralPath $rk.Path -ErrorAction Stop } catch { continue }
  foreach ($p in $props.PSObject.Properties) {
    if ($p.Name -like 'PS*' -and @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider') -contains $p.Name) { continue }
    $tog = if ($rk.Kind) { Get-StartupToggle $rk.Hive $rk.Kind $p.Name } else { 'n/a (RunOnce)' }
    $autostarts += [pscustomobject]@{ Where = $rk.Path; FullWhere = $rk.Path; Kind = 'Run'; Name = $p.Name; Command = [string]$p.Value; Toggle = $tog; IsUserRun = ($rk.Path -eq 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run') }
  }
}
foreach ($sf in @(@{ Dir = $StartupFolder; Hive = 'HKCU:' }, @{ Dir = $CommonStartup; Hive = 'HKLM:' })) {
  if (-not $sf.Dir -or -not (Test-Path -LiteralPath $sf.Dir)) { continue }
  foreach ($f in @(Get-ChildItem -LiteralPath $sf.Dir -File -Force -ErrorAction SilentlyContinue)) {
    if ($f.Name -ieq 'desktop.ini') { continue }
    $cmd = ''
    if ($f.Extension -ieq '.lnk') { $l = Get-Lnk $f.FullName; $cmd = ('"' + $l.Target + '" ' + $l.Args).Trim() }
    elseif (@('.vbs', '.cmd', '.bat', '.ps1', '.js') -contains $f.Extension.ToLower()) { try { $cmd = [IO.File]::ReadAllText($f.FullName) } catch { } }
    $autostarts += [pscustomobject]@{ Where = $sf.Dir; FullWhere = $f.FullName; Kind = 'StartupFolder'; Name = $f.Name; Command = $cmd; Toggle = (Get-StartupToggle $sf.Hive 'StartupFolder' $f.Name); IsUserRun = $false }
  }
}
$cursorEntries = @()
foreach ($a in $autostarts) {
  $id = "$($a.Where)\$($a.Name)"
  if ($a.Kind -eq 'StartupFolder') { $id = $a.FullWhere }
  if ($a.Name -match $RetiredNameRx -or $a.Command -match $RetiredRx) {
    Add-Finding 'CONFLICT' 'autostart' $id "retired auto-start, should be gone: $($a.Command)"
  } elseif ($a.Command -match $CursorExeRx) {
    $cursorEntries += $a
  } elseif ($a.Command -match $OurScriptRx) {
    Add-Finding 'CONFLICT' 'autostart' $id "starts one of this package's scripts at sign-in (they are manual or run by tasks): $($a.Command)"
  }
}
# ---------------------------------------------------------------- 4. Cursor autostart (install.ps1 makes sure there is exactly one)
function Find-CursorExe {
  $c = @()
  if ($env:LOCALAPPDATA) { $c += (Join-Path $env:LOCALAPPDATA 'Programs\cursor\Cursor.exe') }
  if ($env:ProgramFiles) { $c += (Join-Path $env:ProgramFiles 'cursor\Cursor.exe') }
  if (${env:ProgramFiles(x86)}) { $c += (Join-Path ${env:ProgramFiles(x86)} 'cursor\Cursor.exe') }
  foreach ($u in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
    foreach ($e in @(Get-ItemProperty -Path $u -ErrorAction SilentlyContinue | Where-Object { $_.PSObject.Properties['DisplayName'] -and "$($_.DisplayName)" -match '^Cursor(\s|$|\()' })) {
      if ($e.PSObject.Properties['InstallLocation'] -and $e.InstallLocation) { $c += (Join-Path (([string]$e.InstallLocation).Trim('"')) 'Cursor.exe') }
      if ($e.PSObject.Properties['DisplayIcon'] -and $e.DisplayIcon) { $c += ((([string]$e.DisplayIcon) -replace ',\d+$', '').Trim('"')) }
    }
  }
  foreach ($p in $c) { if ($p -and (Split-Path $p -Leaf) -ieq 'Cursor.exe' -and (Test-Path -LiteralPath $p -PathType Leaf)) { return $p } }
  return $null
}
$CursorExe = Find-CursorExe
$CursorStartup = @($cursorEntries | ForEach-Object {
  [pscustomobject]@{ Kind = $_.Kind; Path = $(if ($_.Kind -eq 'StartupFolder') { $_.FullWhere } else { "$($_.FullWhere)\$($_.Name)" }); Name = $_.Name; Command = $_.Command; Toggle = $_.Toggle }
})
if ($CursorStartup.Count -eq 0) {
  if ($CursorExe) { Add-Finding 'OK' 'cursor-autostart' 'Cursor start at sign-in' "no entry yet; install.ps1 adds Cursor.lnk to $StartupFolder (target $CursorExe)" }
  else { Add-Finding 'WARN' 'cursor-autostart' 'Cursor start at sign-in' 'Cursor.exe not found (not installed?). install.ps1 skips the Cursor autostart.' }
} elseif ($CursorStartup.Count -eq 1) {
  $e = $CursorStartup[0]
  if ($e.Toggle -like 'OFF*') { Add-Finding 'WARN' 'cursor-autostart' $e.Path "already present but turned OFF in Startup apps (left as is; turn it on in Task Manager > Startup apps if wanted): $($e.Command)" }
  else { Add-Finding 'ALREADY-INSTALLED' 'cursor-autostart' $e.Path "$($e.Command) [$($e.Toggle)]" }
} else {
  foreach ($e in $CursorStartup) { Add-Finding 'CONFLICT' 'cursor-autostart' $e.Path "one of $($CursorStartup.Count) Cursor start-at-sign-in entries (duplicate launch); keep one: $($e.Command) [$($e.Toggle)]" }
}

# ---------------------------------------------------------------- 5. running processes
$procs = $null
try { $procs = @(Get-CimInstance Win32_Process -ErrorAction Stop) } catch { Add-Finding 'WARN' 'processes' 'process list' "could not read: $($_.Exception.Message)" }
if ($null -ne $procs) {
  $hidden = @($procs | Where-Object { -not $_.CommandLine }).Count
  $hits = 0
  foreach ($p in $procs) {
    $cl = [string]$p.CommandLine
    if (-not $cl -or $p.ProcessId -eq $PID) { continue }
    $id = "$($p.Name) pid $($p.ProcessId)"
    if ($cl -match '(?i)watch-pull') { $hits++; Add-Finding 'CONFLICT' 'processes' $id "retired watch-pull loop is running (Workers Stop ends it): $cl" }
    elseif ($cl -match '(?i)cursor-worker\\run-worker\.ps1|run-worker\.ps1') {
      $hits++
      if ($cl.ToLower().Contains((Join-Path $BridgeDir $TK.WorkerFolder).ToLower())) { Add-Finding 'OK' 'processes' $id 'Cursor worker supervisor from this toolkit (started by Workers Start; Workers Stop ends it)' }
      elseif (@($LegacyDirs | Where-Object { $cl.ToLower().Contains($_.ToLower() + '\') }).Count) { Add-Finding 'WARN' 'processes' $id "Cursor worker running from the LEGACY toolkit folder; stop it (old Workers Stop) and start it from $BridgeDir after install: $cl" }
      else { Add-Finding 'WARN' 'processes' $id "Cursor worker running from another toolkit folder; stop it with that toolkit's Workers Stop before using this one: $cl" }
    }
    elseif ($cl -match $OurScriptRx) { $hits++; Add-Finding 'OK' 'processes' $id "short-lived package script running now: $cl" }
  }
  if (-not $hits) { Add-Finding 'OK' 'processes' 'package scripts' 'none running' }
  if ($hidden) { Add-Finding 'OK' 'processes' 'unreadable command lines' "$hidden process(es) of other accounts or the system cannot be read without admin (skipped)" }
}

# ---------------------------------------------------------------- 6. Claude settings (user + project)
$SimilarHookRx = '(?i)handoff|compact|backup|memory|context|continuity|snapshot'
function Test-ClaudeSettings([string]$Path, [bool]$IsUser) {
  $j = Read-JsonFile $Path
  if (-not $j.Exists) { if ($IsUser) { Add-Finding 'OK' 'claude' $Path 'not found; install.ps1 creates it' }; return }
  if (-not $j.Ok) { Add-Finding 'CONFLICT' 'claude' $Path "does not parse as JSON ($($j.Err)); install.ps1 cannot merge into it. Fix it first."; return }
  $s = $j.Obj
  $hooks = @(Get-ClaudeHooks $s)
  $wantEvents = @{ 'context-guard.ps1' = @('Stop', 'PreCompact'); 'memory-link-guard.ps1' = @('SessionStart', 'PreToolUse') }
  foreach ($leaf in $wantEvents.Keys) {
    $mine = @($hooks | Where-Object { $_.Command -match [regex]::Escape($leaf) })
    foreach ($ev in @($mine | ForEach-Object Event | Sort-Object -Unique)) {
      $inEv = @($mine | Where-Object Event -eq $ev)
      $tag = "$Path > hooks.$ev > $leaf"
      if (-not $IsUser) { Add-Finding 'CONFLICT' 'claude' $tag "project settings also run $leaf; with the user-level hook it runs twice. Remove it from the project file."; continue }
      if ($inEv.Count -gt 1) { Add-Finding 'CONFLICT' 'claude' $tag "$($inEv.Count) entries run the same script (runs twice). Keep one." ; continue }
      if ($wantEvents[$leaf] -notcontains $ev) { Add-Finding 'WARN' 'claude' $tag "unexpected event for this script: $($inEv[0].Command)"; continue }
      $sp = Get-ScriptPath $inEv[0].Command $leaf
      if ($sp -ieq $Expected[$leaf]) { Add-Finding 'ALREADY-INSTALLED' 'claude' $tag $inEv[0].Command }
      else { Add-Finding 'WARN' 'claude' $tag "points at $sp; install.ps1 re-points it to $($Expected[$leaf])" }
    }
    if ($IsUser) {
      foreach ($ev in $wantEvents[$leaf]) { if (-not @($mine | Where-Object Event -eq $ev).Count) { Add-Finding 'OK' 'claude' "$Path > hooks.$ev > $leaf" 'not wired yet; install.ps1 adds it' } }
    }
  }
  foreach ($h in $hooks) {
    if ($h.Command -match 'context-guard\.ps1|memory-link-guard\.ps1') { continue }
    if (@('Stop', 'PreCompact', 'SessionStart', 'PreToolUse', 'SubagentStop', 'SessionEnd') -contains $h.Event -and $h.Command -match $SimilarHookRx) {
      Add-Finding 'WARN' 'claude' "$Path > hooks.$($h.Event)" "other hook with a similar purpose (handoff / backup / memory); check it does not double up: $($h.Command)"
    }
  }
  if ($s.PSObject.Properties['statusLine'] -and $s.statusLine) {
    $cmd = ''; if ($s.statusLine.PSObject.Properties['command']) { $cmd = [string]$s.statusLine.command }
    if ($cmd -match 'context-guard\.ps1') {
      $sp = Get-ScriptPath $cmd 'context-guard.ps1'
      if (-not $IsUser) { Add-Finding 'WARN' 'claude' "$Path > statusLine" 'project statusLine overrides the user one (runs context-guard from the project file)' }
      elseif ($sp -ieq $Expected['context-guard.ps1']) { Add-Finding 'ALREADY-INSTALLED' 'claude' "$Path > statusLine" $cmd }
      else { Add-Finding 'WARN' 'claude' "$Path > statusLine" "context-guard statusLine points at $sp; install.ps1 re-points it" }
    } else {
      $why = if ($IsUser) { 'install.ps1 will NOT overwrite it, so the Claude Code 80% handoff cannot measure context and will not fire. Decide which statusLine to keep.' } else { 'it overrides the user statusLine in that project, so the Claude Code 80% handoff will not fire there.' }
      Add-Finding 'WARN' 'claude' "$Path > statusLine" "another statusLine is set ($cmd); $why"
    }
  } elseif ($IsUser) { Add-Finding 'OK' 'claude' "$Path > statusLine" 'not set; install.ps1 adds the context-guard statusLine' }
  if ($s.PSObject.Properties['autoMemoryDirectory'] -and $s.autoMemoryDirectory) {
    $am = [string]$s.autoMemoryDirectory; $amFull = Expand-UserPath $am
    if (-not $IsUser) { Add-Finding 'WARN' 'claude' "$Path > autoMemoryDirectory" "project file sets its own memory folder ($am); it overrides the shared store in that project" }
    elseif ($amFull -ieq (Expand-UserPath $AutoMemValue)) { Add-Finding 'ALREADY-INSTALLED' 'claude' "$Path > autoMemoryDirectory" $am }
    elseif ($amFull -ieq $Store) { Add-Finding 'CONFLICT' 'claude' "$Path > autoMemoryDirectory" "points straight at the store ($am), not at the junction $AutoMemValue. install.ps1 refuses to wire the guard; see README Troubleshooting." }
    else { Add-Finding 'WARN' 'claude' "$Path > autoMemoryDirectory" "is '$am'; install.ps1 changes it to $AutoMemValue. Include the old folder in MIGRATION.md." }
  } elseif ($IsUser) { Add-Finding 'OK' 'claude' "$Path > autoMemoryDirectory" "not set; install.ps1 sets $AutoMemValue" }
  # Project instructions (read CLAUDE.md and AGENTS.md): only the user settings file counts.
  $ifNew = Get-InstructionFiles $s 'cc-plugin-agents-md@builtin'; $ifOld = Get-InstructionFiles $s 'agents-md@builtin'
  if (-not $IsUser) {
    if ($ifNew -or $ifOld) { Add-Finding 'WARN' 'claude' "$Path > pluginConfigs" 'sets Project instructions in a project settings file; Claude Code ignores it there (only ~\.claude\settings.json counts).' }
  } else {
    $cur = Get-InstructionFiles $s $AgentsPlugin
    $tag = "$Path > pluginConfigs > $AgentsPlugin > instructionFiles"
    $otherOk = ($ClaudeVer -and $ClaudeVer -ge [version]'2.1.285' -and $ifOld -eq 'claude-md-and-agents-md')
    if ($cur -eq 'claude-md-and-agents-md' -or $otherOk) { Add-Finding 'ALREADY-INSTALLED' 'claude' $tag ('claude-md-and-agents-md' + $(if ($otherOk -and $cur -ne 'claude-md-and-agents-md') { ' (under agents-md@builtin, which this version also reads)' } else { '' })) }
    elseif ($cur) { Add-Finding 'WARN' 'claude' $tag "is '$cur'; install.ps1 changes it to claude-md-and-agents-md (uninstall puts '$cur' back)" }
    else { Add-Finding 'OK' 'claude' $tag 'not set (default: AGENTS.md is hidden wherever a CLAUDE.md or CLAUDE.local.md exists); install.ps1 sets claude-md-and-agents-md' }
  }
}
Test-ClaudeSettings $SettingsPath $true
$projSettings = @()
foreach ($pat in @("$ProjectsRoot\.claude\settings*.json", "$ProjectsRoot\*\.claude\settings*.json", "$ProjectsRoot\active\*\.claude\settings*.json", "$ProjectsRoot\active\*\*\.claude\settings*.json")) {
  $projSettings += @(Get-ChildItem -Path $pat -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(node_modules|_scratch|_archive)\\' -and -not (Test-Under $_.FullName $PkgRoot) })
}
foreach ($f in @($projSettings | Sort-Object FullName -Unique)) { Test-ClaudeSettings $f.FullName $false }
# Projects root guide: AGENTS.md only. A root CLAUDE.md is merged into it by hand (REORGANIZE.md step 5).
$rootCm = Join-Path $ProjectsRoot 'CLAUDE.md'; $rootAm = Join-Path $ProjectsRoot 'AGENTS.md'
if (Test-Path -LiteralPath $rootCm) { Add-Finding 'WARN' 'rules' $rootCm ("root CLAUDE.md: merge it into AGENTS.md and delete it (REORGANIZE.md step 5)." + $(if (Test-Path -LiteralPath $rootAm) { ' AGENTS.md is there too.' } else { '' })) }
elseif (Test-Path -LiteralPath $rootAm) { Add-Finding 'OK' 'rules' $rootAm 'root guide is AGENTS.md (no root CLAUDE.md)' }
else { Add-Finding 'OK' 'rules' $rootAm 'not there yet; install.ps1 creates it' }
if (-not $projSettings.Count) { Add-Finding 'OK' 'claude' 'project .claude\settings*.json' "none under $ProjectsRoot (checked the root, its folders and active\*)" }

# ---------------------------------------------------------------- 7. Cursor hooks.json (user + project)
function Test-CursorHooks([string]$Path, [bool]$IsUser) {
  $j = Read-JsonFile $Path
  if (-not $j.Exists) { if ($IsUser) { Add-Finding 'OK' 'cursor' $Path 'not found; install.ps1 creates it (needs py -3)' }; return }
  if (-not $j.Ok) { Add-Finding 'CONFLICT' 'cursor' $Path "does not parse as JSON ($($j.Err)); install.ps1 cannot merge into it."; return }
  $hooks = @(Get-CursorHooks $j.Obj)
  $leaf = 'handoff-at-80.py'
  $mine = @($hooks | Where-Object { $_.Command -match [regex]::Escape($leaf) })
  foreach ($ev in @($mine | ForEach-Object Event | Sort-Object -Unique)) {
    $inEv = @($mine | Where-Object Event -eq $ev); $tag = "$Path > hooks.$ev > $leaf"
    if (-not $IsUser) { Add-Finding 'CONFLICT' 'cursor' $tag 'project hooks.json also runs it; with the user hook it fires twice. Remove it from the project file.'; continue }
    if ($inEv.Count -gt 1) { Add-Finding 'CONFLICT' 'cursor' $tag "$($inEv.Count) entries run the same script. Keep one."; continue }
    $sp = Get-ScriptPath $inEv[0].Command $leaf
    if ($sp -ieq $Expected[$leaf]) { Add-Finding 'ALREADY-INSTALLED' 'cursor' $tag $inEv[0].Command }
    else { Add-Finding 'WARN' 'cursor' $tag "points at $sp; install.ps1 re-points it to $($Expected[$leaf])" }
  }
  if ($IsUser) {
    foreach ($ev in 'preCompact', 'stop') { if (-not @($mine | Where-Object Event -eq $ev).Count) { Add-Finding 'OK' 'cursor' "$Path > hooks.$ev > $leaf" 'not wired yet; install.ps1 adds it' } }
    if ($mine.Count -and -not (Test-Path -LiteralPath $ArmedPath)) { Add-Finding 'WARN' 'cursor' $ArmedPath 'armed flag missing: the Cursor handoff hook is wired but disarmed (install.ps1 creates the flag only on a fresh install of the hook)' }
  }
  foreach ($h in $hooks) {
    if ($h.Command -match [regex]::Escape($leaf)) { continue }
    if (@('preCompact', 'stop', 'sessionStart', 'sessionEnd') -contains $h.Event -and $h.Command -match $SimilarHookRx) {
      Add-Finding 'WARN' 'cursor' "$Path > hooks.$($h.Event)" "other hook with a similar purpose; check it does not double up: $($h.Command)"
    }
  }
}
Test-CursorHooks $CursorHooksJson $true
foreach ($f in @(@(Get-ChildItem -Path "$ProjectsRoot\.cursor\hooks.json", "$ProjectsRoot\active\*\.cursor\hooks.json" -File -Force -ErrorAction SilentlyContinue) | Sort-Object FullName -Unique)) { Test-CursorHooks $f.FullName $false }
Add-Finding 'OK' 'cursor' 'Claude hooks inside Cursor' 'Cursor also runs ~/.claude/settings.json hooks; context-guard.ps1 ignores Cursor payloads (conversation_id), so only handoff-at-80.py fires in Cursor.'

# ---------------------------------------------------------------- 8. skills and rules
$skillRoots = New-Object System.Collections.Generic.List[object]   # {Path; Owner = cursor|claude}
$agentStores = Join-Path $LocalAppData 'Cursor\AgentStores'
if (Test-Path -LiteralPath $agentStores) {
  foreach ($d in @(Get-ChildItem -LiteralPath $agentStores -Recurse -Directory -Force -Depth 5 -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'skills' })) { $skillRoots.Add([pscustomobject]@{ Path = $d.FullName; Owner = 'cursor' }) }
}
foreach ($p in @((Join-Path $DotCursor 'skills'), (Join-Path $DotCursor 'skills-cursor'), (Join-Path $ProjectsRoot '.cursor\skills'))) { if (Test-Path -LiteralPath $p) { $skillRoots.Add([pscustomobject]@{ Path = $p; Owner = 'cursor' }) } }
foreach ($d in @(Get-ChildItem -Path "$ProjectsRoot\active\*\.cursor\skills" -Directory -Force -ErrorAction SilentlyContinue)) { $skillRoots.Add([pscustomobject]@{ Path = $d.FullName; Owner = 'cursor' }) }
foreach ($p in @((Join-Path $DotClaude 'skills'), (Join-Path $ProjectsRoot '.claude\skills'))) { if (Test-Path -LiteralPath $p) { $skillRoots.Add([pscustomobject]@{ Path = $p; Owner = 'claude' }) } }
foreach ($d in @(Get-ChildItem -Path "$ProjectsRoot\active\*\.claude\skills" -Directory -Force -ErrorAction SilentlyContinue)) { $skillRoots.Add([pscustomobject]@{ Path = $d.FullName; Owner = 'claude' }) }
$ruleFiles = @()
foreach ($p in @((Join-Path $DotCursor 'rules'), (Join-Path $ProjectsRoot '.cursor\rules'))) { if (Test-Path -LiteralPath $p) { $ruleFiles += @(Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue) } }
$ruleFiles += @(Get-ChildItem -Path "$ProjectsRoot\active\*\.cursor\rules\*" -File -Force -ErrorAction SilentlyContinue)

$memSectionRx = '(?s)<!-- shared-memory:v\d+ -->.*?<!-- /shared-memory:v\d+ -->'
$pathRx = '(?i)(?:[A-Za-z]:|%USERPROFILE%|%HOMEPATH%|\$env:USERPROFILE|~)[\\/][^`''"\r\n|<>*?]+'
function Get-RefKind([string]$Ref) {
  $p = Expand-UserPath ($Ref -replace '\$env:USERPROFILE', $UserHome)
  if (-not $p) { return 'other' }
  if ($p -match '(?i)\\_claude\\Cursor Notes(\\|$)') { return 'notes' }
  if ((Test-Under $p $Store) -or $p -match '(?i)\\Working Memory\\memory(\\|$)' -or $p -match '(?i)\\\.claude\\working-memory(\\|$)' -or
      $p -match '(?i)\\\.claude\\projects\\[^\\]+\\memory(\\|$)' -or (Split-Path $p -Leaf) -match '^(?i)(MEMORY|INDEX)\.md$' -or $p -match '(?i)\\memory(\\|$)') { return 'memory' }
  if ((Split-Path $p -Leaf) -match '^(?i)(CLAUDE|AGENTS)(\.local)?\.md$|\.mdc$') { return 'rules' }
  return 'other'
}
# One scan result for a set of files: memory refs and rule refs.
function Get-MemoryScan([object[]]$Files) {
  $mem = New-Object System.Collections.Generic.List[string]; $rules = New-Object System.Collections.Generic.List[string]
  foreach ($f in $Files) {
    if ($f.Length -gt 512KB -or @('.md', '.mdc', '.txt') -notcontains $f.Extension.ToLower()) { continue }
    $text = $null; try { $text = [IO.File]::ReadAllText($f.FullName) } catch { continue }
    # This package's own marked rule section is fine (Cursor edits the live store); scan only the rest.
    $text = [regex]::Replace($text, $memSectionRx, '')
    $short = $f.Name
    foreach ($m in [regex]::Matches($text, $pathRx)) {
      $ref = $m.Value.Trim().TrimEnd('.', ',', ';', ')')
      switch (Get-RefKind $ref) { 'memory' { $mem.Add("$short`: $ref") } 'rules' { $rules.Add("$short`: $ref") } }
    }
    $lines = $text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
      $ln = $lines[$i]
      # Relative mentions only (absolute paths were counted above); a "never / do not" line is a prohibition, not a use.
      if ($ln -match '(?i)Working Memory\W{0,4}memory[/\\]|memory[/\\]MEMORY\.md|\bMEMORY\.md\b' -and $ln -notmatch '(?i)Cursor Notes' -and
          $ln -notmatch '(?i)\b(never|do not|don''t)\b' -and -not [regex]::IsMatch($ln, $pathRx)) { $mem.Add("$short line $($i+1): " + $ln.Trim()) }
    }
  }
  return [pscustomobject]@{ Mem = @($mem | Select-Object -Unique); Rules = @($rules | Select-Object -Unique) }
}
function Report-Scan([string]$Item, $Scan) {
  if ($Scan.Mem.Count) {
    Add-Finding 'OK' 'cursor-skills' $Item ("references Claude memory (Cursor edits the live store): " + ($Scan.Mem -join ' | '))
  } elseif ($Scan.Rules.Count) {
    Add-Finding 'OK' 'cursor-skills' $Item ("references only rule files (no memory files): " + ($Scan.Rules -join ' | '))
  }
}
$cursorSkillDirs = 0
foreach ($r in @($skillRoots | Where-Object Owner -eq 'cursor')) {
  foreach ($sd in @(Get-ChildItem -LiteralPath $r.Path -Directory -Force -ErrorAction SilentlyContinue)) {
    $cursorSkillDirs++
    Report-Scan "skill $($sd.FullName)" (Get-MemoryScan @(Get-ChildItem -LiteralPath $sd.FullName -Recurse -File -Force -ErrorAction SilentlyContinue))
  }
}
foreach ($rf in $ruleFiles) { Report-Scan "rule $($rf.FullName)" (Get-MemoryScan @($rf)) }
Add-Finding 'OK' 'cursor-skills' 'scan scope' ("checked $cursorSkillDirs Cursor skill folder(s) and $($ruleFiles.Count) rule file(s) for hard-coded memory paths. Skill roots: " + $(if ($skillRoots.Count) { (($skillRoots | ForEach-Object Path) -join ' | ') } else { 'none found' }))

# Named skills: where they exist (plain answer). handoff-sync-continue is retired (merged into agent-handoff-pack).
foreach ($name in 'claude-cowork', 'handoff-sync-continue') {
  $found = @()
  foreach ($r in $skillRoots) { $p = Join-Path $r.Path $name; if (Test-Path -LiteralPath $p -PathType Container) { $found += [pscustomobject]@{ Path = $p; Owner = $r.Owner } } }
  if ($name -eq 'claude-cowork') {
    if ($found.Count) { Add-Finding 'OK' 'skills' "skill '$name'" ('EXISTS at: ' + (($found | ForEach-Object Path) -join ' | ') + ' (its memory-path findings are listed under cursor-skills)') }
    else { Add-Finding 'OK' 'skills' "skill '$name'" 'not found in any skill folder checked (see cursor-skills scan scope)' }
    continue
  }
  if (-not $found.Count) { Add-Finding 'OK' 'skills' "skill '$name'" 'retired (merged into agent-handoff-pack); no old copy found' }
  foreach ($f in $found) { Add-Finding 'WARN' 'skills' $f.Path "retired skill (merged into agent-handoff-pack); link-skills.ps1 (install.ps1 -LinkSkills) moves it to ~\.skills-backup" }
}

# Claude instruction texts (package instructions\, pasted by hand; never edited by install). Read-only check.
Add-Finding 'OK' 'instructions' 'Instructions for Claude' 'account-level, not on disk: paste instructions\instructions-for-claude.md into Claude desktop > Settings > Instructions for Claude if not done yet'
$coworkFiles = @()
foreach ($pattern in @((Join-Path $LocalAppData 'Packages\Claude_*\LocalCache\Roaming\Claude\local-agent-mode-sessions\*\*\memory\CLAUDE.md'),
                       (Join-Path $RoamingAppData 'Claude\local-agent-mode-sessions\*\*\memory\CLAUDE.md'))) {
  if ($pattern) { $coworkFiles += @(Get-ChildItem -Path $pattern -File -Force -ErrorAction SilentlyContinue | ForEach-Object FullName) }
}
$coworkWith = @($coworkFiles | Where-Object { [IO.File]::ReadAllText($_) -match '(?i)\.claude\s*[\\/]\s*working-memory' })
if ($coworkWith.Count) {
  foreach ($f in $coworkWith) { Add-Finding 'ALREADY-INSTALLED' 'instructions' $f 'Cowork Global instructions have the working-memory line' }
  foreach ($f in @($coworkFiles | Where-Object { $coworkWith -notcontains $_ })) { Add-Finding 'OK' 'instructions' $f 'other Cowork account/org folder without the working-memory line (left alone)' }
} else {
  Add-Finding 'OK' 'instructions' 'Cowork Global instructions' ('TODO: ' + $(if ($coworkFiles.Count) { 'no working-memory line in ' + ($coworkFiles -join ' | ') } else { 'not found on this PC' }) + '. Paste instructions\cowork-global-instructions.md into Claude desktop > Cowork settings > Global instructions.')
}

# ---------------------------------------------------------------- 9. memory stores and links
if (Test-Path -LiteralPath $Store -PathType Container) { Add-Finding 'ALREADY-INSTALLED' 'memory' $Store ("memory store exists (" + @(Get-ChildItem -LiteralPath $Store -Recurse -File -Force -ErrorAction SilentlyContinue).Count + ' files)') }
else { Add-Finding 'OK' 'memory' $Store 'memory store not there yet; install.ps1 creates it' }
$wm = Get-Item -LiteralPath $WmLink -Force -ErrorAction SilentlyContinue
if (-not $wm) { Add-Finding 'OK' 'memory' $WmLink 'not there yet; install.ps1 creates the junction' }
elseif ($wm.LinkType) {
  $t = Get-LinkTarget $wm
  if ($t -ieq $Store) { Add-Finding 'ALREADY-INSTALLED' 'memory' $WmLink "$($wm.LinkType) to the store" }
  elseif (-not $t -or -not (Test-Path -LiteralPath $t)) { Add-Finding 'CONFLICT' 'memory' $WmLink "BROKEN $($wm.LinkType): target $t does not exist. Remove the link (the link only) and re-run." }
  else { Add-Finding 'CONFLICT' 'memory' $WmLink "$($wm.LinkType) to $t, not the store $Store. Pointer lines would read the wrong notes; fix by hand (MIGRATION.md) first." }
} else { Add-Finding 'CONFLICT' 'memory' $WmLink 'is a real folder or file, not a junction to the store. Merge it (MIGRATION.md) and move it aside first.' }
$roots = @{}
if (Test-Path -LiteralPath $Store) { $roots[$Store.ToLower()] = $Store }
$projDir = Join-Path $DotClaude 'projects'
foreach ($pd in @(Get-ChildItem -LiteralPath $projDir -Directory -Force -ErrorAction SilentlyContinue)) {
  $m = Join-Path $pd.FullName 'memory'
  $mi = Get-Item -LiteralPath $m -Force -ErrorAction SilentlyContinue
  if (-not $mi) { continue }
  $isMain = ($m -ieq $LinkPath)
  if ($mi.LinkType) {
    $t = Get-LinkTarget $mi
    if (-not $t -or -not (Test-Path -LiteralPath $t)) { Add-Finding 'WARN' 'memory' $m "BROKEN $($mi.LinkType): target $t does not exist" ; continue }
    if ($t -ieq $Store) { if ($isMain) { Add-Finding 'ALREADY-INSTALLED' 'memory' $m "$($mi.LinkType) to the store" }; continue }
    $n = @(Get-ChildItem -LiteralPath $t -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    if ($n) { $roots[$t.ToLower()] = $t }
    Add-Finding 'WARN' 'memory' $m ("$($mi.LinkType) to $t ($n files), not the store." + $(if ($isMain) { ' The guard hook re-points it; merge first (MIGRATION.md).' } else { ' Merge those notes (MIGRATION.md).' }))
  } else {
    $n = @(Get-ChildItem -LiteralPath $m -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    if ($n) {
      $roots[$m.ToLower()] = $m
      Add-Finding 'WARN' 'memory' $m ("real memory folder with $n file(s)." + $(if ($isMain) { ' install.ps1 will not replace it; do MIGRATION.md first.' } else { ' The guard hook moves it into the store on the next Claude Code start; back it up first (MIGRATION.md step a).' }))
    }
  }
}
$st = Read-JsonFile $SettingsPath
if ($st.Ok -and $st.Obj.PSObject.Properties['autoMemoryDirectory'] -and $st.Obj.autoMemoryDirectory) {
  $amp = Expand-UserPath ([string]$st.Obj.autoMemoryDirectory)
  $ami = Get-Item -LiteralPath $amp -Force -ErrorAction SilentlyContinue
  if ($ami) { $amt = $amp; if ($ami.LinkType) { $amt = Get-LinkTarget $ami }; if ($amt -and (Test-Path -LiteralPath $amt) -and @(Get-ChildItem -LiteralPath $amt -Recurse -File -Force -ErrorAction SilentlyContinue).Count) { $roots[$amt.ToLower()] = $amt } }
}
if (Test-Path -LiteralPath $ClaudeDir) {
  foreach ($mf in @(Get-ChildItem -LiteralPath $ClaudeDir -Recurse -File -Force -Depth 5 -Filter 'MEMORY.md' -ErrorAction SilentlyContinue)) {
    $d = $mf.DirectoryName
    if ((Test-Under $d $Store) -or (Test-Under $d $CursorNotes) -or (Test-Under $d $OldCursorCopy)) { continue }
    $roots[$d.ToLower()] = $d
  }
}
if (Test-Path -LiteralPath $OldCursorCopy) {
  Add-Finding 'OK' 'memory' $OldCursorCopy 'retired Cursor copy of Claude memory (frozen mirror, not a store; do NOT merge it into memory). Safe to archive to <Projects>\_archive when convenient.'
}
if ($roots.Count -gt 1) { Add-Finding 'WARN' 'memory' 'memory stores' ("more than one Claude memory store: " + ($roots.Values -join ' | ') + '. Merge into the shared store with MIGRATION.md.') }
else { Add-Finding 'OK' 'memory' 'memory stores' $(if ($roots.Count) { "one store: $($roots.Values -join '')" } else { 'none yet' }) }

# ---------------------------------------------------------------- 10. Toolkit and Desktop shortcuts (names from toolkit.psd1)
if (Test-Path -LiteralPath $BridgeDir) { Add-Finding 'OK' 'toolkit' $BridgeDir 'toolkit runs straight from this package (install copies nothing under the Projects root)' }
else { Add-Finding 'CONFLICT' 'toolkit' $BridgeDir 'toolkit folder missing from this package; run install from a complete workstation repo clone' }
foreach ($ld in $LegacyDirs) {
  if (Test-Path -LiteralPath $ld) { Add-Finding 'WARN' 'toolkit' $ld "OLD installed toolkit copy. The toolkit now runs from $BridgeDir; install leaves this folder in place. Stop its workers (Workers Stop), re-point anything that still uses it, then archive it." }
}
# Empty names are dropped: PullScript is '' now, and an empty marker matched EVERY file (false "another toolkit copy" WARNs).
$markers = @(@($TK.PullScript, $TK.CommonScript) + @($legacyLeaves | Where-Object { $_ -match '(?i)common|pull' } | ForEach-Object { $_ }) | Where-Object { $_ } | Select-Object -Unique)
$others = @()
foreach ($root in @($ProjectsRoot, (Join-Path $ProjectsRoot 'active'), $UserHome, $DesktopDir, (Join-Path $UserHome 'Documents'))) {
  if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
  foreach ($mk in $markers) {
    foreach ($pat in @("*\$mk", "*\*\$mk", "*\*\*\$mk")) {
      foreach ($f in @(Get-ChildItem -Path (Join-Path $root $pat) -File -Force -ErrorAction SilentlyContinue | Where-Object { $_ -is [IO.FileInfo] })) {
        # pwsh 7 can return a DirectoryInfo here despite -File (seen: a folder named ' ' holding a folder called sync-pull.ps1); it has no DirectoryName.
        # toolkit root = the folder that holds the marker's relative path (or, for a bare legacy name, its shortcuts\ parent)
        $dir = $f.DirectoryName
        $depth = @($mk -split '\\').Count - 1
        for ($i = 0; $i -lt $depth -and $dir; $i++) { $dir = Split-Path $dir -Parent }
        if (-not $dir) { continue }
        if ($mk -notmatch '\\' -and (Split-Path $dir -Leaf) -ieq 'shortcuts') { $dir = Split-Path $dir -Parent }
        if ((Test-Under $dir $BridgeDir) -or (Test-Under $dir $PkgRoot) -or @($LegacyDirs | Where-Object { Test-Under $dir $_ }).Count -or $dir -match '(?i)\\(_scratch|_archive|node_modules)(\\|$)') { continue }
        # A workstation package / repo clone (toolkit.psd1 next to its toolkit folder) is source, not an installed copy.
        $dirUp = Split-Path $dir -Parent
        if ($dirUp -and (Test-Path -LiteralPath (Join-Path $dirUp 'toolkit.psd1'))) { continue }
        $others += $dir
      }
    }
  }
}
foreach ($o in @($others | Sort-Object -Unique)) { Add-Finding 'WARN' 'toolkit' $o "another toolkit copy (not $BridgeDir). Keep one; its shortcuts or worker may double up." }
$newNames = @($TK.Shortcuts | ForEach-Object { $_.Name })
$oldNames = @($TK.LegacyShortcutNames)
$scLeaves = @(@($TK.Shortcuts | ForEach-Object { Split-Path $_.Script -Leaf }) + @($legacyLeaves | Where-Object { $_ -match '(?i)start|stop|status|pull|push' }) | Select-Object -Unique)
$bridgeScriptRx = '(?i)(' + (($scLeaves | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')'
$ourShortcutDirs = @($TK.Shortcuts | ForEach-Object { (Split-Path (Join-Path $BridgeDir $_.Script) -Parent).ToLower() } | Select-Object -Unique)
$desks = @($DesktopDir); if (-not $testMode) { $desks += [Environment]::GetFolderPath('CommonDesktopDirectory') }
$desks += $ScDir   # where the shortcuts live now (inside the package)
$scFound = 0
foreach ($dk in @($desks | Where-Object { $_ -and (Test-Path -LiteralPath $_) })) {
  foreach ($lsf in @($TK.LegacyShortcutFolders)) {
    $oldDir = Join-Path $dk $lsf
    if (Test-Path -LiteralPath $oldDir -PathType Container) {
      $nOld = @(Get-ChildItem -LiteralPath $oldDir -Force -ErrorAction SilentlyContinue).Count
      Add-Finding 'WARN' 'shortcuts' $oldDir ("old Desktop ""$lsf"" folder (pre-rename, $nOld item(s)); the shortcuts installer now puts the links in $ScDir and removes only links here that run the toolkit scripts, then the folder once empty)")
    }
  }
  $lnks = @(Get-ChildItem -LiteralPath $dk -Filter *.lnk -File -Force -ErrorAction SilentlyContinue) + @(Get-ChildItem -Path (Join-Path $dk '*\*.lnk') -File -Force -ErrorAction SilentlyContinue)
  foreach ($l in $lnks) {
    $base = [IO.Path]::GetFileNameWithoutExtension($l.Name)
    $li = Get-Lnk $l.FullName
    $runs = "$($li.Target) $($li.Args)"
    if ($runs -notmatch $bridgeScriptRx -and $newNames -notcontains $base -and $oldNames -notcontains $base) { continue }
    $scFound++
    $sp = $null; $m = [regex]::Match($runs, '(?i)"([^"]*' + $bridgeScriptRx.Substring(4) + ')"'); if ($m.Success) { $sp = Expand-UserPath $m.Groups[1].Value }
    $ours = ($sp -and $ourShortcutDirs -contains (Split-Path $sp -Parent).ToLower())
    $legacy = ($sp -and (@($LegacyDirs | Where-Object { Test-Under $sp $_ }).Count -or $legacyLeaves -contains (Split-Path $sp -Leaf)))
    $isNew = ($newNames -contains $base)
    if ($ours -and $isNew -and $l.DirectoryName -ieq $ScDir) { Add-Finding 'ALREADY-INSTALLED' 'shortcuts' $l.FullName "runs $sp" }
    elseif ($legacy) { Add-Finding 'WARN' 'shortcuts' $l.FullName "legacy shortcut (old toolkit folder or old script name: $sp); the shortcuts installer re-creates the set for $BridgeDir" }
    elseif ($ours -or (-not $isNew -and $oldNames -contains $base)) { Add-Finding 'WARN' 'shortcuts' $l.FullName "old-name or loose shortcut ($runs); the shortcuts installer replaces it" }
    elseif ($sp) { Add-Finding 'CONFLICT' 'shortcuts' $l.FullName "Workstation-style shortcut that runs a DIFFERENT toolkit ($sp); a second set would double up. Remove or re-point it." }
    else { Add-Finding 'WARN' 'shortcuts' $l.FullName "same name as a Workstation shortcut but runs something else ($runs)" }
  }
}
if (-not $scFound) { Add-Finding 'OK' 'shortcuts' $ScDir ("no Workstation shortcuts yet" + $(if ($testMode) { ' (test mode: checked ' + $DesktopDir + ')' } else { '' })) }

# ---------------------------------------------------------------- report
$order = @{ 'CONFLICT' = 0; 'WARN' = 1; 'ALREADY-INSTALLED' = 2; 'OK' = 3 }
$conf = @($Findings | Where-Object Class -eq 'CONFLICT').Count
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Workstation setup preflight (read-only)  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("  User home     : $UserHome" + $(if ($testMode) { '  (TEST MODE)' } else { '' }))
$lines.Add("  Projects root : $ProjectsRoot")
$lines.Add("  Startup folder: $StartupFolder")
$lines.Add('')
foreach ($f in $Findings) { $lines.Add(("[{0}] {1}: {2} -- {3}" -f $f.Class, $f.Area, $f.Item, $f.Detail)) }
$lines.Add('')
$counts = foreach ($c in 'CONFLICT', 'WARN', 'ALREADY-INSTALLED', 'OK') { "{0} {1}" -f @($Findings | Where-Object Class -eq $c).Count, $c }
$lines.Add('Summary: ' + ($counts -join ', '))
if ($conf) { $lines.Add('CONFLICTS found: install.ps1 stops until they are resolved, or until it is run with -AcceptConflicts after the user reviewed this report.') }
else { $lines.Add('No conflicts. install.ps1 can run.') }

Write-Host ''
Write-Host 'Preflight (read-only check, changes nothing)' -ForegroundColor White
foreach ($f in ($Findings | Sort-Object @{ e = { $order[$_.Class] } }, Area)) {
  $color = switch ($f.Class) { 'CONFLICT' { 'Red' } 'WARN' { 'Yellow' } 'ALREADY-INSTALLED' { 'DarkGreen' } default { 'Gray' } }
  Write-Host ("[{0,-17}] {1}: {2} -- {3}" -f $f.Class, $f.Area, $f.Item, $f.Detail) -ForegroundColor $color
}
$ReportPath = $null
$dirs = @(); if ($ReportDir) { $dirs += $ReportDir }; if ($env:TEMP) { $dirs += $env:TEMP }   # never $PkgRoot: keep reports out of the repo
foreach ($d in $dirs) {
  try {
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { continue }
    $rp = Join-Path $d "preflight-report-$Stamp.txt"
    [IO.File]::WriteAllLines($rp, [string[]]$lines, (New-Object Text.UTF8Encoding $false))
    $ReportPath = $rp; break
  } catch { }
}
Write-Host ''
Write-Host ('Preflight summary: ' + ($counts -join ', ')) -ForegroundColor $(if ($conf) { 'Red' } else { 'Green' })
if ($ReportPath) { Write-Host "Report: $ReportPath" } else { Write-Host 'Report could not be written (no writable folder).' -ForegroundColor Yellow }

$result = [pscustomobject]@{
  Findings = $Findings.ToArray(); Conflicts = $conf; ReportPath = $ReportPath
  CursorStartup = $CursorStartup; CursorExe = $CursorExe; PyOk = $PyOk; StartupFolder = $StartupFolder
  ClaudeVer = $ClaudeVer; AgentsPlugin = $AgentsPlugin
}
if ($PassThru) { return $result }
if ($conf) { exit 2 }
exit 0
