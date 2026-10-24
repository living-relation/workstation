# Test: worktree sessions use the main repo's memory folder (no folder per worktree).
# Runs in a temp fake profile; touches nothing real. Usage: powershell -File <this>
$ErrorActionPreference = 'Stop'
$hook = Join-Path $PSScriptRoot '..\memory-link-guard.ps1'
$t = Join-Path ([IO.Path]::GetTempPath()) ("mlg-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$store = Join-Path $t 'Projects\_claude\mem'
$active = Join-Path $t 'Projects\active'
New-Item -ItemType Directory -Force $store, $active, (Join-Path $t '.claude') | Out-Null
Set-Content (Join-Path $store 'MEMORY.md') "# Memory Index`r`n`r`n## Projects`r`n" -Encoding ascii
'{"autoMemoryDirectory": "' + ($store -replace '\\', '/') + '"}' | Set-Content (Join-Path $t '.claude\settings.json') -Encoding ascii
New-Item -ItemType Directory -Force (Join-Path $t '.claude\hooks') | Out-Null
'{"storePath": "' + ($store -replace '\\', '/') + '"}' | Set-Content (Join-Path $t '.claude\hooks\memory-link-guard.config.json') -Encoding ascii
$repo = Join-Path $active 'My Repo'
git init -q $repo; git -C $repo -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C $repo worktree add -q (Join-Path $repo '.claude\worktrees\wt-a') -b wt-a 2>$null
git -C $repo worktree add -q (Join-Path $active 'my-repo-wt-b') -b wt-b 2>$null
New-Item -ItemType Directory -Force (Join-Path $active 'plain\sub') | Out-Null
function Run($cwd) {
  $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', "-NoProfile -ExecutionPolicy Bypass -File `"$hook`""
  $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true
  $psi.EnvironmentVariables['USERPROFILE'] = $t
  $p = [Diagnostics.Process]::Start($psi)
  $p.StandardInput.Write((@{ cwd = $cwd } | ConvertTo-Json -Compress)); $p.StandardInput.Close()
  $null = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
}
$fail = 0
function Check($what, $ok) { if ($ok) { "PASS $what" } else { "FAIL $what"; $script:fail++ } }
Run (Join-Path $repo '.claude\worktrees\wt-a')
Check 'nested worktree -> main repo folder' ((Test-Path (Join-Path $store 'my-repo\INDEX.md')) -and -not (Test-Path (Join-Path $store 'wt-a')))
Run (Join-Path $active 'my-repo-wt-b')
Check 'sibling worktree -> main repo folder' (-not (Test-Path (Join-Path $store 'my-repo-wt-b')))
Run $repo
Check 'plain repo unchanged' ((Get-ChildItem $store -Directory).Name -join ',' -eq 'my-repo')
Run (Join-Path $active 'plain\sub')
Check 'non-git folder -> top folder' (Test-Path (Join-Path $store 'plain\INDEX.md'))
Check 'one MEMORY.md line per project' (@(Select-String -Path (Join-Path $store 'MEMORY.md') -Pattern '\(my-repo/INDEX.md\)').Count -eq 1)
git -C $repo worktree remove --force (Join-Path $repo '.claude\worktrees\wt-a') 2>$null
git -C $repo worktree remove --force (Join-Path $active 'my-repo-wt-b') 2>$null
Get-ChildItem $t -Recurse -Force -Attributes ReparsePoint -EA 0 | % { [IO.Directory]::Delete($_.FullName) }
Remove-Item $t -Recurse -Force
if ($fail) { exit 1 } else { 'ALL PASS' }
