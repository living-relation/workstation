# End-to-end tests for fusion-lock.ps1 in a temp LOCALAPPDATA (the real lock is never touched; Fusion is faked).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File workstation/fusion-lock/tests/test-fusion-lock.ps1
$ErrorActionPreference = 'Stop'
$script = Join-Path (Split-Path -Parent $PSScriptRoot) 'fusion-lock.ps1'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("fl-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$realLocal = $env:LOCALAPPDATA
$env:LOCALAPPDATA = $tmp
$env:WORKSTATION_FUSION_MCP_URL = 'http://127.0.0.1:9/mcp'   # dead port: never the real add-in
$fail = 0
function Run { param([Parameter(ValueFromRemainingArguments = $true)]$A) $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $script @A 2>&1; @{ code = $LASTEXITCODE; out = ($o -join "`n") } }
function Check([string]$What, $Got, $Want) { if ($Got -eq $Want) { "PASS $What" } else { "FAIL $What (got '$Got', want '$Want')"; $script:fail++ } }
$lock = Join-Path $tmp 'Workstation\fusion.lock'
function Age-Lock([int]$Min) { $j = Get-Content $lock -Raw | ConvertFrom-Json; $j.last_checkin = (Get-Date).ToUniversalTime().AddMinutes(-$Min).ToString('o'); Set-Content $lock ($j | ConvertTo-Json) }
try {
    Check 'status free' (Run status).code 0
    Check 'acquire A' (Run acquire -Holder A -Kind cursor -Files 'C:\x\Bracket.f3d').code 0
    Check 'lock file in temp' (Test-Path $lock) $true
    Check 'status held' (Run status).code 1
    Check 'acquire B refused' (Run acquire -Holder B -Kind remote).code 2
    Check 'checkin B refused' (Run checkin -Holder B).code 2
    Check 'checkin A' (Run checkin -Holder A).code 0
    Check 'check fresh = held' (Run check).code 1
    Age-Lock 600
    $env:WORKSTATION_FUSION_FAKE_DOCS = 'unreachable'
    Check 'stale + add-in unreachable = needs owner' (Run check).code 3
    $env:WORKSTATION_FUSION_FAKE_DOCS = '[{"name":"Other v2","modified":true}]'
    Check 'stale + unsaved doc = needs owner' (Run check).code 3
    $env:WORKSTATION_FUSION_FAKE_DOCS = '[{"name":"Bracket v3","modified":false}]'
    Check 'stale + holder file open = needs owner' (Run check).code 3
    Check 'lock still there' (Test-Path $lock) $true
    $env:WORKSTATION_FUSION_FAKE_DOCS = '[{"name":"Other v2","modified":false}]'
    Check 'stale + clean = cleared' (Run check).code 0
    Check 'lock gone' (Test-Path $lock) $false
    Check 'acquire B' (Run acquire -Holder B -Kind remote).code 0
    Check 'release A refused' (Run release -Holder A).code 2
    Check 'release B' (Run release -Holder B).code 0
    $env:WORKSTATION_FUSION_FAKE_DOCS = 'none'
    # pinger: tie it to a short-lived parent; it must check in, then exit when the parent dies
    $parent = Start-Process powershell -ArgumentList '-NoProfile -Command Start-Sleep 6' -WindowStyle Hidden -PassThru
    Check 'acquire C with pinger' (Run acquire -Holder C -Kind claude-code -StartPinger -ParentPid $parent.Id -IntervalSec 2).code 0
    $pp = [int](Get-Content $lock -Raw | ConvertFrom-Json).pinger_pid
    Check 'pinger running' ([bool](Get-Process -Id $pp -ErrorAction SilentlyContinue)) $true
    Age-Lock 600; Start-Sleep 4
    Check 'pinger renewed check-in' ((Run check).code) 1
    Start-Sleep 7
    Check 'pinger exited with parent' ([bool](Get-Process -Id $pp -ErrorAction SilentlyContinue)) $false
    Check 'release C' (Run release -Holder C).code 0
    $log = Get-Content (Join-Path $tmp 'Workstation\fusion-lock.log') -Raw
    foreach ($w in 'ACQUIRE A', 'STALE-FLAG A', 'CLEAR A', 'RELEASE B', 'PINGER C', 'PINGER-EXIT C', 'RELEASE C') { Check "log has $w" ($log -like "*$w*") $true }
} finally {
    $env:LOCALAPPDATA = $realLocal; Remove-Item Env:WORKSTATION_FUSION_FAKE_DOCS, Env:WORKSTATION_FUSION_MCP_URL -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
if ($fail) { "FAILED: $fail"; exit 1 } else { 'ALL PASS'; exit 0 }
