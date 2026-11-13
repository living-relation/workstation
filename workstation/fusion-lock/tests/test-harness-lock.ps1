# harness.design lock plus a Fusion regression (same script, -Name defaults to fusion).
# Temp LOCALAPPDATA only. Fusion docs and harness windows are faked. The real locks are never touched.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File workstation/fusion-lock/tests/test-harness-lock.ps1
$ErrorActionPreference = 'Stop'
$script = Join-Path (Split-Path -Parent $PSScriptRoot) 'fusion-lock.ps1'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("hl-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$realLocal = $env:LOCALAPPDATA
$env:LOCALAPPDATA = $tmp
$env:WORKSTATION_FUSION_MCP_URL = 'http://127.0.0.1:9/mcp'
$fail = 0
function Run { param([Parameter(ValueFromRemainingArguments = $true)]$A) $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $script @A 2>&1; @{ code = $LASTEXITCODE; out = ($o -join "`n") } }
function Check([string]$What, $Got, $Want) { if ($Got -eq $Want) { "PASS $What" } else { "FAIL $What (got '$Got', want '$Want')"; $script:fail++ } }
$fusion = Join-Path $tmp 'Workstation\fusion.lock'
$harness = Join-Path $tmp 'Workstation\harness-design.lock'
function Age-Lock([string]$Path, [int]$Min) { $j = Get-Content $Path -Raw | ConvertFrom-Json; $j.last_checkin = (Get-Date).ToUniversalTime().AddMinutes(-$Min).ToString('o'); Set-Content $Path ($j | ConvertTo-Json) }
function Status-Keys($Text) { @($Text -split "`n" | ForEach-Object { if ($_ -match '^([^:]+):') { $matches[1] } }) -join ',' }
try {
    # Fusion regression: default name, output shape, files, exit codes. harness env must not affect it.
    $env:WORKSTATION_HARNESS_FAKE_WINDOWS = '["QjYZ"]'
    $free = Run status
    Check 'fusion status free' $free.code 0
    Check 'fusion free keys' (Status-Keys $free.out) 'state,lock'
    Check 'fusion free path' ($free.out -like '*fusion.lock*') $true
    Check 'fusion free path is not harness' ($free.out -like '*harness-design.lock*') $false
    Check 'fusion acquire A' (Run acquire -Holder A -Kind cursor -Files 'C:\x\Bracket.f3d').code 0
    Check 'fusion lock exists' (Test-Path $fusion) $true
    Check 'harness lock not created by fusion acquire' (Test-Path $harness) $false
    $held = Run status
    Check 'fusion status held' $held.code 1
    Check 'fusion held keys' (Status-Keys $held.out) 'state,holder,kind,started,last_checkin,minutes_since_checkin,files,pinger_pid,pinger_alive'
    Check 'harness still free while fusion held' (Run status -Name harness-design).code 0
    Check 'fusion check fresh held' (Run check).code 1
    Age-Lock $fusion 600
    $env:WORKSTATION_FUSION_FAKE_DOCS = 'unreachable'
    Check 'fusion stale unreachable' (Run check).code 3
    $env:WORKSTATION_FUSION_FAKE_DOCS = '[{"name":"Other v2","modified":false}]'
    Check 'fusion stale clean clears' (Run check).code 0
    Check 'fusion lock gone' (Test-Path $fusion) $false
    $flog = Get-Content (Join-Path $tmp 'Workstation\fusion-lock.log') -Raw
    Check 'fusion log CLEAR wording' ($flog -like '*CLEAR A*nothing unsaved*') $true

    # harness.design: acquire, status, check-in, release, two holders, stale clear and ask-the-owner.
    Remove-Item Env:WORKSTATION_FUSION_FAKE_DOCS -ErrorAction SilentlyContinue
    $env:WORKSTATION_HARNESS_FAKE_WINDOWS = 'none'
    $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $script acquire -Name harness-design -Holder A -Kind cursor -Files rBjB,QjYZ 2>&1
    Check 'harness acquire A' $LASTEXITCODE 0
    Check 'harness lock exists' (Test-Path $harness) $true
    Check 'fusion lock still absent' (Test-Path $fusion) $false
    $hj = Get-Content $harness -Raw | ConvertFrom-Json
    Check 'harness files count' @($hj.files).Count 2
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
    # A busy harness window must not stop Fusion from clearing, and Fusion docs must not stop a harness clear.
    Check 'fusion acquire for isolation' (Run acquire -Holder A -Kind remote).code 0
    Age-Lock $fusion 600
    $env:WORKSTATION_FUSION_FAKE_DOCS = '[{"name":"Other v2","modified":false}]'
    $env:WORKSTATION_HARNESS_FAKE_WINDOWS = '["QjYZ"]'
    Check 'fusion clear ignores harness windows' (Run check).code 0
    Check 'harness acquire for isolation' (Run acquire -Name harness-design -Holder A -Kind remote).code 0
    Age-Lock $harness 600
    $env:WORKSTATION_FUSION_FAKE_DOCS = '[{"name":"Bracket v3","modified":true}]'
    $env:WORKSTATION_HARNESS_FAKE_WINDOWS = 'none'
    Check 'harness clear ignores fusion docs' (Run check -Name harness-design).code 0
    $hlog = Get-Content (Join-Path $tmp 'Workstation\harness-design-lock.log') -Raw
    foreach ($w in 'ACQUIRE A', 'STALE-FLAG A', 'CLEAR A', 'RELEASE B') { Check "harness log has $w" ($hlog -like "*$w*") $true }
    Check 'fusion log has no harness file name' ($flog -notlike '*harness-design*') $true
} finally {
    $env:LOCALAPPDATA = $realLocal
    Remove-Item Env:WORKSTATION_FUSION_FAKE_DOCS, Env:WORKSTATION_FUSION_MCP_URL, Env:WORKSTATION_HARNESS_FAKE_WINDOWS -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
if ($fail) { "FAILED: $fail"; exit 1 } else { 'ALL PASS'; exit 0 }
