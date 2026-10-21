# Live task tracker window (read-only). Started by: tracker.ps1 -Show. Single instance (named mutex).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tracker-common.ps1')
$created = $false
$mutex = New-Object Threading.Mutex($true, $TrackerWindowMutex, [ref]$created)
if (-not $created) { [IO.File]::WriteAllText((Join-Path $TrackerDir 'show.signal'), (Get-Date).ToString('o')); exit 0 }
Initialize-TrackerDir
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Tasks" Width="320" Height="400" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowActivated="False" ShowInTaskbar="True" ResizeMode="CanResizeWithGrip">
  <Border Background="#FF111214" BorderBrush="#FF2A2C31" BorderThickness="1" CornerRadius="10">
    <DockPanel>
      <Grid x:Name="TitleBar" DockPanel.Dock="Top" Height="34" Background="Transparent">
        <TextBlock x:Name="TitleText" Margin="12,0,90,0" VerticalAlignment="Center" Foreground="#FFECECEC"
                   FontFamily="Segoe UI Semibold" FontSize="13" TextTrimming="CharacterEllipsis"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,0,6,0">
          <Button x:Name="PinBtn" Width="26" Height="24" Background="Transparent" BorderThickness="0" Foreground="#FFB0B3B8" FontFamily="Segoe MDL2 Assets" FontSize="12" Cursor="Hand"/>
          <Button x:Name="MinBtn" Width="26" Height="24" Background="Transparent" BorderThickness="0" Foreground="#FFB0B3B8" FontFamily="Segoe MDL2 Assets" FontSize="10" Content="&#xE921;" ToolTip="Minimize" Cursor="Hand"/>
          <Button x:Name="CloseBtn" Width="26" Height="24" Background="Transparent" BorderThickness="0" Foreground="#FFB0B3B8" FontFamily="Segoe MDL2 Assets" FontSize="10" Content="&#xE8BB;" ToolTip="Close" Cursor="Hand"/>
        </StackPanel>
      </Grid>
      <StackPanel DockPanel.Dock="Top" Margin="12,0,12,8">
        <TextBlock x:Name="CountText" Foreground="#FF9DA1A8" FontFamily="Segoe UI" FontSize="11" Margin="0,0,0,4"/>
        <ProgressBar x:Name="Bar" Height="4" Minimum="0" Maximum="1" Background="#FF2A2C31" Foreground="#FF4C8DFF" BorderThickness="0"/>
      </StackPanel>
      <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="4,0,4,8">
        <StackPanel x:Name="List" Margin="8,0,8,0"/>
      </ScrollViewer>
    </DockPanel>
  </Border>
</Window>
'@
$win = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xaml))
$c = @{}; foreach ($n in 'TitleBar','TitleText','PinBtn','MinBtn','CloseBtn','CountText','Bar','List') { $c[$n] = $win.FindName($n) }
$bc = New-Object Windows.Media.BrushConverter
function Brush($h) { $bc.ConvertFromString($h) }

# Settings: pin state + position
$settings = Read-JsonFile $TrackerSettings
$pinned = $true
if ($settings) {
  if ($null -ne $settings.pinned) { $pinned = [bool]$settings.pinned }
  if ($null -ne $settings.left -and $null -ne $settings.top) {
    $l = [double]$settings.left; $t = [double]$settings.top
    $sw = [Windows.SystemParameters]::VirtualScreenWidth + [Windows.SystemParameters]::VirtualScreenLeft
    $sh = [Windows.SystemParameters]::VirtualScreenHeight + [Windows.SystemParameters]::VirtualScreenTop
    if ($l -lt $sw - 40 -and $t -lt $sh - 40 -and $l -gt [Windows.SystemParameters]::VirtualScreenLeft - 280) { $win.WindowStartupLocation = 'Manual'; $win.Left = $l; $win.Top = $t }
  }
  if ($settings.width) { $win.Width = [double]$settings.width }; if ($settings.height) { $win.Height = [double]$settings.height }
}
if ($win.WindowStartupLocation -ne 'Manual') {
  $wa = [Windows.SystemParameters]::WorkArea; $win.WindowStartupLocation = 'Manual'
  $win.Left = $wa.Right - $win.Width - 16; $win.Top = $wa.Bottom - $win.Height - 16
}
function Save-Settings { try { Write-JsonAtomic $TrackerSettings ([ordered]@{ pinned = $pinned; left = $win.Left; top = $win.Top; width = $win.Width; height = $win.Height }) } catch { } }
function Set-Pin { $win.Topmost = $pinned
  if ($pinned) { $c.PinBtn.Content = [char]0xE841; $c.PinBtn.Foreground = Brush '#FF4C8DFF'; $c.PinBtn.ToolTip = 'Pinned on top (click to unpin)' }
  else { $c.PinBtn.Content = [char]0xE718; $c.PinBtn.Foreground = Brush '#FFB0B3B8'; $c.PinBtn.ToolTip = 'Not on top (click to pin)' } }
Set-Pin

$c.TitleBar.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch { }; Save-Settings })
$c.PinBtn.Add_Click({ $script:pinned = -not $script:pinned; Set-Pin; Save-Settings })
$c.MinBtn.Add_Click({ $win.WindowState = 'Minimized' })
$c.CloseBtn.Add_Click({ $win.Close() })
$win.Add_Closing({ Save-Settings })

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
  if ($agentId -and (Test-Path 'Registry::HKEY_CLASSES_ROOT\grokbot')) {
    try { Start-Process "grokbot://app/v1/agent?id=$agentId"; $ok = $true } catch { }
  }
  if (-not $ok) {
    $p = Get-Process -Name 'Grok Bot' -ErrorAction SilentlyContinue | ? { $_.MainWindowHandle -ne 0 } | Select -First 1
    if ($p) { [TrkWin]::ShowWindow($p.MainWindowHandle, 9) | Out-Null; [TrkWin]::SetForegroundWindow($p.MainWindowHandle) | Out-Null }
  }
}
function Get-Bots { $m = @{}; $b = Read-JsonFile $TrackerBots; if ($b) { foreach ($p in $b.PSObject.Properties) { $m[$p.Name] = [string]$p.Value } }; $m }

$script:hideTimer = New-Object Windows.Threading.DispatcherTimer
$script:hideTimer.Interval = [TimeSpan]::FromSeconds(60)
$script:hideTimer.Add_Tick({ $script:hideTimer.Stop(); $win.Hide() })

function Add-Clickable($el, [string]$agentId, [string]$bot) {
  if (-not $agentId) { return }
  $el.Cursor = [Windows.Input.Cursors]::Hand
  $el.ToolTip = "Open $bot chat"
  $el.Tag = $agentId
  $el.Add_MouseLeftButtonUp({ param($s, $e) Open-Chat ([string]$s.Tag); $e.Handled = $true })
}

function Render {
  $d = Read-JsonFile $TrackerFile
  $tasks = @(); $title = 'Tasks'
  if ($d) { $tasks = @($d.tasks | ? { $_ }); if ($d.title) { $title = [string]$d.title } }
  $bots = Get-Bots
  $done = @($tasks | ? { $_.status -eq 'done' }).Count; $total = $tasks.Count
  $c.TitleText.Text = $title
  $c.Bar.Maximum = [Math]::Max(1, $total); $c.Bar.Value = $done
  $allDone = ($total -gt 0 -and $done -eq $total)
  $c.CountText.Text = if ($allDone) { "All done  -  $done of $total" } elseif ($total -eq 0) { 'No tasks' } else { "$done of $total done" }
  $c.Bar.Foreground = Brush $(if ($allDone) { '#FF3FB950' } else { '#FF4C8DFF' })
  $c.List.Children.Clear()
  # Own tasks grouped by group; tasks with an owner go under "Delegated", by owner.
  $mine = @($tasks | ? { -not $_.owner }); $deleg = @($tasks | ? { $_.owner })
  $sections = New-Object Collections.ArrayList
  foreach ($g in ($mine | % { if ($_.group) { [string]$_.group } else { 'General' } } | Select -Unique)) {
    [void]$sections.Add(@{ Head = $g; Tasks = @($mine | ? { $(if ($_.group) { [string]$_.group } else { 'General' }) -eq $g }); Owner = $null })
  }
  if ($deleg.Count) {
    [void]$sections.Add(@{ Head = 'Delegated'; Tasks = @(); Owner = $null })
    foreach ($o in ($deleg | % { [string]$_.owner } | Select -Unique)) {
      [void]$sections.Add(@{ Head = $o; Tasks = @($deleg | ? { [string]$_.owner -eq $o }); Owner = $o })
    }
  }
  foreach ($s in $sections) {
    $h = New-Object Windows.Controls.TextBlock
    $h.Text = $s.Head.ToUpper(); $h.FontFamily = 'Segoe UI Semibold'; $h.FontSize = 10
    $h.Foreground = Brush $(if ($s.Owner) { '#FF8AB4FF' } else { '#FF7D828A' })
    $h.Margin = $(if ($s.Owner) { '8,6,0,2' } else { '0,10,0,2' })
    $h.Background = Brush '#00000000'
    if ($s.Owner) { $aid = ($s.Tasks | ? { $_.agentId } | Select -First 1).agentId; if (-not $aid) { $aid = $bots[$s.Owner] }; Add-Clickable $h $aid $s.Owner }
    [void]$c.List.Children.Add($h)
    foreach ($t in $s.Tasks) {
      $row = New-Object Windows.Controls.Grid; $row.Margin = $(if ($s.Owner) { '8,3,0,3' } else { '0,3,0,3' }); $row.Background = Brush '#00000000'
      [void]$row.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{ Width = '22' }))
      [void]$row.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
      $ic = New-Object Windows.Controls.TextBlock; $ic.FontFamily = 'Segoe MDL2 Assets'; $ic.FontSize = 12; $ic.Margin = '0,2,0,0'
      switch ([string]$t.status) {
        'done'        { $ic.Text = [char]0xE73E; $ic.Foreground = Brush '#FF3FB950' }
        'in_progress' { $ic.Text = [char]0xE91F; $ic.Foreground = Brush '#FF4C8DFF' }
        'blocked'     { $ic.Text = [char]0xE7BA; $ic.Foreground = Brush '#FFF2A33A' }
        default       { $ic.Text = [char]0xE739; $ic.Foreground = Brush '#FF7D828A' }
      }
      $sp = New-Object Windows.Controls.StackPanel; [Windows.Controls.Grid]::SetColumn($sp, 1)
      $tt = New-Object Windows.Controls.TextBlock; $tt.Text = [string]$t.title; $tt.TextWrapping = 'Wrap'; $tt.FontFamily = 'Segoe UI'; $tt.FontSize = 12
      $tt.Foreground = Brush $(if ($t.status -eq 'done') { '#FF8B9097' } else { '#FFECECEC' })
      [void]$sp.Children.Add($tt)
      if ($t.note) { $nt = New-Object Windows.Controls.TextBlock; $nt.Text = [string]$t.note; $nt.TextWrapping = 'Wrap'; $nt.FontSize = 10; $nt.FontFamily = 'Segoe UI'; $nt.Foreground = Brush '#FF7D828A'; [void]$sp.Children.Add($nt) }
      [void]$row.Children.Add($ic); [void]$row.Children.Add($sp)
      $aid = $t.agentId; $bn = if ($t.owner) { [string]$t.owner } else { 'Grok Bot' }
      if (-not $aid) { $aid = $bots[$bn] }
      Add-Clickable $row $aid $bn
      [void]$c.List.Children.Add($row)
    }
  }
  if ($allDone) { $script:hideTimer.Stop(); $script:hideTimer.Start() } else { $script:hideTimer.Stop() }
}

function Bring-Front {
  if (-not $win.IsVisible) { $win.Show() }
  if ($win.WindowState -eq 'Minimized') { $win.WindowState = 'Normal' }
  $h = (New-Object Windows.Interop.WindowInteropHelper $win).Handle
  # HWND_TOPMOST then restore state; SWP_NOMOVE|NOSIZE|NOACTIVATE so focus is not stolen.
  [TrkWin]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x13) | Out-Null
  if (-not $pinned) { [TrkWin]::SetWindowPos($h, [IntPtr](-2), 0, 0, 0, 0, 0x13) | Out-Null }
}

# Live refresh: FileSystemWatcher on the tracker folder; changes are applied on the UI thread.
$script:dirty = $false
$fsw = New-Object IO.FileSystemWatcher $TrackerDir
$fsw.NotifyFilter = 'LastWrite, FileName, Size'
$fsw.EnableRaisingEvents = $true
# Events are queued by PowerShell (no cross-thread callbacks) and drained on the UI timer below.
Register-ObjectEvent $fsw Changed -SourceIdentifier TrkChanged | Out-Null
Register-ObjectEvent $fsw Created -SourceIdentifier TrkCreated | Out-Null
Register-ObjectEvent $fsw Renamed -SourceIdentifier TrkRenamed | Out-Null
$poll = New-Object Windows.Threading.DispatcherTimer
$poll.Interval = [TimeSpan]::FromMilliseconds(400)
$poll.Add_Tick({
  foreach ($ev in @(Get-Event -ErrorAction SilentlyContinue | ? { $_.SourceIdentifier -like 'Trk*' })) {
    if ($ev.SourceEventArgs.Name -in 'tracker.json','show.signal','bots.json') { $script:dirty = $true }
    Remove-Event -EventIdentifier $ev.EventIdentifier
  }
  if ($script:dirty) { $script:dirty = $false; try { Render; Bring-Front } catch { } } })
$poll.Start()

Render
$win.Add_ContentRendered({ Bring-Front })
$app = New-Object Windows.Application
$app.ShutdownMode = 'OnExplicitShutdown'
$win.Add_Closed({ $app.Shutdown() })
[void]$app.Run($win)
$mutex.ReleaseMutex()
