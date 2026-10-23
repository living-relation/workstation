#Requires -Version 5.1
# Generic toggle "stop" for a local dev server: finds what listens on each -Port, walks up to the
# highest node/cmd/pnpm/npm ancestor (the console window that runs it) and stops that tree.
# Never stops explorer, terminals, PowerShell, Cursor, Claude or anything else outside that chain.
param([Parameter(Mandatory)][int[]]$Port)
$ErrorActionPreference = 'Continue'
$chain = @('node.exe', 'cmd.exe', 'pnpm.exe', 'npm.exe', 'conhost.exe', 'esbuild.exe')
$procs = @{}
Get-CimInstance Win32_Process | ForEach-Object { $procs[[int]$_.ProcessId] = $_ }
$roots = @{}
foreach ($p in $Port) {
    foreach ($c in @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue)) {
        $cur = $procs[[int]$c.OwningProcess]
        if (-not $cur) { continue }
        while ($true) {
            $parent = $procs[[int]$cur.ParentProcessId]
            if (-not $parent -or $chain -notcontains $parent.Name.ToLower() -or $parent.CreationDate -gt $cur.CreationDate) { break }
            $cur = $parent
        }
        $roots[[int]$cur.ProcessId] = "$($cur.Name) (port $p)"
    }
}
if (-not $roots.Count) { Write-Output "nothing listens on port(s) $($Port -join ', ')"; exit 0 }
foreach ($id in $roots.Keys) {
    $null = & taskkill.exe /T /F /PID $id 2>&1
    Write-Output "stopped pid $id $($roots[$id])"
}
Start-Sleep -Seconds 1
$left = @($Port | Where-Object { Get-NetTCPConnection -State Listen -LocalPort $_ -ErrorAction SilentlyContinue })
if ($left) { Write-Output "still listening: $($left -join ', ')"; exit 1 }
exit 0
