#Requires -Version 5.1
# Write one open shortcut and one close shortcut for each git repo directly in active\.
# A repo's .git must be a directory. Worktrees (.git is a file) and plain folders are skipped.
# Names that start with a dot are skipped. Does not start a session. Re-running updates the
# links and removes a pair whose folder is gone or is no longer a repo.
param(
    [string]$ActiveDir,
    [string]$LinkDir,
    [switch]$NoPause
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'rc-lib.ps1')

if (-not $ActiveDir -or -not $LinkDir) {
    $defaults = Get-RcDefaults -ScriptRoot $PSScriptRoot
    if (-not $ActiveDir) { $ActiveDir = $defaults.ActiveDir }
    if (-not $LinkDir) { $LinkDir = $defaults.LinkDir }
}

Write-Host ''
Write-Host "==== Make Claude remote shortcuts ====  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "  projects: $ActiveDir"
Write-Host "  links:    $LinkDir"
Write-Host ''

$open = Join-Path $PSScriptRoot 'rc-open.ps1'
$close = Join-Path $PSScriptRoot 'rc-close.ps1'
$r = Write-RcShortcuts -ActiveDir $ActiveDir -LinkDir $LinkDir -OpenScript $open -CloseScript $close
foreach ($e in @($r.Errors)) { Write-Host "  [FAIL] $e" -ForegroundColor Red }
if ($r.Ok) {
    Write-Host "  [ OK ] $($r.Projects) git repo(s); $($r.Created) created, $($r.Updated) updated, $($r.Removed) removed" -ForegroundColor Green
}
Write-Host ''
Write-Host "Start a project with its 'Start Claude remote - <folder>' shortcut. 'Stop Claude remote - <folder>' stops that session by folder and name, not by session id." -ForegroundColor DarkGray
if (-not $NoPause) {
    Write-Host ''
    Write-Host 'Press any key to close...' -ForegroundColor DarkGray
    try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
}
if ($r.Ok) { exit 0 }
exit 1
