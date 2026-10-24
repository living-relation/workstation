<#
.SYNOPSIS
  Workstation setup: shared Claude / Cursor memory, the Bridge toolkit, the 80% handoff hooks and the Cursor
  autostart, for the CURRENT Windows user.

.DESCRIPTION
  Run as a normal user (not elevated) from the workstation repo clone (normally <Projects>\active\workstation; the
  toolkit scripts and shortcuts run straight from this clone, so keep it on main):
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -WhatIf
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1

  Every path is worked out at run time from the current user and -ProjectsRoot.
  Safe to re-run: it only adds what is missing.
  - FIRST runs preflight.ps1 (read-only). Any CONFLICT stops the install unless -AcceptConflicts is given
    (only after the user reviewed the preflight report). -WhatIf runs preflight too.
  - Never moves or deletes folders, never overwrites memory or starter files.
  - Appends memory sections to rule files only when the marker <!-- shared-memory:v1 --> is missing.
  - Backs up ~\.claude\settings.json (timestamped .bak next to it) before changing it.
  - Sets Claude Code's Project instructions to claude-md-and-agents-md (read CLAUDE.md AND AGENTS.md) in
    ~\.claude\settings.json > pluginConfigs (plugin cc-plugin-agents-md@builtin, or agents-md@builtin before
    Claude Code 2.1.285). WARN if Claude Code is older than 2.1.281. uninstall.ps1 reverts only that key.
  - The Projects root guide is AGENTS.md (memory section appended there). A root CLAUDE.md is merged into it
    by hand (REORGANIZE.md step 5), never by install.
  - Does NOT copy the toolkit anywhere: it runs from this package's toolkit folder (PackageFolder in toolkit.psd1,
    e.g. <clone>\workstation\). Writes %LOCALAPPDATA%\<StateFolder>\<ConfigFile> (projectsRoot) so the scripts find
    the Projects root; runtime files (stop flag, worker logs/state) also go under %LOCALAPPDATA%\<StateFolder>\,
    never into the clone. Then runs the toolkit's shortcuts installer (Workers Start / Workers Stop / Workstation
    Status links in this package's shortcuts\ folder, gitignored, + prerequisite checks).
    An old installed copy (<Projects>\_workstation or _bridge, LegacyFolders) is only reported, never moved.
  - Creates the junction ~\.claude\working-memory -> the memory store (the same path on every PC;
    the Cowork Global instructions line uses it). An existing folder or link there is never changed.
  - Installs the 80% handoff hooks (handoff\): context-guard.ps1 (Claude Code statusLine + Stop + PreCompact),
    handoff-at-80.py (Cursor preCompact + stop, needs py -3); the skill they trigger, agent-handoff-pack, is linked by
    -LinkSkills (which also moves an old handoff-sync-continue copy to ~\.skills-backup). Entries are
    merged by script name (never duplicated); an unrelated statusLine is never overwritten.
  - Makes sure Cursor starts at sign-in: an existing Cursor entry (Startup folder or Run key) is left alone,
    even if it is turned off in Startup apps (warning only); otherwise adds Cursor.lnk to the Startup folder.
  - Everything it adds is listed in <Projects>\_claude\automation-installed-files.txt for uninstall.ps1.
  - Does NOT migrate old memory. See MIGRATION.md.
  Scheduled tasks need admin: run install-admin.ps1 afterwards in an elevated PowerShell.
  - Ends by running Workstation Status (-NoPause: read-only, never prompts) and printing its FAIL / WARN counts.
    The manual steps (admin command, the two instruction pastes, sign-ins) are walked through by the
    installing agent from SETUP-PROMPT.txt. Setup is finished only when Workstation Status shows 0 FAIL, 0 WARN.

.PARAMETER ProjectsRoot
  Projects root folder. Default: %USERPROFILE%\Projects

.PARAMETER WhatIf
  Dry run. Shows what would change and changes nothing.

.PARAMETER UserHome
  Testing only. Use this folder instead of %USERPROFILE% for ~\.claude, ~\.cursor and AppData lookups.

.PARAMETER AcceptConflicts
  Install even though preflight found CONFLICT items. Only after the user reviewed the report.

.PARAMETER StartupFolder
  Testing only. Startup folder for the Cursor autostart. Default: the user's Startup folder
  (test mode: under -UserHome).

.PARAMETER LinkSkills
  Opt in to linking this repo's skills\ into ~\.claude\skills (link-skills.ps1, junctions; Cursor reads it too). Off by
  default. Re-running it also removes links it made whose skill was renamed or removed (the link only).

.PARAMETER ReportDir
  Folder for the preflight report. Default: %TEMP% (never the package/repo folder).


.NOTES
  Exit codes: 0 = done, 1 = error, 2 = stopped on preflight CONFLICT.

#>
[CmdletBinding()]
param(
  [string]$ProjectsRoot,
  [switch]$WhatIf,
  [string]$UserHome,
  [switch]$AcceptConflicts,
  [string]$StartupFolder,
  [string]$ReportDir,
  [switch]$LinkSkills
)

$ErrorActionPreference = 'Stop'
$Marker    = '<!-- shared-memory:v1 -->'
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$Today     = Get-Date -Format 'yyyy-MM-dd'
$PkgRoot   = $PSScriptRoot
if (-not $PkgRoot) { $PkgRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Utf8NoBom = New-Object Text.UTF8Encoding $false
# Toolkit folder and script names come from ONE place: toolkit.psd1 next to this script.
$ToolkitDef = Join-Path $PkgRoot 'toolkit.psd1'
if (-not (Test-Path -LiteralPath $ToolkitDef)) { Write-Host "toolkit.psd1 not found next to this script: $ToolkitDef" -ForegroundColor Red; exit 1 }
$TK = Import-PowerShellDataFile -LiteralPath $ToolkitDef

# ---------------------------------------------------------------- paths (all derived)
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
} else {
  $LocalAppData = $env:LOCALAPPDATA
  $RoamingAppData = $env:APPDATA
}

$ProjectKey  = $ProjectsRoot -replace '[^A-Za-z0-9]', '-'      # Claude Code's folder name for the Projects root
$ClaudeDir   = Join-Path $ProjectsRoot '_claude'
$WorkingMem  = Join-Path $ClaudeDir 'Claude Projects\Working Memory'
$Store       = Join-Path $WorkingMem 'memory'
$CursorNotes = Join-Path $ClaudeDir 'Cursor Notes'   # Cursor's own notes; Cursor reads $Store read-only
$DotClaude   = Join-Path $UserHome '.claude'
$HooksDir    = Join-Path $DotClaude 'hooks'
$LinkPath    = Join-Path $DotClaude ("projects\$ProjectKey\memory")
# Path-independent alias of the store, the same on every PC. The Cowork Global instructions line uses it.
$WmLink      = Join-Path $DotClaude 'working-memory'
$SettingsPath = Join-Path $DotClaude 'settings.json'
$GuardDest   = Join-Path $HooksDir 'memory-link-guard.ps1'
$GuardCfg    = Join-Path $HooksDir 'memory-link-guard.config.json'
# what was there before this run (recorded on a first install so uninstall keeps it)
$GuardScriptPre = Test-Path -LiteralPath $GuardDest
$GuardCfgPre    = Test-Path -LiteralPath $GuardCfg
$CursorRule  = Join-Path $UserHome '.cursor\rules\claude-shared-memory.mdc'
$BackupDir   = Join-Path $ProjectsRoot ("_archive\automation-install-backup-$Stamp")
# The toolkit runs straight from this package (no copy under <Projects>).
$BridgeDir   = Join-Path $PkgRoot $TK.PackageFolder
$StateDir    = Join-Path $LocalAppData $(if ($TK.StateFolder) { $TK.StateFolder } else { 'Workstation' })
$WsConfig    = Join-Path $StateDir $(if ($TK.ConfigFile) { $TK.ConfigFile } else { 'workstation.json' })
# Files this install newly created under <Projects> (uninstall.ps1 removes only these).
$ManifestPath = Join-Path $ClaudeDir 'automation-installed-files.txt'
$AddedFiles  = New-Object System.Collections.Generic.List[string]
# Junctions this install created outside <Projects> (manifest lines 'junction|<full path>'; uninstall removes the link only).
$AddedLinks  = New-Object System.Collections.Generic.List[string]
$Templates   = Join-Path $PkgRoot 'memory\templates'
# 80% handoff hooks + skill
$HandoffPkg  = Join-Path $PkgRoot 'handoff'
$CtxDest     = Join-Path $HooksDir 'context-guard.ps1'
$DotCursor   = Join-Path $UserHome '.cursor'
$CursorHookDest = Join-Path $DotCursor 'hooks\handoff-at-80.py'
$CursorHooksJson = Join-Path $DotCursor 'hooks.json'
$ArmedPath   = Join-Path $DotCursor 'hooks\state\handoff-at-80\armed'
if (-not $StartupFolder) {
  if ($testMode) { $StartupFolder = Join-Path $UserHome 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup' }
  else { $StartupFolder = [Environment]::GetFolderPath('Startup') }
}
$StartupFolder = [IO.Path]::GetFullPath($StartupFolder).TrimEnd('\')
# Manifest lines for things outside <Projects> or inside JSON files: 'json|{...}' (see uninstall.ps1).
$AddedJson   = New-Object System.Collections.Generic.List[string]

# autoMemoryDirectory = the junction path (resolves to the store). Same Projects path as the junction name.
if ($testMode) { $AutoMemValue = ($LinkPath -replace '\\', '/') } else { $AutoMemValue = "~/.claude/projects/$ProjectKey/memory" }
$GuardCommand = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + ($GuardDest -replace '\\', '/') + '"'
# Same command shapes as the hand-made originals, built from this user's real profile path (forward slashes).
function Get-CtxCommand([string]$Mode) { return ('powershell -NoProfile -ExecutionPolicy Bypass -File "' + ($CtxDest -replace '\\', '/') + '" ' + $Mode) }
$CursorHookFwd = ($CursorHookDest -replace '\\', '/')
$CursorCommand = 'py -3 ' + $(if ($CursorHookFwd -match '\s') { '"' + $CursorHookFwd + '"' } else { $CursorHookFwd })

$Placeholders = [ordered]@{
  '{{USERPROFILE_FWD}}'   = ($UserHome -replace '\\', '/')
  '{{USERPROFILE}}'       = $UserHome
  '{{PROJECTS_ROOT_FWD}}' = ($ProjectsRoot -replace '\\', '/')
  '{{PROJECTS_ROOT}}'     = $ProjectsRoot
  '{{CLAUDE_PROJECT_KEY}}' = $ProjectKey
  '{{USERNAME}}'          = $env:USERNAME
  '{{DATE}}'              = $Today
  '{{TOOLKIT_PATH}}'      = $BridgeDir
  '{{TOOLKIT_PULL}}'      = $TK.PullScript
  '{{TOOLKIT_STATUS}}'    = $TK.StatusScript
}

# ---------------------------------------------------------------- helpers
$Summary = New-Object System.Collections.Generic.List[object]
function Note([string]$Status, [string]$NoteText_) {
  $Summary.Add([pscustomobject]@{ Status = $Status; Item = $NoteText_ })
  $color = switch ($Status) { 'DONE' { 'Green' } 'WOULD' { 'Cyan' } 'WARN' { 'Yellow' } 'ERROR' { 'Red' } 'TODO' { 'Magenta' } default { 'Gray' } }
  Write-Host ("[{0,-5}] {1}" -f $Status, $NoteText_) -ForegroundColor $color
}
# Runs a change, or only reports it in -WhatIf mode. (Odd parameter names so they never hide the caller's variables.)
function Invoke-Change([string]$ChangeDesc_, [scriptblock]$ChangeBlock_) {
  if ($WhatIf) { Note 'WOULD' $ChangeDesc_; return }
  try { & $ChangeBlock_; Note 'DONE' $ChangeDesc_ } catch { Note 'ERROR' ("$ChangeDesc_ -- " + $_.Exception.Message) }
}
function Fill-Placeholders([string]$Text) {
  foreach ($k in $Placeholders.Keys) { $Text = $Text.Replace($k, [string]$Placeholders[$k]) }
  return $Text
}
function Get-Template([string]$Name) {
  $t = Fill-Placeholders ([IO.File]::ReadAllText((Join-Path $Templates $Name), $Utf8NoBom))
  return ($t -replace "`r`n", "`n")
}
# Same rules as the guard hook: env vars and ~ expanded, / -> \, \??\ prefix dropped, no trailing \.
function Resolve-UserPath([string]$P) {
  if (-not $P) { return $null }
  $P = ([Environment]::ExpandEnvironmentVariables($P.Trim()) -replace '/', '\') -replace '^\\\?\?\\', ''
  if ($P -eq '~') { $P = $UserHome } elseif ($P.StartsWith('~\')) { $P = Join-Path $UserHome $P.Substring(2) }
  try { $P = [IO.Path]::GetFullPath($P) } catch { }
  return $P.TrimEnd('\')
}
function Add-Manifest([string]$FullPath) {
  if ($FullPath.ToLower().StartsWith($ProjectsRoot.ToLower() + '\')) { $AddedFiles.Add($FullPath.Substring($ProjectsRoot.Length + 1)) }
}
function ConvertTo-Newline([string]$Text, [string]$Nl) { if ($Nl -eq "`r`n") { return ($Text -replace "`r?`n", "`r`n") } return $Text }
function Get-FreePath([string]$Path) {
  $candidate = $Path; $i = 1
  while (Test-Path -LiteralPath $candidate) { $candidate = "$Path-$i"; $i++ }
  return $candidate
}
function Backup-File([string]$Path) {
  if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
  $name = ($Path -replace '[:\\/]+', '_').Trim('_')
  Copy-Item -LiteralPath $Path -Destination (Get-FreePath (Join-Path $BackupDir $name))
}
function Ensure-Dir([string]$Path, [string]$Label) {
  if (Test-Path -LiteralPath $Path -PathType Container) { Note 'OK' "$Label exists: $Path"; return }
  if (Test-Path -LiteralPath $Path) { Note 'ERROR' "$Label is a file, not a folder: $Path"; return }
  Invoke-Change "create $Label`: $Path" { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}
function New-FileIfMissing([string]$Path, [string]$TemplateName) {
  if (Test-Path -LiteralPath $Path) { Note 'OK' "kept existing file: $Path"; return }
  $text = ConvertTo-Newline (Get-Template $TemplateName) "`r`n"
  Invoke-Change "create starter file: $Path" {
    New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force | Out-Null
    [IO.File]::WriteAllText($Path, $text, $Utf8NoBom)
  }
}
# Appends a marked block. -CreateIfMissing writes the full template when the file does not exist.
# For .mdc files only the part from the marker on is appended (the front matter stays the file's own).
function Add-MemoryBlock([string]$Path, [string]$TemplateName, [switch]$CreateIfMissing) {
  $full = Get-Template $TemplateName
  if (-not (Test-Path -LiteralPath $Path)) {
    if (-not $CreateIfMissing) { Note 'SKIP' "not found (left alone): $Path"; return }
    $text = ConvertTo-Newline ($full.TrimStart("`n")) "`r`n"
    Invoke-Change "create with memory section: $Path" {
      New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force | Out-Null
      [IO.File]::WriteAllText($Path, $text, $Utf8NoBom)
      # uninstall removes a marked section only when it is recorded here (install created the file or appended it)
      Add-ManifestJson @{ kind = 'section'; path = $Path; created = $true }
    }
    return
  }
  $existing = [IO.File]::ReadAllText($Path)
  if ($existing.Contains($Marker)) { Note 'OK' "memory section already present (not recorded as added by this run): $Path"; return }
  if ($existing -match '(?i)<!-- shared-memory:v\d+ -->|Cursor Copy of Claude Memory|_claude\\Cursor Notes') { Note 'WARN' "already has a shared-memory section without the marker; left alone (no duplicate added): $Path"; return }
  $block = $full.Substring($full.IndexOf($Marker))
  $nl = if ($existing.Contains("`r`n") -or -not $existing.Contains("`n")) { "`r`n" } else { "`n" }
  $prefix = if ($existing.Length -eq 0 -or $existing.EndsWith("`n")) { $nl } else { $nl + $nl }
  $add = ConvertTo-Newline ($prefix + $block) $nl
  Invoke-Change "append memory section to: $Path (backup in $BackupDir)" {
    Backup-File $Path
    [IO.File]::AppendAllText($Path, $add, $Utf8NoBom)
    Add-ManifestJson @{ kind = 'section'; path = $Path; created = $false }
  }
}
function Copy-PackageFile([string]$Source, [string]$Dest) {
  if (-not (Test-Path -LiteralPath $Source)) { Note 'ERROR' "package file missing: $Source"; return }
  if (Test-Path -LiteralPath $Dest) {
    if ((Get-FileHash -LiteralPath $Dest).Hash -eq (Get-FileHash -LiteralPath $Source).Hash) { Note 'OK' "up to date: $Dest"; return }
    Invoke-Change "update $Dest (old copy kept as .bak-$Stamp)" {
      Copy-Item -LiteralPath $Dest -Destination (Get-FreePath "$Dest.bak-$Stamp")
      Copy-Item -LiteralPath $Source -Destination $Dest -Force
    }
    return
  }
  Invoke-Change "install $Dest" {
    New-Item -ItemType Directory -Path (Split-Path $Dest -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Dest
    Add-Manifest $Dest
  }
}
# PowerShell 5.1 writes \u0027-style escapes and very wide indentation. Undo the escapes (only where the
# backslash is not itself escaped) and re-indent with 2 spaces. Only whitespace outside strings changes.
function Format-Json([string]$Json, [string]$Nl = "`r`n") {
  foreach ($pair in @(@('\u0027', "'"), @('\u003c', '<'), @('\u003e', '>'), @('\u0026', '&'))) {
    $Json = [regex]::Replace($Json, '(?<=(?:^|[^\\])(?:\\\\)*)' + [regex]::Escape($pair[0]), $pair[1])
  }
  $sb = New-Object Text.StringBuilder
  $chars = $Json.ToCharArray(); $indent = 0; $inStr = $false; $esc = $false
  for ($i = 0; $i -lt $chars.Length; $i++) {
    $ch = $chars[$i]
    if ($inStr) {
      [void]$sb.Append($ch)
      if ($esc) { $esc = $false } elseif ($ch -eq [char]'\') { $esc = $true } elseif ($ch -eq [char]'"') { $inStr = $false }
    } elseif ($ch -eq [char]'"') { $inStr = $true; [void]$sb.Append($ch) }
    elseif ($ch -eq [char]'{' -or $ch -eq [char]'[') {
      $close = if ($ch -eq [char]'{') { [char]'}' } else { [char]']' }
      $j = $i + 1; while ($j -lt $chars.Length -and [char]::IsWhiteSpace($chars[$j])) { $j++ }
      if ($j -lt $chars.Length -and $chars[$j] -eq $close) { [void]$sb.Append($ch).Append($close); $i = $j }
      else { $indent++; [void]$sb.Append($ch).Append($Nl).Append('  ' * $indent) }
    } elseif ($ch -eq [char]'}' -or $ch -eq [char]']') { $indent--; [void]$sb.Append($Nl).Append('  ' * $indent).Append($ch) }
    elseif ($ch -eq [char]',') { [void]$sb.Append(',').Append($Nl).Append('  ' * $indent) }
    elseif ($ch -eq [char]':') { [void]$sb.Append(': ') }
    elseif (-not [char]::IsWhiteSpace($ch)) { [void]$sb.Append($ch) }
  }
  return $sb.ToString() + $Nl
}

function Add-ManifestJson([hashtable]$Entry) { $AddedJson.Add('json|' + (ConvertTo-Json -InputObject ([pscustomobject]$Entry) -Compress -Depth 5)) }
function Get-Sha([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
# Creates missing folders and records each one (deepest last) so uninstall can remove them again if empty.
function New-RecordedDir([string]$Dir) {
  $missing = @(); $d = $Dir
  while ($d -and -not (Test-Path -LiteralPath $d)) { $missing = @($d) + $missing; $d = Split-Path $d -Parent }
  foreach ($m in $missing) { New-Item -ItemType Directory -Path $m -Force | Out-Null; Add-ManifestJson @{ kind = 'dir'; path = $m } }
}
# Copies one package file outside <Projects>. A new file is recorded with its hash (uninstall removes it only
# while unchanged); a changed existing file is kept as .bak-<time> and replaced (not recorded: it was there before).
function Copy-HomeFile([string]$Source, [string]$Dest) {
  if (-not (Test-Path -LiteralPath $Source)) { Note 'ERROR' "package file missing: $Source"; return }
  if (Test-Path -LiteralPath $Dest) {
    if ((Get-Sha $Dest) -eq (Get-Sha $Source)) { Note 'OK' "up to date: $Dest"; return }
    Invoke-Change "update $Dest (old copy kept as .bak-$Stamp)" {
      Copy-Item -LiteralPath $Dest -Destination (Get-FreePath "$Dest.bak-$Stamp")
      Copy-Item -LiteralPath $Source -Destination $Dest -Force
    }
    return
  }
  Invoke-Change "install $Dest" {
    New-RecordedDir (Split-Path $Dest -Parent)
    Copy-Item -LiteralPath $Source -Destination $Dest
    Add-ManifestJson @{ kind = 'file'; path = $Dest; sha256 = (Get-Sha $Dest) }
  }
}
# pluginConfigs.<Plugin>.options.instructionFiles from a parsed settings object, or $null.
function Get-InstructionFiles($S, [string]$Plugin) {
  if (-not $S -or -not $S.PSObject.Properties['pluginConfigs'] -or -not $S.pluginConfigs) { return $null }
  $p = $S.pluginConfigs.PSObject.Properties[$Plugin]; if (-not $p -or -not $p.Value) { return $null }
  $o = $p.Value.PSObject.Properties['options']; if (-not $o -or -not $o.Value) { return $null }
  $f = $o.Value.PSObject.Properties['instructionFiles']; if (-not $f) { return $null }
  return [string]$f.Value
}
# Full path of the script named $Leaf inside a hook command (quoted or not), or $null.
function Get-ScriptPath([string]$Cmd, [string]$Leaf) {
  if (-not $Cmd) { return $null }
  $e = [regex]::Escape($Leaf)
  $m = [regex]::Match($Cmd, '(?i)"([^"]*?' + $e + ')"')
  if (-not $m.Success) { $m = [regex]::Match($Cmd, '(?i)(\S*' + $e + ')') }
  if ($m.Success) { return (Resolve-UserPath $m.Groups[1].Value) }
  return $null
}
# Writes JSON, checks it parses, restores the backup if not. Keeps the file's newline style and final newline.
function Write-JsonChecked([string]$Path, $Obj, [string]$Raw, [bool]$Existed, [string]$Bak) {
  $nl = "`r`n"; if ($Existed -and $Raw -and $Raw.Contains("`n") -and -not $Raw.Contains("`r`n")) { $nl = "`n" }
  $json = Format-Json ($Obj | ConvertTo-Json -Depth 100) $nl
  if ($Existed -and $Raw -and -not $Raw.EndsWith("`n")) { $json = $json.TrimEnd("`r", "`n") }
  New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force | Out-Null
  if ($Existed) { Copy-Item -LiteralPath $Path -Destination $Bak -Force; Backup-File $Path }
  [IO.File]::WriteAllText($Path, $json, $Utf8NoBom)
  try { [IO.File]::ReadAllText($Path) | ConvertFrom-Json | Out-Null }
  catch { if ($Existed) { Copy-Item -LiteralPath $Bak -Destination $Path -Force } else { Remove-Item -LiteralPath $Path -Force }; throw "written JSON did not parse; restored the original" }
}
# Merges one hook command into a list of hook objects. Match by script file name: same path = keep,
# other path = re-point that entry, none = append. $Pending gets the manifest entries (written only on success).
function Merge-HookCommand($Container, [string]$Event, [string]$Leaf, [string]$Command, $NewItem, [string]$Target, [System.Collections.Generic.List[object]]$Pending, [ref]$Changes, [switch]$Nested) {
  $found = @()
  if ($Container.PSObject.Properties[$Event]) {
    foreach ($entry in @($Container.$Event)) {
      if (-not $entry) { continue }
      if ($Nested) { foreach ($h in @($entry.hooks)) { if ($h -and $h.PSObject.Properties['command'] -and ([string]$h.command) -match [regex]::Escape($Leaf)) { $found += $h } } }
      elseif ($entry.PSObject.Properties['command'] -and ([string]$entry.command) -match [regex]::Escape($Leaf)) { $found += $entry }
    }
  }
  $want = Resolve-UserPath (Get-ScriptPath $Command $Leaf)
  if ($found.Count) {
    if ($found.Count -gt 1) { Note 'WARN' "$Target $Event has $($found.Count) entries for $Leaf (duplicate); none added. Remove the extra one by hand." }
    if (@($found | Where-Object { (Get-ScriptPath ([string]$_.command) $Leaf) -ieq $want }).Count) { Note 'OK' "$Target $Event already runs $Leaf"; return }
    $h = $found[0]; $old = [string]$h.command
    $h.command = $Command
    $Pending.Add(@{ kind = 'hook-updated'; target = $Target; event = $Event; script = $Leaf; old = $old; new = $Command })
    $Changes.Value += "$Event`: re-point $Leaf"
    return
  }
  if ($Container.PSObject.Properties[$Event]) { $Container.$Event = @(@($Container.$Event) + $NewItem) }
  else { $Container | Add-Member -NotePropertyName $Event -NotePropertyValue @($NewItem) }
  $Pending.Add(@{ kind = 'hook'; target = $Target; event = $Event; script = $Leaf; command = $Command })
  $Changes.Value += "$Event += $Leaf"
}

# ---------------------------------------------------------------- final Workstation Status check
# Runs Workstation Status -NoPause (read-only, never prompts) and reports the FAIL / WARN counts.
# The manual steps (admin command, the two pastes, sign-ins) are walked through by the installing
# agent from SETUP-PROMPT.txt; install does not list or confirm them. Setup is finished only when
# Workstation Status shows 0 FAIL and 0 WARN (SETUP-PROMPT.txt last check).
function Invoke-StatusCheck {
  $ErrorActionPreference = 'Continue'  # PS 5.1: native stderr with 2>&1 must not stop the script
  if ($testMode -or $WhatIf) {
    Write-Host ''
    Write-Host ('  ' + $(if ($WhatIf) { 'Dry run' } else { 'Test mode (-UserHome)' }) + ': not running Workstation Status.') -ForegroundColor Cyan
    return
  }
  $statusRel = @($TK.Shortcuts | Where-Object { $_.Name -eq 'Workstation Status' } | ForEach-Object { $_.Script }) | Select-Object -First 1
  if (-not $statusRel) { $statusRel = 'shortcuts\workstation-status.ps1' }
  $statusPs = Join-Path $BridgeDir $statusRel
  Write-Host ''
  Write-Host "Workstation Status check: $statusPs -NoPause" -ForegroundColor White
  if (-not (Test-Path -LiteralPath $statusPs)) { Write-Host "  [FAIL] Workstation Status script not found: $statusPs" -ForegroundColor Red; return }
  $out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $statusPs -NoPause 2>&1 | ForEach-Object { [string]$_ })
  foreach ($l in $out) { Write-Host $l }
  $fails = @($out | Where-Object { $_ -match '\[FAIL\]' }).Count
  $warns = @($out | Where-Object { $_ -match '\[WARN\]' }).Count
  Write-Host ("  Workstation Status: {0} FAIL, {1} WARN" -f $fails, $warns) -ForegroundColor White
  if ($fails -or $warns) { Write-Host '  Setup is finished only at 0 FAIL and 0 WARN. The remaining SETUP-PROMPT.txt steps usually clear these.' -ForegroundColor Yellow }
  else { Write-Host '  Workstation Status: 0 FAIL, 0 WARN.' -ForegroundColor Green }
}

# ---------------------------------------------------------------- start
Write-Host ''
Write-Host ('Workstation setup install' + $(if ($WhatIf) { '  (DRY RUN: nothing will change)' } else { '' })) -ForegroundColor White
Write-Host "  User home     : $UserHome"
Write-Host "  Projects root : $ProjectsRoot"
Write-Host "  Claude key    : $ProjectKey"
Write-Host "  Memory store  : $Store"
Write-Host "  Junction      : $LinkPath"
Write-Host "  Store alias   : $WmLink"
Write-Host "  Startup folder: $StartupFolder"
Write-Host "  Toolkit (runs from the clone): $BridgeDir"
Write-Host "  Runtime folder: $StateDir"
Write-Host ''

$isAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole((New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544'))
if ($isAdmin) { Note 'WARN' 'running elevated. This script is meant for a normal PowerShell window; files will still go to the current user.' }
if (-not (Test-Path -LiteralPath $Templates)) { Note 'ERROR' "templates folder not found next to this script: $Templates"; exit 1 }

# 0. Preflight (read-only). Stops on CONFLICT unless -AcceptConflicts.
$Preflight = $null
$pfScript = Join-Path $PkgRoot 'preflight.ps1'
if (-not (Test-Path -LiteralPath $pfScript)) { Note 'ERROR' "preflight.ps1 not found next to this script: $pfScript"; exit 1 }
$pfArgs = @{ ProjectsRoot = $ProjectsRoot; StartupFolder = $StartupFolder; PassThru = $true }
if ($testMode) { $pfArgs.UserHome = $UserHome }
if ($ReportDir) { $pfArgs.ReportDir = $ReportDir }
try { $Preflight = @(& $pfScript @pfArgs) | Where-Object { $_ -and $_.PSObject.Properties['Findings'] } | Select-Object -Last 1 }
catch { Note 'ERROR' "preflight failed: $($_.Exception.Message)"; exit 1 }
if (-not $Preflight) { Note 'ERROR' 'preflight returned no result'; exit 1 }
Write-Host ''
if ($Preflight.Conflicts -gt 0) {
  if ($AcceptConflicts) { Note 'WARN' "preflight found $($Preflight.Conflicts) CONFLICT(s); continuing because -AcceptConflicts was given. Report: $($Preflight.ReportPath)" }
  elseif ($WhatIf) { Note 'WARN' "preflight found $($Preflight.Conflicts) CONFLICT(s). A real run STOPS here until they are resolved (or -AcceptConflicts after review). Dry run continues. Report: $($Preflight.ReportPath)" }
  else {
    Note 'ERROR' "preflight found $($Preflight.Conflicts) CONFLICT(s). Nothing was changed. Resolve them (report: $($Preflight.ReportPath)), or re-run with -AcceptConflicts after the user reviewed the report."
    exit 2
  }
} else { Note 'OK' "preflight: no conflicts (report: $($Preflight.ReportPath))" }
Write-Host ''

# 1. Projects root layout (create missing folders only; never move anything)
Ensure-Dir $ProjectsRoot 'Projects root'
foreach ($sub in @('active', '_archive', '_scratch', '_claude')) { Ensure-Dir (Join-Path $ProjectsRoot $sub) "layout folder $sub" }
if (Test-Path -LiteralPath $ProjectsRoot) {
  $extra = @(Get-ChildItem -LiteralPath $ProjectsRoot -Force | Where-Object { (@('active', '_archive', '_scratch', '_claude', '_refs', 'CLAUDE.md', 'AGENTS.md') + @($TK.LegacyFolders)) -notcontains $_.Name -and $_.Name -notlike '.*' })
  if ($extra.Count -gt 0) { Note 'INFO' ("$($extra.Count) other item(s) in the Projects root (not moved). See REORGANIZE.md: " + (($extra | Select-Object -First 8 | ForEach-Object Name) -join ', ')) }
}

# 2. No memory sync: Cursor reads the store below read-only and keeps its own notes in <Projects>\_claude\Cursor Notes.
#    (Older installs had a Claude-Memory-To-Cursor-Sync task and copy; preflight flags them as retired.)

# 3. Memory store (empty starter files only if missing)
Ensure-Dir $Store 'memory store'
Ensure-Dir (Join-Path $Store '_unassigned') 'memory _unassigned'
Ensure-Dir (Join-Path $Store '_archive') 'memory _archive'
New-FileIfMissing (Join-Path $Store 'MEMORY.md') 'MEMORY.md'
New-FileIfMissing (Join-Path $Store '_unassigned\INDEX.md') 'unassigned-INDEX.md'
Add-MemoryBlock (Join-Path $WorkingMem 'CLAUDE.md') 'working-memory-CLAUDE.md' -CreateIfMissing

# 4. Cursor's own notes folder (one folder, one INDEX.md). Cursor never writes in the store.
Ensure-Dir $CursorNotes 'Cursor Notes'
New-FileIfMissing (Join-Path $CursorNotes 'INDEX.md') 'cursor-notes-INDEX.md'

# Safety check (read only): autoMemoryDirectory must be the junction path, not the store itself. The current
# guard leaves that case alone, but older guard versions treated the store as a stray folder and deleted it.
# As a safety net, do not install or wire the guard at all in that case.
$AutoMemAtStore = $false
if (Test-Path -LiteralPath $SettingsPath) {
  try {
    $am = ([IO.File]::ReadAllText($SettingsPath) | ConvertFrom-Json).autoMemoryDirectory
    if ($am -and ((Resolve-UserPath ([string]$am)) -ieq $Store)) { $AutoMemAtStore = $true }
  } catch { }
}
if ($AutoMemAtStore) {
  Note 'WARN' "REFUSED: autoMemoryDirectory in $SettingsPath points straight at the store ($Store), not at the junction path. Older guard versions could delete the store in that setup, so as a safety net the guard is not installed or wired and settings.json is not changed. Fix it by hand (README.md > Troubleshooting), then re-run install.ps1."
}

# 5. Guard hook script + its config (the guard reads storePath from memory-link-guard.config.json)
if ($AutoMemAtStore) { Note 'SKIP' "guard hook not installed (see the REFUSED warning): $GuardDest" }
else { Copy-HomeFile (Join-Path $PkgRoot 'memory\hooks\memory-link-guard.ps1') $GuardDest }   # recorded only when this run adds it
if (Test-Path -LiteralPath $GuardCfg) {
  $cur = $null
  try { $cur = (Get-Content -LiteralPath $GuardCfg -Raw | ConvertFrom-Json).storePath } catch { }
  if ($cur -and ([IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($cur)).TrimEnd('\') -ieq $Store)) { Note 'OK' "guard config points at the store: $GuardCfg" }
  else { Note 'WARN' "guard config exists but points somewhere else ($cur). Left alone: $GuardCfg" }
} else {
  $cfgJson = (@{ storePath = $Store } | ConvertTo-Json)
  Invoke-Change "create guard config: $GuardCfg" {
    New-RecordedDir $HooksDir
    [IO.File]::WriteAllText($GuardCfg, $cfgJson, $Utf8NoBom)
    Add-ManifestJson @{ kind = 'file'; path = $GuardCfg; sha256 = (Get-Sha $GuardCfg) }
  }
}

# 6. Junction ~\.claude\projects\<key>\memory -> store
$DeferHook = $false
$link = Get-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue
if (-not $link) {
  Invoke-Change "create junction $LinkPath -> $Store" {
    New-RecordedDir (Split-Path $LinkPath -Parent)
    New-Item -ItemType Junction -Path $LinkPath -Target $Store | Out-Null
    $AddedLinks.Add($LinkPath)
  }
} elseif ($link.LinkType) {
  $targets = @($link.Target | ForEach-Object { ($_ -replace '^\\\?\?\\', '').TrimEnd('\') })
  if ($targets -contains $Store) { Note 'OK' "junction already points at the store: $LinkPath" }
  else { Note 'WARN' ("$LinkPath is a $($link.LinkType) to '" + ($targets -join ';') + "', not the store. Left alone; include that target in MIGRATION.md. The guard hook will re-point the link (it never deletes the old target's files).") }
} else {
  $n = @(Get-ChildItem -LiteralPath $LinkPath -Force -Recurse -ErrorAction SilentlyContinue).Count
  if ($n -eq 0) {
    Invoke-Change "replace EMPTY folder with junction: $LinkPath -> $Store" {
      [IO.Directory]::Delete($LinkPath)
      New-Item -ItemType Junction -Path $LinkPath -Target $Store | Out-Null
      $AddedLinks.Add($LinkPath)
    }
  } else {
    $DeferHook = $true
    Note 'WARN' "$LinkPath is a real folder with $n item(s). NOT replaced. Do MIGRATION.md first, then move that folder aside and re-run install.ps1. The SessionStart guard hook is not wired until then (it would otherwise move those notes on its own)."
  }
}

# 6b. Junction ~\.claude\working-memory -> store. Same path on every PC, so the Cowork Global instructions line
#     (account-wide) never names a user or a Projects folder. Never changes an existing folder or other link.
$wmItem = Get-Item -LiteralPath $WmLink -Force -ErrorAction SilentlyContinue
if (-not $wmItem) {
  Invoke-Change "create junction $WmLink -> $Store" {
    New-Item -ItemType Directory -Path $DotClaude -Force | Out-Null
    New-Item -ItemType Junction -Path $WmLink -Target $Store | Out-Null
    $AddedLinks.Add($WmLink)
  }
} elseif ($wmItem.LinkType) {
  $targets = @($wmItem.Target | ForEach-Object { ($_ -replace '^\\\?\?\\', '').TrimEnd('\') })
  if ($targets -contains $Store) { Note 'OK' "junction already points at the store: $WmLink" }
  else { Note 'WARN' ("$WmLink is a $($wmItem.LinkType) to '" + ($targets -join ';') + "', not the store. Left alone; the Cowork Global instructions line will not reach the store on this PC until it is fixed by hand.") }
} elseif ($wmItem.PSIsContainer) {
  Note 'WARN' "$WmLink is a real folder, not a junction. Left alone; move it aside by hand and re-run install.ps1 so the Cowork Global instructions line reaches the store."
} else {
  Note 'WARN' "$WmLink is a file, not a junction. Left alone; move it aside by hand and re-run install.ps1."
}

# 6c. 80% handoff files: context-guard.ps1, handoff-at-80.py (only with py -3), the skill (never overwritten)
Copy-HomeFile (Join-Path $HandoffPkg 'claude\context-guard.ps1') $CtxDest
$CursorHookOk = [bool]$Preflight.PyOk
if ($CursorHookOk) { Copy-HomeFile (Join-Path $HandoffPkg 'cursor\handoff-at-80.py') $CursorHookDest }
else { Note 'WARN' "py -3 (Python 3.7+) not available: Cursor 80% handoff hook skipped ($CursorHookDest, $CursorHooksJson unchanged). Install Python 3, then re-run install.ps1." }
# The skill the hooks trigger is agent-handoff-pack (skills\), linked by -LinkSkills (section 9b).

# 7. ~\.claude\settings.json: merge (autoMemoryDirectory + SessionStart guard hook + handoff hooks/statusLine), keep everything else
$settings = $null; $settingsOk = $true; $settingsExisted = Test-Path -LiteralPath $SettingsPath
if ($AutoMemAtStore) {
  $settingsOk = $false
  Note 'SKIP' "settings.json left unchanged (see the REFUSED warning): $SettingsPath"
  if (Select-String -LiteralPath $SettingsPath -Pattern 'memory-link-guard\.ps1' -Quiet) { Note 'WARN' 'the guard hook is ALREADY wired while autoMemoryDirectory points at the store: do not start Claude Code until autoMemoryDirectory is fixed.' }
} elseif ($settingsExisted) {
  try {
    $raw = [IO.File]::ReadAllText($SettingsPath)
    if ($raw.Trim()) { $settings = $raw | ConvertFrom-Json } else { $settings = New-Object psobject }
  } catch { $settingsOk = $false; Note 'ERROR' "could not parse $SettingsPath (left unchanged): $($_.Exception.Message)" }
} else { $settings = New-Object psobject }
if ($settingsOk) {
  $changes = @()
  # First install on this profile = no manifest yet. Only then is something that is already in place recorded as
  # pre-existing (a later run finds what an earlier install of this package set, and must not claim it).
  $firstInstall = -not (Test-Path -LiteralPath $ManifestPath)
  $oldAuto = $null; $hadAuto = [bool]$settings.PSObject.Properties['autoMemoryDirectory']
  if ($hadAuto) { $oldAuto = [string]$settings.autoMemoryDirectory }
  if ($oldAuto -ne $AutoMemValue) {
    if ($oldAuto) { Note 'WARN' "autoMemoryDirectory was '$oldAuto'. Include that folder in MIGRATION.md (uninstall.ps1 puts that value back; it is also in the settings .bak)." }
    if ($hadAuto) { $settings.autoMemoryDirectory = $AutoMemValue }
    else { $settings | Add-Member -NotePropertyName autoMemoryDirectory -NotePropertyValue $AutoMemValue }
    $changes += "autoMemoryDirectory = $AutoMemValue"
    # uninstall restores exactly this: the prior value, or no key at all
    Add-ManifestJson @{ kind = 'automem'; target = 'claude'; value = $AutoMemValue; hadPrior = $hadAuto; prior = $(if ($hadAuto) { $oldAuto } else { $null }) }
  } else {
    Note 'OK' "autoMemoryDirectory already $AutoMemValue"
    if ($firstInstall) { Add-ManifestJson @{ kind = 'automem-preexisting'; target = 'claude'; value = $AutoMemValue } }
  }

  $hasGuard = $false
  if ($settings.PSObject.Properties['hooks'] -and $settings.hooks -and $settings.hooks.PSObject.Properties['SessionStart']) {
    foreach ($entry in @($settings.hooks.SessionStart)) {
      foreach ($h in @($entry.hooks)) { if ($h -and ([string]$h.command) -match 'memory-link-guard\.ps1') { $hasGuard = $true } }
    }
  }
  if ($hasGuard) {
    Note 'OK' 'SessionStart guard hook already in settings.json'
    if ($firstInstall) { Add-ManifestJson @{ kind = 'guard-hook-preexisting'; target = 'claude'; guardScript = $GuardScriptPre; guardConfig = $GuardCfgPre } }
    if ($DeferHook) { Note 'WARN' 'the guard hook is already wired while the junction path is a real folder: start no Claude Code session until MIGRATION.md is done.' }
  } elseif ($DeferHook) {
    Note 'WARN' 'SessionStart guard hook NOT added yet (junction path is a real folder with notes). Re-run install.ps1 after the migration.'
  } else {
    if (-not $settings.PSObject.Properties['hooks'] -or -not $settings.hooks) {
      if ($settings.PSObject.Properties['hooks']) { $settings.hooks = New-Object psobject } else { $settings | Add-Member -NotePropertyName hooks -NotePropertyValue (New-Object psobject) }
    }
    $newEntry = [pscustomobject]@{ hooks = @([pscustomobject]@{ type = 'command'; command = $GuardCommand; timeout = 20 }) }
    if ($settings.hooks.PSObject.Properties['SessionStart']) { $settings.hooks.SessionStart = @(@($settings.hooks.SessionStart) + $newEntry) }
    else { $settings.hooks | Add-Member -NotePropertyName SessionStart -NotePropertyValue @($newEntry) }
    $changes += 'hooks.SessionStart += memory-link-guard.ps1'
    Add-ManifestJson @{ kind = 'guard-hook'; target = 'claude'; command = $GuardCommand }
  }

  # 80% handoff: Stop + PreCompact hooks and the statusLine (context-guard.ps1)
  $pendingS = New-Object System.Collections.Generic.List[object]
  if (-not $settings.PSObject.Properties['hooks'] -or -not $settings.hooks) {
    if ($settings.PSObject.Properties['hooks']) { $settings.hooks = New-Object psobject } else { $settings | Add-Member -NotePropertyName hooks -NotePropertyValue (New-Object psobject) }
  }
  $stopCmd = Get-CtxCommand 'stop'; $preCmd = Get-CtxCommand 'precompact'
  Merge-HookCommand $settings.hooks 'PreCompact' 'context-guard.ps1' $preCmd ([pscustomobject]@{ hooks = @([pscustomobject]@{ type = 'command'; command = $preCmd; timeout = 60; statusMessage = 'Backing up before compaction...' }) }) 'claude' $pendingS ([ref]$changes) -Nested
  Merge-HookCommand $settings.hooks 'Stop' 'context-guard.ps1' $stopCmd ([pscustomobject]@{ hooks = @([pscustomobject]@{ type = 'command'; command = $stopCmd; timeout = 15 }) }) 'claude' $pendingS ([ref]$changes) -Nested
  $slCmd = Get-CtxCommand 'statusline'
  $curSl = $null; if ($settings.PSObject.Properties['statusLine']) { $curSl = $settings.statusLine }
  $curSlCmd = ''; if ($curSl -and $curSl.PSObject.Properties['command']) { $curSlCmd = [string]$curSl.command }
  if (-not $curSl) {
    $newSl = [pscustomobject]@{ type = 'command'; command = $slCmd }
    if ($settings.PSObject.Properties['statusLine']) { $settings.statusLine = $newSl } else { $settings | Add-Member -NotePropertyName statusLine -NotePropertyValue $newSl }
    $pendingS.Add(@{ kind = 'statusline'; target = 'claude'; command = $slCmd }); $changes += 'statusLine = context-guard.ps1 statusline'
  } elseif ($curSlCmd -match 'context-guard\.ps1') {
    if ((Get-ScriptPath $curSlCmd 'context-guard.ps1') -ieq $CtxDest) { Note 'OK' 'statusLine already runs context-guard.ps1' }
    else { $curSl.command = $slCmd; $pendingS.Add(@{ kind = 'statusline-updated'; target = 'claude'; old = $curSlCmd; new = $slCmd }); $changes += 'statusLine: re-point context-guard.ps1' }
  } else {
    $shown = if ($curSlCmd) { $curSlCmd } else { ($curSl | ConvertTo-Json -Compress) }
    Note 'WARN' "an unrelated statusLine is set and was NOT overwritten: $shown. The Claude Code 80% handoff cannot measure context without the context-guard statusLine, so it will not fire. Decide which one to keep."
    Add-ManifestJson @{ kind = 'note'; what = 'statusline-kept'; existing = $shown }
  }

  # Project instructions: read CLAUDE.md AND AGENTS.md. Without this, any CLAUDE.md or CLAUDE.local.md (the memory
  # pointer) at or above the working folder hides AGENTS.md. Honored only in the user settings file.
  $ReadBoth = 'claude-md-and-agents-md'
  $cv = $Preflight.ClaudeVer
  $ap = [string]$Preflight.AgentsPlugin; if (-not $ap) { $ap = 'cc-plugin-agents-md@builtin' }
  if (-not $cv) { Note 'WARN' "Claude Code not found (claude --version). AGENTS.md loading needs Claude Code 2.1.281 or newer; the read-both option is still set (under $ap)." }
  elseif ($cv -lt [version]'2.1.281') { Note 'WARN' "Claude Code $cv is older than 2.1.281: it may not load AGENTS.md. Update Claude Code. The read-both option is set under $ap (newer versions read it too)." }
  else { Note 'OK' "Claude Code $cv (AGENTS.md loading needs 2.1.281+); plugin id $ap" }
  $otherId = if ($ap -eq 'agents-md@builtin') { 'cc-plugin-agents-md@builtin' } else { 'agents-md@builtin' }
  $curIF = Get-InstructionFiles $settings $ap
  $otherOk = ($cv -and $cv -ge [version]'2.1.285' -and (Get-InstructionFiles $settings $otherId) -eq $ReadBoth)
  if ($curIF -eq $ReadBoth -or $otherOk) {
    Note 'OK' "Project instructions already $ReadBoth (pluginConfigs > $(if ($curIF -eq $ReadBoth) { $ap } else { $otherId }))"
    if ($firstInstall) { Add-ManifestJson @{ kind = 'plugin-config-preexisting'; target = 'claude'; plugin = $ap; value = $ReadBoth } }
  } else {
    $hadPC = [bool]($settings.PSObject.Properties['pluginConfigs'] -and $settings.pluginConfigs)
    if (-not $hadPC) {
      if ($settings.PSObject.Properties['pluginConfigs']) { $settings.pluginConfigs = New-Object psobject } else { $settings | Add-Member -NotePropertyName pluginConfigs -NotePropertyValue (New-Object psobject) }
    }
    $hadP = [bool]($settings.pluginConfigs.PSObject.Properties[$ap] -and $settings.pluginConfigs.$ap)
    if (-not $hadP) {
      if ($settings.pluginConfigs.PSObject.Properties[$ap]) { $settings.pluginConfigs.$ap = New-Object psobject } else { $settings.pluginConfigs | Add-Member -NotePropertyName $ap -NotePropertyValue (New-Object psobject) }
    }
    $pobj = $settings.pluginConfigs.$ap
    $hadO = [bool]($pobj.PSObject.Properties['options'] -and $pobj.options)
    if (-not $hadO) {
      if ($pobj.PSObject.Properties['options']) { $pobj.options = New-Object psobject } else { $pobj | Add-Member -NotePropertyName options -NotePropertyValue (New-Object psobject) }
    }
    $hadIF = [bool]$pobj.options.PSObject.Properties['instructionFiles']
    if ($hadIF) { Note 'WARN' "Project instructions was '$curIF'; set to $ReadBoth (uninstall.ps1 puts '$curIF' back)."; $pobj.options.instructionFiles = $ReadBoth }
    else { $pobj.options | Add-Member -NotePropertyName instructionFiles -NotePropertyValue $ReadBoth }
    $changes += "pluginConfigs.$ap.options.instructionFiles = $ReadBoth"
    # uninstall reverts exactly this key (prior value, or no key, plus the parent objects install created)
    $pendingS.Add(@{ kind = 'plugin-config'; target = 'claude'; plugin = $ap; value = $ReadBoth; hadPrior = $hadIF; prior = $(if ($hadIF) { $curIF } else { $null }); createdPluginConfigs = (-not $hadPC); createdPlugin = (-not $hadP); createdOptions = (-not $hadO) })
  }

  if ($changes.Count -gt 0) {
    $bak = Get-FreePath "$SettingsPath.bak-$Stamp"
    $what = "update $SettingsPath (" + ($changes -join '; ') + ')' + $(if ($settingsExisted) { "; backup $bak" } else { '' })
    Invoke-Change $what {
      Write-JsonChecked $SettingsPath $settings $raw $settingsExisted $bak
      foreach ($p in $pendingS) { Add-ManifestJson $p }
    }
  }
}

# 7b. ~\.cursor\hooks.json: preCompact + stop run handoff-at-80.py (only with py -3); armed flag
if ($CursorHookOk) {
  $hjExisted = Test-Path -LiteralPath $CursorHooksJson
  $hj = $null; $hjRaw = $null; $hjOk = $true
  if ($hjExisted) {
    try { $hjRaw = [IO.File]::ReadAllText($CursorHooksJson); if ($hjRaw.Trim()) { $hj = $hjRaw | ConvertFrom-Json } else { $hj = New-Object psobject } }
    catch { $hjOk = $false; Note 'ERROR' "could not parse $CursorHooksJson (left unchanged): $($_.Exception.Message)" }
  } else { $hj = [pscustomobject]@{ version = 1; hooks = (New-Object psobject) } }
  if ($hjOk) {
    if (-not $hj.PSObject.Properties['version']) { $hj | Add-Member -NotePropertyName version -NotePropertyValue 1 }
    if (-not $hj.PSObject.Properties['hooks'] -or -not $hj.hooks) {
      if ($hj.PSObject.Properties['hooks']) { $hj.hooks = New-Object psobject } else { $hj | Add-Member -NotePropertyName hooks -NotePropertyValue (New-Object psobject) }
    }
    $hjChanges = @(); $pendingC = New-Object System.Collections.Generic.List[object]
    Merge-HookCommand $hj.hooks 'preCompact' 'handoff-at-80.py' $CursorCommand ([pscustomobject]@{ command = $CursorCommand; timeout = 10 }) 'cursor' $pendingC ([ref]$hjChanges)
    Merge-HookCommand $hj.hooks 'stop' 'handoff-at-80.py' $CursorCommand ([pscustomobject]@{ command = $CursorCommand; timeout = 10; loop_limit = 1 }) 'cursor' $pendingC ([ref]$hjChanges)
    if ($hjChanges.Count) {
      $hbak = Get-FreePath "$CursorHooksJson.bak-$Stamp"
      Invoke-Change ("update $CursorHooksJson (" + ($hjChanges -join '; ') + ')' + $(if ($hjExisted) { "; backup $hbak" } else { '; new file' })) {
        if (-not $hjExisted) { New-RecordedDir (Split-Path $CursorHooksJson -Parent) }
        Write-JsonChecked $CursorHooksJson $hj $hjRaw $hjExisted $hbak
        if (-not $hjExisted) { Add-ManifestJson @{ kind = 'file-created'; target = 'cursor'; path = $CursorHooksJson } }
        foreach ($p in $pendingC) { Add-ManifestJson $p }
      }
    }
    if (Test-Path -LiteralPath $ArmedPath) { Note 'OK' "Cursor handoff hook armed: $ArmedPath" }
    elseif ($pendingC.Count -and @($pendingC | Where-Object { $_.kind -eq 'hook' }).Count -eq $pendingC.Count) {
      Invoke-Change "arm the Cursor handoff hook: $ArmedPath" {
        New-RecordedDir (Split-Path $ArmedPath -Parent)
        [IO.File]::WriteAllText($ArmedPath, 'armed', $Utf8NoBom)
        Add-ManifestJson @{ kind = 'file'; path = $ArmedPath; sha256 = (Get-Sha $ArmedPath) }
      }
    } else { Note 'WARN' "Cursor handoff hook was already wired but is disarmed (no $ArmedPath). Left as is; create that file to arm it." }
  }
}

# 8. Rule files: append the memory section where the marker is missing
Add-MemoryBlock (Join-Path $DotClaude 'CLAUDE.md') 'claude-global-memory-section.md' -CreateIfMissing
Add-MemoryBlock $CursorRule 'claude-shared-memory.mdc' -CreateIfMissing
# Projects root: AGENTS.md is the one root guide. A root CLAUDE.md is merged into it by hand (REORGANIZE.md step 5).
$RootClaudeMd = Join-Path $ProjectsRoot 'CLAUDE.md'
$RootAgentsMd = Join-Path $ProjectsRoot 'AGENTS.md'
$rootClaudeMarked = $false
if (Test-Path -LiteralPath $RootClaudeMd) {
  $rootClaudeMarked = ([IO.File]::ReadAllText($RootClaudeMd)).Contains($Marker)
  Note 'WARN' "root CLAUDE.md still exists: $RootClaudeMd. Merge it into AGENTS.md, then delete it (REORGANIZE.md step 5). Install never changes it."
}
$rootAgentsMarked = (Test-Path -LiteralPath $RootAgentsMd) -and ([IO.File]::ReadAllText($RootAgentsMd)).Contains($Marker)
if ($rootClaudeMarked -and -not $rootAgentsMarked) { Note 'SKIP' "memory section not added to ${RootAgentsMd}: the root CLAUDE.md already has it (no second copy). It moves over with the merge." }
else { Add-MemoryBlock $RootAgentsMd 'projects-AGENTS.md' -CreateIfMissing }
# Claude's instruction texts (instructions\ in the package) are pasted by hand; install never edits them.
# 'Instructions for Claude' is account-level (not on disk): only a reminder. Cowork Global instructions are stored
# in local-agent-mode-sessions\<account>\<org>\memory\CLAUDE.md: checked for the working-memory line, read-only.
Note 'TODO' 'Reminder: paste instructions\instructions-for-claude.md into Claude desktop > Settings > Instructions for Claude (account-level; cannot be checked on disk). Skip if already done.'
$CoworkText = 'instructions\cowork-global-instructions.md'
$CoworkLineRx = '(?i)\.claude\s*[\\/]\s*working-memory'
$coworkFiles = @()
foreach ($pattern in @((Join-Path $LocalAppData 'Packages\Claude_*\LocalCache\Roaming\Claude\local-agent-mode-sessions\*\*\memory\CLAUDE.md'),
                       (Join-Path $RoamingAppData 'Claude\local-agent-mode-sessions\*\*\memory\CLAUDE.md'))) {
  if ($pattern) { $coworkFiles += @(Get-ChildItem -Path $pattern -File -Force -ErrorAction SilentlyContinue | ForEach-Object FullName) }
}
$coworkWith = @($coworkFiles | Where-Object { [IO.File]::ReadAllText($_) -match $CoworkLineRx })
if ($coworkWith.Count) {
  foreach ($f in $coworkWith) { Note 'OK' "ALREADY-INSTALLED: Cowork Global instructions have the working-memory line (not changed): $f" }
  foreach ($f in @($coworkFiles | Where-Object { $coworkWith -notcontains $_ })) { Note 'INFO' "other Cowork account/org folder without the working-memory line (left alone): $f" }
} elseif ($coworkFiles.Count) {
  Note 'TODO' ("Cowork Global instructions do not have the working-memory line yet (not changed): " + ($coworkFiles -join ' | ') + ". Paste $CoworkText into Claude desktop > Cowork settings > Global instructions.")
} else {
  Note 'TODO' "Cowork Global instructions not found on this PC. Paste $CoworkText into Claude desktop > Cowork settings > Global instructions."
}

# 9. Toolkit: runs straight from this package's toolkit folder (no copy). Write the runtime config the scripts read
#    (%LOCALAPPDATA%\<StateFolder>\<ConfigFile>: projectsRoot), then create the shortcuts in <package>\<ShortcutFolder>
#    (resolved from this script's folder; the .lnk files are gitignored).
if (-not (Test-Path -LiteralPath $BridgeDir)) { Note 'ERROR' "toolkit folder missing from the package: $BridgeDir" }
else { Note 'OK' "toolkit runs from the package (nothing copied under $ProjectsRoot): $BridgeDir" }
$gitDir = Join-Path $PkgRoot '.git'
if (Test-Path -LiteralPath $gitDir) {
  $ErrorActionPreference = 'Continue'
  $br = $null; try { $br = (& git -C $PkgRoot rev-parse --abbrev-ref HEAD 2>$null | Select-Object -First 1) } catch { }
  $ErrorActionPreference = 'Stop'
  if ($br -and @('main', 'master') -notcontains [string]$br) { Note 'WARN' "this clone is on branch '$br', not main: the shortcuts and the Cursor worker run whatever is checked out here. Switch it back to main." }
  elseif ($br) { Note 'OK' "package clone is on $br (the toolkit runs what is checked out)" }
  else { Note 'INFO' "could not read this clone's branch with git (keep it on main: the toolkit runs what is checked out)" }
}
$cfgWant = [ordered]@{ projectsRoot = $ProjectsRoot; toolkit = $BridgeDir }
$cfgText = (ConvertTo-Json -InputObject ([pscustomobject]$cfgWant)) + "`r`n"
$cfgCur = $null
if (Test-Path -LiteralPath $WsConfig) { try { $cfgCur = [IO.File]::ReadAllText($WsConfig) | ConvertFrom-Json } catch { } }
if ($cfgCur -and ([string]$cfgCur.projectsRoot -ieq $ProjectsRoot) -and ([string]$cfgCur.toolkit -ieq $BridgeDir)) { Note 'OK' "runtime config up to date: $WsConfig" }
elseif (Test-Path -LiteralPath $WsConfig) {
  Invoke-Change "update runtime config $WsConfig (projectsRoot = $ProjectsRoot; toolkit = $BridgeDir; old copy kept as .bak-$Stamp)" {
    Copy-Item -LiteralPath $WsConfig -Destination (Get-FreePath "$WsConfig.bak-$Stamp")
    [IO.File]::WriteAllText($WsConfig, $cfgText, $Utf8NoBom)
  }
} else {
  Invoke-Change "create runtime config $WsConfig (projectsRoot = $ProjectsRoot; toolkit = $BridgeDir)" {
    New-RecordedDir $StateDir
    [IO.File]::WriteAllText($WsConfig, $cfgText, $Utf8NoBom)
    Add-ManifestJson @{ kind = 'file'; path = $WsConfig; sha256 = (Get-Sha $WsConfig) }
  }
}
$shortcutScript = Join-Path $BridgeDir $TK.ShortcutsInstaller
$scDir = [IO.Path]::GetFullPath((Join-Path $PkgRoot $TK.ShortcutFolder)).TrimEnd('\')
$shortcutPlan = "create or update '$scDir' with " + (($TK.Shortcuts | ForEach-Object { $_.Name }) -join ', ') + "; remove old copies (loose Desktop links and links in the old Desktop '" + ($TK.LegacyShortcutFolders -join "', '") + "' folders, only links that run these scripts, then those folders once empty); then run the read-only prerequisite checks"
if ($testMode) { Note 'SKIP' "test mode (-UserHome): not running $(Split-Path $shortcutScript -Leaf), it cleans old links on the real Desktop. It would $shortcutPlan" }
elseif ($WhatIf) { Note 'WOULD' "run $shortcutScript -LinkDir `"$scDir`" -NoPause: $shortcutPlan" }
elseif (-not (Test-Path -LiteralPath $shortcutScript)) { Note 'ERROR' "not found: $shortcutScript" }
else {
  Write-Host ''
  # Record only the links (and the folder) this run creates, so uninstall removes exactly those.
  $scDirPre = Test-Path -LiteralPath $scDir
  $scPre = @{}; foreach ($sc in $TK.Shortcuts) { $scPre[$sc.Name] = Test-Path -LiteralPath (Join-Path $scDir "$($sc.Name).lnk") }
  # Links an earlier install recorded (it created them): when they are re-pointed, record the new script too, so
  # uninstall still recognizes them.
  $scRecorded = @()
  if (Test-Path -LiteralPath $ManifestPath) {
    foreach ($ln in @([IO.File]::ReadAllLines($ManifestPath) | Where-Object { $_ -like 'json|*' })) {
      try { $j = $ln.Substring(5) | ConvertFrom-Json; if ($j.kind -eq 'shortcut') { $scRecorded += $j } } catch { }
    }
  }
  $suPre = @{}; foreach ($u in @($TK.StartupLinks)) { $suPre[$u.Name] = Test-Path -LiteralPath (Join-Path $StartupFolder "$($u.Name).lnk") }
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $shortcutScript -LinkDir $scDir -StartupDir $StartupFolder -NoPause
  $scExit = $LASTEXITCODE
  foreach ($u in @($TK.StartupLinks)) {
    $lp = Join-Path $StartupFolder "$($u.Name).lnk"
    if (-not $suPre[$u.Name] -and (Test-Path -LiteralPath $lp)) { Add-ManifestJson @{ kind = 'startup-link'; path = $lp; script = (Join-Path $BridgeDir $u.Script) } }
  }
  if (-not $scDirPre -and (Test-Path -LiteralPath $scDir)) { Add-ManifestJson @{ kind = 'shortcut-dir'; path = $scDir } }
  foreach ($sc in $TK.Shortcuts) {
    $lp = Join-Path $scDir "$($sc.Name).lnk"
    $want = Join-Path $BridgeDir $sc.Script
    $rec = @($scRecorded | Where-Object { [string]$_.path -ieq $lp })
    if ((Test-Path -LiteralPath $lp) -and (-not $scPre[$sc.Name] -or ($rec.Count -and -not @($rec | Where-Object { [string]$_.script -ieq $want }).Count))) { Add-ManifestJson @{ kind = 'shortcut'; path = $lp; script = $want } }
  }
  if ($scExit -eq 0) { Note 'DONE' "shortcuts in $scDir (prerequisite results are listed above)" }
  else { Note 'WARN' "$(Split-Path $shortcutScript -Leaf) reported failures (exit $scExit). See its output above." }
}
# An old installed toolkit copy (LegacyFolders) is never moved or deleted; it is only reported.
foreach ($lf in @($TK.LegacyFolders | Where-Object { $_ })) {
  $lp = Join-Path $ProjectsRoot $lf
  if (Test-Path -LiteralPath $lp) { Note 'WARN' "old toolkit copy left in place: $lp (the toolkit now runs from $BridgeDir). Stop its workers (Workers Stop), check nothing else uses it, then archive it by hand." }
}

# 9b. Cursor starts at sign-in: keep an existing entry (even if it is turned off), else add Cursor.lnk
$cs = @($Preflight.CursorStartup)
if ($cs.Count -ge 1) {
  foreach ($e in $cs) {
    if ($e.Toggle -like 'OFF*') { Note 'WARN' "Cursor autostart exists but is turned OFF in Startup apps; left off (not changed): $($e.Path)" }
    else { Note 'OK' "Cursor autostart already set: $($e.Path)" }
  }
  if ($cs.Count -gt 1) { Note 'WARN' "$($cs.Count) Cursor autostart entries (duplicate launch). None added; keep one (see the preflight report)." }
} elseif (-not $Preflight.CursorExe) {
  Note 'WARN' 'Cursor.exe not found (Cursor not installed?). Cursor autostart skipped; re-run install.ps1 after installing Cursor.'
} else {
  $lnkPath = Join-Path $StartupFolder 'Cursor.lnk'
  if (Test-Path -LiteralPath $lnkPath) { Note 'WARN' "$lnkPath exists but does not start Cursor.exe; left alone, no autostart added." }
  else {
    $exe = [string]$Preflight.CursorExe
    Invoke-Change "add Cursor autostart: $lnkPath -> $exe" {
      New-RecordedDir $StartupFolder
      $wsh = New-Object -ComObject WScript.Shell
      $sc = $wsh.CreateShortcut($lnkPath)
      $sc.TargetPath = $exe
      $sc.WorkingDirectory = (Split-Path $exe -Parent)
      $sc.Description = 'Start Cursor at sign-in (workstation setup)'
      $sc.Save()
      Add-ManifestJson @{ kind = 'startup'; path = $lnkPath; target = $exe }
    }
  }
}

# 9b. Skills (opt-in, -LinkSkills): link (junction) this repo's skills\ into ~\.claude\skills only (Cursor reads it too);
#     old links from this repo in ~\.cursor\skills are removed (link only) so skills are not listed twice.
#     link-skills.ps1 backs up a same-name folder first and removes only its own links whose skill is gone (link only).
#     Other repos link their own skills from their own setup.
$skillTargets = @((Join-Path $DotClaude 'skills'))
if (-not $LinkSkills) { Note 'OK' 'skills: not linked (opt in with -LinkSkills)' }
else { try {
  foreach ($r in @(& (Join-Path $PSScriptRoot 'link-skills.ps1') -From (Join-Path $PSScriptRoot 'skills') -Targets $skillTargets -Unlink @((Join-Path $DotCursor 'skills')) -BackupRoot (Join-Path $UserHome '.skills-backup') -WhatIf:$WhatIf)) {
    if ($r.Action -eq 'ok') { Note 'OK' "skill link already in place: $($r.Path)" }
    elseif ($r.Action -eq 'would-link') { Note 'WOULD' "link skill $($r.Path) -> $($r.Target)" }
    elseif ($r.Action -eq 'would-prune') { Note 'WOULD' "remove dead skill link $($r.Path) -> $($r.Target)" }
    elseif ($r.Action -eq 'pruned') { Note 'DONE' "removed dead skill link $($r.Path) -> $($r.Target)" }
    elseif ($r.Action -eq 'would-unlink') { Note 'WOULD' "remove duplicate skill link $($r.Path) -> $($r.Target)" }
    elseif ($r.Action -eq 'unlinked') { Note 'DONE' "removed duplicate skill link $($r.Path) -> $($r.Target)" }
    elseif ($r.Action -eq 'would-retire') { Note 'WOULD' "move retired skill $($r.Path) to $($r.Target)" }
    elseif ($r.Action -eq 'retired') { Note 'DONE' "moved retired skill $($r.Path) to $($r.Target)" }
    else { Note 'DONE' "skill $($r.Path) -> $($r.Target) ($($r.Action))"; Add-ManifestJson @{ kind = 'skill-link'; path = $r.Path; target = $r.Target; backup = $r.Backup } }
  }
} catch { Note 'ERROR' ("link skills -- " + $_.Exception.Message) } }

# 9d. Ownership notes in the folders this install creates (add-only).
try {
  foreach ($r in @(& (Join-Path $PSScriptRoot 'ownership-notes.ps1') -ProjectsRoot $ProjectsRoot -UserHome $UserHome -StateDir $StateDir -WhatIf:$WhatIf)) {
    if ($r.Action -eq 'added') { Note 'DONE' "ownership note $($r.Path)"; Add-Manifest $r.Path }
  }
} catch { Note 'ERROR' ("ownership notes -- " + $_.Exception.Message) }

# 10. Record the files this run added (uninstall.ps1 removes only files listed here)
if (($AddedFiles.Count -gt 0 -or $AddedLinks.Count -gt 0 -or $AddedJson.Count -gt 0) -and -not $WhatIf) {
  try {
    $old = @(); if (Test-Path -LiteralPath $ManifestPath) { $old = @([IO.File]::ReadAllLines($ManifestPath)) }
    $all = @($old + $AddedFiles + @($AddedLinks | ForEach-Object { "junction|$_" }) + $AddedJson | Where-Object { $_ } | Select-Object -Unique)
    New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
    [IO.File]::WriteAllLines($ManifestPath, [string[]]$all, $Utf8NoBom)
    Note 'DONE' "recorded $($AddedFiles.Count) added file(s), $($AddedLinks.Count) junction(s) and $($AddedJson.Count) other item(s) in $ManifestPath"
  } catch { Note 'ERROR' "could not write $ManifestPath -- $($_.Exception.Message)" }
}

# ---------------------------------------------------------------- summary
Write-Host ''
Write-Host '==================== SUMMARY ====================' -ForegroundColor White
foreach ($s in 'DONE', 'WOULD', 'SKIP', 'WARN', 'ERROR') {
  $n = @($Summary | Where-Object Status -eq $s).Count
  if ($n) { Write-Host ("  {0,-5} : {1}" -f $s, $n) }
}
Write-Host ("  OK    : {0} (already in place)" -f @($Summary | Where-Object Status -eq 'OK').Count)
$attention = @($Summary | Where-Object { 'WARN', 'ERROR' -contains $_.Status })
if ($attention.Count) {
  Write-Host ''
  Write-Host 'Needs attention:' -ForegroundColor Yellow
  foreach ($a in $attention) { Write-Host ("  [{0}] {1}" -f $a.Status, $a.Item) -ForegroundColor Yellow }
}
Write-Host ''
if ($WhatIf) { Write-Host 'Dry run only. Nothing was changed. Run again without -WhatIf to apply.' -ForegroundColor Cyan }
else {
  Write-Host 'Next: open PowerShell with "Run as admin" (same Windows account) and run this one command:' -ForegroundColor White
  Write-Host ('  powershell -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $PkgRoot 'install-admin.ps1') + '" -ProjectsRoot "' + $ProjectsRoot + '"')
}
Invoke-StatusCheck
if (@($Summary | Where-Object Status -eq 'ERROR').Count) { exit 1 }
exit 0
