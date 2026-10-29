# claude-setup.ps1 - merge Claude Code MCP connectors into ~/.claude.json and
# install plugins from claude/plugins.json. install.ps1 runs it. Safe to re-run:
# existing servers and plugins are left alone; missing ones are added. Secrets
# come from env (or a prompt); never from this repo. A server that still lacks
# a required key is skipped with a message; this script does not fail the install.
#
# Output: one object per action (Status, Item, Manifest). Status is DONE / WOULD /
# OK / SKIP / WARN / ERROR, same as install.ps1.
param(
  [string]$UserHome,
  [string]$ProjectsRoot,
  [switch]$WhatIf,
  [switch]$Quiet,
  [string]$SpecPath,
  [string]$PluginListPath,
  [switch]$SkipPlugins,
  [switch]$SkipMcp
)
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $SpecPath) { $SpecPath = Join-Path $here 'mcp-servers.json' }
if (-not $PluginListPath) { $PluginListPath = Join-Path $here 'plugins.json' }

$testMode = [bool]$UserHome
if (-not $UserHome) { $UserHome = $env:USERPROFILE }; if (-not $UserHome) { $UserHome = $HOME }
$UserHome = [IO.Path]::GetFullPath($UserHome).TrimEnd('\', '/')
if (-not $ProjectsRoot) { $ProjectsRoot = Join-Path $UserHome 'Projects' }
$Utf8NoBom = New-Object Text.UTF8Encoding $false
$ClaudeJson = Join-Path $UserHome '.claude.json'
$IsWin = ($env:OS -eq 'Windows_NT')
$NoPrompt = $Quiet -or $WhatIf -or $testMode
if ($env:CI -or $env:GITHUB_ACTIONS -or $env:TF_BUILD -or $env:GITLAB_CI) { $NoPrompt = $true }
try { if (-not [Environment]::UserInteractive) { $NoPrompt = $true } } catch { }

function Get-Prop($Obj, [string]$Name) {
  if ($Obj -and $Obj.PSObject.Properties[$Name]) { return $Obj.PSObject.Properties[$Name].Value }
  return $null
}
function Ensure-Prop($Obj, [string]$Name) {
  $cur = Get-Prop $Obj $Name
  if ($null -ne $cur -and $cur) { return $cur }
  $fresh = New-Object psobject
  if ($Obj.PSObject.Properties[$Name]) { $Obj.$Name = $fresh } else { $Obj | Add-Member -NotePropertyName $Name -NotePropertyValue $fresh }
  return $fresh
}
function ConvertTo-NormPath([string]$P) {
  if (-not $P) { return '' }
  return (($P -replace '\\', '/').TrimEnd('/'))
}
# Same pretty-printer as install.ps1 (PS 5.1-safe). Only whitespace outside strings changes.
function Format-Json([string]$Json, [string]$Nl = "`r`n") {
  foreach ($pair in @(@('\u0027', "'"), @('\u003c', '<'), @('\u003e', '>'), @('\u0026', '&'))) {
    $Json = [regex]::Replace($Json, '(?<=(?:^|[^\\])(?:\\\\)*)' + [regex]::Escape($pair[0]), $pair[1])
  }
  $sb = New-Object Text.StringBuilder
  $chars = $Json.ToCharArray(); $indent = 0; $inStr = $false; $esc = $false
  for ($i = 0; $i -lt $chars.Length; $i++) {
    $ch = $chars[$i]
    if ($inStr) {
      [void]$sb.Append($ch)
      if ($esc) { $esc = $false } elseif ($ch -eq [char]'\') { $esc = $true } elseif ($ch -eq [char]'"') { $inStr = $false }
    } elseif ($ch -eq [char]'"') { $inStr = $true; [void]$sb.Append($ch) }
    elseif ($ch -eq [char]'{' -or $ch -eq [char]'[') {
      $close = if ($ch -eq [char]'{') { [char]'}' } else { [char]']' }
      $j = $i + 1; while ($j -lt $chars.Length -and [char]::IsWhiteSpace($chars[$j])) { $j++ }
      if ($j -lt $chars.Length -and $chars[$j] -eq $close) { [void]$sb.Append($ch).Append($close); $i = $j }
      else { $indent++; [void]$sb.Append($ch).Append($Nl).Append('  ' * $indent) }
    } elseif ($ch -eq [char]'}' -or $ch -eq [char]']') { $indent--; [void]$sb.Append($Nl).Append('  ' * $indent).Append($ch) }
    elseif ($ch -eq [char]',') { [void]$sb.Append(',').Append($Nl).Append('  ' * $indent) }
    elseif ($ch -eq [char]':') { [void]$sb.Append(': ') }
    elseif (-not [char]::IsWhiteSpace($ch)) { [void]$sb.Append($ch) }
  }
  return $sb.ToString() + $Nl
}

function Read-JsonSpec([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { throw "missing spec: $Path" }
  return [IO.File]::ReadAllText($Path) | ConvertFrom-Json
}

function Get-FirstEnv([string[]]$Names) {
  foreach ($n in @($Names | Where-Object { $_ })) {
    $v = [Environment]::GetEnvironmentVariable($n)
    if ($v) { return [pscustomobject]@{ Name = $n; Value = [string]$v } }
  }
  return $null
}

function Read-KeyPrompt([string]$Server, [string[]]$Names) {
  if ($NoPrompt) { return $null }
  $shown = ($Names -join ' or ')
  Write-Host "MCP server '$Server' needs $shown. Paste a value, or press Enter to skip this server."
  $r = Read-Host 'Value (empty to skip)'
  if ($r) { return [string]$r }
  return $null
}

function Find-McpName($Doc, [string]$Name) {
  $ms = Get-Prop $Doc 'mcpServers'
  if ($ms -and $ms.PSObject.Properties[$Name]) { return "user:$Name" }
  $projects = Get-Prop $Doc 'projects'
  if ($projects) {
    foreach ($p in $projects.PSObject.Properties) {
      $pms = Get-Prop $p.Value 'mcpServers'
      if ($pms -and $pms.PSObject.Properties[$Name]) { return "local:$($p.Name)" }
    }
  }
  return $null
}

function Get-ProjectEntry($Doc, [string]$WantPath) {
  $projects = Get-Prop $Doc 'projects'
  if (-not $projects) { return $null }
  $want = ConvertTo-NormPath $WantPath
  foreach ($p in $projects.PSObject.Properties) {
    if ((ConvertTo-NormPath $p.Name) -ieq $want) { return [pscustomobject]@{ Key = $p.Name; Value = $p.Value } }
  }
  return $null
}

function New-StdioEntry($Spec) {
  $cmd = [string]$Spec.command
  $args = @($Spec.args)
  if ($IsWin -and @('npx', 'npx.cmd', 'uvx', 'uv') -contains $cmd) {
    $args = @('/c', $cmd) + $args
    $cmd = 'cmd'
  }
  $entry = [pscustomobject]@{ type = 'stdio'; command = $cmd; args = @($args) }
  return $entry
}

function Get-McpFingerprint($Entry) {
  if (-not $Entry) { return '' }
  $url = Get-Prop $Entry 'url'
  if ($url) { return "http|$url" }
  $cmd = Get-Prop $Entry 'command'
  $args = @(Get-Prop $Entry 'args') -join ' '
  return "stdio|$cmd|$args"
}

function Add-ServerMember($Container, [string]$Name, $Entry) {
  if ($Container.PSObject.Properties[$Name]) { $Container.$Name = $Entry }
  else { $Container | Add-Member -NotePropertyName $Name -NotePropertyValue $Entry }
}

function Merge-ClaudeMcpServers {
  param(
    $Doc,
    $Spec,
    [string]$ClaudeJsonPath
  )
  $results = New-Object System.Collections.Generic.List[object]
  $changed = $false
  foreach ($s in @($Spec.servers)) {
    $name = [string]$s.name
    $scope = [string]$s.scope
    if (-not $name) { continue }
    $already = Find-McpName $Doc $name
    if ($already) {
      $results.Add([pscustomobject]@{ Status = 'OK'; Item = "MCP $name already in $ClaudeJsonPath ($already); left alone"; Manifest = $null })
      continue
    }

    $envMap = $null
    $headers = $null
    $need = @($s.requiredEnvAny)
    if (-not $need -or $need.Count -eq 0) { $need = @() }
    $copyVars = @($s.envVars)
    if (-not $copyVars -or $copyVars.Count -eq 0) { $copyVars = @() }

    if ($need.Count) {
      $got = Get-FirstEnv $need
      $val = $null
      if ($got) { $val = $got.Value }
      else {
        $val = Read-KeyPrompt $name $need
        if ($val -and $need[0]) { [Environment]::SetEnvironmentVariable($need[0], $val, 'Process') }
      }
      if (-not $val) {
        $results.Add([pscustomobject]@{
          Status = 'SKIP'
          Item = "MCP $name skipped: set $($need -join ' or ') and re-run install.ps1 (not failing)"
          Manifest = $null
        })
        continue
      }
      $hdr = [string]$s.authHeader
      if (-not $hdr) { $hdr = 'Authorization' }
      $prefix = [string]$s.authPrefix
      if ($null -eq $prefix) { $prefix = '' }
      $headers = New-Object psobject
      $headers | Add-Member -NotePropertyName $hdr -NotePropertyValue ($prefix + $val)
    }
    if ($copyVars.Count) {
      $envMap = New-Object psobject
      $missing = @()
      foreach ($v in $copyVars) {
        $got = Get-FirstEnv @($v)
        $val = $null
        if ($got) { $val = $got.Value }
        else { $val = Read-KeyPrompt $name @($v) }
        if (-not $val) { $missing += $v; continue }
        $envMap | Add-Member -NotePropertyName $v -NotePropertyValue $val
      }
      if ($missing.Count) {
        $results.Add([pscustomobject]@{
          Status = 'SKIP'
          Item = "MCP $name skipped: set $($missing -join ', ') and re-run install.ps1 (not failing)"
          Manifest = $null
        })
        continue
      }
    }

    $type = [string]$s.type
    if ($type -eq 'http') {
      $entry = [pscustomobject]@{ type = 'http'; url = [string]$s.url }
      if ($headers) { $entry | Add-Member -NotePropertyName headers -NotePropertyValue $headers }
    } else {
      $entry = New-StdioEntry $s
      if ($envMap) { $entry | Add-Member -NotePropertyName env -NotePropertyValue $envMap }
    }

    $targetLabel = "user mcpServers.$name"
    if ($scope -eq 'local') {
      $projPath = [string]$s.projectPath
      if (-not $projPath) { $projPath = 'C:/projects' }
      $hit = Get-ProjectEntry $Doc $projPath
      if ($hit) {
        $pobj = $hit.Value
        $pms = Ensure-Prop $pobj 'mcpServers'
        Add-ServerMember $pms $name $entry
        $targetLabel = "local $($hit.Key) mcpServers.$name"
      } else {
        $projects = Ensure-Prop $Doc 'projects'
        $pobj = New-Object psobject
        $pms = New-Object psobject
        Add-ServerMember $pms $name $entry
        $pobj | Add-Member -NotePropertyName mcpServers -NotePropertyValue $pms
        $key = ConvertTo-NormPath $projPath
        Add-ServerMember $projects $key $pobj
        $targetLabel = "local $key mcpServers.$name"
      }
    } else {
      $ms = Ensure-Prop $Doc 'mcpServers'
      Add-ServerMember $ms $name $entry
    }
    $changed = $true
    $fp = Get-McpFingerprint $entry
    $results.Add([pscustomobject]@{
      Status = $(if ($WhatIf) { 'WOULD' } else { 'DONE' })
      Item = $(if ($WhatIf) { "add MCP $name to $ClaudeJsonPath ($targetLabel)" } else { "added MCP $name to $ClaudeJsonPath ($targetLabel)" })
      Manifest = @{ kind = 'mcp-server'; target = 'claude-json'; name = $name; scope = $scope; fingerprint = $fp; path = $ClaudeJsonPath }
    })
  }
  return [pscustomobject]@{ Changed = $changed; Results = $results }
}

function Write-ClaudeJsonChecked([string]$Path, $Obj, [string]$Raw, [bool]$Existed, [string]$Bak) {
  $nl = "`r`n"; if ($Existed -and $Raw -and $Raw.Contains("`n") -and -not $Raw.Contains("`r`n")) { $nl = "`n" }
  $json = Format-Json ($Obj | ConvertTo-Json -Depth 100) $nl
  if ($Existed -and $Raw -and -not $Raw.EndsWith("`n")) { $json = $json.TrimEnd("`r", "`n") }
  New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force | Out-Null | Out-Null
  if ($Existed) { Copy-Item -LiteralPath $Path -Destination $Bak -Force }
  [IO.File]::WriteAllText($Path, $json, $Utf8NoBom)
  try { [IO.File]::ReadAllText($Path) | ConvertFrom-Json | Out-Null }
  catch {
    if ($Existed) { Copy-Item -LiteralPath $Bak -Destination $Path -Force }
    else { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
    throw 'written ~/.claude.json did not parse; restored the original'
  }
}

function Get-LastJsonLine([string[]]$Lines) {
  for ($i = $Lines.Count - 1; $i -ge 0; $i--) {
    $t = [string]$Lines[$i]
    if ($t -match '^\s*\{') {
      try { return ($t | ConvertFrom-Json) } catch { }
    }
  }
  return $null
}

function Install-ClaudePluginsFromList {
  param($List)
  $results = New-Object System.Collections.Generic.List[object]
  $names = @($List.plugins | ForEach-Object { [string]$_ } | Where-Object { $_ })
  if ($names.Count -eq 0) {
    $results.Add([pscustomobject]@{ Status = 'SKIP'; Item = "plugin list is empty: $PluginListPath"; Manifest = $null })
    return $results
  }
  $mpName = [string]$List.marketplaceName
  if (-not $mpName) { $mpName = 'claude-plugins-official' }
  $mpSrc = [string]$List.marketplace
  if (-not $mpSrc) { $mpSrc = 'anthropics/claude-plugins-official' }

  if ($WhatIf) {
    foreach ($n in $names) {
      $results.Add([pscustomobject]@{ Status = 'WOULD'; Item = "install Claude Code plugin $n@$mpName (user scope)"; Manifest = $null })
    }
    return $results
  }
  if ($testMode) {
    $results.Add([pscustomobject]@{ Status = 'SKIP'; Item = 'Claude Code plugins: not installed in -UserHome test mode'; Manifest = $null })
    return $results
  }

  $claude = Get-Command claude -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $claude) {
    $results.Add([pscustomobject]@{
      Status = 'SKIP'
      Item = 'Claude Code CLI not found; plugin install skipped. Install Claude Code, then re-run install.ps1'
      Manifest = $null
    })
    return $results
  }

  $ErrorActionPreference = 'Continue'
  $addOut = & $claude.Source plugin marketplace add $mpSrc 2>&1 | ForEach-Object { [string]$_ }
  $ErrorActionPreference = 'Stop'
  $addText = $addOut -join "`n"
  if ($LASTEXITCODE -and $addText -notmatch '(?i)already|exists|Successfully added') {
    $results.Add([pscustomobject]@{
      Status = 'WARN'
      Item = "could not add marketplace $mpSrc (exit $LASTEXITCODE); plugin installs may fail. $($addText.Trim())"
      Manifest = $null
    })
  } else {
    $results.Add([pscustomobject]@{ Status = 'OK'; Item = "Claude Code marketplace $mpName available"; Manifest = $null })
  }

  foreach ($n in $names) {
    $qual = "$n@$mpName"
    $ErrorActionPreference = 'Continue'
    $out = @(& $claude.Source plugin install $qual --scope user --yes --json 2>&1 | ForEach-Object { [string]$_ })
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $parsed = Get-LastJsonLine $out
    $msg = if ($parsed -and $parsed.message) { [string]$parsed.message } else { ($out | Select-Object -Last 3) -join ' ' }
    $already = ($msg -match '(?i)already installed') -or ($parsed -and [string]$parsed.outcome -eq 'ok' -and $msg -match '(?i)already')
    if ($already) {
      $results.Add([pscustomobject]@{
        Status = 'OK'
        Item = "plugin $qual already installed (user scope)"
        Manifest = @{ kind = 'claude-plugin-preexisting'; name = $n; marketplace = $mpName }
      })
      continue
    }
    $ok = ($code -eq 0) -or ($parsed -and [string]$parsed.outcome -eq 'ok')
    if ($ok) {
      $results.Add([pscustomobject]@{
        Status = 'DONE'
        Item = "installed Claude Code plugin $qual (user scope)"
        Manifest = @{ kind = 'claude-plugin'; name = $n; marketplace = $mpName }
      })
    } else {
      $safe = $msg
      if ($safe.Length -gt 300) { $safe = $safe.Substring(0, 300) }
      $results.Add([pscustomobject]@{
        Status = 'WARN'
        Item = "plugin $qual not installed (left the rest to continue): $safe"
        Manifest = $null
      })
    }
  }
  return $results
}

function Invoke-ClaudeSetup {
  $out = New-Object System.Collections.Generic.List[object]
  if (-not $SkipMcp) {
    if (-not (Test-Path -LiteralPath $SpecPath)) {
      $out.Add([pscustomobject]@{ Status = 'ERROR'; Item = "MCP spec missing: $SpecPath"; Manifest = $null })
    } else {
      $spec = Read-JsonSpec $SpecPath
      $existed = Test-Path -LiteralPath $ClaudeJson
      $raw = $null; $doc = $null; $ok = $true
      if ($existed) {
        try {
          $raw = [IO.File]::ReadAllText($ClaudeJson)
          if ($raw.Trim()) { $doc = $raw | ConvertFrom-Json } else { $doc = New-Object psobject }
        } catch {
          $ok = $false
          $out.Add([pscustomobject]@{ Status = 'ERROR'; Item = "could not parse $ClaudeJson (left unchanged): $($_.Exception.Message)"; Manifest = $null })
        }
      } else { $doc = New-Object psobject }
      if ($ok) {
        $merged = Merge-ClaudeMcpServers -Doc $doc -Spec $spec -ClaudeJsonPath $ClaudeJson
        $writeFailed = $false
        if ($merged.Changed -and -not $WhatIf) {
          $bak = "$ClaudeJson.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
          $i = 1
          while (Test-Path -LiteralPath $bak) { $bak = "$ClaudeJson.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$i"; $i++ }
          try {
            Write-ClaudeJsonChecked $ClaudeJson $doc $raw $existed $bak
          } catch {
            $writeFailed = $true
            $out.Add([pscustomobject]@{ Status = 'ERROR'; Item = "failed to write $ClaudeJson -- $($_.Exception.Message)"; Manifest = $null })
          }
        }
        foreach ($r in $merged.Results) {
          if ($writeFailed -and $r.Status -eq 'DONE') { continue }
          $out.Add($r)
        }
      }
    }
  }
  if (-not $SkipPlugins) {
    if (-not (Test-Path -LiteralPath $PluginListPath)) {
      $out.Add([pscustomobject]@{ Status = 'ERROR'; Item = "plugin list missing: $PluginListPath"; Manifest = $null })
    } else {
      $list = Read-JsonSpec $PluginListPath
      foreach ($r in @(Install-ClaudePluginsFromList $list)) { $out.Add($r) }
    }
  }
  foreach ($item in $out) { Write-Output $item }
}

if ($MyInvocation.InvocationName -ne '.') {
  Invoke-ClaudeSetup
}
