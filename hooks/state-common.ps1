# Shared helpers for the state hooks (state-inject, state-lint-stop, protected-files-guard).
# The state tools live in the plugin's scripts/state folder. Order: WORKSTATION_STATE_TOOLS,
# CLAUDE_PLUGIN_ROOT/scripts/state, CURSOR_PLUGIN_ROOT/scripts/state, then <this folder>/../scripts/state.
# Every helper returns $null instead of throwing, so a hook can exit quietly on a repo that is not migrated.

function Read-StateHookInput {
  $raw = ''
  $redirected = $true
  try { $redirected = [Console]::IsInputRedirected } catch { $redirected = $true }
  if ($redirected) {
    try { $raw = [Console]::In.ReadToEnd() } catch { $raw = '' }
  }
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
  try { return ($raw | ConvertFrom-Json) } catch { return $null }
}

function Get-StateToolsDir {
  $candidates = @()
  if ($env:WORKSTATION_STATE_TOOLS) { $candidates += $env:WORKSTATION_STATE_TOOLS }
  if ($env:CLAUDE_PLUGIN_ROOT) { $candidates += (Join-Path $env:CLAUDE_PLUGIN_ROOT 'scripts/state') }
  if ($env:CURSOR_PLUGIN_ROOT) { $candidates += (Join-Path $env:CURSOR_PLUGIN_ROOT 'scripts/state') }
  $candidates += (Join-Path (Join-Path $PSScriptRoot '..') 'scripts/state')
  foreach ($dir in $candidates) {
    if ($dir -and (Test-Path -LiteralPath (Join-Path $dir 'state_paths.py') -PathType Leaf)) {
      return (Resolve-Path -LiteralPath $dir).Path
    }
  }
  return $null
}

function Get-StatePython {
  foreach ($name in @('python', 'python3')) {
    $cmd = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source -notmatch '(?i)WindowsApps') { return @($cmd.Source) }
  }
  $py = Get-Command 'py' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($py) { return @($py.Source, '-3') }
  return $null
}

function Invoke-StateTool {
  param([string]$Script, [string[]]$Arguments)
  $tools = Get-StateToolsDir
  $python = @(Get-StatePython)
  if (-not $tools -or $python.Count -eq 0 -or -not $python[0]) { return $null }
  $exe = $python[0]
  $args_ = @()
  if ($python.Count -gt 1) { $args_ += $python[1..($python.Count - 1)] }
  $args_ += (Join-Path $tools $Script)
  $args_ += $Arguments
  $oldPref = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $env:PYTHONIOENCODING = 'utf-8'
  $errFile = [IO.Path]::GetTempFileName()
  try {
    $out = & $exe @args_ 2> $errFile
    $code = $LASTEXITCODE
    $err = ''
    try { $err = [IO.File]::ReadAllText($errFile) } catch { $err = '' }
  } catch {
    return $null
  } finally {
    $ErrorActionPreference = $oldPref
    Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
  }
  return [pscustomobject]@{ Code = $code; Out = (@($out) -join [Environment]::NewLine); Err = $err }
}

function Get-StateHookCwd {
  param($HookInput)
  $cwd = $null
  try {
    if ($HookInput -and $HookInput.PSObject.Properties['cwd'] -and $HookInput.cwd) { $cwd = [string]$HookInput.cwd }
  } catch { $cwd = $null }
  if (-not $cwd) {
    try {
      if ($HookInput -and $HookInput.PSObject.Properties['workspace_roots'] -and @($HookInput.workspace_roots).Count -gt 0) {
        $cwd = [string](@($HookInput.workspace_roots)[0])
      }
    } catch { $cwd = $null }
  }
  if (-not $cwd) { try { $cwd = (Get-Location).ProviderPath } catch { return $null } }
  if (-not (Test-Path -LiteralPath $cwd -PathType Container)) { return $null }
  return $cwd
}

function Get-StatePathInfo {
  param([string]$Repo)
  if (-not $Repo) { return $null }
  $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue
  if (-not $git) { return $null }
  $result = Invoke-StateTool 'state_paths.py' @('--repo', $Repo, '--json')
  if (-not $result -or $result.Code -ne 0 -or -not $result.Out) { return $null }
  try { $info = $result.Out | ConvertFrom-Json } catch { return $null }
  if (-not $info.project -or -not $info.project_dir) { return $null }
  return $info
}

function Test-CursorHook {
  param($HookInput)
  if ($env:CURSOR_VERSION) { return $true }
  try {
    if ($HookInput -and ($HookInput.PSObject.Properties['cursor_version'] -or $HookInput.PSObject.Properties['conversation_id'])) { return $true }
  } catch { }
  return $false
}
