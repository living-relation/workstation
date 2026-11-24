# SessionStart hook. Prints the workstation memory-store rules and the app lock rules (harness.design, Fusion Desktop) from this
# plugin's memory\templates, so they load from the workstation-core plugin instead of text appended to
# ~\.claude\CLAUDE.md or ~\.cursor\rules\*.mdc (owner decision 2026-11-22, E3).
# Claude Code / Cowork: claude-global-memory-section.md + app-locks.md as plain text on stdout.
# Cursor (sessionStart): claude-shared-memory.mdc (without front matter) + app-locks.md as one
# {"additional_context": ...} line.
# A part is skipped when the user's own rule file already has that marked block (older installs appended
# it), so nothing is loaded twice. Placeholders are filled from the projects root saved by install.ps1
# (%LOCALAPPDATA%\Workstation\workstation.json) or WORKSTATION_PROJECTS_ROOT.
# Silent exit 0 when this PC is not a workstation PC (no projects root) or there is nothing to add
# (the user's own rule file already has the block, or a template is missing). An unexpected error
# exits 0 with a loud fail: Claude Code gets systemMessage plus additionalContext; Cursor sessionStart
# gets the same instruction in additional_context (it cannot show a user message). The agent is told
# to open its reply with "WORKSTATION RULES NOT LOADED: <reason>". Never writes anything.
# Tests set WORKSTATION_INJECT_FAIL to force that path.
. (Join-Path $PSScriptRoot 'state-common.ps1')

function Get-RulesProjectsRoot {
  if ($env:WORKSTATION_PROJECTS_ROOT) { return $env:WORKSTATION_PROJECTS_ROOT.TrimEnd('\', '/') }
  if (-not $env:LOCALAPPDATA) { return $null }
  $cfg = Join-Path (Join-Path $env:LOCALAPPDATA 'Workstation') 'workstation.json'
  if (-not (Test-Path -LiteralPath $cfg -PathType Leaf)) { return $null }
  try { $root = [string](Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json).projectsRoot } catch { return $null }
  if (-not $root) { return $null }
  return $root.TrimEnd('\', '/')
}

function Get-RulesHome {
  if ($env:USERPROFILE) { return $env:USERPROFILE.TrimEnd('\', '/') }
  return ([string]$HOME).TrimEnd('\', '/')
}

function Get-MarkedBlock {
  param([string]$Text, [string]$Name)
  $start = "<!-- ${Name}:v1 -->"
  $end = "<!-- /${Name}:v1 -->"
  $i = $Text.IndexOf($start)
  if ($i -lt 0) { return $null }
  $j = $Text.IndexOf($end, $i)
  if ($j -lt 0) { return $Text.Substring($i).Trim() }
  return $Text.Substring($i, $j + $end.Length - $i).Trim()
}

function Test-FileHasMarker {
  param([string[]]$Paths, [string]$Name)
  foreach ($p in $Paths) {
    if (-not $p -or -not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
    try { $t = [IO.File]::ReadAllText($p) } catch { continue }
    if ($t.Contains("<!-- ${Name}:v1 -->")) { return $true }
  }
  return $false
}

function Format-RulesInjection {
  param([string]$TemplatesDir, [string]$ProjectsRoot, [string]$UserHome, [bool]$Cursor)
  $map = [ordered]@{
    '{{USERPROFILE_FWD}}'    = ($UserHome -replace '\\', '/')
    '{{USERPROFILE}}'        = $UserHome
    '{{PROJECTS_ROOT_FWD}}'  = ($ProjectsRoot -replace '\\', '/')
    '{{PROJECTS_ROOT}}'      = $ProjectsRoot
    '{{CLAUDE_PROJECT_KEY}}' = ($ProjectsRoot -replace '[^A-Za-z0-9]', '-')
  }
  if ($Cursor) {
    $memName = 'claude-shared-memory.mdc'
    $own = @(Get-ChildItem -LiteralPath (Join-Path (Join-Path $UserHome '.cursor') 'rules') -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
  } else {
    $memName = 'claude-global-memory-section.md'
    $own = @((Join-Path (Join-Path $UserHome '.claude') 'CLAUDE.md'))
  }
  $parts = New-Object 'System.Collections.Generic.List[string]'
  foreach ($pair in @(@($memName, 'shared-memory'), @('app-locks.md', 'app-locks'))) {
    if (Test-FileHasMarker $own $pair[1]) { continue }
    $path = Join-Path $TemplatesDir $pair[0]
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $block = Get-MarkedBlock ([IO.File]::ReadAllText($path)) $pair[1]
    if (-not $block) { continue }
    foreach ($k in $map.Keys) { $block = $block.Replace($k, [string]$map[$k]) }
    [void]$parts.Add(($block -replace "`r`n", "`n"))
  }
  if (-not $parts.Count) { return $null }
  $head = 'rules-inject: workstation-core rules (memory store and app locks). They apply to this session.'
  return (($head, ($parts -join "`n`n")) -join "`n")
}

if ($MyInvocation.InvocationName -ne '.') {
  $ErrorActionPreference = 'SilentlyContinue'
  $hookIn = $null
  try {
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
    $hookIn = Read-StateHookInput
    if ($env:WORKSTATION_INJECT_FAIL) { throw $env:WORKSTATION_INJECT_FAIL }
    $root = Get-RulesProjectsRoot
    if (-not $root) { exit 0 }
    $templates = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'memory') 'templates'
    $cursor = [bool](Test-CursorHook $hookIn)
    $text = Format-RulesInjection -TemplatesDir $templates -ProjectsRoot $root -UserHome (Get-RulesHome) -Cursor $cursor
    if (-not $text) { exit 0 }
    if ($cursor) { [Console]::Out.WriteLine((@{ additional_context = $text } | ConvertTo-Json -Compress)) }
    else { [Console]::Out.WriteLine($text) }
    exit 0
  } catch {
    Write-RulesNotLoaded -HookInput $hookIn -Reason $_.Exception.Message -EventName 'SessionStart'
    exit 0
  }
}
