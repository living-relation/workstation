# Live task tracker window: read-only, never creates or writes files (state in HKCU\Software\Workstation\Tracker). Started by: tracker.ps1 -Show. Single instance (named mutex).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tracker-common.ps1')
$created = $false
$mutex = New-Object Threading.Mutex($true, $TrackerWindowMutex, [ref]$created)
if (-not $created) { try { $e = [Threading.EventWaitHandle]::OpenExisting($TrackerShowEvent); [void]$e.Set(); $e.Dispose() } catch { }; exit 0 }
$showEv = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::AutoReset, $TrackerShowEvent)
[void]$showEv.WaitOne(0)   # this start is the -Show; drop a stale signal
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Tasks" Width="450" Height="670" MinWidth="310" MinHeight="240" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowActivated="False" ShowInTaskbar="True" ResizeMode="CanResizeWithGrip">
  <Border Background="#FF111214" BorderBrush="#FF2A2C31" BorderThickness="1" CornerRadius="11">
    <DockPanel>
      <Grid x:Name="TitleBar" DockPanel.Dock="Top" Height="38" Background="Transparent">
        <TextBlock x:Name="TitleText" Margin="14,0,120,0" VerticalAlignment="Center" Foreground="#FFECECEC"
                   FontFamily="Segoe UI Semibold" FontSize="16" TextTrimming="CharacterEllipsis"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,0,8,0">
          <Button x:Name="PinBtn" Width="31" Height="28" Background="Transparent" BorderThickness="0" Foreground="#FFB0B3B8" FontFamily="Segoe MDL2 Assets" FontSize="13" Cursor="Hand"/>
          <Button x:Name="MinBtn" Width="31" Height="28" Background="Transparent" BorderThickness="0" Foreground="#FFB0B3B8" FontFamily="Segoe MDL2 Assets" FontSize="11" Content="&#xE921;" ToolTip="Minimize" Cursor="Hand"/>
          <Button x:Name="CloseBtn" Width="31" Height="28" Background="Transparent" BorderThickness="0" Foreground="#FFB0B3B8" FontFamily="Segoe MDL2 Assets" FontSize="11" Content="&#xE8BB;" ToolTip="Close" Cursor="Hand"/>
        </StackPanel>
      </Grid>
      <StackPanel DockPanel.Dock="Top" Margin="14,0,14,8">
        <DockPanel><Button x:Name="ClearBtn" DockPanel.Dock="Right" Content="Clear finished" FontFamily="Segoe UI" FontSize="12" Padding="8,2" Margin="6,0,0,0" VerticalAlignment="Center" Background="#FF2A2C31" Foreground="#FFB0B3B8" BorderBrush="#FF3A3D44" BorderThickness="1" Cursor="Hand" ToolTip="Hide finished jobs in this window (the list file is not changed)"/><TextBlock x:Name="CountText" Foreground="#FFECECEC" FontFamily="Segoe UI Semibold" FontSize="19"/></DockPanel>
        <TextBlock x:Name="SubCountText" Foreground="#FF9DA1A8" FontFamily="Segoe UI" FontSize="13" Margin="0,0,0,4"/>
        <ProgressBar x:Name="Bar" Height="6" Minimum="0" Maximum="1" Background="#FF2A2C31" Foreground="#FF4C8DFF" BorderThickness="0"/>
      </StackPanel>
      <ScrollViewer x:Name="Scroll" VerticalScrollBarVisibility="Auto" Margin="4,0,4,9">
        <StackPanel x:Name="List" Margin="8,0,8,0"/>
      </ScrollViewer>
    </DockPanel>
  </Border>
</Window>
'@
$win = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xaml))
$c = @{}; foreach ($n in 'TitleBar','TitleText','PinBtn','MinBtn','CloseBtn','CountText','SubCountText','ClearBtn','Bar','List','Scroll') { $c[$n] = $win.FindName($n) }
$bc = New-Object Windows.Media.BrushConverter
function Brush($h) { $bc.ConvertFromString($h) }

# Window state from the registry; on first run migrate once (read-only) from an old settings.json.
function Read-TrackerPrefs {
  try {
    if (Test-Path $TrackerRegKey) {
      $r = Get-ItemProperty -Path $TrackerRegKey
      $ex = [pscustomobject]@{}; foreach ($x in @(([string]$r.Expanded) -split ',' | ? { $_ })) { $ex | Add-Member -Force $x $true }
      return [pscustomobject]@{ pinned = $(if ($null -ne $r.Pinned) { [int]$r.Pinned -ne 0 } else { $null }); left = $(if ($r.Left) { [double]$r.Left } else { $null })
        top = $(if ($r.Top) { [double]$r.Top } else { $null }); width = [double]$r.Width; height = [double]$r.Height; expanded = $ex }
    }
    $old = Read-JsonFile $TrackerSettings
    if ($old) { $script:migrate = $true }
    return $old
  } catch { return $null }
}
$settings = Read-TrackerPrefs
$pinned = $true
if ($settings) {
  if ($null -ne $settings.pinned) { $pinned = [bool]$settings.pinned }
  if ($null -ne $settings.left -and $null -ne $settings.top) {
    $l = [double]$settings.left; $t = [double]$settings.top
    $sw = [Windows.SystemParameters]::VirtualScreenWidth + [Windows.SystemParameters]::VirtualScreenLeft
    $sh = [Windows.SystemParameters]::VirtualScreenHeight + [Windows.SystemParameters]::VirtualScreenTop
    if ($l -lt $sw - 40 -and $t -lt $sh - 40 -and $l -gt [Windows.SystemParameters]::VirtualScreenLeft - 280) { $win.WindowStartupLocation = 'Manual'; $win.Left = $l; $win.Top = $t }
  }
  if ($settings.width -ge 310) { $win.Width = [double]$settings.width }; if ($settings.height -ge 240) { $win.Height = [double]$settings.height }
}
if ($win.WindowStartupLocation -ne 'Manual') {
  $wa = [Windows.SystemParameters]::WorkArea; $win.WindowStartupLocation = 'Manual'
  $win.Left = $wa.Right - $win.Width - 16; $win.Top = $wa.Bottom - $win.Height - 16
}
$script:expand = @{}   # job id -> expanded (collapsed by default; remembered in settings.json)
if ($settings -and $settings.expanded) { foreach ($p in $settings.expanded.PSObject.Properties) { if ($p.Value) { $script:expand[$p.Name] = $true } } }
function Save-Settings { try {
  if (-not (Test-Path $TrackerRegKey)) { New-Item -Path $TrackerRegKey -Force | Out-Null }
  $inv = [Globalization.CultureInfo]::InvariantCulture
  Set-ItemProperty -Path $TrackerRegKey -Name Pinned -Value ([int][bool]$pinned) -Type DWord
  foreach ($n in 'Left','Top','Width','Height') { Set-ItemProperty -Path $TrackerRegKey -Name $n -Value ([double]$win.$n).ToString($inv) -Type String }
  Set-ItemProperty -Path $TrackerRegKey -Name Expanded -Value (@($script:expand.Keys) -join ',') -Type String
} catch { } }
function Set-Pin { $win.Topmost = $pinned
  if ($pinned) { $c.PinBtn.Content = [char]0xE841; $c.PinBtn.Foreground = Brush '#FF4C8DFF'; $c.PinBtn.ToolTip = 'Pinned on top (click to unpin)' }
  else { $c.PinBtn.Content = [char]0xE718; $c.PinBtn.Foreground = Brush '#FFB0B3B8'; $c.PinBtn.ToolTip = 'Not on top (click to pin)' } }
Set-Pin

$c.TitleBar.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch { }; Save-Settings })
$c.PinBtn.Add_Click({ $script:pinned = -not $script:pinned; Set-Pin; Save-Settings })
$c.MinBtn.Add_Click({ $win.WindowState = 'Minimized' })
$c.CloseBtn.Add_Click({ $win.Close() })
$win.Add_Closing({ Save-Settings })
# Clear finished: hides done jobs in this window only (tracker.json is never written). A hidden job comes back if it
# changes in the list or the window restarts.
$script:hidden = @{}   # job id -> compact JSON of the job when it was hidden
function Get-JobKey($t) { $t | ConvertTo-Json -Compress -Depth 8 }
$c.ClearBtn.Add_Click({
  $d = Read-JsonFile $TrackerFile
  if ($d) { foreach ($t in @($d.tasks | ? { $_ -and (Get-JobStatus $_) -eq 'done' })) { $script:hidden[[string]$t.id] = Get-JobKey $t } }
  $script:dirty = $true
})


# Chat links: grokbot://app/v1/agent?id=<agentId>; fall back to focusing the Grok Bot app.
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class TrkWin {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
}
'@
function Open-Chat([string]$agentId) {
  $ok = $false
  if ((Test-AgentId $agentId) -and (Test-Path 'Registry::HKEY_CLASSES_ROOT\grokbot')) {
    try { Start-Process "grokbot://app/v1/agent?id=$agentId"; $ok = $true } catch { }
  }
  if (-not $ok) {
    $p = Get-Process -Name 'Grok Bot' -ErrorAction SilentlyContinue | ? { $_.MainWindowHandle -ne 0 } | Select -First 1
    if ($p) { [TrkWin]::ShowWindow($p.MainWindowHandle, 9) | Out-Null; [TrkWin]::SetForegroundWindow($p.MainWindowHandle) | Out-Null }
  }
}
function Test-AgentId([string]$id) { $g = [Guid]::Empty; [Guid]::TryParse($id, [ref]$g) -and $g -ne [Guid]::Empty -and $id -notmatch '^[0-]+$' }
# bots.json: { "Name": "<agentId>" } or { "Name": { "agentId": "<id>", "color": "#RRGGBB" } }
$DefaultColors = @{ 'Grok Bot' = '#4C8DFF' }
$Palette = @('#A371F7','#3FB950','#F778BA','#2DD4BF','#F2A33A','#FF7B72','#79C0FF','#D2A8FF')
function Get-Bots {
  $m = @{}; $b = Read-JsonFile $TrackerBots
  if ($b) { foreach ($p in $b.PSObject.Properties) {
    $v = $p.Value; $id = ''; $col = ''
    if ($v -is [string]) { $id = $v } else { $id = [string]$v.agentId; $col = [string]$v.color }
    if (-not (Test-AgentId $id)) { $id = '' }
    $m[$p.Name] = @{ id = $id; color = $col }
  } }
  $m
}
function Get-BotColor([string]$name, $bots) {
  $c = $null; if ($bots[$name]) { $c = $bots[$name].color }
  if ($c -match '^#[0-9A-Fa-f]{6}$') { return $c }
  if ($DefaultColors[$name]) { return $DefaultColors[$name] }
  $h = 0; foreach ($ch in $name.ToCharArray()) { $h = ($h * 31 + [int]$ch) % 100003 }
  $Palette[$h % $Palette.Count]
}
function Get-BotId([string]$name, $bots) { if ($bots[$name]) { $bots[$name].id } else { '' } }

$script:hideTimer = New-Object Windows.Threading.DispatcherTimer
$script:hideTimer.Interval = [TimeSpan]::FromSeconds(60)
$script:hideTimer.Add_Tick({
  $script:hideTimer.Stop()
  # A -Show that is pending (signal not yet drained) cancels the close; tracker.ps1 relaunches if we exit anyway.
  if ($showEv.WaitOne(0)) { $script:showHold = $true; $script:dirty = $true; $script:raise = $true; return }
  $win.Close() })  # exits the process

function Add-Clickable($el, [string]$agentId, [string]$bot) {
  if (-not (Test-AgentId $agentId)) { $agentId = '' }
  $el.Cursor = [Windows.Input.Cursors]::Hand
  $el.ToolTip = "Open $bot chat"
  $el.Tag = $agentId   # empty -> Open-Chat just focuses Grok Bot
  $el.Add_MouseLeftButtonUp({ param($s, $e) Open-Chat ([string]$s.Tag); $e.Handled = $true })
}


function New-Text([string]$text, [double]$size, [string]$color, [string]$font = 'Segoe UI') {
  $tb = New-Object Windows.Controls.TextBlock; $tb.Text = $text; $tb.FontSize = $size; $tb.FontFamily = $font
  $tb.Foreground = Brush $color; $tb.TextWrapping = 'Wrap'; $tb
}
function New-StatusIcon([string]$status, [double]$size) {
  $ic = New-Text '' $size '#FF7D828A' 'Segoe MDL2 Assets'; $ic.Margin = '0,3,10,0'
  switch ($status) {
    'done'        { $ic.Text = [char]0xE73E; $ic.Foreground = Brush '#FF3FB950' }
    'in_progress' { $ic.Text = [char]0xE91F; $ic.Foreground = Brush '#FF4C8DFF' }
    'blocked'     { $ic.Text = [char]0xE7BA; $ic.Foreground = Brush '#FFF2A33A' }
    default       { $ic.Text = [char]0xE739 }
  }
  $ic
}
function Shade([string]$hex, [byte]$alpha) { '#{0:X2}{1}' -f $alpha, $hex.TrimStart('#') }

function New-Bubble($t, [string]$bot, [string]$color, [string]$agentId) {
  $status = Get-JobStatus $t
  $isDone = ($status -eq 'done')
  $subs = @($t.subtasks | ? { $_ })
  $card = New-Object Windows.Controls.Border
  $card.CornerRadius = '11'; $card.Margin = '0,5,0,5'; $card.Padding = '0'
  $card.BorderThickness = '1.25'; $card.BorderBrush = Brush (Shade $color 0x90)
  $g = New-Object Windows.Media.LinearGradientBrush; $g.StartPoint = '0,0'; $g.EndPoint = '0,1'
  $g.GradientStops.Add((New-Object Windows.Media.GradientStop ((Brush '#FF2B2F37').Color), 0))
  $g.GradientStops.Add((New-Object Windows.Media.GradientStop ((Brush '#FF1A1C21').Color), 1))
  $card.Background = $g
  $sh = New-Object Windows.Media.Effects.DropShadowEffect; $sh.BlurRadius = 7; $sh.ShadowDepth = 1.5; $sh.Opacity = 0.3; $sh.Direction = 270
  $card.Effect = $sh
  if ($isDone) { $card.Opacity = 0.55 }   # finished jobs are dimmed and crossed off
  $outer = New-Object Windows.Controls.Grid
  $hl = New-Object Windows.Controls.Border; $hl.CornerRadius = '10,10,0,0'; $hl.Height = 13; $hl.VerticalAlignment = 'Top'; $hl.IsHitTestVisible = $false
  $hg = New-Object Windows.Media.LinearGradientBrush; $hg.StartPoint = '0,0'; $hg.EndPoint = '0,1'
  $hg.GradientStops.Add((New-Object Windows.Media.GradientStop ((Brush '#22FFFFFF').Color), 0))
  $hg.GradientStops.Add((New-Object Windows.Media.GradientStop ((Brush '#00FFFFFF').Color), 1))
  $hl.Background = $hg
  $acc = New-Object Windows.Controls.Border; $acc.Width = 4; $acc.HorizontalAlignment = 'Left'; $acc.CornerRadius = '10,0,0,10'; $acc.Background = Brush $color
  $body = New-Object Windows.Controls.StackPanel; $body.Margin = '15,9,12,9'
  # Title row: [chevron] status dot, title, "X of Y"
  $row = New-Object Windows.Controls.DockPanel
  $id = [string]$t.id; $open = [bool]$script:expand[$id]
  if ($subs.Count) {
    $chev = New-Object Windows.Controls.Button; $chev.Width = 24; $chev.Height = 24; $chev.Padding = '0'; $chev.Margin = '0,0,4,0'
    $chev.Background = Brush '#00000000'; $chev.BorderThickness = '0'; $chev.Foreground = Brush '#FFD0D3D8'
    $chev.FontFamily = 'Segoe MDL2 Assets'; $chev.FontSize = 13; $chev.VerticalAlignment = 'Top'; $chev.Cursor = [Windows.Input.Cursors]::Hand
    $chev.Content = [char]$(if ($open) { 0xE70D } else { 0xE76C }); $chev.Tag = $id
    $chev.ToolTip = $(if ($open) { 'Hide subtasks' } else { "Show $($subs.Count) subtasks" })
    $chev.Add_Click({ param($s, $e) $k = [string]$s.Tag
      if ($script:expand[$k]) { $script:expand.Remove($k) } else { $script:expand[$k] = $true }
      Save-Settings; $script:dirty = $true; $e.Handled = $true })
    $chev.Add_PreviewMouseLeftButtonUp({ param($s, $e) $e.Handled = $false })
    [Windows.Controls.DockPanel]::SetDock($chev, 'Left'); [void]$row.Children.Add($chev)
  } else {
    $sp0 = New-Object Windows.Controls.Border; $sp0.Width = 28; [Windows.Controls.DockPanel]::SetDock($sp0, 'Left'); [void]$row.Children.Add($sp0)
  }
  $dot = New-Object Windows.Shapes.Ellipse; $dot.Width = 11; $dot.Height = 11; $dot.Margin = '0,7,9,0'; $dot.VerticalAlignment = 'Top'
  $dot.Stroke = Brush $(if ($status -eq 'blocked') { '#FFF2A33A' } else { $color }); $dot.StrokeThickness = 2
  $dot.Fill = Brush $(switch ($status) { 'done' { $color } 'in_progress' { Shade $color 0x80 } 'blocked' { '#FFF2A33A' } default { '#00000000' } })
  $dot.ToolTip = $status
  [Windows.Controls.DockPanel]::SetDock($dot, 'Left'); [void]$row.Children.Add($dot)
  if ($subs.Count) {
    $sd = @($subs | ? { $_.status -eq 'done' }).Count
    $ct = New-Text "$sd/$($subs.Count)" 13 '#FFB0B3B8'; $ct.Margin = '6,1,0,0'; $ct.VerticalAlignment = 'Top'
    [Windows.Controls.DockPanel]::SetDock($ct, 'Right'); [void]$row.Children.Add($ct)
  }
  $tt = New-Text ([string]$t.title) 16 $(if ($isDone) { '#FF9DA1A8' } else { '#FFF2F2F2' }) 'Segoe UI Semibold'
  if ($isDone) { $tt.TextDecorations = [Windows.TextDecorations]::Strikethrough }
  [void]$row.Children.Add($tt)
  [void]$body.Children.Add($row)
  if ($t.note) { $n = New-Text ([string]$t.note) 13 '#FF9DA1A8'; $n.Margin = '48,0,0,0'; [void]$body.Children.Add($n) }
  if ($subs.Count -and $open) {
    $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = '34,4,0,0'
    foreach ($st in $subs) {
      $sdn = ([string]$st.status -eq 'done')
      $sr = New-Object Windows.Controls.DockPanel; $sr.Margin = '0,2,0,2'
      if ($sdn) { $sr.Opacity = 0.6 }
      $si = New-StatusIcon ([string]$st.status) 13; $si.Margin = '0,3,8,0'; [Windows.Controls.DockPanel]::SetDock($si, 'Left'); [void]$sr.Children.Add($si)
      $sc = New-Object Windows.Controls.StackPanel
      $stt = New-Text ([string]$st.title) 14 $(if ($sdn) { '#FF8B9097' } else { '#FFE6E6E6' })
      if ($sdn) { $stt.TextDecorations = [Windows.TextDecorations]::Strikethrough }
      [void]$sc.Children.Add($stt)
      if ($st.note) { [void]$sc.Children.Add((New-Text ([string]$st.note) 13 '#FF7D828A')) }
      [void]$sr.Children.Add($sc); [void]$sp.Children.Add($sr)
    }
    [void]$body.Children.Add($sp)
  }
  [void]$outer.Children.Add($acc); [void]$outer.Children.Add($body); [void]$outer.Children.Add($hl)
  $card.Child = $outer
  Add-Clickable $card $agentId $bot
  $card
}
function Render {
  $d = Read-JsonFile $TrackerFile
  $tasks = @(); $title = 'Tasks'
  if ($d) { $tasks = @($d.tasks | ? { $_ }); if ($d.title) { $title = [string]$d.title } }
  # Jobs hidden by Clear finished stay hidden while unchanged.
  if ($d -and $script:hidden.Count) {
    $ids = @($tasks | % { [string]$_.id }); foreach ($k in @($script:hidden.Keys | ? { $_ -notin $ids })) { $script:hidden.Remove($k) }
    $tasks = @($tasks | ? { $k = [string]$_.id; if ($script:hidden.ContainsKey($k)) { if ($script:hidden[$k] -eq (Get-JobKey $_)) { $false } else { $script:hidden.Remove($k); $true } } else { $true } })
  }
  # Forget the expanded state of jobs that are no longer in the list (only when the list was read).
  if ($d) {
    $ids = @($tasks | % { [string]$_.id })
    $gone = @($script:expand.Keys | ? { $_ -notin $ids })
    if ($gone.Count) { foreach ($k in $gone) { $script:expand.Remove($k) }; Save-Settings }
  }
  $bots = Get-Bots
  $done = @($tasks | ? { (Get-JobStatus $_) -eq 'done' }).Count; $total = $tasks.Count
  $allSubs = @($tasks | % { @($_.subtasks | ? { $_ }) }); $subDone = @($allSubs | ? { $_.status -eq 'done' }).Count
  $c.TitleText.Text = $title
  $c.Bar.Maximum = [Math]::Max(1, $total); $c.Bar.Value = $done
  $allDone = ($total -gt 0 -and $done -eq $total)
  $c.CountText.Text = if ($allDone) { "All done  -  $done of $total" } elseif ($total -eq 0) { 'No tasks' } else { "$done of $total done" }
  $c.SubCountText.Text = if ($allSubs.Count) { "$subDone of $($allSubs.Count) subtasks done" } else { '' }
  $c.SubCountText.Visibility = $(if ($allSubs.Count) { 'Visible' } else { 'Collapsed' })
  $c.Bar.Foreground = Brush $(if ($allDone) { '#FF3FB950' } else { '#FF4C8DFF' })
  $scrollY = $c.Scroll.VerticalOffset
  $c.List.Children.Clear()
  $mine = @($tasks | ? { -not $_.owner }); $deleg = @($tasks | ? { $_.owner })
  # Owner of un-delegated jobs: tracker.json top-level "owner" (default Grok Bot).
  $me = if ($d -and $d.owner) { [string]$d.owner } else { 'Grok Bot' }; $meColor = Get-BotColor $me $bots
  foreach ($g in ($mine | % { if ($_.group) { [string]$_.group } else { 'General' } } | Select -Unique)) {
    $h = New-Text $g.ToUpper() 12 '#FF8B9097' 'Segoe UI Semibold'; $h.Margin = '2,10,0,2'; [void]$c.List.Children.Add($h)
    foreach ($t in @($mine | ? { $(if ($_.group) { [string]$_.group } else { 'General' }) -eq $g })) {
      $aid = if (Test-AgentId $t.agentId) { $t.agentId } else { Get-BotId $me $bots }
      [void]$c.List.Children.Add((New-Bubble $t $me $meColor $aid))
    }
  }
  if ($deleg.Count) {
    $dh = New-Text 'Delegated' 17 '#FF8AB4FF' 'Segoe UI Semibold'; $dh.Margin = '2,14,0,3'; [void]$c.List.Children.Add($dh)
    $line = New-Object Windows.Controls.Border; $line.Height = 2; $line.Background = Brush '#FF4C8DFF'; $line.Margin = '0,0,0,5'; $line.CornerRadius = '1'
    [void]$c.List.Children.Add($line)
    foreach ($o in ($deleg | % { [string]$_.owner } | Select -Unique)) {
      $oc = Get-BotColor $o $bots; $ojobs = @($deleg | ? { [string]$_.owner -eq $o })
      $oid = ($ojobs | ? { Test-AgentId $_.agentId } | Select -First 1).agentId; if (-not $oid) { $oid = Get-BotId $o $bots }
      $oh = New-Text $o 14 $oc 'Segoe UI Semibold'; $oh.Margin = '4,7,0,0'; $oh.Background = Brush '#00000000'
      Add-Clickable $oh $oid $o; [void]$c.List.Children.Add($oh)
      foreach ($t in $ojobs) {
        $aid = if (Test-AgentId $t.agentId) { $t.agentId } else { $oid }
        [void]$c.List.Children.Add((New-Bubble $t $o $oc $aid))
      }
    }
  }
  # All done: close after 60 s, unless a -Show asked for the window (showHold). The hold ends when the list has open jobs again.
  if (-not $allDone) { $script:showHold = $false }
  if ($allDone -and -not $script:showHold) { $script:hideTimer.Stop(); $script:hideTimer.Start() } else { $script:hideTimer.Stop() }
  $c.Scroll.UpdateLayout(); $c.Scroll.ScrollToVerticalOffset($scrollY)
}

# Only for an explicit -Show (named show event): restore if minimized and raise without taking focus.
function Bring-Front {
  if ($win.WindowState -eq 'Minimized') { $win.WindowState = 'Normal' }
  $h = (New-Object Windows.Interop.WindowInteropHelper $win).Handle
  # SWP_NOMOVE|NOSIZE|NOACTIVATE. Pinned: re-assert topmost. Unpinned: HWND_TOP only, never topmost.
  $after = if ($pinned) { [IntPtr](-1) } else { [IntPtr]::Zero }
  [TrkWin]::SetWindowPos($h, $after, 0, 0, 0, 0, 0x13) | Out-Null
}

# Live refresh: FileSystemWatcher on the tracker folder (started once the folder exists; the window never creates it).
$script:dirty = $false; $script:raise = $false
$script:showHold = $true   # this process was started by -Show, so an all-done list stays open until it has open jobs again
$script:fsw = $null
function Start-Watch {
  if ($script:fsw -or -not (Test-Path -LiteralPath $TrackerDir)) { return }
  $script:fsw = New-Object IO.FileSystemWatcher $TrackerDir
  $script:fsw.NotifyFilter = 'LastWrite, FileName, Size'
  $script:fsw.EnableRaisingEvents = $true
  # Events are queued by PowerShell (no cross-thread callbacks) and drained on the UI timer below.
  Register-ObjectEvent $script:fsw Changed -SourceIdentifier TrkChanged | Out-Null
  Register-ObjectEvent $script:fsw Created -SourceIdentifier TrkCreated | Out-Null
  Register-ObjectEvent $script:fsw Renamed -SourceIdentifier TrkRenamed | Out-Null
  $script:dirty = $true
}
Start-Watch
$poll = New-Object Windows.Threading.DispatcherTimer
$poll.Interval = [TimeSpan]::FromMilliseconds(400)
$poll.Add_Tick({
  if (-not $script:fsw) { Start-Watch }
  foreach ($ev in @(Get-Event -ErrorAction SilentlyContinue | ? { $_.SourceIdentifier -like 'Trk*' })) {
    if ($ev.SourceEventArgs.Name -in 'tracker.json','bots.json') { $script:dirty = $true }
    Remove-Event -EventIdentifier $ev.EventIdentifier
  }
  if ($showEv.WaitOne(0)) { $script:showHold = $true; $script:hideTimer.Stop(); $script:dirty = $true; $script:raise = $true }
  if ($script:dirty) { $script:dirty = $false; try { Render } catch { } }
  if ($script:raise) { $script:raise = $false; try { Bring-Front } catch { } } })
$poll.Start()

Render
if ($script:migrate) { Save-Settings }   # one-time copy of an old settings.json into the registry (the file is left alone)
$win.Add_ContentRendered({ Bring-Front })
$app = New-Object Windows.Application
$app.ShutdownMode = 'OnExplicitShutdown'
$win.Add_Closed({ $app.Shutdown() })
[void]$app.Run($win)
$mutex.ReleaseMutex()
