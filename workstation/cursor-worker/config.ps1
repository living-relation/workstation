# Shared settings for the Cursor "this PC" worker. Dot-sourced by the other scripts.
# Compatible with Windows PowerShell 5.1.

# Full host name (not $env:COMPUTERNAME, which Windows cuts to 15 characters).
$WorkerName   = [System.Net.Dns]::GetHostName()
# Projects root = two levels up from this folder (cursor-worker -> _workstation -> Projects).
$WorkerDir    = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$MgmtAddr     = '127.0.0.1:8787'
$HealthUrl    = "http://$MgmtAddr/healthz"

# Cursor CLI: 'agent' on PATH first (a folder that has versions\), else the default per-user install.
$AgentPs1 = $null
foreach ($c in @(Get-Command 'agent.ps1' -CommandType ExternalScript -All -ErrorAction SilentlyContinue)) {
    if ($c.Source -and (Test-Path (Join-Path (Split-Path -Parent $c.Source) 'versions'))) { $AgentPs1 = $c.Source; break }
}
if (-not $AgentPs1) { $AgentPs1 = Join-Path $env:LOCALAPPDATA 'cursor-agent\agent.ps1' }
$AgentRoot    = Split-Path -Parent $AgentPs1

$BaseDir      = $PSScriptRoot
$LogDir       = Join-Path $BaseDir 'logs'
$StateDir     = Join-Path $BaseDir 'state'
$CacheDir     = Join-Path $BaseDir 'sqlite-cache'
$PidFile      = Join-Path $StateDir 'supervisor.pid'
$FailFile     = Join-Path $StateDir 'health-fails.txt'
$DirsSigFile  = Join-Path $StateDir 'dirs.sig'
$WorkerLog    = Join-Path $LogDir 'worker.log'
$SupLog       = Join-Path $LogDir 'supervisor.log'
$HealthLog    = Join-Path $LogDir 'health.log'

$SupervisorTask = 'Cursor-Worker'
$HealthTask     = 'Cursor-Worker-Health'

foreach ($d in @($LogDir, $StateDir, $CacheDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

function Write-Log {
    param([string]$Message, [string]$File = $SupLog)
    if ((Test-Path $File) -and ((Get-Item $File).Length -gt 2MB)) {
        Move-Item $File "$File.old" -Force
    }
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $File -Value $line -Encoding UTF8
}

function Get-LatestAgentVersionDir {
    $dirs = Get-ChildItem -Path (Join-Path $AgentRoot 'versions') -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(\d{4})\.(\d{1,2})\.(\d{1,2})(-\d{2}-\d{2}-\d{2})?-[a-f0-9]+$' }
    $dirs | Sort-Object {
        $null = $_.Name -match '^(\d{4})\.(\d{1,2})\.(\d{1,2})'
        [int]('{0}{1}{2}' -f $Matches[1], $Matches[2].PadLeft(2, '0'), $Matches[3].PadLeft(2, '0'))
    } -Descending | Select-Object -First 1
}

# Cursor matches requests to a machine by each folder's git remote, so every project
# repo under active\ is registered as its own worker dir. The root goes first.
function Get-WorkerDirs {
    $dirs = New-Object System.Collections.Generic.List[string]
    $dirs.Add($WorkerDir)
    $active = Join-Path $WorkerDir 'active'
    if (Test-Path $active) {
        foreach ($d in (Get-ChildItem -Path $active -Directory | Sort-Object Name)) {
            if (-not (Test-Path (Join-Path $d.FullName '.git'))) { continue }
            $origin = & git -C $d.FullName remote get-url origin 2>$null
            if ($LASTEXITCODE -eq 0 -and $origin) { $dirs.Add($d.FullName) }
        }
    }
    return ,$dirs.ToArray()
}

function Get-DirsSignature {
    return ((Get-WorkerDirs) -join '|')
}

function Get-SessionActive {
    try {
        $m = (Invoke-WebRequest -Uri "http://$MgmtAddr/metrics" -UseBasicParsing -TimeoutSec 5).Content
        if ($m -match 'cursor_self_hosted_worker_session_active\s+(\d+)') { return [int]$Matches[1] }
    } catch { }
    return -1
}

function Get-SupervisorProcess {
    if (-not (Test-Path $PidFile)) { return $null }
    $id = (Get-Content $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    if (-not $id) { return $null }
    $proc = Get-Process -Id ([int]$id) -ErrorAction SilentlyContinue
    if (-not $proc) { return $null }
    # Command lines are hidden for task-launched processes, so guard against PID reuse by
    # checking the name and that the process started just before the PID file was written.
    if ($proc.ProcessName -ne 'powershell') { return $null }
    $written = (Get-Item $PidFile).LastWriteTime
    $delta = ($written - $proc.StartTime).TotalSeconds
    if ($delta -ge -5 -and $delta -le 120) { return $proc }
    return $null
}

function Start-Supervisor {
    $task = Get-ScheduledTask -TaskName $SupervisorTask -ErrorAction SilentlyContinue
    if ($task) {
        Start-ScheduledTask -TaskName $SupervisorTask
        return 'via scheduled task'
    }
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $BaseDir 'run-worker.ps1'))
    return 'via direct launch (task missing)'
}
