#Requires -Version 5.1
<#
.SYNOPSIS
  Copy each instruction file to the clipboard, open it, and wait for Enter.
.DESCRIPTION
  install.ps1 runs this at the end. -Quiet skips it. One app and section at a time.
  Sublime Text is C:\Program Files\Sublime Text\subl.exe. Notepad is the fallback.
  Cowork is included only when the Global instructions box exists.

  Tests and CI must set WORKSTATION_PASTE_HOOK_DIR. When that directory is set,
  clipboard text is written to clipboard-N.txt and the editor path to editor.log;
  Set-Clipboard, clip.exe, pbcopy, xclip, Start-Process, subl.exe, and notepad
  are never called. Under CI or pytest, a missing hook directory is a hard
  refusal (exit 1) so a real clipboard or editor cannot be touched. Optional
  WORKSTATION_PASTE_SIDE_EFFECT_LOG records any real clipboard or editor call.
#>
[CmdletBinding()]
param(
  [switch]$Quiet,
  [switch]$WhatIf,
  [string]$PackageRoot
)

$ErrorActionPreference = 'Stop'
if ($Quiet) {
  Write-Output 'Paste helper skipped (-Quiet).'
  exit 0
}
if (-not $PackageRoot) {
  $PackageRoot = Split-Path -Parent $PSScriptRoot
}

$sections = @(
  @{
    File = 'instructions\instructions-for-claude.md'
    Where = 'Claude Desktop > Settings > General > Instructions for Claude'
    Ask = $false
  },
  @{
    File = 'instructions\cowork-global-instructions.md'
    Where = 'Cowork Global instructions'
    Ask = $true
  },
  @{
    File = 'instructions\cursor-user-rules.md'
    Where = 'Cursor Settings > Rules > User Rules'
    Ask = $false
  }
)

function Test-PasteSealed {
  return -not [string]::IsNullOrWhiteSpace($env:WORKSTATION_PASTE_HOOK_DIR)
}

function Test-PasteMustRefuseRealTools {
  if (Test-PasteSealed) { return $false }
  $ci = "$env:CI"
  if ($ci -eq 'true' -or $ci -eq 'True' -or $ci -eq '1') { return $true }
  if (-not [string]::IsNullOrWhiteSpace($env:PYTEST_CURRENT_TEST)) { return $true }
  return $false
}

function Write-SideEffectLog([string]$What) {
  $log = $env:WORKSTATION_PASTE_SIDE_EFFECT_LOG
  if ([string]::IsNullOrWhiteSpace($log)) { return }
  $dir = Split-Path -Parent $log
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir | Out-Null
  }
  [IO.File]::AppendAllText($log, $What + [Environment]::NewLine)
}

function Get-HookDir {
  $hook = $env:WORKSTATION_PASTE_HOOK_DIR
  if ([string]::IsNullOrWhiteSpace($hook)) { return $null }
  if (-not (Test-Path -LiteralPath $hook)) {
    New-Item -ItemType Directory -Path $hook | Out-Null
  }
  return $hook
}

function Write-RefuseAndExit {
  Write-Output 'Refusing to write the clipboard or open an editor in CI or pytest without WORKSTATION_PASTE_HOOK_DIR.'
  exit 1
}

function Copy-InstructionText([string]$Text) {
  $hook = Get-HookDir
  if ($hook) {
    $n = 1
    while (Test-Path -LiteralPath (Join-Path $hook "clipboard-$n.txt")) { $n++ }
    [IO.File]::WriteAllText((Join-Path $hook "clipboard-$n.txt"), $Text)
    Write-Output 'Copied to the clipboard.'
    Write-Output 'Clipboard write was sealed (no real clipboard).'
    return
  }
  if (Test-PasteMustRefuseRealTools) { Write-RefuseAndExit }
  try {
    if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) {
      Write-SideEffectLog 'Set-Clipboard'
      Set-Clipboard -Value $Text
      Write-Output 'Copied to the clipboard.'
      return
    }
  } catch { }
  Write-Output 'Could not copy to the clipboard. Copy the open file yourself.'
}

function Open-InstructionFile([string]$Path) {
  $hook = Get-HookDir
  if ($hook) {
    [IO.File]::AppendAllText((Join-Path $hook 'editor.log'), $Path + [Environment]::NewLine)
    Write-Output "Opened in sealed editor: $Path"
    return
  }
  if (Test-PasteMustRefuseRealTools) { Write-RefuseAndExit }
  $subl = 'C:\Program Files\Sublime Text\subl.exe'
  if (Test-Path -LiteralPath $subl) {
    Write-SideEffectLog "Start-Process $subl"
    Start-Process -FilePath $subl -ArgumentList $Path
    Write-Output "Opened in Sublime Text: $Path"
    return
  }
  $notepad = Get-Command notepad -ErrorAction SilentlyContinue
  if ($notepad) {
    Write-SideEffectLog "Start-Process $($notepad.Source)"
    Start-Process -FilePath $notepad.Source -ArgumentList $Path
    Write-Output "Opened in notepad: $Path"
    return
  }
  Write-Output "Sublime Text and notepad were not found. Open this file yourself: $Path"
}

foreach ($section in $sections) {
  $path = Join-Path $PackageRoot $section.File
  Write-Output ''
  Write-Output ("Paste into: " + $section.Where)
  Write-Output "File: $path"
  if ($section.Ask) {
    if ($WhatIf) {
      Write-Output 'Would ask whether the Cowork Global instructions box exists, and paste only if it does.'
      continue
    }
    $answer = Read-Host 'Does the Cowork Global instructions box exist? (y/n)'
    if ($answer -notmatch '^[Yy]') {
      Write-Output 'Skipped Cowork Global instructions (that box was not confirmed).'
      continue
    }
  }
  if ($WhatIf) {
    Write-Output 'Would copy the file to the clipboard, open it, and wait for Enter.'
    continue
  }
  if (-not (Test-Path -LiteralPath $path)) {
    Write-Output "WARN missing file: $path"
    continue
  }
  $text = [IO.File]::ReadAllText($path)
  Copy-InstructionText $text
  Open-InstructionFile $path
  Read-Host 'Press Enter when this paste is done' | Out-Null
}
exit 0
