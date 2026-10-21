#Requires -Version 5.1
# Start Desktop Commander remote in the background.
# Logon shortcut calls this with no switches (silent).
# Manual shortcut passes -Show so a window reports status.
# Command: npx @wonderwhy-er/desktop-commander@<pinned version> remote
# Lives in the workstation repo; the Startup link and shortcuts come from toolkit.psd1 via install-shortcuts.ps1.
# Logs stay in %LOCALAPPDATA%\Workstation\desktop-commander-remote (never in the clone). No tokens here.
param([switch]$Show, [switch]$NoPause)
# Pinned Desktop Commander version; keep in step with workstation.lock.yaml (upstream.desktop_commander).
$DcVersion = '0.3.0'
$ErrorActionPreference = 'Continue'
$dir = Join-Path $env:LOCALAPPDATA 'Workstation\desktop-commander-remote'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$log = Join-Path $dir 'start-dc-remote.log'

function Write-Log([string]$msg) {
    Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffzzz'), $msg) -Encoding UTF8
    try {
        $lines = @(Get-Content $log -Encoding UTF8)
        if ($lines.Count -gt 200) { Set-Content $log ($lines | Select-Object -Last 200) -Encoding UTF8 }
    } catch {}
}
function Write-Ok([string]$m)  { Write-Host "  [ OK ] $m" -ForegroundColor Green }
function Write-Off([string]$m) { Write-Host "  [ -- ] $m" -ForegroundColor DarkGray }
function Write-Bad([string]$m) { Write-Host "  [FAIL] $m" -ForegroundColor Red }

if ($Show) {
    Write-Host ''
    Write-Host '==== Desktop Commander Remote Start ====' -ForegroundColor Cyan
}

$already = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -and
    $_.CommandLine -match 'desktop-commander' -and
    $_.CommandLine -match '\bremote\b' -and
    $_.CommandLine -notmatch 'start-dc-remote' -and
    $_.CommandLine -notmatch 'stop-dc-remote'
})
if ($already) {
    $pids = ($already | ForEach-Object ProcessId) -join ','
    Write-Log ("already running (pids: $pids)")
    if ($Show) { Write-Ok "already running (pid $pids)" }
} else {
    $npxCmd = (Get-Command npx.cmd -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $npxCmd) { $npxCmd = Join-Path $env:ProgramFiles 'nodejs\npx.cmd' }
    if (-not (Test-Path -LiteralPath $npxCmd)) {
        Write-Log "launch FAILED: npx.cmd not found at $npxCmd"
        if ($Show) { Write-Bad "npx.cmd not found at $npxCmd" }
        if ($Show -and -not $NoPause) {
            Write-Host ''
            Write-Host 'Press any key to close...' -ForegroundColor DarkGray
            try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
        }
        exit 1
    }
    $out = Join-Path $dir 'remote.out.log'
    $err = Join-Path $dir 'remote.err.log'
    try {
        $p = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') `
            -ArgumentList @('/c', 'npx.cmd', '--yes', "@wonderwhy-er/desktop-commander@$DcVersion", 'remote') `
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
            if ($ok) { Write-Ok "Desktop Commander Remote is connected ($env:COMPUTERNAME Online)" }
            else { Write-Off 'started in background; check remote.out.log if it does not come online' }
        }
    } catch {
        Write-Log ("launch FAILED: {0}" -f $_.Exception.Message)
        if ($Show) { Write-Bad $_.Exception.Message }
        if ($Show -and -not $NoPause) {
            Write-Host ''
            Write-Host 'Press any key to close...' -ForegroundColor DarkGray
            try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
        }
        exit 1
    }
}

if ($Show) {
    Write-Host ''
    if (-not $NoPause) {
        Write-Host 'Press any key to close...' -ForegroundColor DarkGray
        try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
    }
}
