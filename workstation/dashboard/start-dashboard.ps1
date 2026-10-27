#Requires -Version 5.1
# Start the local project dashboard if it is not already answering.
# Does not start or stop Cursor or Claude workers (the dashboard's toggles do, on request).
# -NoPause: never wait at the end. Otherwise the window waits only when something needs reading
# (a warning or a failure); on success it opens the page and closes after a few seconds.
param([switch]$NoPause, [switch]$NoBrowser)
$ErrorActionPreference = 'Continue'
$script:Warnings = 0
function Write-DashWarn([string]$m) { $script:Warnings++; Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Exit-Dash([int]$code) {
    if (-not $NoPause) {
        if ($code -ne 0 -or $script:Warnings -gt 0) { Write-Host 'Press Enter to close.'; Read-Host | Out-Null }
        else { Write-Host 'Closing in 5 s.' -ForegroundColor DarkGray; Start-Sleep -Seconds 5 }
    }
    exit $code
}
$here = $PSScriptRoot
$port = 8791
$state = Join-Path $env:LOCALAPPDATA 'Workstation\dashboard'
New-Item -ItemType Directory -Force -Path $state | Out-Null

function Find-Python313 {
    $cmd = Get-Command python3.13 -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $root = Join-Path $env:APPDATA 'uv\python'
    if (Test-Path -LiteralPath $root) {
        $hit = Get-ChildItem -LiteralPath $root -Directory -Filter 'cpython-3.13.*-windows-x86_64-none' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($hit) {
            $exe = Join-Path $hit.FullName 'python.exe'
            if (Test-Path -LiteralPath $exe) { return $exe }
        }
    }
    return $null
}

function New-DashLink([string]$Path, [string]$Script) {
    $wsh = New-Object -ComObject WScript.Shell
    $item = $wsh.CreateShortcut($Path)
    $item.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $item.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$Script`""
    $item.WorkingDirectory = Split-Path -Parent $Script
    $item.WindowStyle = 1
    $item.Description = 'Local project dashboard'
    $item.IconLocation = "$(Join-Path $env:SystemRoot 'System32\shell32.dll'),13"
    $item.Save()
}

$tokenFile = Join-Path $state 'token.txt'
if (-not (Test-Path -LiteralPath $tokenFile)) {
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $token = ([Convert]::ToBase64String($bytes)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    Set-Content -LiteralPath $tokenFile -Value $token -Encoding ascii -NoNewline
}

$ts = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
if (Test-Path -LiteralPath $ts) {
    $ip = ((& $ts ip -4 2>$null) | Select-Object -First 1)
    if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$') { $env:DASHBOARD_BIND = $ip.Trim()
    $env:PYTHONUNBUFFERED = '1' }
}

$python = Find-Python313
if (-not $python) {
    Write-Host '[FAIL] Python 3.13 was not found. Install it or put python3.13 on PATH.' -ForegroundColor Red
    Exit-Dash 1
}

$healthy = $false
try {
    $health = Invoke-WebRequest -Uri "http://127.0.0.1:$port/api/health" -UseBasicParsing -TimeoutSec 2
    $healthy = $health.StatusCode -eq 200
} catch { $healthy = $false }

if (-not $healthy) {
    $outLog = Join-Path $state 'server.log'
    $errLog = Join-Path $state 'server.err.log'
    $proc = Start-Process -FilePath $python -WorkingDirectory $here -WindowStyle Hidden -PassThru `
        -ArgumentList @((Join-Path $here 'server.py')) `
        -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    Set-Content -LiteralPath (Join-Path $state 'server.pid') -Value $proc.Id -Encoding ascii
    $deadline = (Get-Date).AddSeconds(20)
    do {
        Start-Sleep -Milliseconds 400
        try {
            $health = Invoke-WebRequest -Uri "http://127.0.0.1:$port/api/health" -UseBasicParsing -TimeoutSec 2
            if ($health.StatusCode -eq 200) { $healthy = $true }
        } catch { $healthy = $false }
    } while (-not $healthy -and (Get-Date) -lt $deadline)
}

if (-not $healthy) {
    Write-Host "[FAIL] Dashboard did not answer on http://127.0.0.1:$port/ (see $state\server.err.log)" -ForegroundColor Red
    Exit-Dash 1
}
Write-Host "Dashboard http://127.0.0.1:$port/"

$ts = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
if (Test-Path -LiteralPath $ts) {
    $status = (& $ts serve status 2>&1 | Out-String)
    $ours = $status -match [regex]::Escape("127.0.0.1:$port") -or $status -match [regex]::Escape(":$port")
    if ($status -match 'No serve config' -or $ours -or $status.Trim() -eq '') {
        $help = (& $ts serve --help 2>&1 | Out-String)
        $serveArgs = @('serve', '--bg', "$port")
        if ($help -match '(?m)^\s*--yes\b' -or $help -match ' --yes') { $serveArgs = @('serve', '--bg', '--yes', "$port") }
        $serveOut = Join-Path $state 'tailscale-serve.log'
        $serveErr = Join-Path $state 'tailscale-serve.err.log'
        $serveProc = Start-Process -FilePath $ts -ArgumentList $serveArgs -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput $serveOut -RedirectStandardError $serveErr
        if (-not $serveProc.WaitForExit(20000)) {
            Stop-Process -Id $serveProc.Id -Force -ErrorAction SilentlyContinue
            Write-DashWarn 'Tailscale serve did not finish. Localhost still works.'
        }
    } else {
        Write-Host 'Tailscale serve already has a different config. Left it alone.'
    }
    $funnel = (& $ts funnel status 2>&1 | Out-String)
    if ($funnel -match 'Funnel on' -and $funnel -match [regex]::Escape("$port")) {
        Write-Host 'Tailscale Funnel is on for this port. It was not changed. The dashboard must stay off the public internet.'
    }
    try {
        $self = (& $ts status --json | ConvertFrom-Json).Self
        $dns = ([string]$self.DNSName).TrimEnd('.')
        $token = (Get-Content -LiteralPath $tokenFile -Raw).Trim()
        # Phone bookmark: HTTPS MagicDNS (Secure cookie). Prefer Serve HTTPS over http://100.x.
        if ($env:DASHBOARD_BIND) {
            Write-Host "Phone: prefer the HTTPS Tailscale address (not http://$($env:DASHBOARD_BIND):$port/)."
            $alias = (Get-NetAdapter -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'Tailscale' -or $_.InterfaceDescription -match 'Tailscale' } |
                Select-Object -First 1).Name
            $rule = Get-NetFirewallRule -DisplayName 'Workstation dashboard tailnet' -ErrorAction SilentlyContinue
            $admin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            if ($alias -and -not $rule -and -not $admin) {
                Write-DashWarn "No firewall rule for TCP $port on the tailnet yet (adding one needs admin). The dashboard works; from the phone use the https://<pc>.ts.net address. To add the rule once, run install-admin.ps1 as admin."
            } elseif ($alias -and -not $rule) {
                try {
                    New-NetFirewallRule -DisplayName 'Workstation dashboard tailnet' -Direction Inbound -Action Allow `
                        -Protocol TCP -LocalPort $port -InterfaceAlias $alias -Profile Any -ErrorAction Stop | Out-Null
                    Write-Host "Firewall allows TCP $port on $alias."
                } catch {
                    Write-DashWarn "Could not add the tailnet firewall rule: $($_.Exception.Message). Localhost and https://<pc>.ts.net still work."
                }
            }
        }
        if ($dns) {
            $phoneHttps = "https://$dns/?token=$token"
            Write-Host "Phone (tailnet HTTPS): https://$dns/"
            # Valid Windows Internet Shortcut so Explorer can open it (plain multi-line text does not).
            $shortcutBody = "[InternetShortcut]`r`nURL=$phoneHttps`r`n"
            Set-Content -LiteralPath (Join-Path $state 'phone.url') -Value $shortcutBody -Encoding ascii -NoNewline
            Set-Content -LiteralPath (Join-Path $state 'phone-link.txt') -Value $phoneHttps -Encoding ascii
            # Optional QR via make_phone_qr.py; skips quietly if segno/qrcode are missing.
            $qrPng = Join-Path $state 'phone-qr.png'
            $qrHelper = Join-Path $here 'make_phone_qr.py'
            if (Test-Path -LiteralPath $qrHelper) {
                & $python $qrHelper (Join-Path $state 'phone-link.txt') $qrPng 2>$null
                if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $qrPng)) {
                    Write-Host "Phone QR written (scan with the phone; Tailscale must be online)."
                }
            }
        }
    } catch { Write-DashWarn 'Could not read the Tailscale name. Localhost still works.' }
} else {
    Write-Host 'Tailscale is not installed. Localhost still works.'
}

$linkDir = $null
$cfg = Join-Path $env:LOCALAPPDATA 'Workstation\workstation.json'
if (Test-Path -LiteralPath $cfg) {
    try {
        $toolkit = [string](Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json).toolkit
        if ($toolkit) { $linkDir = Join-Path (Split-Path -Parent $toolkit) 'shortcuts' }
    } catch { $linkDir = $null }
}
if (-not $linkDir -or -not (Test-Path -LiteralPath $linkDir)) {
    $linkDir = Join-Path (Split-Path -Parent (Split-Path -Parent $here)) 'shortcuts'
}
if (Test-Path -LiteralPath $linkDir) {
    New-DashLink (Join-Path $linkDir 'Dashboard.lnk') (Join-Path (Split-Path -Parent $here) 'shortcuts\dashboard.ps1')
}

Push-Location -LiteralPath $here
& $python -c "import json; from collect import state_dir, _capabilities, _usage_limits; usage=_usage_limits(); auth=bool((usage.get('cursor') or {}).get('authenticated')); (state_dir()/'capabilities.json').write_text(json.dumps(_capabilities(auth), indent=2), encoding='utf-8')"
Pop-Location
if (-not $NoBrowser -and -not $NoPause) { Start-Process "http://127.0.0.1:$port/" }
Exit-Dash 0
