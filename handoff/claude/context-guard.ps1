# context-guard.ps1 — Claude Code context-pressure handoff + compaction backup.
# Modes:
#   statusline : show context % + handoff point; save used/trigger tokens (hooks can't see context).
#   stop       : at >= $Threshold% of the compaction point (min $Headroom tokens left), block the stop ONCE so Claude runs state-closeout (closeout mode).
#   precompact : back up transcript + git snapshot, then re-arm the 80% trigger for the fresh context.
# Cursor also runs ~/.claude/settings.json hooks; it has its own handoff-at-80.py, so Cursor
# payloads (they carry conversation_id) are ignored here to avoid a double handoff.
# Delivery: the workstation-core plugin runs this script from hooks/hooks.json (Stop and PreCompact, with
# -FromPlugin). Install no longer copies it or wires it (decision D-2026-11-26-hooks-in-plugin). A plugin
# cannot set statusLine, so stop mode works without one: it uses the statusline file when a statusLine
# that runs this script exists, else the token usage of the last assistant turn in the transcript.
# With -FromPlugin the script does nothing when ~\.claude\settings.json still wires an older copy for the
# same event (that copy runs instead, so the handoff never fires twice).
param([string]$Mode = 'stop', [switch]$FromPlugin)

$Threshold = 80      # % of the compaction point
$Headroom  = 40000   # tokens always left for the handoff to run
# 'Continue' so git's stderr (e.g. "not a git repository") can't crash the backup.
$ErrorActionPreference = 'Continue'
$raw = [Console]::In.ReadToEnd()
$in = if ($raw) { $raw | ConvertFrom-Json } else { [pscustomobject]@{} }
if ($in.conversation_id) { exit 0 }
$sid = if ($in.session_id) { $in.session_id } else { 'unknown' }
$userSettings = $null
try { $userSettings = Get-Content (Join-Path $env:USERPROFILE '.claude\settings.json') -Raw -ErrorAction Stop | ConvertFrom-Json } catch {}
if ($FromPlugin -and $userSettings -and $userSettings.hooks) {
    $ev = if ($Mode -eq 'precompact') { 'PreCompact' } else { 'Stop' }
    foreach ($pp in $userSettings.hooks.PSObject.Properties) {
        if ($pp.Name -ieq $ev -and (($pp.Value | ConvertTo-Json -Depth 20 -Compress) -match 'context-guard\.ps1')) { exit 0 }
    }
}
# Compaction point for a window: CLAUDE_CODE_AUTO_COMPACT_WINDOW, else autoCompactWindow, else ~96.7% of the window.
function Get-CompactAt([double]$Window) {
    $acw = $env:CLAUDE_CODE_AUTO_COMPACT_WINDOW
    if (-not $acw -and $userSettings) { $acw = $userSettings.autoCompactWindow }
    if ($acw) { return [Math]::Min([double]$acw, $Window) }
    return $Window * 0.967
}
# 80% of the compaction point, but always leave >= $Headroom tokens for the handoff itself.
function Get-Trigger([double]$Window) {
    $compactAt = Get-CompactAt $Window
    return [Math]::Min($compactAt * $Threshold / 100, $compactAt - $Headroom)
}
# Context in use from the transcript: input + cache tokens of the newest assistant turn that reports usage.
# The window is not in the Stop payload: 200K, or 1M once usage passes 200K (CLAUDE_CODE_AUTO_COMPACT_WINDOW
# or autoCompactWindow sets the compaction point directly).
function Get-TranscriptUsage([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    $lines = @(Get-Content -LiteralPath $Path -Tail 400 -ErrorAction SilentlyContinue)
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -notmatch '"usage"') { continue }
        try { $o = $lines[$i] | ConvertFrom-Json } catch { continue }
        $u = $null; if ($o.message -and $o.message.usage) { $u = $o.message.usage } elseif ($o.usage) { $u = $o.usage }
        if (-not $u) { continue }
        $used = [double]$u.input_tokens + [double]$u.cache_creation_input_tokens + [double]$u.cache_read_input_tokens
        if ($used -le 0) { continue }
        $window = if ($used -gt 200000) { 1000000 } else { 200000 }
        return @{ Used = $used; Trigger = (Get-Trigger $window) }
    }
    return $null
}

$root  = Join-Path $env:USERPROFILE '.claude\compaction-backups'
$state = Join-Path $root '.state'
New-Item -ItemType Directory -Force -Path $state | Out-Null
$pctFile = Join-Path $state "$sid.pct"
$fired   = Join-Path $state "$sid.fired"

switch ($Mode) {
    'statusline' {
        # Trigger relative to where compaction actually happens, not the raw window, so the
        # handoff lands at the same point on any model / window size / autocompact setting.
        $window = [double]$in.context_window.context_window_size
        if (-not $window) { $window = 200000 }
        $used = [double]$in.context_window.used_percentage / 100 * $window
        # Default compaction point is ~96.7% of the window (967K on 1M models).
        $trigger = Get-Trigger $window
        $pct = [int]($used / $window * 100)
        $trigPct = [int]($trigger / $window * 100)
        Set-Content -Path $pctFile -Value "$([int]$used),$([int]$trigger)" -NoNewline
        Write-Output "[$($in.model.display_name)] $pct% context | handoff at $trigPct%"
        exit 0
    }
    'stop' {
        if ($in.stop_hook_active -or (Test-Path $fired)) { exit 0 }
        if (Test-Path $pctFile) { $used, $trigger = (Get-Content $pctFile -Raw) -split ',' }
        else {
            $tu = Get-TranscriptUsage ([string]$in.transcript_path)
            if (-not $tu) { exit 0 }
            $used = [int]$tu.Used; $trigger = [int]$tu.Trigger
        }
        if ([int]$used -lt [int]$trigger) { exit 0 }
        $pct = "$([int]([int]$used / 1000))K tokens"
        New-Item -ItemType File -Force -Path $fired | Out-Null
        @{
            decision = 'block'
            reason   = "CONTEXT PRESSURE: context is at $pct, near the compaction point. Invoke the state-closeout skill in closeout mode now: tag what this session did, graduate each item to its home, queue the rest in BACKLOG.md, and rewrite this branch's STATE file in the repo (STATE.md on trunk, STATE-<branch-slug>.md on a branch, committed on that branch; 30 lines max, one [NEXT] step). Commit finished repo work on the task branch first. Do not push to main. Do not start new project work."
        } | ConvertTo-Json -Compress
        exit 0
    }
}

# --- precompact: backup only, never blocks ---
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dir = Join-Path $root "$stamp-$($sid.Substring(0, [Math]::Min(8, $sid.Length)))-$($in.trigger)"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

if ($in.transcript_path -and (Test-Path $in.transcript_path)) {
    Copy-Item $in.transcript_path (Join-Path $dir 'transcript.jsonl')
}

$snap = @("cwd: $($in.cwd)", "trigger: $($in.trigger)", "time: $stamp", '')
if ($in.cwd -and (Test-Path $in.cwd)) {
    Push-Location $in.cwd
    try {
        $git = git rev-parse --is-inside-work-tree 2>$null
        if ($git -eq 'true') {
            $snap += '## git status'; $snap += (git status -sb 2>&1)
            $snap += ''; $snap += '## last 5 commits'; $snap += (git log --oneline -5 2>&1)
            $snap += ''; $snap += '## unpushed'; $snap += (git log --oneline '@{u}..' 2>&1)
        } else { $snap += 'not a git repo' }
    } finally { Pop-Location }
}
$snap | Set-Content -Encoding utf8 (Join-Path $dir 'snapshot.txt')

# Compaction frees context, so let the 80% handoff fire again later in this session.
Remove-Item $fired, $pctFile -Force -ErrorAction SilentlyContinue
exit 0
