#Requires -Version 5.1
# One-time setup on a new PC for Grok Bot auto-launch. Run in an ELEVATED Windows PowerShell
# (Run as administrator), signed in as the Windows user who uses Grok Bot. Safe to re-run.
#   1. Copies ensure-grokbot.ps1 (next to this script) to %USERPROFILE%\.grokbot\latch\
#   2. Registers/replaces task Latch-EnsureGrokBot: Mon-Fri at 8:30am + on session unlock, current user
#   3. Adds HKCU Run entry GrokBot -> Grok Bot.exe if it is missing (an existing value is left alone)
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File register-ensure-grokbot-task.ps1 [-At 8:30am] [-NoPause]
param([string]$At = '8:30am', [switch]$NoPause)
$ErrorActionPreference = 'Stop'

$TaskName = 'Latch-EnsureGrokBot'
$user     = "$env:USERDOMAIN\$env:USERNAME"
$src      = Join-Path $PSScriptRoot 'ensure-grokbot.ps1'
$dstDir   = Join-Path $env:USERPROFILE '.grokbot\latch'
$dst      = Join-Path $dstDir 'ensure-grokbot.ps1'
$psExe    = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$runKey   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

function Done([int]$code) {
    if (-not $NoPause) {
        Write-Host ''
        Write-Host 'Press any key to close...' -ForegroundColor DarkGray
        try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
    }
    exit $code
}

Write-Host ''
Write-Host "==== Register Grok Bot auto-launch ====  user $user" -ForegroundColor Cyan

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '  [FAIL] Not elevated. Right-click Windows PowerShell > Run as administrator, then run this again.' -ForegroundColor Red
    Done 1
}
Write-Host '  Note: task and Run entry go to the account running this window. If you elevated with a' -ForegroundColor DarkGray
Write-Host '        different admin account, stop and re-run from the Grok Bot user''s own elevated window.' -ForegroundColor DarkGray

try {
    # 1. Copy the launcher script
    if (-not (Test-Path -LiteralPath $src)) { throw "missing $src" }
    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "  [ OK ] copied ensure-grokbot.ps1 -> $dst" -ForegroundColor Green

    # 2. Scheduled task (Register -Force replaces an existing one, so re-runs are safe)
    $action = New-ScheduledTaskAction -Execute $psExe `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dst`""
    $weekly = New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 `
        -DaysOfWeek Monday, Tuesday, Wednesday, Thursday, Friday -At $At
    $stateClass = Get-CimClass -Namespace 'ROOT\Microsoft\Windows\TaskScheduler' -ClassName 'MSFT_TaskSessionStateChangeTrigger'
    $unlock = New-CimInstance -CimClass $stateClass -ClientOnly
    $unlock.StateChange = 8          # TASK_SESSION_UNLOCK
    $unlock.UserId      = $user
    $unlock.Enabled     = $true
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($weekly, $unlock) `
        -Settings $settings -Principal $principal -Force `
        -Description 'Launches the Grok Bot desktop app if it is not running (weekdays 8:30am or first unlock).' | Out-Null
    $t = Get-ScheduledTask -TaskName $TaskName
    Write-Host "  [ OK ] task $TaskName registered (state $($t.State); triggers: weekdays $At + session unlock)" -ForegroundColor Green

    # 3. HKCU Run entry GrokBot (only added when missing)
    $current = (Get-ItemProperty -Path $runKey -Name 'GrokBot' -ErrorAction SilentlyContinue).GrokBot
    if ($current) {
        Write-Host "  [ OK ] Run entry GrokBot already present: $current" -ForegroundColor Green
    } else {
        $exe = $null
        foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
            if (-not $root) { continue }
            $p = Join-Path $root 'Grok Bot\Grok Bot.exe'
            if (Test-Path -LiteralPath $p) { $exe = $p; break }
        }
        if ($exe) {
            Set-ItemProperty -Path $runKey -Name 'GrokBot' -Value "`"$exe`""
            Write-Host "  [ OK ] Run entry GrokBot added -> `"$exe`"" -ForegroundColor Green
        } else {
            Write-Host '  [WARN] Grok Bot.exe not found under Program Files or LocalAppData\Programs; Run entry not added. Install Grok Bot and re-run.' -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "  [FAIL] $($_.Exception.Message)" -ForegroundColor Red
    Done 1
}

Write-Host ''
Write-Host '==== done ====' -ForegroundColor Green
Done 0
