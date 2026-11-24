# Fusion Desktop lock (-Name fusion-desktop). Temp LOCALAPPDATA only. Fusion is faked. The real lock is never touched.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File workstation/app-lock/tests/test-fusion-desktop-lock.ps1
$ErrorActionPreference = 'Stop'
$script = Join-Path (Split-Path -Parent $PSScriptRoot) 'app-lock.ps1'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("fdl-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$realLocal = $env:LOCALAPPDATA
$env:LOCALAPPDATA = $tmp
$fail = 0
$pwsh = @(Get-Command powershell, pwsh -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $pwsh) { 'FAIL powershell not found'; exit 1 }
function Run { param([Parameter(ValueFromRemainingArguments = $true)]$A) $o = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $script @A 2>&1; @{ code = $LASTEXITCODE; out = ($o -join "`n") } }
function Check([string]$What, $Got, $Want) { if ($Got -eq $Want) { "PASS $What" } else { "FAIL $What (got '$Got', want '$Want')"; $script:fail++ } }
$fusion = Join-Path $tmp 'Workstation\fusion-desktop.lock'
$harness = Join-Path $tmp 'Workstation\harness-design.lock'
$oldFusion = Join-Path $tmp 'Workstation\fusion.lock'
function Age-Lock([string]$Path, [int]$Min) { $j = Get-Content $Path -Raw | ConvertFrom-Json; $j.last_checkin = (Get-Date).ToUniversalTime().AddMinutes(-$Min).ToString('o'); Set-Content $Path ($j | ConvertTo-Json) }
try {
    $free = Run status -Name fusion-desktop
    Check 'fusion-desktop status free exits 0' $free.code 0
    Check 'status names fusion-desktop.lock' ($free.out -like '*fusion-desktop.lock*') $true
    Check 'status does not create the lock file' (Test-Path $fusion) $false
    Check 'old fusion name is still refused' ((Run status -Name fusion).code -ne 0) $true

    # Acquire, two holders, check-in, release.
    Check 'acquire A' (Run acquire -Name fusion-desktop -Holder A -Kind cursor -Repo 'C:\work\widget' -Files 'Bracket v3').code 0
    Check 'own lock file' (Test-Path $fusion) $true
    Check 'no old fusion.lock' (Test-Path $oldFusion) $false
    Check 'no harness lock' (Test-Path $harness) $false
    Check 'repo recorded' ([string](Get-Content $fusion -Raw | ConvertFrom-Json).repo) 'C:\work\widget'
    Check 'status held' (Run status -Name fusion-desktop).code 1
    Check 'acquire B refused' (Run acquire -Name fusion-desktop -Holder B -Kind remote).code 2
    Check 'checkin B refused' (Run checkin -Name fusion-desktop -Holder B).code 2
    Check 'checkin A' (Run checkin -Name fusion-desktop -Holder A).code 0
    Check 'check fresh = held' (Run check -Name fusion-desktop).code 1

    # Separate from the harness.design lock both ways.
    Check 'harness still free while fusion is held' (Run status -Name harness-design).code 0
    Check 'B takes harness while A holds fusion' (Run acquire -Name harness-design -Holder B -Kind remote).code 0
    Check 'fusion still held by A' ([string](Get-Content $fusion -Raw | ConvertFrom-Json).holder) 'A'
    Check 'release harness B' (Run release -Name harness-design -Holder B).code 0
    Check 'fusion lock kept after harness release' (Test-Path $fusion) $true

    # Stale: never cleared on time alone; cleared only when Fusion is not running.
    Age-Lock $fusion 600
    $env:WORKSTATION_FUSION_FAKE_RUNNING = 'yes'
    $busy = Run check -Name fusion-desktop
    Check 'stale + Fusion running = needs owner' $busy.code 3
    Check 'stale says ask the owner' ($busy.out -like '*ask the owner*') $true
    Check 'lock kept' (Test-Path $fusion) $true
    $env:WORKSTATION_FUSION_FAKE_RUNNING = 'unknown'
    Check 'stale + unknown = needs owner' (Run check -Name fusion-desktop).code 3
    $env:WORKSTATION_FUSION_FAKE_RUNNING = 'no'
    Check 'stale + Fusion closed = cleared' (Run check -Name fusion-desktop).code 0
    Check 'lock gone after clear' (Test-Path $fusion) $false

    Check 'acquire B' (Run acquire -Name fusion-desktop -Holder B -Kind remote).code 0
    Check 'release A refused' (Run release -Name fusion-desktop -Holder A).code 2
    Check 'release B' (Run release -Name fusion-desktop -Holder B).code 0
    Check 'lock released' (Test-Path $fusion) $false
    $log = Get-Content (Join-Path $tmp 'Workstation\fusion-desktop-lock.log') -Raw
    foreach ($w in 'ACQUIRE A', 'STALE-FLAG A', 'CLEAR A', 'RELEASE B') { Check "fusion log has $w" ($log -like "*$w*") $true }
    $hlog = Get-Content (Join-Path $tmp 'Workstation\harness-design-lock.log') -Raw
    Check 'harness log has no fusion holder A' ($hlog -like '*ACQUIRE A*') $false
} catch {
    "FAIL exception: $($_.Exception.Message)"
    $fail++
} finally {
    $env:LOCALAPPDATA = $realLocal
    Remove-Item Env:WORKSTATION_FUSION_FAKE_RUNNING -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
if ($fail) { "FAILED: $fail"; exit 1 } else { 'ALL PASS'; exit 0 }
