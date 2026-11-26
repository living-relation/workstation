<#
.SYNOPSIS
  Workstation setup: shared Claude / Cursor memory, the Bridge toolkit and the 80% handoff hooks, for the CURRENT
  Windows user. It adds no autostart: no scheduled task, no Startup item, no Run key.

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
  - The memory-store rules and the app lock rules (harness.design, Fusion Desktop) load from the workstation-core plugin's
    SessionStart hook (hooks\rules-inject.ps1) in Claude Code and the Cursor desktop app (owner decision 2026-11-22). Not in Cowork (hooks/README.md).
    Install no longer creates ~\.claude\CLAUDE.md or ~\.cursor\rules\claude-shared-memory.mdc and no longer
    appends to them or to repo-rules.mdc. A block an older install appended there is kept (the hook then
    skips that part). Install only fixes old paths inside such a block (fusion-lock -> app-lock,
    agents\projects-AGENTS.md -> instructions\projects-AGENTS.md), drops its retired Fusion rule lines, and adds the
    Fusion Desktop lock lines when the block has none.
  - <Projects>\AGENTS.md (read by every agent, including ones with no hooks) still gets the memory section
    (marker <!-- shared-memory:v1 -->) and the lock block (<!-- app-locks:v1 -->) when missing.
    uninstall removes only a block this install added.
  - Backs up ~\.claude\settings.json and ~\.claude.json (timestamped .bak next to each) before changing them.
  - Sets Claude Code's Project instructions to claude-md-and-agents-md (read CLAUDE.md AND AGENTS.md) in
    ~\.claude\settings.json > pluginConfigs (plugin cc-plugin-agents-md@builtin, or agents-md@builtin before
    Claude Code 2.1.285). This does not create a CLAUDE.md. It keeps AGENTS.md visible if a leftover
    CLAUDE file would hide it. WARN if Claude Code is older than 2.1.281. uninstall.ps1 reverts only that key.
  - Does not change Claude Code autoMode, and does not write a remote-control startup flag.
  - The Projects root guide is AGENTS.md (memory section appended there). Install does not create a root
    CLAUDE.md and does not edit one. A leftover root CLAUDE.md is only warned: fold it into AGENTS.md
    (REORGANIZE.md step 5). That fold is not a blocker. Install does not edit the file.
  - Does NOT copy the toolkit anywhere: it runs from this package's toolkit folder (PackageFolder in toolkit.psd1,
    e.g. <clone>\workstation\). Writes %LOCALAPPDATA%\<StateFolder>\<ConfigFile> (projectsRoot) so the scripts find
    the Projects root; runtime files (worker logs and instance notes) also go under %LOCALAPPDATA%\<StateFolder>\,
    never into the clone. Then creates manual shortcuts (Health check, Start and Stop Cursor worker,
    Start, Stop, and status for Desktop Commander, and the orphan tool) in this
    package's shortcuts\ folder. Those links are gitignored.
    An empty shortcuts\rc folder left by the old per-project links is removed. A folder that still has
    files, or that is a link, is left alone. No Startup item and no Run key.
    An old installed copy (<Projects>\_workstation or _bridge, LegacyFolders) is only reported, never moved.
  - Does not create, check or remove ~\.claude\working-memory. That junction only let Cowork / Chat
    pointer lines find the store. Claude desktop no longer writes local memory files (personal account
    verified 2026-11-03, Store app 4.4212.0.0, Unified Claude; work account unverified). A leftover
    junction is left as it is and is harmless. Claude Code still uses the autoMemoryDirectory junction.
  - Installs no hooks and copies no hook files. memory-link-guard.ps1 (SessionStart + PreToolUse Write|Edit),
    context-guard.ps1 (Stop + PreCompact), pr-closeout-nudge.ps1 (PostToolUse) and, for Cursor, handoff-at-80.py
    (preCompact + stop) run from the workstation-core plugin: hooks\hooks.json for Claude Code and
    hooks\cursor-hooks.json for the Cursor plugin (decision D-2026-11-26-hooks-in-plugin). Install does not write
    ~\.claude\hooks, hook entries or a statusLine in ~\.claude\settings.json, or ~\.cursor\hooks.json. Copies and
    entries an older install added stay until the owner removes them (uninstall.ps1 removes only what it recorded);
    the plugin copy stays quiet for an event an older copy still handles. The skill the handoff triggers,
    state-closeout (agent-handoff-pack forwards to it), also comes from the plugin. Skills get in from workstation-core: claude.ai for Claude desktop and Cowork, the workstation-plugins
    catalog for Claude Code (INSTALL.md). On a real run this script runs
    `claude plugin marketplace add living-relation/workstation` and
    `claude plugin install workstation-core@workstation-plugins` (skipped if the claude CLI is missing;
    it never uninstalls or disables a plugin). This script does not
    copy skills into ~\.claude\skills. No zip upload. On a real run it opens the Plugins page and prints the clicks.
  - Merges Claude Code MCP connectors into ~\.claude.json (user-scope) from claude\mcp-servers.json.
    Existing servers of the same name are left alone. API keys come from env (or a
    prompt unless -Quiet / CI / -WhatIf / -UserHome); a server that still lacks a required key is skipped with a
    message, not a failed install. Then installs Claude Code plugins at user scope from claude\plugins.json
    (Anthropic official marketplace). A plugin already enabled in ~\.claude\settings.json, or already
    installed at user scope, is left as is (a dry run says OK, not WOULD install). That file is the source
    of truth for plugin names. Nothing is scheduled and nothing reinstalls in the background.
    An existing Cursor sign-in entry is only reported (WARN), never added or removed.
    Desktop Commander is a manual shortcut only.
  - Everything it adds is listed in <Projects>\_claude\automation-installed-files.txt for uninstall.ps1.
  - Does NOT migrate old memory. See MIGRATION.md.
  - Ends by running Health check (-NoPause: read-only, never prompts) and printing its FAIL / WARN counts.
    The manual steps (admin command, instruction pastes, sign-ins) are the numbered phases printed by
    scripts\setup_guide.py. SETUP-PROMPT.txt only points at that script. A real run pastes the instruction
    files at the end unless -Quiet. Setup is finished only when Health check shows 0 FAIL, 0 WARN
    and scripts\setup_verify.py exits 0.

.PARAMETER ProjectsRoot
  Projects root folder. Default: the projectsRoot saved by the last install, else %USERPROFILE%\Projects,
  else C:\projects (the first that has _claude).

.PARAMETER WhatIf
  Dry run. Shows what would change and changes nothing.

.PARAMETER UserHome
  Testing only. Use this folder instead of %USERPROFILE% for ~\.claude, ~\.cursor and AppData lookups.

.PARAMETER AcceptConflicts
  Install even though preflight found CONFLICT items. Only after the user reviewed the report.

.PARAMETER StartupFolder
  Testing only. Startup folder for the Cursor autostart. Default: the user's Startup folder
  (test mode: under -UserHome).

.PARAMETER NoPopup
  Quiet run: passed to claude\claude-setup.ps1 as -Quiet (no API key prompts). Alias: Quiet.

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
  [Alias('Quiet')]
  [switch]$NoPopup
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
if (-not $ProjectsRoot -and $testMode) { $ProjectsRoot = Join-Path $UserHome 'Projects' }
if (-not $ProjectsRoot) {
  # Saved runtime config first, then
  # %USERPROFILE%\Projects, then C:\projects; the first one that has _claude wins.
  $cfg = Join-Path (Join-Path $env:LOCALAPPDATA $(if ($TK.StateFolder) { $TK.StateFolder } else { 'Workstation' })) $(if ($TK.ConfigFile) { $TK.ConfigFile } else { 'workstation.json' })
  try { if (Test-Path -LiteralPath $cfg) { $ProjectsRoot = [string](Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json).projectsRoot } } catch { }
  if (-not $ProjectsRoot -or -not (Test-Path -LiteralPath (Join-Path $ProjectsRoot '_claude') -PathType Container)) {
    $ProjectsRoot = Join-Path $UserHome 'Projects'
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectsRoot '_claude') -PathType Container) -and (Test-Path -LiteralPath 'C:\projects\_claude' -PathType Container)) { $ProjectsRoot = 'C:\projects' }
  }
}
$ProjectsRoot = [IO.Path]::GetFullPath($ProjectsRoot).TrimEnd('\')

if ($testMode) {
  $LocalAppData = Join-Path $UserHome 'AppData\Local'
  $RoamingAppData = Join-Path $UserHome 'AppData\Roaming'
} else {
  $LocalAppData = $env:LOCALAPPDATA; if (-not $LocalAppData) { $LocalAppData = Join-Path $UserHome 'AppData\Local' }
  $RoamingAppData = $env:APPDATA; if (-not $RoamingAppData) { $RoamingAppData = Join-Path $UserHome 'AppData\Roaming' }
}

$ProjectKey  = $ProjectsRoot -replace '[^A-Za-z0-9]', '-'      # Claude Code's folder name for the Projects root
$ClaudeDir   = Join-Path $ProjectsRoot '_claude'
$WorkingMem  = Join-Path $ClaudeDir 'Claude Projects\Working Memory'
$Store       = Join-Path $WorkingMem 'memory'
$DotClaude   = Join-Path $UserHome '.claude'
$LinkPath    = Join-Path $DotClaude ("projects\$ProjectKey\memory")
$SettingsPath = Join-Path $DotClaude 'settings.json'
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
if (-not $StartupFolder) {
  if ($testMode) { $StartupFolder = Join-Path $UserHome 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup' }
  else { $StartupFolder = [Environment]::GetFolderPath('Startup') }
}
$StartupFolder = [IO.Path]::GetFullPath($StartupFolder).TrimEnd('\')
# Manifest lines for things outside <Projects> or inside JSON files: 'json|{...}' (see uninstall.ps1).
$AddedJson   = New-Object System.Collections.Generic.List[string]

# autoMemoryDirectory = the junction path (resolves to the store). Same Projects path as the junction name.
if ($testMode) { $AutoMemValue = ($LinkPath -replace '\\', '/') } else { $AutoMemValue = "~/.claude/projects/$ProjectKey/memory" }

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
# Appends the app-lock block. Skips a file that already has the marker or the full rule text.
function Test-AppLockText([string]$Text) {
  if (-not $Text) { return $false }
  return ($Text -match '(?i)\bacquire\b' -and $Text -match '(?i)(check-?in|check in)\b' -and $Text -match '(?i)\brelease\b' -and $Text -match '(?i)harness\.design')
}
function Add-AppLockBlock([string]$Path) {
  $marker = '<!-- app-locks:v1 -->'
  if (-not (Test-Path -LiteralPath $Path)) { Note 'SKIP' "app locks not added (file missing): $Path"; return }
  $existing = [IO.File]::ReadAllText($Path)
  if ($existing.Contains($marker)) { Note 'OK' "app lock section already present: $Path"; return }
  if (Test-AppLockText $existing) { Note 'OK' "lock rule already in the text: $Path"; return }
  $block = Get-Template 'app-locks.md'
  $nl = if ($existing.Contains("`r`n") -or -not $existing.Contains("`n")) { "`r`n" } else { "`n" }
  $prefix = if ($existing.Length -eq 0 -or $existing.EndsWith("`n")) { $nl } else { $nl + $nl }
  $add = ConvertTo-Newline ($prefix + $block.TrimStart("`n")) $nl
  Invoke-Change "append app lock section to: $Path (backup in $BackupDir)" {
    Backup-File $Path
    [IO.File]::AppendAllText($Path, $add, $Utf8NoBom)
    Add-ManifestJson @{ kind = 'app-locks'; path = $Path }
  }
}
# Fixes old paths inside a marked app-locks block an older install wrote: fusion-lock\fusion-lock.ps1 ->
# app-lock\app-lock.ps1, agents\projects-AGENTS.md -> instructions\projects-AGENTS.md, and drops retired
# Fusion rule lines (D-2026-11-24-no-fusion-mcp). Adds the Fusion Desktop lock lines from the template when
# the block has none, and replaces an older Fusion Desktop line with the template's. Only text between the markers changes. No backup.
function Update-AppLockPaths([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
  $text = [IO.File]::ReadAllText($Path)
  $start = '<!-- app-locks:v1 -->'; $end = '<!-- /app-locks:v1 -->'
  $i = $text.IndexOf($start); if ($i -lt 0) { return }
  $j = $text.IndexOf($end, $i); if ($j -lt 0) { return }
  $old = $text.Substring($i, $j - $i)
  $new = $old.Replace('\workstation\fusion-lock\fusion-lock.ps1', '\workstation\app-lock\app-lock.ps1')
  $new = $new.Replace('\workstation\agents\projects-AGENTS.md', '\workstation\instructions\projects-AGENTS.md')
  $new = [regex]::Replace($new, '(?m)^Fusion work uses Autodesk''s official[^\r\n]*\r?\n', '')
  $what = 'update app lock paths (app-lock.ps1, instructions\projects-AGENTS.md)'
  # A Fusion Desktop line from an older template (it named the retired Fusion MCP): use the template's line.
  if ($new -match '(?m)^Local Fusion Desktop[^\r\n]*MCP') {
    $tplLine = [regex]::Match((Get-Template 'app-locks.md'), '(?m)^Local Fusion Desktop[^\r\n]*').Value
    if ($tplLine) {
      $new = [regex]::Replace($new, '(?m)^Local Fusion Desktop[^\r\n]*MCP[^\r\n]*', $tplLine.Replace('$', '$$'))
      $what = 'update the Fusion Desktop lock line and app lock paths'
    }
  }
  # Older blocks have only the harness.design lines: add the Fusion Desktop lock lines from the template.
  if ($new -notmatch 'fusion-desktop') {
    $tpl = Get-Template 'app-locks.md'
    $k = $tpl.IndexOf('Local Fusion Desktop'); $m = $tpl.IndexOf($end)
    if ($k -ge 0 -and $m -gt $k) {
      $nl = $(if ($text.Contains("`r`n")) { "`r`n" } else { "`n" })
      $add = ConvertTo-Newline $tpl.Substring($k, $m - $k) $nl
      if (-not $new.EndsWith("`n")) { $new += $nl }
      $new += $add
      $what = 'add the Fusion Desktop lock lines and update app lock paths'
    }
  }
  if ($new -eq $old) { Note 'OK' "app lock paths current: $Path"; return }
  $out = $text.Substring(0, $i) + $new + $text.Substring($j)
  Invoke-Change "${what} in: $Path" {
    [IO.File]::WriteAllText($Path, $out, $Utf8NoBom)
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
# pluginConfigs.<Plugin>.options.instructionFiles from a parsed settings object, or $null.
function Get-InstructionFiles($S, [string]$Plugin) {
  if (-not $S -or -not $S.PSObject.Properties['pluginConfigs'] -or -not $S.pluginConfigs) { return $null }
  $p = $S.pluginConfigs.PSObject.Properties[$Plugin]; if (-not $p -or -not $p.Value) { return $null }
  $o = $p.Value.PSObject.Properties['options']; if (-not $o -or -not $o.Value) { return $null }
  $f = $o.Value.PSObject.Properties['instructionFiles']; if (-not $f) { return $null }
  return [string]$f.Value
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
# ---------------------------------------------------------------- final Health check
# Runs Health check -NoPause (read-only, never prompts) and reports the FAIL / WARN counts.
# The manual steps are the phases printed by scripts\setup_guide.py (SETUP-PROMPT.txt is only a pointer).
# Setup is finished only when Health check shows 0 FAIL and 0 WARN and setup_verify.py exits 0.
function Invoke-StatusCheck {
  $ErrorActionPreference = 'Continue'  # PS 5.1: native stderr with 2>&1 must not stop the script
  if ($testMode -or $WhatIf) {
    Write-Host ''
    Write-Host ('  ' + $(if ($WhatIf) { 'Dry run' } else { 'Test mode (-UserHome)' }) + ': not running Health check.') -ForegroundColor Cyan
    return
  }
  $statusRel = [string]$TK.HealthScript
  if (-not $statusRel) { $statusRel = 'health\workstation-status.ps1' }
  $statusPs = Join-Path $BridgeDir $statusRel
  Write-Host ''
  Write-Host "Health check: $statusPs -NoPause" -ForegroundColor White
  if (-not (Test-Path -LiteralPath $statusPs)) { Write-Host "  [FAIL] Health check script not found: $statusPs" -ForegroundColor Red; return }
  $out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $statusPs -NoPause 2>&1 | ForEach-Object { [string]$_ })
  foreach ($l in $out) { Write-Host $l }
  $fails = @($out | Where-Object { $_ -match '\[FAIL\]' }).Count
  $warns = @($out | Where-Object { $_ -match '\[WARN\]' }).Count
  Write-Host ("  Health check: {0} FAIL, {1} WARN" -f $fails, $warns) -ForegroundColor White
  if ($fails -or $warns) { Write-Host '  Setup is finished only at 0 FAIL and 0 WARN. The remaining setup_guide.py phases usually clear these.' -ForegroundColor Yellow }
  else { Write-Host '  Health check: 0 FAIL, 0 WARN.' -ForegroundColor Green }
}

# ---------------------------------------------------------------- start
Write-Host ''
Write-Host ('Workstation setup install' + $(if ($WhatIf) { '  (DRY RUN: nothing will change)' } else { '' })) -ForegroundColor White
Write-Host "  User home     : $UserHome"
Write-Host "  Projects root : $ProjectsRoot"
Write-Host "  Claude key    : $ProjectKey"
Write-Host "  Memory store  : $Store"
Write-Host "  Junction      : $LinkPath"
Write-Host "  Startup folder: $StartupFolder"
Write-Host "  Toolkit (runs from the clone): $BridgeDir"
Write-Host "  Runtime folder: $StateDir"
Write-Host ''

$isAdmin = $false
try { $isAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole((New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544')) } catch { $isAdmin = $false }
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
catch {
  $ii = $_.InvocationInfo
  $where = if ($ii -and $ii.ScriptName) { " at $(Split-Path $ii.ScriptName -Leaf) line $($ii.ScriptLineNumber): $($ii.Line.Trim())" } else { '' }
  Note 'ERROR' "preflight failed: $($_.Exception.Message)$where"
  exit 1
}
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
  $extra = @(Get-ChildItem -LiteralPath $ProjectsRoot -Force | Where-Object { (@('active', '_archive', '_scratch', '_claude', '_refs', 'AGENTS.md') + @($TK.LegacyFolders)) -notcontains $_.Name -and $_.Name -notlike '.*' })
  if ($extra.Count -gt 0) { Note 'INFO' ("$($extra.Count) other item(s) in the Projects root (not moved). See REORGANIZE.md: " + (($extra | Select-Object -First 8 | ForEach-Object Name) -join ', ')) }
}

# 2. No memory sync: Cursor edits the live store below. No Cursor Notes folder, no copy, no task.
#    (Older installs had a Claude-Memory-To-Cursor-Sync task, a Cursor copy, and Cursor Notes; preflight flags the task/copy as retired.)

# 3. Memory store (empty starter files only if missing)
Ensure-Dir $Store 'memory store'
Ensure-Dir (Join-Path $Store '_unassigned') 'memory _unassigned'
Ensure-Dir (Join-Path $Store '_archive') 'memory _archive'
New-FileIfMissing (Join-Path $Store 'MEMORY.md') 'MEMORY.md'
New-FileIfMissing (Join-Path $Store '_unassigned\INDEX.md') 'unassigned-INDEX.md'
Add-MemoryBlock (Join-Path $WorkingMem 'CLAUDE.md') 'working-memory-CLAUDE.md' -CreateIfMissing

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

# 5. No guard script or guard config is written. memory-link-guard.ps1 runs from the workstation-core plugin and finds
#    the store through the junction below (an existing ~\.claude\hooks\memory-link-guard.config.json is still read).

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
    Note 'WARN' "$LinkPath is a real folder with $n item(s). NOT replaced. Do MIGRATION.md first, then move that folder aside and re-run install.ps1. autoMemoryDirectory is not set until then, so the plugin's memory-link guard stays inactive on this PC (it would otherwise move those notes on its own)."
  }
}

# 6b. ~\.claude\working-memory is not created, checked or removed. Older installs may have left a
#     junction there for Cowork / Chat. Leave it. It is harmless. Claude Code uses $LinkPath (section 6).
Note 'OK' '~\.claude\working-memory is not created or checked. A leftover junction is harmless and was left as it is.'

# 6c. No hook files are copied into ~\.claude\hooks or ~\.cursor\hooks. context-guard.ps1, pr-closeout-nudge.ps1,
#     memory-link-guard.ps1 and handoff-at-80.py run from the workstation-core plugin (decision D-2026-11-26-hooks-in-plugin).

# 7. ~\.claude\settings.json: merge autoMemoryDirectory and the Project instructions option, keep everything else. No hooks and no statusLine (they come from the workstation-core plugin). Does not change autoMode or a remote-control startup flag.
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
  if ($DeferHook -and $oldAuto -ne $AutoMemValue) {
    Note 'WARN' "autoMemoryDirectory NOT set yet ($LinkPath is a real folder with notes). Re-run install.ps1 after the migration."
  } elseif ($oldAuto -ne $AutoMemValue) {
    if ($oldAuto) { Note 'WARN' "autoMemoryDirectory was '$oldAuto'. Include that folder in MIGRATION.md (uninstall.ps1 puts that value back; it is also in the settings .bak)." }
    if ($hadAuto) { $settings.autoMemoryDirectory = $AutoMemValue }
    else { $settings | Add-Member -NotePropertyName autoMemoryDirectory -NotePropertyValue $AutoMemValue }
    $changes += "autoMemoryDirectory = $AutoMemValue"
    # uninstall restores exactly this: the prior value, or no key at all
    Add-ManifestJson @{ kind = 'automem'; target = 'claude'; value = $AutoMemValue; hadPrior = $hadAuto; prior = $(if ($hadAuto) { $oldAuto } else { $null }) }
  } else {
    Note 'OK' "autoMemoryDirectory already $AutoMemValue"
    if ($DeferHook) { Note 'WARN' "autoMemoryDirectory is already set while $LinkPath is a real folder: the plugin's memory-link guard will move those notes into the store at the next Claude Code session. Do MIGRATION.md first." }
    if ($firstInstall) { Add-ManifestJson @{ kind = 'automem-preexisting'; target = 'claude'; value = $AutoMemValue } }
  }

  # Hooks: memory-link-guard (SessionStart, PreToolUse Write|Edit), context-guard (Stop, PreCompact) and pr-closeout-nudge
  # (PostToolUse) come from the workstation-core plugin (hooks\hooks.json; decision D-2026-11-26-hooks-in-plugin).
  # Install adds no hook entries and no statusLine here. Entries and a statusLine an older install added stay; the
  # plugin copy of each script stays quiet for an event an older copy still handles, so nothing runs twice.
  $pendingS = New-Object System.Collections.Generic.List[object]

  # Project instructions: read CLAUDE.md AND AGENTS.md so a leftover CLAUDE.md or CLAUDE.local.md does not
  # hide AGENTS.md. This does not create those files. Repo and Projects-root guides are AGENTS.md.
  # Honored only in the user settings file.
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

# 7c. Claude Code MCP connectors (~/.claude.json) and official-marketplace plugins (claude\)
$ccSetup = Join-Path $PkgRoot 'claude\claude-setup.ps1'
if (-not (Test-Path -LiteralPath $ccSetup)) { Note 'ERROR' "claude-setup.ps1 not found: $ccSetup" }
else {
  $ccArgs = @{ ProjectsRoot = $ProjectsRoot }
  if ($testMode) { $ccArgs.UserHome = $UserHome }
  if ($WhatIf) { $ccArgs.WhatIf = $true }
  if ($NoPopup) { $ccArgs.Quiet = $true }
  try {
    foreach ($r in @(& $ccSetup @ccArgs)) {
      if (-not $r -or -not $r.PSObject.Properties['Status']) { continue }
      Note $r.Status $r.Item
      if ($r.Manifest -and -not $WhatIf) { Add-ManifestJson $r.Manifest }
    }
  } catch { Note 'ERROR' ("claude setup -- " + $_.Exception.Message) }
}

# 7b. ~\.cursor\hooks.json is not changed. The Cursor 80% handoff (handoff-at-80.py), the memory-link guard and the
#     pr-closeout nudge come from the workstation-core Cursor plugin (hooks\cursor-hooks.json; decision
#     D-2026-11-26-hooks-in-plugin). Entries an older install added stay until the owner removes them (uninstall.ps1).

# 8. Rule files. Claude Code and the Cursor desktop app (not Cowork; hooks/README.md) get the memory and lock rules from the workstation-core plugin's
#    SessionStart hook (hooks\rules-inject.ps1), so ~\.claude\CLAUDE.md and ~\.cursor\rules\*.mdc are not
#    created or appended any more. Blocks an older install appended there stay; only their old paths are fixed.
$RepoRulesMdc = Join-Path $UserHome '.cursor\rules\repo-rules.mdc'
foreach ($rf in @((Join-Path $DotClaude 'CLAUDE.md'), $CursorRule, $RepoRulesMdc)) { Update-AppLockPaths $rf }
# Projects root guide is AGENTS.md. Do not create or edit a root CLAUDE.md.
$RootAgentsMd = Join-Path $ProjectsRoot 'AGENTS.md'
$RootClaudeMd = Join-Path $ProjectsRoot 'CLAUDE.md'
if (Test-Path -LiteralPath $RootClaudeMd) {
  Note 'WARN' "root CLAUDE.md still exists: $RootClaudeMd. Fold its content into AGENTS.md (keep every rule, drop exact duplicates), then delete the CLAUDE file. Install does not change that file."
}
Add-MemoryBlock $RootAgentsMd 'projects-AGENTS.md' -CreateIfMissing
# harness.design lock rules in the root guide (agents without hooks read it). Paste texts in instructions\
# are still updated by hand.
Update-AppLockPaths $RootAgentsMd
Add-AppLockBlock $RootAgentsMd
# Claude's instruction texts (instructions\ in the package) are pasted by hand; install never edits them.
# Instructions for Claude are account-level (not on disk): only a reminder.
# Cowork / Chat no longer write local memory (personal account verified 2026-11-03; work account unverified),
# so install does not search Cowork instruction files for a working-memory line.
Note 'TODO' 'Reminder: paste instructions\instructions-for-claude.md into Claude desktop > Settings > Instructions for Claude if that box is still there (account-level; cannot be checked on disk). Skip if already done.'
Note 'INFO' 'instructions\cowork-global-instructions.md no longer points at a local memory folder. Paste it only if a Global instructions box is still there. Install does not check it. Online Memory (Settings > Your Claude > Memory) is separate and not synced. Personal account verified 2026-11-03; work account unverified.'

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
  if ($br -and @('main', 'master') -notcontains [string]$br) { Note 'WARN' "this clone is on branch '$br', not main: the shortcuts run whatever is checked out here. Switch it back to main." }
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
$rcDir = Join-Path $scDir 'rc'
$rcState = 'absent'
if (Test-Path -LiteralPath $rcDir -PathType Container) {
  $rcItem = Get-Item -LiteralPath $rcDir -Force
  if ($rcItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { $rcState = 'link' }
  elseif (-not (Get-ChildItem -LiteralPath $rcDir -Force -ErrorAction SilentlyContinue)) { $rcState = 'empty' }
  else { $rcState = 'busy' }
}
if ($rcState -eq 'empty') {
  if ($WhatIf) { Note 'WOULD' "remove empty folder $rcDir" }
  elseif ($testMode) { Note 'SKIP' "test mode: would remove empty folder $rcDir" }
  else { Remove-Item -LiteralPath $rcDir -Force -ErrorAction SilentlyContinue; Note 'DONE' "removed empty folder $rcDir" }
} elseif ($rcState -eq 'link') { Note 'WARN' "left $rcDir alone (it is a link)" }
elseif ($rcState -eq 'busy') { Note 'OK' "left $rcDir alone (it still has files)" }
$shortcutPlan = "create manual links in '$scDir': " + (($TK.Shortcuts | ForEach-Object { $_.Name }) -join ', ') + '. No sign-in link.'
if ($testMode) { Note 'SKIP' "test mode (-UserHome): not running $(Split-Path $shortcutScript -Leaf). It would $shortcutPlan" }
elseif ($WhatIf) { Note 'WOULD' "run $shortcutScript -LinkDir `"$scDir`" -NoPause: $shortcutPlan" }
elseif (-not (Test-Path -LiteralPath $shortcutScript)) { Note 'ERROR' "not found: $shortcutScript" }
else {
  $scDirPre = Test-Path -LiteralPath $scDir
  $scPre = @{}; foreach ($sc in $TK.Shortcuts) { $scPre[$sc.Name] = Test-Path -LiteralPath (Join-Path $scDir "$($sc.Name).lnk") }
  $scRecorded = @()
  if (Test-Path -LiteralPath $ManifestPath) {
    foreach ($ln in @([IO.File]::ReadAllLines($ManifestPath) | Where-Object { $_ -like 'json|*' })) {
      try { $j = $ln.Substring(5) | ConvertFrom-Json; if ($j.kind -eq 'shortcut') { $scRecorded += $j } } catch { }
    }
  }
  $hostExe = 'powershell.exe'
  if ($env:OS -ne 'Windows_NT') { $hostExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName }
  & $hostExe -NoProfile -ExecutionPolicy Bypass -File $shortcutScript -LinkDir $scDir -StartupDir $StartupFolder -NoPause
  $scExit = $LASTEXITCODE
  if (-not $scDirPre -and (Test-Path -LiteralPath $scDir)) { Add-ManifestJson @{ kind = 'shortcut-dir'; path = $scDir } }
  foreach ($sc in $TK.Shortcuts) {
    $lp = Join-Path $scDir "$($sc.Name).lnk"
    $want = Join-Path $BridgeDir $sc.Script
    $rec = @($scRecorded | Where-Object { [string]$_.path -ieq $lp })
    if ((Test-Path -LiteralPath $lp) -and (-not $scPre[$sc.Name] -or ($rec.Count -and -not @($rec | Where-Object { [string]$_.script -ieq $want }).Count))) { Add-ManifestJson @{ kind = 'shortcut'; path = $lp; script = $want } }
  }
  if ($scExit -eq 0) { Note 'DONE' "manual shortcuts in $scDir (they do not start at sign-in)" }
  else { Note 'WARN' "$(Split-Path $shortcutScript -Leaf) reported failures (exit $scExit). See its output above." }
}
# An old installed toolkit copy (LegacyFolders) is never moved or deleted; it is only reported.
foreach ($lf in @($TK.LegacyFolders | Where-Object { $_ })) {
  $lp = Join-Path $ProjectsRoot $lf
  if (Test-Path -LiteralPath $lp) { Note 'WARN' "old toolkit copy left in place: $lp (the toolkit now runs from $BridgeDir). Stop anything still running from it, check nothing else uses it, then archive it by hand." }
}

# 9b. No Cursor autostart (since 2026-10-31 nothing of this package starts at sign-in). An existing entry is only
#     reported (preflight WARN); install never adds, changes or removes one. uninstall.ps1 still removes a Cursor.lnk an
#     older install recorded.
$cs = @($Preflight.CursorStartup)
if ($cs.Count) { foreach ($e in $cs) { Note 'WARN' "Cursor starts at sign-in (not added by this install; remove it by hand if unwanted): $($e.Path)" } }
else { Note 'OK' 'Cursor does not start at sign-in (install adds no autostart)' }

# 9b. Skills come from the workstation-core plugin (claude.ai; Claude Code: the catalog, INSTALL.md). This script does not copy them into ~\.claude\skills.
#     A real run opens the Plugins page and prints the clicks. -WhatIf does not open a browser or copy files.
. (Join-Path $PSScriptRoot 'workstation\health\claude-ai-plugin.ps1')
if (Test-WorkstationCoreOnClaudeAi -UserRoot $UserHome) { Note 'OK' $WsPluginPresentText }
else { Note 'WARN' $WsPluginMissingText }
$pluginArgs = @{ WhatIf = [bool]$WhatIf }
if ($testMode) { $pluginArgs.UserHome = $UserHome }
try {
  & (Join-Path $PSScriptRoot 'install-plugins.ps1') @pluginArgs
  if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { Note 'WARN' "install-plugins.ps1 exit $LASTEXITCODE" }
} catch { Note 'ERROR' ("plugin setup -- " + $_.Exception.Message) }

# 9c. Claude Code catalog. Two commands only. A missing claude CLI skips them. Never uninstalls or disables.
$catalog = Join-Path $PSScriptRoot 'scripts\install-catalog-plugin.ps1'
if (-not (Test-Path -LiteralPath $catalog)) { Note 'ERROR' "not found: $catalog" }
else {
  try {
    if ($WhatIf -or $testMode) { & $catalog -WhatIf } else { & $catalog }
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { Note 'WARN' "install-catalog-plugin.ps1 exit $LASTEXITCODE" }
  } catch { Note 'ERROR' ("catalog plugin -- " + $_.Exception.Message) }
}

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
else { Write-Host 'Desktop Commander and the Cursor worker run only from their manual shortcuts. On a PC that still has the old local setup, run cleanup-legacy.ps1 -WhatIf first.' -ForegroundColor White }
Invoke-StatusCheck

# Paste helper: one instruction file at a time. -Quiet skips it. A dry run and -UserHome only print the plan.
$paste = Join-Path $PSScriptRoot 'scripts\paste-instructions.ps1'
if (Test-Path -LiteralPath $paste) {
  try {
    if ($NoPopup) { & $paste -Quiet -PackageRoot $PkgRoot }
    elseif ($WhatIf -or $testMode) { & $paste -WhatIf -PackageRoot $PkgRoot }
    else { & $paste -PackageRoot $PkgRoot }
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { Note 'WARN' "paste-instructions.ps1 exit $LASTEXITCODE" }
  } catch { Note 'ERROR' ("paste helper -- " + $_.Exception.Message) }
} else { Note 'ERROR' "not found: $paste" }

if (@($Summary | Where-Object Status -eq 'ERROR').Count) { exit 1 }
exit 0
