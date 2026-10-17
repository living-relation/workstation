# Fixes the Cursor agent CLI bug on Windows where better-sqlite3 was built for a
# different Node version than the one the CLI ships ("NODE_MODULE_VERSION 127 vs 137").
# Safe to run any time: it does nothing if the module already loads.
. "$PSScriptRoot\config.ps1"

$ver = Get-LatestAgentVersionDir
if (-not $ver) { Write-Log 'repair: no agent version dir found'; exit 1 }

$node    = Join-Path $ver.FullName 'node.exe'
$pkgDir  = Join-Path $ver.FullName 'node_modules\better-sqlite3'
$target  = Join-Path $pkgDir 'build\Release\better_sqlite3.node'
$testJs  = "const D=require(process.argv[1]); const db=new D(':memory:'); db.close();"

function Test-Sqlite {
    & $node -e $testJs $pkgDir *> $null
    return ($LASTEXITCODE -eq 0)
}

if (Test-Sqlite) { exit 0 }

Write-Log "repair: better-sqlite3 fails to load in $($ver.Name); fetching prebuilt binary"
$sqliteVer = (Get-Content (Join-Path $pkgDir 'package.json') -Raw | ConvertFrom-Json).version
$abi       = (& $node -p 'process.versions.modules').Trim()
$cache     = Join-Path $CacheDir "$sqliteVer-abi$abi"
$cached    = Join-Path $cache 'node_modules\better-sqlite3\build\Release\better_sqlite3.node'

if (-not (Test-Path $cached)) {
    New-Item -ItemType Directory -Force -Path $cache | Out-Null
    Push-Location $cache
    try {
        if (-not (Test-Path 'package.json')) { npm init -y *> $null }
        npm install "better-sqlite3@$sqliteVer" --ignore-scripts --no-audit --no-fund *> $null
        Push-Location (Join-Path $cache 'node_modules\better-sqlite3')
        try {
            # Use the agent's own node so the binary matches its ABI.
            & $node (Join-Path $cache 'node_modules\prebuild-install\bin.js') *> $null
        } finally { Pop-Location }
    } finally { Pop-Location }
}

if (-not (Test-Path $cached)) {
    Write-Log "repair: could not obtain a prebuilt binary for better-sqlite3 $sqliteVer ABI $abi"
    exit 2
}

if ((Test-Path $target) -and -not (Test-Path "$target.orig")) {
    Copy-Item $target "$target.orig"
}
Copy-Item $cached $target -Force

if (Test-Sqlite) {
    Write-Log "repair: fixed better-sqlite3 $sqliteVer (ABI $abi) in $($ver.Name)"
    exit 0
}
Write-Log 'repair: replaced binary but module still fails to load'
exit 3
