#Requires -Version 5.1
<#
.SYNOPSIS
  Copy each instruction file to the clipboard, open it, and wait for Enter.
.DESCRIPTION
  install.ps1 runs this at the end. -Quiet skips it. One app and section at a time.
  Sublime Text is C:\Program Files\Sublime Text\subl.exe. Notepad is the fallback.
  Cowork is included only when the Global instructions box exists.
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

function Copy-InstructionText([string]$Text) {
  try {
    if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) {
      Set-Clipboard -Value $Text
      Write-Output 'Copied to the clipboard.'
      return
    }
  } catch { }
  Write-Output 'Could not copy to the clipboard. Copy the open file yourself.'
}

function Open-InstructionFile([string]$Path) {
  $subl = 'C:\Program Files\Sublime Text\subl.exe'
  if (Test-Path -LiteralPath $subl) {
    Start-Process -FilePath $subl -ArgumentList $Path
    Write-Output "Opened in Sublime Text: $Path"
    return
  }
  $notepad = Get-Command notepad -ErrorAction SilentlyContinue
  if ($notepad) {
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
