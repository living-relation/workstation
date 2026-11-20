# harness.design lock. Temp LOCALAPPDATA only. Harness windows are faked. The real lock is never touched.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File workstation/fusion-lock/tests/test-harness-lock.ps1
$ErrorActionPreference = 'Stop'
$script = Join-Path (Split-Path -Parent $PSScriptRoot) 'fusion-lock.ps1'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("hl-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$realLocal = $env:LOCALAPPDATA
$env:LOCALAPPDATA = $tmp
$fail = 0
$pwsh = @(Get-Command powershell, pwsh -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $pwsh) { 'FAIL powershell not found'; exit 1 }
function Run { param([Parameter(ValueFromRemainingArguments = $true)]$A) $o = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $script @A 2>&1; @{ code = $LASTEXITCODE; out = ($o -join "`n") } }
function Check([string]$What, $Got, $Want) { if ($Got -eq $Want) { "PASS $What" } else { "FAIL $What (got '$Got', want '$Want')"; $script:fail++ } }
$harness = Join-Path $tmp 'Workstation\harness-design.lock'
function Age-Lock([string]$Path, [int]$Min) { $j = Get-Content $Path -Raw | ConvertFrom-Json; $j.last_checkin = (Get-Date).ToUniversalTime().AddMinutes(-$Min).ToString('o'); Set-Content $Path ($j | ConvertTo-Json) }
try {
    # Default -Name fusion does not take a lock and does not create the harness lock.
    $plain = Run status
    Check 'default name exits 0' $plain.code 0
    Check 'default name does not create harness lock' (Test-Path $harness) $false

    # harness.design: acquire, status, check-in, release, two holders, stale clear and ask-the-owner.
    $env:WORKSTATION_HARNESS_FAKE_WINDOWS = 'none'
    $null = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $script acquire -Name harness-design -Holder A -Kind cursor -Repo 'C:\work\harness' -Files rBjB,QjYZ 2>&1
    Check 'harness acquire A' $LASTEXITCODE 0
    Check 'harness lock exists' (Test-Path $harness) $true
    $hj = Get-Content $harness -Raw | ConvertFrom-Json
    Check 'harness files count' @($hj.files).Count 2
    Check 'harness repo recorded' ([string]$hj.repo) 'C:\work\harness'
    Check 'other repo does not steal harness' (Run acquire -Name harness-design -Holder B -Kind remote -Repo 'C:\work\other').code 2
    $hs = Run status -Name harness-design
    Check 'harness status held' $hs.code 1
    Check 'harness status shows id' ($hs.out -like '*rBjB*') $true
    Check 'harness acquire B refused' (Run acquire -Name harness-design -Holder B -Kind remote).code 2
    Check 'harness checkin B refused' (Run checkin -Name harness-design -Holder B).code 2
    Check 'harness checkin A' (Run checkin -Name harness-design -Holder A -Files 'QjYZ').code 0
    Check 'harness check fresh held' (Run check -Name harness-design).code 1
    Age-Lock $harness 600
    $env:WORKSTATION_HARNESS_FAKE_WINDOWS = 'none'
    Check 'stale + app not running = cleared' (Run check -Name harness-design).code 0
    Check 'harness lock gone' (Test-Path $harness) $false
    Check 'harness acquire again' (Run acquire -Name harness-design -Holder A -Kind cursor -Files rBjB).code 0
    Age-Lock $harness 600
    $env:WORKSTATION_HARNESS_FAKE_WINDOWS = '["harness.design"]'
    Check 'stale + app-name window = cleared' (Run check -Name harness-design).code 0
    Check 'harness acquire for editor' (Run acquire -Name harness-design -Holder A -Kind remote -Files rBjB).code 0
    Age-Lock $harness 600
    $env:WORKSTATION_HARNESS_FAKE_WINDOWS = '["QjYZ"]'
    $busy = Run check -Name harness-design
    Check 'stale + document title = needs owner' $busy.code 3
    Check 'stale says ask the owner' ($busy.out -like '*ask the owner*') $true
    Check 'harness lock kept' (Test-Path $harness) $true
    $env:WORKSTATION_HARNESS_FAKE_WINDOWS = 'unknown'
    Check 'stale + unknown windows = needs owner' (Run check -Name harness-design).code 3
    $env:WORKSTATION_HARNESS_FAKE_WINDOWS = '["Harness.Design"]'
    Check 'stale + app name any case = cleared' (Run check -Name harness-design).code 0
    Check 'harness acquire B' (Run acquire -Name harness-design -Holder B -Kind claude-code).code 0
    Check 'harness release A refused' (Run release -Name harness-design -Holder A).code 2
    Check 'harness release B' (Run release -Name harness-design -Holder B).code 0
    Check 'harness lock released' (Test-Path $harness) $false
    Check 'default acquire does not create harness lock' (Run acquire -Holder A -Kind remote).code 0
    Check 'harness lock still absent' (Test-Path $harness) $false
    $hlog = Get-Content (Join-Path $tmp 'Workstation\harness-design-lock.log') -Raw
    foreach ($w in 'ACQUIRE A', 'STALE-FLAG A', 'CLEAR A', 'RELEASE B') { Check "harness log has $w" ($hlog -like "*$w*") $true }
} finally {
    $env:LOCALAPPDATA = $realLocal
    Remove-Item Env:WORKSTATION_HARNESS_FAKE_WINDOWS -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
if ($fail) { "FAILED: $fail"; exit 1 } else { 'ALL PASS'; exit 0 }
