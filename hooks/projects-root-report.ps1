# Stop hook. Lists entries in the projects root that are not on the allowed list.
# No projects root: exit with no output. stop_hook_active or a later Cursor loop stays quiet.
. (Join-Path $PSScriptRoot 'projects-root-common.ps1')

function Invoke-ProjectsRootReport {
  param($In)
  if ($In -and $In.stop_hook_active) { exit 0 }
  if ($In -and $null -ne $In.loop_count -and ([int]$In.loop_count -ge 1)) { exit 0 }
  $root = Get-ProjectsRoot
  if (-not $root) { exit 0 }
  $display = Get-ProjectsRootDisplay $root
  $allowed = @('active', '_archive', '_scratch', '_claude', '_tools', '_refs', '.claude', '.cursor', 'AGENTS.md')
  $stray = @(Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | Where-Object { $allowed -notcontains $_.Name } | ForEach-Object { $_.Name })
  if ($stray.Count -eq 0) { exit 0 }
  $list = ($stray | ForEach-Object { (Join-Path $display $_) }) -join ', '
  $msg = "projects-root-report: these entries are in the projects root but are not allowed there: $list. If you made them this session, move them into $display\active\<project>\ (or that project's _scratch\). If you did not make them, tell Dan instead of moving them. See $display\AGENTS.md."
  $cursor = [bool]$env:CURSOR_VERSION
  if ((-not $cursor) -and $In -and $In.cursor_version) { $cursor = $true }
  if ($cursor) {
    [ordered]@{ followup_message = $msg } | ConvertTo-Json -Compress
  } else {
    [ordered]@{ decision = 'block'; reason = $msg } | ConvertTo-Json -Compress
  }
  exit 0
}

if ($MyInvocation.InvocationName -ne '.') {
  $ErrorActionPreference = 'SilentlyContinue'
  $raw = ''
  try { $raw = [Console]::In.ReadToEnd() } catch { $raw = '' }
  if ([string]::IsNullOrWhiteSpace($raw)) {
    $raw = @($input | ForEach-Object { "$_" }) -join "`n"
  }
  $in = $null
  if (-not [string]::IsNullOrWhiteSpace($raw)) {
    try { $in = $raw | ConvertFrom-Json } catch { $in = $null }
  }
  Invoke-ProjectsRootReport -In $in
}
