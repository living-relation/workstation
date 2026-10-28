# ownership-notes.ps1 - add "owned by the workstation repo" notes to the folders install.ps1 creates. A note this script wrote (it starts with its own
# heading) is refreshed when its text changes; any other existing README.md / AGENTS.md / README-workstation.md is never changed. install.ps1 runs it; safe to run by hand.
# Usage: .\ownership-notes.ps1 [-ProjectsRoot <dir>] [-UserHome <dir>] [-StateDir <dir>] [-WhatIf]
[CmdletBinding(SupportsShouldProcess = $true)]
param([string]$ProjectsRoot, [string]$UserHome = $env:USERPROFILE,
      [string]$StateDir = (Join-Path $env:LOCALAPPDATA 'Workstation'))
$ErrorActionPreference = 'Stop'
$Repo = $PSScriptRoot
$Url = (& git -C $Repo remote get-url origin 2>$null); if (-not $Url) { $Url = 'the workstation repo' }
if (-not $ProjectsRoot) { $ProjectsRoot = Split-Path (Split-Path $Repo -Parent) -Parent }
$enc = New-Object Text.UTF8Encoding($false)
function Add-Note([string]$Dir, [string]$Name, [string]$Text) {
  if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return }
  $p = Join-Path $Dir $Name
  $action = 'added'
  if (Test-Path -LiteralPath $p) {
    $cur = [IO.File]::ReadAllText($p)
    $ours = $cur.StartsWith('# Owned by the workstation repo') -or $cur.StartsWith('# Workstation skill links')
    if (-not $ours -or $cur -eq $Text) { [pscustomobject]@{ Path = $p; Action = 'exists' }; return }
    $action = 'updated'
  }
  if ($PSCmdlet.ShouldProcess($p, "$action ownership note")) { [IO.File]::WriteAllText($p, $Text, $enc); [pscustomobject]@{ Path = $p; Action = $action } }
}
$own = @(
  @{ Dir = $StateDir; What = 'runtime state of the Workstation toolkit (config, logs, backups)' },
  @{ Dir = (Join-Path $StateDir 'desktop-commander-remote'); What = 'the Desktop Commander remote logs (the launcher scripts run from the repo, workstation\desktop-commander-remote\); the device login is held by Desktop Commander itself' },
  @{ Dir = (Join-Path $StateDir 'cursor-worker'); What = 'Cursor worker state and logs' },
  @{ Dir = (Join-Path $StateDir 'dashboard'); What = 'local dashboard runtime files (logs, token, cache; never commit them)' },
  @{ Dir = (Join-Path $StateDir 'backups'); What = 'backups the installer made before replacing links (add-only)' },
  @{ Dir = (Join-Path $ProjectsRoot '_claude'); What = 'the ONE shared working memory store, Claude Projects\Working Memory\memory\, and the install manifest. Claude Code, Claude desktop / Cowork and Cursor all use this same store: Claude Code reaches it through the junction %USERPROFILE%\.claude\working-memory, and Cursor edits the notes directly (no copy, no sync). Never create another memory store. The memory files inside are your own data; the repo only manages the scripts and links' }
  # Nothing is written inside the clone itself (that would dirty it); the repo's own README covers its folders.
)
foreach ($o in $own) {
  $body = "# Owned by the workstation repo`n`nThis folder is created and managed by the workstation repo ($Url, local clone ``$Repo``).`nIt holds $($o.What).`n`n- Don't move or rename it; the toolkit finds it by this path.`n- Change it through the workstation repo (install.ps1 / uninstall.ps1), not by hand.`n- No other repo owns it.`n"
  Add-Note $o.Dir 'README.md' $body
  Add-Note $o.Dir 'AGENTS.md' ($body + "`nAgents: treat this folder as add-only, and never delete anything here without the owner's yes.`n")
}
# Shared folders: only a note listing what workstation put there (the folder itself isn't workstation's).
# Directories with SKILL.md only; skills\<name>.zip files beside them are Claude import packages, not linked.
$names = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'skills') -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } | ForEach-Object Name)
foreach ($d in @((Join-Path $UserHome '.claude\skills'))) {
  Add-Note $d 'README-workstation.md' ("# Workstation skill links`n`nThis folder is shared. The workstation repo ($Url, clone ``$Repo``) owns only these links here, made by link-skills.ps1:`n" + (($names | ForEach-Object { "- $_" }) -join "`n") + "`n`nEvery other entry belongs to its own app or repo. uninstall.ps1 removes only the links it recorded.`n")
}
