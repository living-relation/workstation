<#
.SYNOPSIS
  Workstation setup: removes what install.ps1 added for the CURRENT user. Never deletes memory or project folders.

.DESCRIPTION
  Run as a normal user from the workstation repo clone:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 -WhatIf
    powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
  Removes ONLY what <Projects>\_claude\automation-installed-files.txt (the manifest install.ps1 writes) lists as
  added by install. Anything else, even if it looks like ours, is listed as "not installed by this package, left
  alone" and never touched. With no manifest, nothing is removed. There is no override.
  From the manifest:
  - memory sections (between <!-- shared-memory:v1 --> markers) install created or appended; a file install created
    that holds nothing else is removed. A marked section that was already there stays, markers included,
  - in ~\.claude\settings.json: the SessionStart guard hook install added; autoMemoryDirectory put back to the value
    it had before install (or removed if there was none; left alone if it changed since); the 80% handoff hook
    entries (a re-pointed entry gets its old command back); the statusLine while it is still the one install set;
    pluginConfigs > <agents-md plugin> > options.instructionFiles put back to its value before install (or removed,
    with the empty parent objects install created; left alone if it changed since),
  - in ~\.cursor\hooks.json: the handoff-at-80.py entries install added; the file if install created it and it is
    empty again,
  - files install created (guard script and config, context-guard.ps1, handoff-at-80.py, the armed flag, the
    handoff-sync-continue skill, the runtime config %LOCALAPPDATA%\<StateFolder>\<ConfigFile>, sync scripts, and
    toolkit files an older install copied into <Projects>\_workstation or _bridge) only while unchanged, and
    folders install created (only if empty). The toolkit itself runs from the repo clone; uninstall never touches
    the clone's files. Runtime logs under %LOCALAPPDATA%\<StateFolder> stay (that folder is kept while not empty),
  - junctions install created (the link only; the notes stay in the store),
  - the shortcuts and shortcut folder install created (in the package's shortcuts\ folder, or an older Desktop one) (only while they still run the toolkit scripts),
  - the Cursor.lnk autostart if install created it. Existing Cursor autostarts are never touched.
  Prints the admin command for the scheduled task (plus, for older installs, how to remove the retired Latch task
  and its startup entry).
  Every changed or removed file is copied first to <Projects>\_archive\automation-uninstall-backup-<time>\.
  Keeps: the memory store, Cursor's copy, all notes, the Projects layout folders, all projects.
  Scheduled tasks need admin: the commands are printed for you to run in an admin PowerShell.
#>
[CmdletBinding()]
param(
  [string]$ProjectsRoot,
  [switch]$WhatIf,
  [string]$UserHome
)
$ErrorActionPreference = 'Stop'
$Marker = '<!-- shared-memory:v1 -->'
$EndMarker = '<!-- /shared-memory:v1 -->'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Utf8NoBom = New-Object Text.UTF8Encoding $false

$testMode = [bool]$UserHome
if (-not $UserHome) { $UserHome = $env:USERPROFILE }
$UserHome = [IO.Path]::GetFullPath($UserHome).TrimEnd('\')
if (-not $ProjectsRoot) { $ProjectsRoot = Join-Path $UserHome 'Projects' }
$ProjectsRoot = [IO.Path]::GetFullPath($ProjectsRoot).TrimEnd('\')
if ($testMode) { $LocalAppData = Join-Path $UserHome 'AppData\Local'; $RoamingAppData = Join-Path $UserHome 'AppData\Roaming' }
else { $LocalAppData = $env:LOCALAPPDATA; $RoamingAppData = $env:APPDATA }

$ProjectKey = $ProjectsRoot -replace '[^A-Za-z0-9]', '-'
$ClaudeDir  = Join-Path $ProjectsRoot '_claude'
$WorkingMem = Join-Path $ClaudeDir 'Claude Projects\Working Memory'
$Store      = Join-Path $WorkingMem 'memory'
$DotClaude  = Join-Path $UserHome '.claude'
$LinkPath   = Join-Path $DotClaude ("projects\$ProjectKey\memory")
$WmLink     = Join-Path $DotClaude 'working-memory'
$SettingsPath = Join-Path $DotClaude 'settings.json'
$BackupDir  = Join-Path $ProjectsRoot ("_archive\automation-uninstall-backup-$Stamp")
$ManifestPath = Join-Path $ClaudeDir 'automation-installed-files.txt'
$CursorHooksJson = Join-Path $UserHome '.cursor\hooks.json'
# 'json|{...}' manifest entries written by install.ps1 (hooks, statusLine, files outside <Projects>, startup link).
$ManifestJson = @()
if (Test-Path -LiteralPath $ManifestPath) {
  foreach ($ln in @([IO.File]::ReadAllLines($ManifestPath) | Where-Object { $_ -like 'json|*' })) {
    try { $ManifestJson += ($ln.Substring(5) | ConvertFrom-Json) } catch { }
  }
}
$PkgRoot = $PSScriptRoot
if (-not $PkgRoot) { $PkgRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
# Toolkit folder and script names come from ONE place: toolkit.psd1 next to this script.
$ToolkitDef = Join-Path $PkgRoot 'toolkit.psd1'
if (-not (Test-Path -LiteralPath $ToolkitDef)) { Write-Host "toolkit.psd1 not found next to this script: $ToolkitDef" -ForegroundColor Red; exit 1 }
$TK = Import-PowerShellDataFile -LiteralPath $ToolkitDef
$Placeholders = [ordered]@{
  '{{USERPROFILE_FWD}}'   = ($UserHome -replace '\\', '/')
  '{{USERPROFILE}}'       = $UserHome
  '{{PROJECTS_ROOT_FWD}}' = ($ProjectsRoot -replace '\\', '/')
  '{{PROJECTS_ROOT}}'     = $ProjectsRoot
  '{{CLAUDE_PROJECT_KEY}}' = $ProjectKey
  '{{USERNAME}}'          = $env:USERNAME
  '{{TOOLKIT_PATH}}'      = (Join-Path $PkgRoot $TK.PackageFolder)
  '{{TOOLKIT_PULL}}'      = $TK.PullScript
  '{{TOOLKIT_STATUS}}'    = $TK.StatusScript
}
if ($testMode) { $AutoMemValue = ($LinkPath -replace '\\', '/') } else { $AutoMemValue = "~/.claude/projects/$ProjectKey/memory" }

$Summary = New-Object System.Collections.Generic.List[object]
function Note([string]$Status, [string]$NoteText_) {
  $Summary.Add([pscustomobject]@{ Status = $Status; Item = $NoteText_ })
  $color = switch ($Status) { 'DONE' { 'Green' } 'WOULD' { 'Cyan' } 'WARN' { 'Yellow' } 'ERROR' { 'Red' } default { 'Gray' } }
  Write-Host ("[{0,-5}] {1}" -f $Status, $NoteText_) -ForegroundColor $color
}
function Invoke-Change([string]$ChangeDesc_, [scriptblock]$ChangeBlock_) {
  if ($WhatIf) { Note 'WOULD' $ChangeDesc_; return }
  try { & $ChangeBlock_; Note 'DONE' $ChangeDesc_ } catch { Note 'ERROR' ("$ChangeDesc_ -- " + $_.Exception.Message) }
}
function Get-Sha([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
# Removes hook entries for $Leaf that install added, restores re-pointed ones. Returns the change texts.
function Undo-Hooks($Container, [string]$Target, [switch]$Nested) {
  $done = @()
  if (-not $Container) { return $done }
  foreach ($m in @($ManifestJson | Where-Object { $_.target -eq $Target -and $_.kind -eq 'hook-updated' })) {
    if (-not $Container.PSObject.Properties[$m.event]) { continue }
    foreach ($entry in @($Container.($m.event))) {
      $items = if ($Nested) { @($entry.hooks) } else { @($entry) }
      foreach ($h in $items) { if ($h -and $h.PSObject.Properties['command'] -and [string]$h.command -eq [string]$m.new) { $h.command = [string]$m.old; $done += "$($m.event): restore old $($m.script) command" } }
    }
  }
  foreach ($m in @($ManifestJson | Where-Object { $_.target -eq $Target -and $_.kind -eq 'hook' })) {
    if (-not $Container.PSObject.Properties[$m.event]) { continue }
    $rx = [regex]::Escape([string]$m.script)
    $kept = @(); $removed = 0
    foreach ($entry in @($Container.($m.event))) {
      if ($Nested) {
        $hs = @($entry.hooks)
        $keep = @($hs | Where-Object { -not ($_ -and ([string]$_.command) -match $rx) })
        $removed += ($hs.Count - $keep.Count)
        if ($keep.Count -eq $hs.Count) { $kept += $entry } elseif ($keep.Count -gt 0) { $entry.hooks = $keep; $kept += $entry }
      } else {
        if ($entry -and ([string]$entry.command) -match $rx) { $removed++ } else { $kept += $entry }
      }
    }
    if ($removed) {
      if ($kept.Count) { $Container.($m.event) = $kept } else { $Container.PSObject.Properties.Remove($m.event) }
      $done += "$($m.event): remove $($m.script)"
    }
  }
  return $done
}
# Writes JSON with a .bak first, keeps newline style and final newline, restores the .bak if it does not parse.
function Write-JsonChecked([string]$Path, $Obj, [string]$Raw, [string]$Bak) {
  $nl = "`r`n"; if ($Raw.Contains("`n") -and -not $Raw.Contains("`r`n")) { $nl = "`n" }
  $json = Format-Json ($Obj | ConvertTo-Json -Depth 100) $nl
  if (-not $Raw.EndsWith("`n")) { $json = $json.TrimEnd("`r", "`n") }
  Copy-Item -LiteralPath $Path -Destination $Bak -Force
  [IO.File]::WriteAllText($Path, $json, $Utf8NoBom)
  try { [IO.File]::ReadAllText($Path) | ConvertFrom-Json | Out-Null }
  catch { Copy-Item -LiteralPath $Bak -Destination $Path -Force; throw 'written JSON did not parse; restored the backup' }
}
function Get-FreePath([string]$Path) {
  $candidate = $Path; $i = 1
  while (Test-Path -LiteralPath $candidate) { $candidate = "$Path-$i"; $i++ }
  return $candidate
}
function Backup-File([string]$Path) {
  if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
  Copy-Item -LiteralPath $Path -Destination (Get-FreePath (Join-Path $BackupDir (($Path -replace '[:\\/]+', '_').Trim('_'))))
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
# -CreatedFrom: template install.ps1 uses to CREATE the file. If what is left after removing the block is
# still exactly that template's top part, install made the whole file, so the file is removed.
function Remove-MemoryBlock([string]$Path, [string]$CreatedFrom) {
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $t = [IO.File]::ReadAllText($Path)
  if (-not $t.Contains($Marker)) { Note 'OK' "no memory section: $Path"; return }
  # Only a section that install itself added (manifest 'section' entry) is removed. A marked section that was there
  # before install, or was marked by hand, is left exactly as it is, markers included.
  $rec = @($ManifestJson | Where-Object { $_.kind -eq 'section' -and [string]$_.path -ieq $Path }) | Select-Object -First 1
  if (-not $rec) { Note 'OK' "memory section not installed by this package, left alone: $Path"; return }
  if (-not $rec.created) { $CreatedFrom = $null }
  $pattern = '(?s)(\r?\n)*' + [regex]::Escape($Marker) + '.*?' + [regex]::Escape($EndMarker) + '[ \t]*(\r?\n)?'
  $new = [regex]::Replace($t, $pattern, '')
  if ($new.Contains($Marker)) { Note 'WARN' "start marker without end marker, left alone: $Path"; return }
  $rest = $new.Trim()
  $createdTop = $null
  if ($CreatedFrom) {
    $tp = Join-Path $PkgRoot "memory\templates\$CreatedFrom"
    if (Test-Path -LiteralPath $tp) {
      $tt = [IO.File]::ReadAllText($tp)
      foreach ($k in $Placeholders.Keys) { $tt = $tt.Replace($k, [string]$Placeholders[$k]) }
      $mi = $tt.IndexOf($Marker); if ($mi -ge 0) { $tt = $tt.Substring(0, $mi) }
      $createdTop = ($tt -replace "`r`n", "`n").Trim()
    }
  }
  if ($rec.created -and (-not $rest -or $rest -match '^(?s)---\r?\n.*?\r?\n---$' -or ($createdTop -and (($rest -replace "`r`n", "`n") -eq $createdTop)))) {
    Invoke-Change "remove file (it held only the memory section): $Path" { Backup-File $Path; Remove-Item -LiteralPath $Path -Force }
  } else {
    $nl = if ($t.Contains("`r`n")) { "`r`n" } else { "`n" }
    $out = $new.TrimEnd() + $nl
    Invoke-Change "remove memory section from: $Path" { Backup-File $Path; [IO.File]::WriteAllText($Path, $out, $Utf8NoBom) }
  }
}

Write-Host ''
Write-Host ('Workstation setup uninstall' + $(if ($WhatIf) { '  (DRY RUN: nothing will change)' } else { '' })) -ForegroundColor White
Write-Host "  User home     : $UserHome"
Write-Host "  Projects root : $ProjectsRoot"
Write-Host ''

# 1. Rule files
Remove-MemoryBlock (Join-Path $DotClaude 'CLAUDE.md')
Remove-MemoryBlock (Join-Path $UserHome '.cursor\rules\claude-shared-memory.mdc')
Remove-MemoryBlock (Join-Path $WorkingMem 'CLAUDE.md')
Remove-MemoryBlock (Join-Path $ProjectsRoot 'AGENTS.md') -CreatedFrom 'projects-AGENTS.md'
# Older installs put the root section in CLAUDE.md; removed only if the manifest lists it.
Remove-MemoryBlock (Join-Path $ProjectsRoot 'CLAUDE.md')
foreach ($pattern in @((Join-Path $LocalAppData 'Packages\Claude_*\LocalCache\Roaming\Claude\local-agent-mode-sessions\*\*\memory\CLAUDE.md'),
                       (Join-Path $RoamingAppData 'Claude\local-agent-mode-sessions\*\*\memory\CLAUDE.md'))) {
  foreach ($f in @(Get-ChildItem -Path $pattern -File -Force -ErrorAction SilentlyContinue)) { Remove-MemoryBlock $f.FullName }
}

# 2. settings.json
# The SessionStart guard hook is removed only if the manifest says install added it.
$GuardAdded = @($ManifestJson | Where-Object { $_.kind -eq 'guard-hook' }).Count -gt 0
if (Test-Path -LiteralPath $SettingsPath) {
  $s = $null
  $rawS = [IO.File]::ReadAllText($SettingsPath)
  $nlS = "`r`n"; if ($rawS.Contains("`n") -and -not $rawS.Contains("`r`n")) { $nlS = "`n" }
  try { $s = $rawS | ConvertFrom-Json } catch { Note 'ERROR' "could not parse $SettingsPath (left unchanged)" }
  if ($s) {
    $changes = @()
    # autoMemoryDirectory: restore exactly what the manifest says was there before install.
    $amRec = @($ManifestJson | Where-Object { $_.kind -eq 'automem' }) | Select-Object -First 1
    $amPre = @($ManifestJson | Where-Object { $_.kind -eq 'automem-preexisting' }).Count -gt 0
    $curAm = $null; if ($s.PSObject.Properties['autoMemoryDirectory']) { $curAm = [string]$s.autoMemoryDirectory }
    if ($amPre -and -not $amRec) { Note 'OK' "autoMemoryDirectory was already set before install; left as is ($curAm)" }
    elseif ($amRec) {
      if ($null -eq $curAm) { Note 'INFO' 'autoMemoryDirectory already removed' }
      elseif ($curAm -ne [string]$amRec.value) { Note 'WARN' "autoMemoryDirectory changed since install ($curAm); left alone" }
      elseif ($amRec.hadPrior) { $s.autoMemoryDirectory = [string]$amRec.prior; $changes += "restore autoMemoryDirectory = $($amRec.prior)" }
      else { $s.PSObject.Properties.Remove('autoMemoryDirectory'); $changes += 'remove autoMemoryDirectory (there was none before install)' }
    } elseif ($null -ne $curAm) { Note 'OK' "autoMemoryDirectory: not installed by this package, left alone ($curAm)" }
    # Project instructions (pluginConfigs > <plugin> > options.instructionFiles): revert only what install set.
    foreach ($pc in @($ManifestJson | Where-Object { $_.kind -eq 'plugin-config' })) {
      $pn = [string]$pc.plugin; $cur = $null; $po = $null; $oo = $null
      if ($s.PSObject.Properties['pluginConfigs'] -and $s.pluginConfigs -and $s.pluginConfigs.PSObject.Properties[$pn]) { $po = $s.pluginConfigs.PSObject.Properties[$pn].Value }
      if ($po -and $po.PSObject.Properties['options'] -and $po.options) { $oo = $po.options }
      if ($oo -and $oo.PSObject.Properties['instructionFiles']) { $cur = [string]$oo.instructionFiles }
      if ($null -eq $cur) { Note 'INFO' "pluginConfigs.$pn instructionFiles already removed"; continue }
      if ($cur -ne [string]$pc.value) { Note 'WARN' "pluginConfigs.$pn instructionFiles changed since install ($cur); left alone"; continue }
      if ($pc.hadPrior) { $oo.instructionFiles = [string]$pc.prior; $changes += "restore pluginConfigs.$pn instructionFiles = $($pc.prior)"; continue }
      $oo.PSObject.Properties.Remove('instructionFiles'); $changes += "remove pluginConfigs.$pn instructionFiles (there was none before install)"
      if ($pc.createdOptions -and @($oo.PSObject.Properties).Count -eq 0) { $po.PSObject.Properties.Remove('options') }
      if ($pc.createdPlugin -and @($po.PSObject.Properties).Count -eq 0) { $s.pluginConfigs.PSObject.Properties.Remove($pn) }
      if ($pc.createdPluginConfigs -and @($s.pluginConfigs.PSObject.Properties).Count -eq 0) { $s.PSObject.Properties.Remove('pluginConfigs') }
    }
    if (@($ManifestJson | Where-Object { $_.kind -eq 'plugin-config-preexisting' }).Count -and -not @($ManifestJson | Where-Object { $_.kind -eq 'plugin-config' }).Count) { Note 'OK' 'Project instructions (read CLAUDE.md and AGENTS.md) was already set before install; left as is' }
    $hasGuardHook = $false
    if ($s.PSObject.Properties['hooks'] -and $s.hooks -and $s.hooks.PSObject.Properties['SessionStart']) { $hasGuardHook = ([string](@($s.hooks.SessionStart) | ConvertTo-Json -Depth 10 -Compress)) -match 'memory-link-guard\.ps1' }
    if ($hasGuardHook -and -not $GuardAdded) { Note 'OK' 'SessionStart memory-link-guard hook: not installed by this package, left alone' }
    if ($GuardAdded -and $s.PSObject.Properties['hooks'] -and $s.hooks -and $s.hooks.PSObject.Properties['SessionStart']) {
      $kept = @()
      $removed = 0
      foreach ($entry in @($s.hooks.SessionStart)) {
        $hs = @($entry.hooks)
        $keepHooks = @($hs | Where-Object { -not ($_ -and ([string]$_.command) -match 'memory-link-guard\.ps1') })
        $removed += ($hs.Count - $keepHooks.Count)
        if ($keepHooks.Count -eq $hs.Count) { $kept += $entry }
        elseif ($keepHooks.Count -gt 0) { $entry.hooks = $keepHooks; $kept += $entry }
      }
      if ($removed -gt 0) {
        if ($kept.Count -gt 0) { $s.hooks.SessionStart = $kept } else { $s.hooks.PSObject.Properties.Remove('SessionStart') }
        $changes += 'remove SessionStart memory-link-guard hook'
      }
    }
    # 80% handoff hooks and statusLine (only what the manifest says install added or re-pointed)
    if ($s.PSObject.Properties['hooks'] -and $s.hooks) { $changes += @(Undo-Hooks $s.hooks 'claude' -Nested) }
    foreach ($m in @($ManifestJson | Where-Object { $_.target -eq 'claude' -and $_.kind -like 'statusline*' })) {
      if (-not $s.PSObject.Properties['statusLine'] -or -not $s.statusLine -or -not $s.statusLine.PSObject.Properties['command']) { continue }
      $cur = [string]$s.statusLine.command
      if ($m.kind -eq 'statusline' -and $cur -eq [string]$m.command) { $s.PSObject.Properties.Remove('statusLine'); $changes += 'remove statusLine (context-guard)' }
      elseif ($m.kind -eq 'statusline-updated' -and $cur -eq [string]$m.new) { $s.statusLine.command = [string]$m.old; $changes += 'restore old statusLine command' }
      elseif ($m.kind -eq 'statusline') { Note 'WARN' "statusLine changed since install; left alone: $cur" }
    }
    if ($s.PSObject.Properties['hooks'] -and $s.hooks -and @($s.hooks.PSObject.Properties).Count -eq 0 -and $changes.Count) { $s.PSObject.Properties.Remove('hooks') }
    if ($changes.Count) {
      $bak = Get-FreePath "$SettingsPath.bak-$Stamp"
      Invoke-Change ("update $SettingsPath (" + ($changes -join '; ') + "; backup $bak)") { Write-JsonChecked $SettingsPath $s $rawS $bak }
    } else { Note 'OK' 'settings.json has nothing from install' }
  }
}

# 2b. ~\.cursor\hooks.json: the handoff-at-80.py entries install added; the file itself if install created it
if (Test-Path -LiteralPath $CursorHooksJson) {
  $rawH = [IO.File]::ReadAllText($CursorHooksJson); $hj = $null
  try { $hj = $rawH | ConvertFrom-Json } catch { Note 'ERROR' "could not parse $CursorHooksJson (left unchanged)" }
  if ($hj) {
    $hc = @(); if ($hj.PSObject.Properties['hooks'] -and $hj.hooks) { $hc = @(Undo-Hooks $hj.hooks 'cursor') }
    $created = @($ManifestJson | Where-Object { $_.kind -eq 'file-created' -and $_.path -ieq $CursorHooksJson }).Count -gt 0
    $empty = (-not $hj.PSObject.Properties['hooks'] -or -not $hj.hooks -or @($hj.hooks.PSObject.Properties).Count -eq 0)
    $onlyOurs = (@($hj.PSObject.Properties | Where-Object { @('version', 'hooks') -notcontains $_.Name }).Count -eq 0)
    if ($hc.Count -and $created -and $empty -and $onlyOurs) {
      Invoke-Change "remove $CursorHooksJson (install created it; nothing else in it)" { Backup-File $CursorHooksJson; Remove-Item -LiteralPath $CursorHooksJson -Force }
    } elseif ($hc.Count) {
      $hbak = Get-FreePath "$CursorHooksJson.bak-$Stamp"
      Invoke-Change ("update $CursorHooksJson (" + ($hc -join '; ') + "; backup $hbak)") { Write-JsonChecked $CursorHooksJson $hj $rawH $hbak }
    } else { Note 'OK' 'hooks.json has nothing from install' }
  }
}

# 2c. Files and folders install created outside <Projects> (only while unchanged), and the Cursor autostart link
foreach ($m in @($ManifestJson | Where-Object { $_.kind -eq 'file' })) {
  $p = [string]$m.path
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
  if ((Get-Sha $p) -eq [string]$m.sha256) { Invoke-Change "remove $p (added by install)" { Backup-File $p; Remove-Item -LiteralPath $p -Force } }
  else { Note 'WARN' "changed since install, left alone: $p" }
}
foreach ($m in @($ManifestJson | Where-Object { $_.kind -eq 'startup' })) {
  $p = [string]$m.path
  if (-not (Test-Path -LiteralPath $p)) { continue }
  $tgt = ''; try { $tgt = (New-Object -ComObject WScript.Shell).CreateShortcut($p).TargetPath } catch { }
  if ((Split-Path $tgt -Leaf) -ieq 'Cursor.exe') { Invoke-Change "remove Cursor autostart added by install: $p" { Backup-File $p; Remove-Item -LiteralPath $p -Force } }
  else { Note 'WARN' "no longer starts Cursor.exe, left alone: $p" }
}

foreach ($m in @($ManifestJson | Where-Object { $_.kind -eq 'skill-link' })) {
  $p = [string]$m.path
  $it = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
  if (-not $it) { continue }
  # only links into this repo's own skills\ (links other repos made are never touched)
  if (-not ([string]$m.target).StartsWith((Join-Path $PSScriptRoot 'skills'), [StringComparison]::OrdinalIgnoreCase)) { Note 'OK' "skill link not owned by this repo, left alone: $p"; continue }
  if ($it.LinkType -eq 'Junction' -and (@($it.Target | ForEach-Object { $_.TrimEnd('\') }) -icontains ([string]$m.target).TrimEnd('\'))) {
    Invoke-Change "remove skill link added by install (the link only; the skill stays in its repo): $p" { [IO.Directory]::Delete($p) }
    $bk = [string]$m.backup
    if ($bk) {
      if ((Test-Path -LiteralPath $bk) -and -not (Test-Path -LiteralPath $p)) { Invoke-Change "restore the skill install backed up: $bk -> $p" { Move-Item -LiteralPath $bk -Destination $p } }
      elseif (Test-Path -LiteralPath $bk) { Note 'TODO' "backed-up skill kept at $bk ($p is in use); restore it by hand if you want it" }
      else { Note 'WARN' "install recorded a skill backup that is gone: $bk" }
    }
  }
  else { Note 'WARN' "skill link changed since install, left alone: $p" }
}

foreach ($m in @($ManifestJson | Where-Object { $_.kind -eq 'startup-link' })) {
  $p = [string]$m.path
  if (-not (Test-Path -LiteralPath $p)) { continue }
  $a = ''; try { $a = (New-Object -ComObject WScript.Shell).CreateShortcut($p).Arguments } catch { }
  if ($a -match [regex]::Escape((Split-Path ([string]$m.script) -Leaf))) { Invoke-Change "remove sign-in link added by install: $p" { Backup-File $p; Remove-Item -LiteralPath $p -Force } }
  else { Note 'WARN' "sign-in link changed since install (does not run $(Split-Path ([string]$m.script) -Leaf)), left alone: $p" }
}

# 2d. 80% handoff pieces that are present but not in the manifest: listed, never touched.
$listedAny = @($ManifestJson | ForEach-Object { [string]$_.path })
if ((Test-Path -LiteralPath $SettingsPath) -and ([IO.File]::ReadAllText($SettingsPath)).Contains('context-guard.ps1') -and -not @($ManifestJson | Where-Object { $_.target -eq 'claude' -and $_.kind -match '^(hook|hook-updated|statusline|statusline-updated)$' }).Count) {
  Note 'OK' "80% handoff hooks / statusLine in settings.json: not installed by this package, left alone"
}
if ((Test-Path -LiteralPath $CursorHooksJson) -and ([IO.File]::ReadAllText($CursorHooksJson)).Contains('handoff-at-80.py') -and -not @($ManifestJson | Where-Object { $_.target -eq 'cursor' -and $_.kind -match '^(hook|hook-updated)$' }).Count) {
  Note 'OK' "handoff-at-80.py entries in hooks.json: not installed by this package, left alone"
}
foreach ($hp in @((Join-Path $DotClaude 'hooks\context-guard.ps1'), (Join-Path $UserHome '.cursor\hooks\handoff-at-80.py'),
                  (Join-Path $UserHome '.cursor\hooks\state\handoff-at-80\armed'), (Join-Path $DotClaude 'skills\handoff-sync-continue'))) {
  if ((Test-Path -LiteralPath $hp) -and -not @($listedAny | Where-Object { $_ -ieq $hp }).Count) { Note 'OK' "not installed by this package, left alone: $hp" }
}
if (-not $testMode) {
  $su = [Environment]::GetFolderPath('Startup'); $wshS = New-Object -ComObject WScript.Shell
  foreach ($l in @(Get-ChildItem -LiteralPath $su -Filter *.lnk -File -Force -ErrorAction SilentlyContinue)) {
    if ($wshS.CreateShortcut($l.FullName).TargetPath -match '(?i)\\cursor\.exe$' -and -not @($ManifestJson | Where-Object { $_.kind -eq 'startup' -and [string]$_.path -ieq $l.FullName }).Count) { Note 'OK' "Cursor autostart: not installed by this package, left alone: $($l.FullName)" }
  }
}

# 3. Guard hook script + config: removed in 2c only if the manifest lists them (install added them).
$listedFiles = @($ManifestJson | Where-Object { $_.kind -eq 'file' } | ForEach-Object { [string]$_.path })
foreach ($f in 'memory-link-guard.ps1', 'memory-link-guard.config.json') {
  $p = Join-Path $DotClaude "hooks\$f"
  if ((Test-Path -LiteralPath $p) -and -not @($listedFiles | Where-Object { $_ -ieq $p }).Count) { Note 'OK' "not installed by this package, left alone: $p" }
}

# 4. Junctions the manifest lists ('junction|<full path>'). Only a junction whose target is the store is removed,
#    and only the link: Directory.Delete(path, $false) on a junction never touches the target's files.
$listedLinks = @()
if (Test-Path -LiteralPath $ManifestPath) {
  $listedLinks = @([IO.File]::ReadAllLines($ManifestPath) | Where-Object { $_ -like 'junction|*' } | ForEach-Object { $_.Substring(9).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
}
foreach ($wl in $listedLinks) {
  $wi = Get-Item -LiteralPath $wl -Force -ErrorAction SilentlyContinue
  if (-not $wi) { continue }
  if ($wi.LinkType -eq 'Junction') {
    $targets = @($wi.Target | ForEach-Object { ($_ -replace '^\\\?\?\\', '').TrimEnd('\') })
    if ($targets -contains $Store) { Invoke-Change "remove junction (link only, notes stay in $Store): $wl" { [IO.Directory]::Delete($wl, $false) } }
    else { Note 'WARN' "junction points elsewhere, left alone: $wl" }
  } else { Note 'WARN' "not a junction to the store, left alone: $wl" }
}
foreach ($jl in @($LinkPath, $WmLink)) {
  if ((Get-Item -LiteralPath $jl -Force -ErrorAction SilentlyContinue) -and -not @($listedLinks | Where-Object { $_ -ieq $jl }).Count) { Note 'OK' "not installed by this package, left alone: $jl" }
}

# 5. Files install.ps1 added under <Projects> (_claude sync scripts, toolkit files). Only files listed in
#    the manifest; anything that was there before install is never listed, so it stays.
if (Test-Path -LiteralPath $ManifestPath) {
  foreach ($rel in @([IO.File]::ReadAllLines($ManifestPath) | Where-Object { $_ -and $_ -notmatch '\.\.' -and $_ -notlike 'junction|*' -and $_ -notlike 'json|*' })) {
    $p = Join-Path $ProjectsRoot $rel
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
    $topDir = ($rel -split '\\')[0]
    # toolkit files under <Projects> only come from older installs that copied the toolkit (LegacyFolders)
    if ((@('_claude') + @($TK.LegacyFolders)) -notcontains $topDir -or $rel -notmatch '\\') { Note 'WARN' "manifest entry outside an old toolkit copy / _claude ignored: $rel"; continue }
    Invoke-Change "remove $p (added by install)" { Backup-File $p; Remove-Item -LiteralPath $p -Force }
  }
  Invoke-Change "remove $ManifestPath" { Backup-File $ManifestPath; Remove-Item -LiteralPath $ManifestPath -Force }
} else { Note 'INFO' "no install manifest ($ManifestPath): nothing on this PC is recorded as installed by this package, so nothing is removed" }

# 5b. Folders install created (deepest first, only if empty), after the files and junctions inside them are gone
foreach ($m in @($ManifestJson | Where-Object { $_.kind -eq 'dir' } | Sort-Object { ([string]$_.path).Length } -Descending)) {
  $p = [string]$m.path
  if (-not (Test-Path -LiteralPath $p -PathType Container)) { continue }
  if ($WhatIf) { Note 'WOULD' "remove folder $p if it is empty"; continue }
  if (@(Get-ChildItem -LiteralPath $p -Force).Count -eq 0) { Invoke-Change "remove empty folder (created by install): $p" { Remove-Item -LiteralPath $p -Force } }
  else { Note 'INFO' "kept $p (not empty)" }
}

# 6. Shortcuts: only the links (and folder) the manifest lists, and only while a link still runs its script.
$wsh = $null
foreach ($m in @($ManifestJson | Where-Object { $_.kind -eq 'shortcut' })) {
  $lnk = [string]$m.path
  if (-not (Test-Path -LiteralPath $lnk)) { continue }
  if (-not $wsh) { $wsh = New-Object -ComObject WScript.Shell }
  $sc = $wsh.CreateShortcut($lnk)
  if ($sc.TargetPath -match 'powershell\.exe$' -and $sc.Arguments -like "*$([string]$m.script)*") {
    Invoke-Change "remove shortcut (added by install): $lnk" { Backup-File $lnk; Remove-Item -LiteralPath $lnk -Force }
  } else { Note 'WARN' "shortcut changed since install (does not run $($m.script)); left alone: $lnk" }
}
foreach ($m in @($ManifestJson | Where-Object { $_.kind -eq 'shortcut-dir' })) {
  $p = [string]$m.path
  if (-not (Test-Path -LiteralPath $p -PathType Container)) { continue }
  if ($WhatIf) { Note 'WOULD' "remove folder $p if it is empty (created by install)"; continue }
  if (@(Get-ChildItem -LiteralPath $p -Force).Count -eq 0) { Invoke-Change "remove empty folder (created by install): $p" { Remove-Item -LiteralPath $p -Force } }
  else { Note 'INFO' "kept $p (it still has other files)" }
}
if (-not $testMode) {
  $listedLnk = @($ManifestJson | Where-Object { $_.kind -eq 'shortcut' } | ForEach-Object { [string]$_.path })
  $scDir = Join-Path $PkgRoot $TK.ShortcutFolder
  foreach ($sc in $TK.Shortcuts) {
    $lp = Join-Path $scDir "$($sc.Name).lnk"
    if ((Test-Path -LiteralPath $lp) -and -not @($listedLnk | Where-Object { $_ -ieq $lp }).Count) { Note 'OK' "not installed by this package, left alone: $lp" }
  }
}

# 6b. Workstation-Watcher task (registered by install-admin.ps1): removed here when this window may, else printed below.
if (-not $testMode) {
  if (Get-ScheduledTask -TaskName 'Workstation-Watcher' -ErrorAction SilentlyContinue) {
    Invoke-Change 'remove scheduled task Workstation-Watcher' { Unregister-ScheduledTask -TaskName 'Workstation-Watcher' -Confirm:$false -ErrorAction Stop }
  } else { Note 'OK' 'task Workstation-Watcher is not registered' }
}

# 7. Admin-only and optional items: print the commands
Write-Host ''
Write-Host 'Scheduled tasks need admin. In PowerShell opened with "Run as admin" (same account), run:' -ForegroundColor White
Write-Host "  Unregister-ScheduledTask -TaskName 'Workstation-Watcher' -Confirm:`$false   # only if it is still listed (step above)"
Write-Host "  Remove-NetFirewallRule -DisplayName 'Workstation dashboard tailnet'   # only if you do not want phone access any more"
Write-Host ''
Write-Host 'Older installs only (this repo no longer ships it): if task Claude-Memory-To-Cursor-Sync exists, remove it in the same admin PowerShell:' -ForegroundColor White
Write-Host "  Unregister-ScheduledTask -TaskName 'Claude-Memory-To-Cursor-Sync' -Confirm:`$false"
Write-Host 'Older installs only (this repo no longer ships them): if task Latch-EnsureGrokBot exists, remove it in the same admin PowerShell:' -ForegroundColor White
Write-Host "  Unregister-ScheduledTask -TaskName 'Latch-EnsureGrokBot' -Confirm:`$false"
Write-Host 'and, only if the app should stop starting at sign-in, the GrokBot startup entry it added (normal PowerShell):' -ForegroundColor White
Write-Host "  Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'GrokBot'"
Write-Host '  Its old log in %USERPROFILE%\.grokbot\latch\ is harmless and can be deleted by hand.'

Write-Host ''
Write-Host 'Kept on purpose: memory store, Cursor Notes (and any old Cursor copy), every note, the Projects layout folders, all projects, the workstation repo clone (the toolkit runs from it), and any toolkit / _claude script that was there before install.'
if ($WhatIf) { Write-Host 'Dry run only. Nothing was changed.' -ForegroundColor Cyan }
if (@($Summary | Where-Object Status -eq 'ERROR').Count) { exit 1 }
exit 0
