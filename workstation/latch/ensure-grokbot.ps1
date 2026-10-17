# Launch the Grok Bot desktop app if it is not running. Once per weekday (the first of 8:30am or
# unlock wins), skips weekends. Never kills or restarts a running copy.
$ErrorActionPreference = 'Continue'
$dir = Join-Path $env:USERPROFILE '.grokbot\latch'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$log    = Join-Path $dir 'ensure-grokbot.log'
$marker = Join-Path $dir 'ensure-grokbot.lastrun'
# Grok Bot.exe: machine-wide (Program Files / Program Files (x86)) or per-user (LocalAppData\Programs) install.
$exe = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs')) | Where-Object { $_ } | ForEach-Object { Join-Path $_ 'Grok Bot\Grok Bot.exe' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
function Write-Log([string]$msg) {
  Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffzzz'), $msg) -Encoding UTF8
  try { $l = @(Get-Content $log -Encoding UTF8); if ($l.Count -gt 200) { Set-Content $log ($l | Select-Object -Last 200) -Encoding UTF8 } } catch {}
}
$today = Get-Date
if ($today.DayOfWeek -in 'Saturday','Sunday') { exit 0 }
$stamp = $today.ToString('yyyy-MM-dd')
if ((Test-Path $marker) -and ((Get-Content $marker -Raw).Trim() -eq $stamp)) { exit 0 }
Set-Content -Path $marker -Value $stamp -Encoding ASCII
$running = Get-Process -Name 'Grok Bot' -ErrorAction SilentlyContinue
if ($running) { Write-Log ("already running (pids: {0})" -f (($running | ForEach-Object Id) -join ',')) }
elseif (-not $exe) { Write-Log 'launch FAILED: Grok Bot.exe not found' }
else { try { Start-Process -FilePath $exe -ErrorAction Stop; Write-Log 'launched' } catch { Write-Log ("launch FAILED: {0}" -f $_.Exception.Message) } }