# Launcher for the Cursor plugin hook (hooks/cursor-hooks.json preCompact and stop).
# Runs handoff-at-80.py --from-plugin with py -3, else python3, else python, and passes the hook payload
# on stdin. With no Python 3 it prints {} (Cursor treats an empty reply as invalid JSON) and exits 0.
$ErrorActionPreference = 'Continue'
$raw = [Console]::In.ReadToEnd()
$py = Join-Path $PSScriptRoot 'handoff-at-80.py'
$cands = @(@('py', '-3'), @('python3'), @('python'))
foreach ($c in $cands) {
  $cmd = Get-Command $c[0] -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $cmd) { continue }
  $pre = @(); if ($c.Count -gt 1) { $pre = $c[1..($c.Count - 1)] }
  $ok = $false
  try { & $cmd.Source @pre -c 'import sys; sys.exit(0 if sys.version_info >= (3, 7) else 1)' 2>$null | Out-Null; $ok = ($LASTEXITCODE -eq 0) } catch { }
  if (-not $ok) { continue }
  $out = $raw | & $cmd.Source @pre $py --from-plugin
  if ($out) { $out } else { '{}' }
  exit 0
}
'{}'
exit 0
