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
Check 'whatif would not add firecrawl' ($names -notcontains 'firecrawl')
Check 'whatif would add windows-mcp' ($names -contains 'windows-mcp')
Check 'whatif would add context7' ($names -contains 'context7')
Check 'whatif would add fetch' ($names -contains 'fetch')
Check 'whatif would add githits' ($names -contains 'githits')
Check 'whatif would not add autodesk-fusion-mcp' ($names -notcontains 'autodesk-fusion-mcp')

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
Check 'user has no autodesk-fusion-mcp' (-not $doc.mcpServers.PSObject.Properties['autodesk-fusion-mcp'])
Check 'github is http' ($doc.mcpServers.github.type -eq 'http')
Check 'github url' ($doc.mcpServers.github.url -match 'githubcopilot')
Check 'firecrawl not user-scope' (-not $doc.mcpServers.PSObject.Properties['firecrawl'])
$fcLocal = $false
if ($doc.projects) {
  foreach ($pp in $doc.projects.PSObject.Properties) {
    $pms = $null; if ($pp.Value) { $pms = $pp.Value.mcpServers }
    if ($pms -and $pms.PSObject.Properties['firecrawl']) { $fcLocal = $true }
  }
}
Check 'firecrawl not local-scoped' (-not $fcLocal)
Check 'unrelated keys not required' (-not $doc.PSObject.Properties['theme'])
Check 'done count' (@($r2 | Where-Object Status -eq 'DONE').Count -ge 6)

# 3. Idempotent: second run leaves a hand-made extra server and does not duplicate.
$doc.mcpServers | Add-Member -NotePropertyName 'handmade' -NotePropertyValue ([pscustomobject]@{ type = 'stdio'; command = 'echo'; args = @('keep-me') })
$nl = if ([IO.File]::ReadAllText($jsonPath).Contains("`r`n")) { "`r`n" } else { "`n" }
[IO.File]::WriteAllText($jsonPath, (($doc | ConvertTo-Json -Depth 20)))
$r3 = Invoke-Setup
$doc2 = [IO.File]::ReadAllText($jsonPath) | ConvertFrom-Json
Check 'second run all OK' (@($r3 | Where-Object Status -eq 'OK').Count -ge 6)
Check 'handmade server kept' ([bool]$doc2.mcpServers.handmade)
Check 'kapture still one entry' ([bool]$doc2.mcpServers.kapture)

# 4. Missing github key skips github only.
$root2 = Join-Path ([IO.Path]::GetTempPath()) ("ccsetup2-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $root2 -Force | Out-Null
$env:GITHUB_PERSONAL_ACCESS_TOKEN = ''
$env:GITHUB_TOKEN = ''
$env:GH_TOKEN = ''
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

# Spec file itself has no firecrawl (not used; install must not prompt for its key).
$spec = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\mcp-servers.json')) | ConvertFrom-Json
$specNames = @($spec.servers | ForEach-Object { $_.name })
Check 'spec has 6 servers' ($specNames.Count -eq 6)
Check 'spec has no firecrawl' ($specNames -notcontains 'firecrawl')
Check 'spec has no FIRECRAWL env' (-not (@($spec.servers | ForEach-Object {
  @($_.envVars) + @($_.requiredEnvAny)
}) -contains 'FIRECRAWL_API_KEY'))

# 6. SkipPlugins + plugins file missing is not hit; plugin install skipped in test mode.
$r6 = @(& $helper -UserHome $root -SkipMcp -Quiet)
Check 'plugins skipped in UserHome' (@($r6 | Where-Object { $_.Status -eq 'SKIP' -and $_.Item -match 'plugin' }).Count -ge 1)

# 7. Official plugins already enabled, or already installed at user scope, are not reinstalled.
#    A project-scope install does not count. No claude command runs for the ones left alone.
function Write-OfficialPluginFixture {
  param(
    [string]$ProfileHome,
    [string[]]$Enabled,
    [string[]]$InstalledUser,
    [string[]]$InstalledOtherScope
  )
  $claudeDir = Join-Path $ProfileHome '.claude'
  $plugDir = Join-Path $claudeDir 'plugins'
  New-Item -ItemType Directory -Path $plugDir -Force | Out-Null
  $epLines = New-Object System.Collections.Generic.List[string]
  foreach ($n in @($Enabled)) { [void]$epLines.Add(('    "{0}@claude-plugins-official": true' -f $n)) }
  foreach ($n in @($InstalledUser)) {
    if (@($Enabled) -notcontains $n) { [void]$epLines.Add(('    "{0}@claude-plugins-official": false' -f $n)) }
  }
  $settings = "{`r`n  `"enabledPlugins`": {`r`n" + ($epLines -join ",`r`n") + "`r`n  }`r`n}`r`n"
  [IO.File]::WriteAllText((Join-Path $claudeDir 'settings.json'), $settings)
  $regLines = New-Object System.Collections.Generic.List[string]
  foreach ($n in @($InstalledUser)) {
    [void]$regLines.Add(('    "{0}@claude-plugins-official": [{{ "scope": "user", "installPath": "cache/claude-plugins-official/{0}/1.0.0", "version": "1.0.0" }}]' -f $n))
  }
  foreach ($n in @($InstalledOtherScope)) {
    [void]$regLines.Add(('    "{0}@claude-plugins-official": [{{ "scope": "project", "projectPath": "work/app", "installPath": "cache/claude-plugins-official/{0}/1.0.0", "version": "1.0.0" }}]' -f $n))
  }
  $registry = "{`r`n  `"version`": 2,`r`n  `"plugins`": {`r`n" + ($regLines -join ",`r`n") + "`r`n  }`r`n}`r`n"
  [IO.File]::WriteAllText((Join-Path $plugDir 'installed_plugins.json'), $registry)
}

$pluginHome = Join-Path ([IO.Path]::GetTempPath()) ("ccplug-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enabledPlugins = @($wantPlugins | Where-Object { $_ -ne 'typescript-lsp' -and $_ -ne 'pyright-lsp' })
$installedUser = @($enabledPlugins + @('typescript-lsp'))
Write-OfficialPluginFixture -ProfileHome $pluginHome -Enabled $enabledPlugins -InstalledUser $installedUser -InstalledOtherScope @('pyright-lsp')
$plugArgs = @{
  UserHome = $pluginHome
  ProjectsRoot = (Join-Path $pluginHome 'Projects')
  SkipMcp = $true
  Quiet = $true
}
$r7 = @(& $helper @plugArgs -WhatIf)
$would7 = @($r7 | Where-Object { $_.Status -eq 'WOULD' -and $_.Item -match 'install Claude Code plugin' })
Check 'whatif would install only the plugin that is not enabled or user-installed' ($would7.Count -eq 1 -and $would7[0].Item -match 'pyright-lsp@claude-plugins-official')
Check 'whatif ok for already enabled plugins' (@($r7 | Where-Object { $_.Status -eq 'OK' -and $_.Item -match 'already enabled' }).Count -eq $enabledPlugins.Count)
Check 'whatif leaves the user-installed disabled plugin' (@($r7 | Where-Object { $_.Status -eq 'OK' -and $_.Item -match 'typescript-lsp@claude-plugins-official already installed' }).Count -eq 1)
$wouldItem = ''
if ($would7.Count) { $wouldItem = [string]$would7[0].Item }
$touched = @($enabledPlugins + @('typescript-lsp') | Where-Object { $wouldItem -match [regex]::Escape("$_@") })
Check 'whatif does not name an enabled or user-installed plugin' ($touched.Count -eq 0)

$r7b = @(& $helper @plugArgs)
Check 'test mode still skips the plugin that is not installed' (@($r7b | Where-Object { $_.Status -eq 'SKIP' -and $_.Item -match 'not installed in -UserHome test mode' }).Count -eq 1)
Check 'test mode does not would-install enabled plugins' (@($r7b | Where-Object Status -eq 'WOULD').Count -eq 0)
Check 'test mode ok for already enabled plugins' (@($r7b | Where-Object { $_.Status -eq 'OK' -and $_.Item -match 'already enabled' }).Count -eq $enabledPlugins.Count)

$rNone = @(& $helper -UserHome $root2 -ProjectsRoot (Join-Path $root2 'Projects') -SkipMcp -WhatIf -Quiet)
Check 'whatif with no plugin state would install all 24' (@($rNone | Where-Object { $_.Status -eq 'WOULD' -and $_.Item -match 'install Claude Code plugin' }).Count -eq 24)

$badHome = Join-Path ([IO.Path]::GetTempPath()) ("ccplugbad-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$badPlug = Join-Path (Join-Path $badHome '.claude') 'plugins'
New-Item -ItemType Directory -Path $badPlug -Force | Out-Null
[IO.File]::WriteAllText((Join-Path (Join-Path $badHome '.claude') 'settings.json'), '{')
[IO.File]::WriteAllText((Join-Path $badPlug 'installed_plugins.json'), '{')
$rBad = @(& $helper -UserHome $badHome -ProjectsRoot (Join-Path $badHome 'Projects') -SkipMcp -WhatIf -Quiet)
Check 'unreadable plugin state warns' (@($rBad | Where-Object Status -eq 'WARN').Count -ge 1)
Check 'unreadable plugin state still would install all 24' (@($rBad | Where-Object { $_.Status -eq 'WOULD' -and $_.Item -match 'install Claude Code plugin' }).Count -eq 24)

# Real path (not -UserHome test mode): a stand-in claude records the install lines.
# Already-enabled and already-installed plugins must not appear.
$fakeClaude = Join-Path $pluginHome 'fake-claude.ps1'
$callLog = Join-Path $pluginHome 'claude-calls.txt'
$utf8 = New-Object Text.UTF8Encoding $false
[IO.File]::WriteAllText($fakeClaude, @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$log = $env:CLAUDE_CALL_LOG
if ($log) {
  $line = ''
  if ($Rest) { $line = $Rest -join ' ' }
  [IO.File]::AppendAllText($log, ($line + [Environment]::NewLine))
}
Write-Output '{"outcome":"ok","message":"installed"}'
'@, $utf8)
$env:CLAUDE_CALL_LOG = $callLog
. $helper -UserHome $pluginHome -ProjectsRoot (Join-Path $pluginHome 'Projects') -SkipMcp -Quiet -PluginListPath (Join-Path $PSScriptRoot '..\plugins.json')
function Get-Command {
  [CmdletBinding()]
  param([Parameter(Position = 0)][string]$Name)
  if ($Name -eq 'claude') { return [pscustomobject]@{ Source = $script:fakeClaude } }
  return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
}
$testMode = $false
$WhatIf = $false
$rReal = @(Install-ClaudePluginsFromList $plist)
$logText = ''
if (Test-Path -LiteralPath $callLog) { $logText = [IO.File]::ReadAllText($callLog) }
$installLines = @($logText -split '\r?\n' | Where-Object { $_ -match 'plugin install' })
Check 'real run installs only pyright-lsp' ($installLines.Count -eq 1 -and $installLines[0] -match 'plugin install pyright-lsp@claude-plugins-official --scope user')
$reinstalled = @($installedUser | Where-Object { $logText -match [regex]::Escape("plugin install $_@") })
Check ('real run does not reinstall enabled or user-installed plugins' + $(if ($reinstalled) { ': ' + ($reinstalled -join ',') } else { '' })) ($reinstalled.Count -eq 0)
Check 'real run ok count for plugins left alone' (@($rReal | Where-Object { $_.Status -eq 'OK' -and $_.Item -match 'left as is' }).Count -eq $installedUser.Count)
Check 'real run done only for pyright' (@($rReal | Where-Object { $_.Status -eq 'DONE' -and $_.Item -match 'pyright-lsp@' }).Count -eq 1)

Write-OfficialPluginFixture -ProfileHome $pluginHome -Enabled $wantPlugins -InstalledUser $wantPlugins -InstalledOtherScope @()
if (Test-Path -LiteralPath $callLog) { Remove-Item -LiteralPath $callLog -Force }
$rAll = @(Install-ClaudePluginsFromList $plist)
Check 'all-enabled run does not call claude' (-not (Test-Path -LiteralPath $callLog))
Check 'all-enabled run is ok for every official plugin' (@($rAll | Where-Object { $_.Status -eq 'OK' -and $_.Item -match 'already enabled' }).Count -eq 24)
Check 'all-enabled run has no WOULD' (@($rAll | Where-Object Status -eq 'WOULD').Count -eq 0)

Remove-Item $root, $root2, $pluginHome, $badHome -Recurse -Force -ErrorAction SilentlyContinue
if ($fail) { exit 1 } else { 'ALL PASS' }
