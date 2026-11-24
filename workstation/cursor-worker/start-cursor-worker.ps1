#Requires -Version 5.1
# Manual Start. Lists folders in <Projects>\active and starts one Cursor worker
# for the folder you pick. Run it again to start another folder.
# No scheduled task, no Startup item, no Run key, no hourly check.
# Shortcut: install.ps1 writes shortcuts\Start Cursor worker.lnk
param([string]$Folder, [switch]$WhatIf, [switch]$NoPause)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'cursor-worker-lib.ps1')

function Write-Ok([string]$m)  { Write-Host "  [ OK ] $m" -ForegroundColor Green }
function Write-Off([string]$m) { Write-Host "  [ -- ] $m" -ForegroundColor DarkGray }
function Write-Bad([string]$m) { Write-Host "  [FAIL] $m" -ForegroundColor Red }
function Wait-Close {
    if ($NoPause) { return }
    Write-Host ''
    Write-Host 'Press any key to close...' -ForegroundColor DarkGray
    try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
}
function Write-CwLog([string]$Msg) {
    # 'none' is an empty process list for tests. Still write the log under the temp LOCALAPPDATA.
    if ($env:WORKSTATION_FAKE_PROCS -and $env:WORKSTATION_FAKE_PROCS -ne 'none') { return }
    try {
        $dir = Get-CursorWorkerRoot
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $log = Join-Path $dir 'start.log'
        Add-Content -LiteralPath $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg) -Encoding ASCII
        $lines = @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue)
        if ($lines.Count -gt 200) { Set-Content -LiteralPath $log ($lines | Select-Object -Last 200) -Encoding ASCII }
    } catch { }
}

Write-Host ''
Write-Host '==== Start Cursor worker ====' -ForegroundColor Cyan
Write-Host 'Manual only. Nothing starts at sign-in.'

$active = Get-ActiveProjectsDir
Write-Host "Projects active folder: $active"

$cli = Resolve-AgentCli
if (-not $cli) {
    Write-Bad 'Cursor CLI (agent) was not found.'
    Write-Host 'Install it, then sign in. Docs: https://cursor.com/docs/cloud-agent/self-hosted/my-machines'
    Write-Host "  irm 'https://cursor.com/install?win32=true' | iex"
    Write-Host '  agent login'
    Wait-Close
    exit 1
}

$folders = @(Get-ActiveFolders)
if ($folders.Count -eq 0) {
    Write-Bad "No folders in $active"
    Write-Host 'The projects root comes from this PC (workstation.json, else the clone location). It is not hard-coded.'
    Wait-Close
    exit 1
}

$picked = $null
if ($Folder) {
    $picked = Resolve-ActiveFolder $Folder
    if (-not $picked) {
        Write-Bad "Not a folder in ${active}: $Folder"
        Wait-Close
        exit 1
    }
} else {
    $running = @(Get-CursorWorkerRows)
    Write-Host ''
    Write-Host 'Pick a folder. A second Start can run another folder.'
    $i = 1
    foreach ($d in @($folders)) {
        $suffix = ''
        foreach ($r in @($running)) {
            if (Test-SamePath $r.Folder $d.FullName) { $suffix = ' (already running)'; break }
        }
        Write-Host (Format-FolderChoice $i $d $suffix)
        $i++
    }
    Write-Host '  q. quit'
    $ans = ''
    try { $ans = Read-Host 'Number' } catch { $ans = '' }
    if (-not $ans -or $ans -eq 'q') { Write-Off 'quit'; Wait-Close; exit 0 }
    $n = 0
    if (-not [int]::TryParse($ans.Trim(), [ref]$n) -or $n -lt 1 -or $n -gt $folders.Count) {
        Write-Bad 'Not a number on the list.'
        Wait-Close
        exit 1
    }
    $picked = $folders[$n - 1].FullName
}

$existing = @(@(Get-CursorWorkerRows) | Where-Object { Test-SamePath $_.Folder $picked })
if ($existing.Count) {
    $hit = $existing[0]
    Write-Ok "Already running for this folder: $($hit.DisplayName) pid $($hit.Pid)"
    Write-Host 'Pick a different folder to start another worker.'
    Wait-Close
    exit 0
}

$name = Get-WorkerDisplayName $picked
$data = Get-WorkerDataDir $picked
$used = @()
foreach ($r in @(Get-CursorWorkerRows)) {
    if ($r.Mgmt -match ':(\d+)\s*$') { $used += [int]$Matches[1] }
}
$port = Get-WorkerMgmtPort $used
if (-not $port) {
    Write-Bad "No free localhost port from $CwPortFirst to $CwPortLast."
    Wait-Close
    exit 1
}
$mgmt = "127.0.0.1:$port"
$workerArgs = @(Get-CursorWorkerArgList -Name $name -Folder $picked -DataDir $data -MgmtAddr $mgmt)
$info = Get-AgentStartInfo $cli $workerArgs
Write-Host ''
Write-Host "CLI: $($info.FilePath)"
Write-Host "Command: agent $($info.Command)"

if ($WhatIf) {
    Write-Host "WOULD|agent $($info.Command)"
    Wait-Close
    exit 0
}

try {
    if (-not (Test-Path -LiteralPath $data)) { New-Item -ItemType Directory -Force -Path $data | Out-Null }
    $outLog = Join-Path $data 'worker.out.log'
    $errLog = Join-Path $data 'worker.err.log'
    $startArgs = @{
        FilePath = $info.FilePath
        ArgumentList = $info.Arguments
        WorkingDirectory = $picked
        PassThru = $true
        RedirectStandardOutput = $outLog
        RedirectStandardError = $errLog
        ErrorAction = 'Stop'
    }
    # -WindowStyle is Windows PowerShell only. pwsh on Linux rejects it.
    if ($env:OS -eq 'Windows_NT') { $startArgs.WindowStyle = 'Hidden' }
    $proc = Start-Process @startArgs
    $waitSec = 5
    if ($env:WORKSTATION_START_WAIT_SEC -match '^\d+$') { $waitSec = [int]$env:WORKSTATION_START_WAIT_SEC }
    $launch = Get-CursorWorkerLaunchResult ([int]$proc.Id) @($outLog, $errLog) $waitSec
    if ($launch.Auth -or -not $launch.Alive) {
        $msg = "worker died at once (pid $($proc.Id))."
        if ($launch.Auth) { $msg = "worker died at once (pid $($proc.Id)). Authentication required. Run agent login." }
        Write-CwLog ("start FAILED: {0}" -f $msg)
        Write-Bad $msg
        Wait-Close
        exit 1
    }
    $rec = [ordered]@{
        pid = $proc.Id; name = $name; folder = $picked; dataDir = $data; mgmt = $mgmt
        startedAt = (Get-Date).ToString('o'); command = $info.Command
    }
    Set-Content -LiteralPath (Join-Path $data 'worker.json') ($rec | ConvertTo-Json) -Encoding ASCII
    Write-CwLog "started pid $($proc.Id) $name $picked"
    Write-Ok "Started $name (pid $($proc.Id))"
    Write-Host 'It keeps running in the background until you use Stop Cursor worker.'
    Write-Host 'In Cursor, pick this machine under My Machines.'
    if (-not (Test-FolderOrigin $picked)) {
        Write-Off 'This folder has no git origin. Cursor matches a machine to a repo by that remote, so it may not show up for a repo request.'
    }
} catch {
    Write-CwLog ("start FAILED: {0}" -f $_.Exception.Message)
    Write-Bad $_.Exception.Message
    Wait-Close
    exit 1
}
Wait-Close
exit 0
