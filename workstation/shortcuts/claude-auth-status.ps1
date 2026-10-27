# Parse helpers for `claude auth status`. Windows PowerShell 5.1 compatible. ASCII-only.
# Dot-sourced by workstation-common.ps1. Docs: https://code.claude.com/docs/en/cli-reference
# `claude auth status` prints JSON (pretty or compact) with loggedIn, authMethod, and (v2.1.268+)
# configDirectory. Use --text for human-readable output. Exit 0 if logged in, 1 if not.

# Join mixed CLI/job output into one string. ConvertFrom-Json on Windows PowerShell 5.1 rejects a
# line array, and Out-String wraps at host width (which can split JSON strings).
function Get-JoinedText($Value) {
    if ($null -eq $Value) { return '' }
    return ((@($Value) | ForEach-Object { "$_" }) -join "`n")
}

# Slice the JSON object out of mixed stdout/stderr: first '{' through last '}'.
function Get-JsonObjectText([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return $null }
    $start = $Text.IndexOf('{')
    $end = $Text.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) { return $null }
    return $Text.Substring($start, $end - $start + 1)
}

# Parse `claude auth status` text. Timeout is handled by the caller ($null from Invoke-WithTimeout).
# Returns @{ Kind = 'logged-in'|'logged-out'|'unparseable'; Hint = '...' }
function Read-ClaudeAuthStatus($Raw) {
    $r = @{ Kind = 'unparseable'; Hint = 'expected JSON with loggedIn' }
    $text = Get-JoinedText $Raw
    if ([string]::IsNullOrWhiteSpace($text)) { $r.Hint = 'empty output'; return $r }
    $json = Get-JsonObjectText $text
    if (-not $json) { $r.Hint = 'no JSON object in output'; return $r }
    $obj = $null
    try { $obj = ConvertFrom-Json $json } catch { $r.Hint = 'JSON did not parse'; return $r }
    if ($null -eq $obj) { $r.Hint = 'JSON did not parse'; return $r }
    $prop = $obj.PSObject.Properties['loggedIn']
    if ($null -eq $prop) { $r.Hint = 'JSON missing loggedIn'; return $r }
    if (-not ($prop.Value -is [bool])) { $r.Hint = 'loggedIn was not a boolean'; return $r }
    if ($prop.Value) { $r.Kind = 'logged-in'; $r.Hint = '' } else { $r.Kind = 'logged-out'; $r.Hint = '' }
    return $r
}
