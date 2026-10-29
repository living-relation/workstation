# Tests for claude/claude-setup.ps1. Fake profile only; never touches the real ~/.claude.json.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File claude/tests/test-claude-setup.ps1
$ErrorActionPreference = 'Stop'
$helper = Join-Path $PSScriptRoot '..\claude-setup.ps1'
$fail = 0
function Check([string]$What, $Ok) {
  if ($Ok) { "PASS $What" } else { "FAIL $What"; $script:fail++ }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("ccsetup-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$env:FIRECRAWL_API_KEY = 'fc-test-key-not-real'
$env:GITHUB_PERSONAL_ACCESS_TOKEN = 'ghp_test_token_not_real'

function Invoke-Setup([switch]$WhatIf) {
  $setupArgs = @{
    UserHome = $root
    ProjectsRoot = (Join-Path $root 'Projects')
    SkipPlugins = $true
    Quiet = $true
  }
  if ($WhatIf) { $setupArgs.WhatIf = $true }
  return @(& $helper @setupArgs)
}

# 1. WhatIf on an empty profile: would add servers that have keys, skip none of kapture/etc.
$r1 = Invoke-Setup -WhatIf
$would = @($r1 | Where-Object Status -eq 'WOULD')
$names = @($would | ForEach-Object { if ($_.Item -match 'MCP (\S+)') { $Matches[1] } })
Check 'whatif does not create claude.json' (-not (Test-Path -LiteralPath (Join-Path $root '.claude.json')))
Check 'whatif would add kapture' ($names -contains 'kapture')
Check 'whatif would add github' ($names -contains 'github')
Check 'whatif would add firecrawl' ($names -contains 'firecrawl')
Check 'whatif would add windows-mcp' ($names -contains 'windows-mcp')
Check 'whatif would add context7' ($names -contains 'context7')
Check 'whatif would add fetch' ($names -contains 'fetch')
Check 'whatif would add githits' ($names -contains 'githits')
Check 'whatif would add autodesk-fusion-mcp' ($names -contains 'autodesk-fusion-mcp')

# 2. Real merge into empty file.
$r2 = Invoke-Setup
$jsonPath = Join-Path $root '.claude.json'
Check 'created claude.json' (Test-Path -LiteralPath $jsonPath)
$doc = [IO.File]::ReadAllText($jsonPath) | ConvertFrom-Json
Check 'user kapture' ([bool]$doc.mcpServers.kapture)
Check 'user github' ([bool]$doc.mcpServers.github)
Check 'user fetch' ([bool]$doc.mcpServers.fetch)
Check 'user windows-mcp' ([bool]$doc.mcpServers.'windows-mcp')
Check 'user context7' ([bool]$doc.mcpServers.context7)
Check 'user githits' ([bool]$doc.mcpServers.githits)
Check 'user autodesk-fusion-mcp' ([bool]$doc.mcpServers.'autodesk-fusion-mcp')
Check 'github is http' ($doc.mcpServers.github.type -eq 'http')
Check 'github url' ($doc.mcpServers.github.url -match 'githubcopilot')
Check 'firecrawl not user-scope' (-not $doc.mcpServers.PSObject.Properties['firecrawl'])
$fc = $null
if ($doc.projects -and $doc.projects.PSObject.Properties['C:/projects']) {
  $fc = $doc.projects.'C:/projects'.mcpServers.firecrawl
}
Check 'firecrawl local to C:/projects' ([bool]$fc)
Check 'firecrawl has env key name' ([bool]($fc.env.PSObject.Properties['FIRECRAWL_API_KEY']))
Check 'unrelated keys not required' (-not $doc.PSObject.Properties['theme'])
Check 'done count' (@($r2 | Where-Object Status -eq 'DONE').Count -ge 8)

# 3. Idempotent: second run leaves a hand-made extra server and does not duplicate.
$doc.mcpServers | Add-Member -NotePropertyName 'handmade' -NotePropertyValue ([pscustomobject]@{ type = 'stdio'; command = 'echo'; args = @('keep-me') })
$nl = if ([IO.File]::ReadAllText($jsonPath).Contains("`r`n")) { "`r`n" } else { "`n" }
[IO.File]::WriteAllText($jsonPath, (($doc | ConvertTo-Json -Depth 20)))
$r3 = Invoke-Setup
$doc2 = [IO.File]::ReadAllText($jsonPath) | ConvertFrom-Json
Check 'second run all OK' (@($r3 | Where-Object Status -eq 'OK').Count -ge 8)
Check 'handmade server kept' ([bool]$doc2.mcpServers.handmade)
Check 'kapture still one entry' ([bool]$doc2.mcpServers.kapture)

# 4. Missing github key skips github only.
$root2 = Join-Path ([IO.Path]::GetTempPath()) ("ccsetup2-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $root2 -Force | Out-Null
$env:GITHUB_PERSONAL_ACCESS_TOKEN = ''
$env:GITHUB_TOKEN = ''
$env:GH_TOKEN = ''
$env:FIRECRAWL_API_KEY = 'fc-test-key-not-real'
$r4 = @(& $helper -UserHome $root2 -ProjectsRoot (Join-Path $root2 'Projects') -SkipPlugins -Quiet)
$skipGh = @($r4 | Where-Object { $_.Status -eq 'SKIP' -and $_.Item -match 'github' })
$doc4 = $null
$p4 = Join-Path $root2 '.claude.json'
if (Test-Path -LiteralPath $p4) { $doc4 = [IO.File]::ReadAllText($p4) | ConvertFrom-Json }
Check 'github skipped without key' ($skipGh.Count -eq 1)
Check 'kapture still added without github key' ($doc4 -and $doc4.mcpServers.kapture)
Check 'github absent when skipped' ($doc4 -and -not $doc4.mcpServers.PSObject.Properties['github'])

# 5. Plugin list file is the source of truth and is DansPC's 24 official-marketplace plugins.
$wantPlugins = @(
  'agent-sdk-dev', 'claude-code-setup', 'claude-md-management', 'code-review', 'code-simplifier',
  'commit-commands', 'desktop-commander', 'explanatory-output-style', 'learning-output-style',
  'pr-review-toolkit', 'hookify', 'code-modernization', 'frontend-design', 'skill-creator',
  'playground', 'feature-dev', 'github', 'superpowers', 'mcp-server-dev', 'plugin-dev',
  'context7', 'security-guidance', 'typescript-lsp', 'pyright-lsp'
)
$plist = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\plugins.json')) | ConvertFrom-Json
Check 'plugin list has sourceOfTruth' ([bool]$plist.sourceOfTruth)
Check 'plugin list mentions official marketplace' ($plist.marketplaceName -eq 'claude-plugins-official')
Check 'plugin list has 24 names' (@($plist.plugins).Count -eq 24)
Check 'plugin list order matches DansPC' ((@($plist.plugins) -join ',') -eq ($wantPlugins -join ','))
Check 'plugin list has no TODO' ($plist.sourceOfTruth -notmatch 'TODO')

# 6. SkipPlugins + plugins file missing is not hit; plugin install skipped in test mode.
$r6 = @(& $helper -UserHome $root -SkipMcp -Quiet)
Check 'plugins skipped in UserHome' (@($r6 | Where-Object { $_.Status -eq 'SKIP' -and $_.Item -match 'plugin' }).Count -ge 1)

Remove-Item $root, $root2 -Recurse -Force -ErrorAction SilentlyContinue
if ($fail) { exit 1 } else { 'ALL PASS' }
