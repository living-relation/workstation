# context-guard.ps1 — Claude Code context-pressure handoff + compaction backup.
# Modes:
#   statusline : show context % + handoff point; save used/trigger tokens (hooks can't see context).
#   stop       : at >= $Threshold% of the compaction point (min $Headroom tokens left), block the stop ONCE so Claude runs agent-handoff-pack (quick mode).
#   precompact : back up transcript + git snapshot, then re-arm the 80% trigger for the fresh context.
# Cursor also runs ~/.claude/settings.json hooks; it has its own handoff-at-80.py, so Cursor
# payloads (they carry conversation_id) are ignored here to avoid a double handoff.
param([string]$Mode = 'stop')

$Threshold = 80      # % of the compaction point
$Headroom  = 40000   # tokens always left for the handoff to run
# 'Continue' so git's stderr (e.g. "not a git repository") can't crash the backup.
$ErrorActionPreference = 'Continue'
$raw = [Console]::In.ReadToEnd()
$in = if ($raw) { $raw | ConvertFrom-Json } else { [pscustomobject]@{} }
if ($in.conversation_id) { exit 0 }
$sid = if ($in.session_id) { $in.session_id } else { 'unknown' }

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
        $acw = $env:CLAUDE_CODE_AUTO_COMPACT_WINDOW
        if (-not $acw) {
            try { $acw = (Get-Content "$env:USERPROFILE\.claude\settings.json" -Raw | ConvertFrom-Json).autoCompactWindow } catch {}
        }
        # Default compaction point is ~96.7% of the window (967K on 1M models).
        $compactAt = if ($acw) { [Math]::Min([double]$acw, $window) } else { $window * 0.967 }
        # 80% of the compaction point, but always leave >= $Headroom tokens for the handoff itself.
        $trigger = [Math]::Min($compactAt * $Threshold / 100, $compactAt - $Headroom)
        $pct = [int]($used / $window * 100)
        $trigPct = [int]($trigger / $window * 100)
        Set-Content -Path $pctFile -Value "$([int]$used),$([int]$trigger)" -NoNewline
        Write-Output "[$($in.model.display_name)] $pct% context | handoff at $trigPct%"
        exit 0
    }
    'stop' {
        if ($in.stop_hook_active -or (Test-Path $fired) -or -not (Test-Path $pctFile)) { exit 0 }
        $used, $trigger = (Get-Content $pctFile -Raw) -split ','
        if ([int]$used -lt [int]$trigger) { exit 0 }
        $pct = "$([int]([int]$used / 1000))K tokens"
        New-Item -ItemType File -Force -Path $fired | Out-Null
        @{
            decision = 'block'
            reason   = "CONTEXT PRESSURE: context is at $pct, near the compaction point. Invoke the agent-handoff-pack skill in quick mode now (context-pressure fast path): update living docs and emit the next-chat paste block (do not commit or push). Do not start new project work."
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
