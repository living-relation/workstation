#Requires -Version 5.1
# Generic toggle check for a local web app. Exit 0 = healthy.
#   -ListenOnly : only checks that something listens on -Port (use as a toggle "status").
#   -Tailscale  : also requires HTTP 200 on this PC's Tailscale IPv4 address.
param([Parameter(Mandatory)][int]$Port, [string]$Path = '/', [switch]$ListenOnly, [switch]$Tailscale)
$ErrorActionPreference = 'Continue'
$listen = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
if (-not $listen) { Write-Output "FAIL nothing listens on port $Port"; exit 1 }
$owner = ($listen | Select-Object -First 1).OwningProcess
Write-Output "OK   port $Port listening on $(($listen | ForEach-Object LocalAddress | Sort-Object -Unique) -join ', ') (pid $owner)"
if ($ListenOnly) { exit 0 }

$script:Lines = @()
function Test-Url([string]$url) {
    try {
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 8
        if ($r.StatusCode -eq 200) { $script:Lines += "OK   $url HTTP 200"; return $true }
        $script:Lines += "FAIL $url HTTP $($r.StatusCode)"; return $false
    } catch { $script:Lines += "FAIL $url $($_.Exception.Message)"; return $false }
}
$ok = Test-Url "http://127.0.0.1:$Port$Path"
if ($Tailscale) {
    $ts = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    $ip = $null
    if (Test-Path -LiteralPath $ts) { $ip = ((& $ts ip -4 2>$null) | Select-Object -First 1) }
    if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$') { if (-not (Test-Url "http://$($ip.Trim()):$Port$Path")) { $ok = $false } }
    else { Write-Output 'FAIL no Tailscale IPv4 address (is Tailscale running?)'; $ok = $false }
}
$script:Lines | ForEach-Object { Write-Output $_ }
if ($ok) { exit 0 } else { exit 1 }
