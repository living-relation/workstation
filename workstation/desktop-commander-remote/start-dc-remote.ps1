#Requires -Version 5.1
# Manual Start. One shortcut, no sign-in item. Does not launch or remove the desktop app.
#   1. Stop stale or duplicate phone-remote copies (keep the one healthy copy).
#   2. Start exactly one phone remote, or say the healthy one is already online.
# On Windows the remote command is: npx.cmd @wonderwhy-er/desktop-commander@latest remote
# The Desktop Commander MCP plugin is separate. Claude starts that itself.
# The shortcut passes -Show. Logs: %LOCALAPPDATA%\Workstation\desktop-commander-remote
param([switch]$Show, [switch]$NoPause)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'dc-remote-lib.ps1')

$dir = Join-Path $env:LOCALAPPDATA 'Workstation\desktop-commander-remote'
if (-not $env:WORKSTATION_FAKE_PROCS) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$log = Join-Path $dir 'start-dc-remote.log'

function Write-Log([string]$msg) {
    if ($env:WORKSTATION_FAKE_PROCS) { return }
    Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffzzz'), $msg) -Encoding UTF8
    try {
        $lines = @(Get-Content $log -Encoding UTF8)
        if ($lines.Count -gt 200) { Set-Content $log ($lines | Select-Object -Last 200) -Encoding UTF8 }
    } catch { }
}
function Write-Ok([string]$m)  { Write-Host "  [ OK ] $m" -ForegroundColor Green }
function Write-Off([string]$m) { Write-Host "  [ -- ] $m" -ForegroundColor DarkGray }
function Write-Bad([string]$m) { Write-Host "  [FAIL] $m" -ForegroundColor Red }
function Wait-Close {
    if (-not $Show -or $NoPause) { return }
    Write-Host ''
    Write-Host 'Press any key to close...' -ForegroundColor DarkGray
    try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
}

if ($Show) {
    Write-Host ''
    Write-Host '==== Start Desktop Commander ====' -ForegroundColor Cyan
    Write-Host 'one copy serves all chats'
}

$rows = @(Get-DcRemoteRows)
$keep = Get-DcRemoteKeep $rows
foreach ($extra in @(Get-DcRemoteStopList $rows)) {
    Write-Log ("stop leftover pid $($extra.Pid) $($extra.Verdict)")
    if ($Show) { Write-Off "stopped leftover pid $($extra.Pid) ($($extra.Verdict))" }
    if (-not $env:WORKSTATION_FAKE_PROCS) { Stop-TrackedPid (Get-DcStopPid $extra) | Out-Null }
}
if ($keep) {
    Write-Log ("already online pid $($keep.Pid)")
    if ($Show) { Write-Ok "already online (pid $($keep.Pid)). One copy serves all chats." }
    Wait-Close
    exit 0
}

$npxCmd = $null
$cmd = Get-Command npx.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
if ($cmd) { $npxCmd = $cmd.Source }
if (-not $npxCmd) { $npxCmd = Join-Path $env:ProgramFiles 'nodejs\npx.cmd' }
if (-not (Test-Path -LiteralPath $npxCmd)) {
    Write-Log "launch FAILED: npx.cmd not found at $npxCmd"
    if ($Show) { Write-Bad "npx.cmd not found at $npxCmd" }
    Wait-Close
    exit 1
}
$out = Join-Path $dir 'remote.out.log'
$err = Join-Path $dir 'remote.err.log'
try {
    $p = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') `
        -ArgumentList @('/c', 'npx.cmd', '--yes', '@wonderwhy-er/desktop-commander@latest', 'remote') `
        -WorkingDirectory (Split-Path $npxCmd -Parent) `
        -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err -ErrorAction Stop
    Write-Log ("launched pid $($p.Id)")
    if ($Show) {
        Write-Ok "started (pid $($p.Id)); waiting for Online..."
        $ok = $false
        for ($i = 0; $i -lt 12; $i++) {
            Start-Sleep -Seconds 1
            if ((Test-Path $out) -and ((Get-Content $out -Raw -ErrorAction SilentlyContinue) -match 'Status: Online|Device ready|Remote is connected')) {
                $ok = $true; break
            }
            if ((Test-Path $err) -and ((Get-Content $err -Raw -ErrorAction SilentlyContinue) -match 'Error|FAILED|Cannot find')) { break }
        }
        if ($ok) { Write-Ok "Desktop Commander remote is online ($env:COMPUTERNAME). One copy serves all chats." }
        else { Write-Off 'started in the background; check remote.out.log if it does not come online' }
    }
} catch {
    Write-Log ("launch FAILED: {0}" -f $_.Exception.Message)
    if ($Show) { Write-Bad $_.Exception.Message }
    Wait-Close
    exit 1
}
Wait-Close
exit 0
