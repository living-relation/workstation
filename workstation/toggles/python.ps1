#Requires -Version 5.1
# Finds Python 3.13 the same way start-dashboard.ps1 does. Dot-source, then call Find-Python313.
function Find-Python313([switch]$Windowless) {
    $exe = $null
    $cmd = Get-Command python3.13 -ErrorAction SilentlyContinue
    if ($cmd) { $exe = $cmd.Source }
    if (-not $exe) {
        $root = Join-Path $env:APPDATA 'uv\python'
        if (Test-Path -LiteralPath $root) {
            $hit = Get-ChildItem -LiteralPath $root -Directory -Filter 'cpython-3.13.*-windows-x86_64-none' -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending | Select-Object -First 1
            if ($hit -and (Test-Path -LiteralPath (Join-Path $hit.FullName 'python.exe'))) { $exe = Join-Path $hit.FullName 'python.exe' }
        }
    }
    if ($exe -and $Windowless) {
        try { $real = (& $exe -c 'import sys; print(sys.executable)' 2>$null | Select-Object -First 1) } catch { $real = $null }
        if ($real -and (Test-Path -LiteralPath $real.Trim())) { $exe = $real.Trim() }
        $w = Join-Path (Split-Path -Parent $exe) 'pythonw.exe'
        if (Test-Path -LiteralPath $w) { return $w }
    }
    return $exe
}
