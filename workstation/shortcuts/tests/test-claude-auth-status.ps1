# Tests for claude-auth-status.ps1. Does not call the live `claude` CLI.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File workstation/shortcuts/tests/test-claude-auth-status.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\claude-auth-status.ps1')

$fail = 0
function Check([string]$What, $Got, $Want) {
    if ($Got -eq $Want) { "PASS $What" }
    else { "FAIL $What (got '$Got', want '$Want')"; $script:fail++ }
}

# Compact JSON (docs: loggedIn + authMethod).
$st = Read-ClaudeAuthStatus '{"loggedIn":true,"authMethod":"claude.ai"}'
Check 'compact logged-in' $st.Kind 'logged-in'

# Pretty-printed JSON as a line array (Windows PowerShell 5.1 ConvertFrom-Json fails on this unless joined).
$pretty = @(
    '{',
    '  "loggedIn": true,',
    '  "authMethod": "claude.ai",',
    '  "configDirectory": "C:\\claude-config"',
    '}'
)
$st = Read-ClaudeAuthStatus $pretty
Check 'pretty line-array logged-in' $st.Kind 'logged-in'

# Extra stderr/info around the object.
$st = Read-ClaudeAuthStatus "refreshing token...`n{`n  `"loggedIn`": true,`n  `"authMethod`": `"oauth_token`"`n}`nnotice: ok"
Check 'mixed stderr logged-in' $st.Kind 'logged-in'

$st = Read-ClaudeAuthStatus '{"loggedIn":false,"authMethod":"none"}'
Check 'logged-out' $st.Kind 'logged-out'

$st = Read-ClaudeAuthStatus ''
Check 'empty' $st.Kind 'unparseable'
Check 'empty hint' $st.Hint 'empty output'

$st = Read-ClaudeAuthStatus 'not json'
Check 'no object' $st.Kind 'unparseable'
Check 'no object hint' $st.Hint 'no JSON object in output'

$st = Read-ClaudeAuthStatus '{"authMethod":"claude.ai"}'
Check 'missing loggedIn' $st.Kind 'unparseable'
Check 'missing loggedIn hint' $st.Hint 'JSON missing loggedIn'

$st = Read-ClaudeAuthStatus '{"loggedIn":"yes"}'
Check 'loggedIn not bool' $st.Kind 'unparseable'

$st = Read-ClaudeAuthStatus '{not json}'
Check 'broken json' $st.Kind 'unparseable'
Check 'broken json hint' $st.Hint 'JSON did not parse'

# Join lines with newline.
Check 'join array' (Get-JoinedText @('{', '}')) "{`n}"
Check 'join null is empty not timeout' (Get-JoinedText $null) ''

if ($fail -gt 0) { Write-Error "$fail test(s) failed"; exit 1 }
'OK'
exit 0
