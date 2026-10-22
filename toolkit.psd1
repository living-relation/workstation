# Workstation toolkit names: the ONE place to change when the toolkit or its scripts are renamed.
# Read by install.ps1, install-admin.ps1, uninstall.ps1 and preflight.ps1. Script paths are relative to the toolkit.
@{
  # The toolkit runs straight from this package (the workstation repo clone, normally <Projects>\active\workstation):
  # PackageFolder is the folder inside the package that holds the scripts. Nothing is copied under <Projects>.
  PackageFolder      = 'workstation'
  # Folders under <Projects> that held an installed COPY of the toolkit in older setups: '_bridge' (until 2026-10-08)
  # and '_workstation' (until the toolkit ran from the repo clone). Preflight and Workstation Status WARN while one
  # still exists; install never moves or deletes it (stop its workers, then archive it by hand).
  LegacyFolders      = @('_bridge', '_workstation')

  # Per-user runtime folder under %LOCALAPPDATA% (never inside the clone): the config file install.ps1 writes
  # (ConfigFile: projectsRoot), the Workers Stop flag and the Cursor worker's logs, state and sqlite cache.
  StateFolder        = 'Workstation'
  ConfigFile         = 'workstation.json'

  # Scripts inside the toolkit.
  ShortcutsInstaller = 'shortcuts\install-shortcuts.ps1'
  CommonScript       = 'shortcuts\workstation-common.ps1'
  PullScript         = ''  # was repo-pull.ps1; do not recreate batch pull
  StatusScript       = 'repo-status.ps1'
  WorkerFolder       = 'cursor-worker'

  # Shortcuts that ShortcutsInstaller creates (link name -> script). ShortcutFolder is a folder INSIDE this package
  # (the workstation repo clone), relative to the package root, so no personal path is stored; the generated .lnk
  # files are gitignored. install.ps1 passes the resolved folder to ShortcutsInstaller as -LinkDir.
  ShortcutFolder     = 'shortcuts'
  # Icon = index in shell32.dll; Args = extra arguments after -File <script>.
  Shortcuts          = @(
    @{ Name = 'Workers Start';      Script = 'shortcuts\workers-start.ps1';      Icon = 137 }
    @{ Name = 'Workers Stop';       Script = 'shortcuts\workers-stop.ps1';       Icon = 131 }
    @{ Name = 'Workstation Status'; Script = 'shortcuts\workstation-status.ps1'; Icon = 23 }
    @{ Name = 'Dashboard';          Script = 'shortcuts\dashboard.ps1';          Icon = 13 }
    @{ Name = 'Desktop Commander Remote Start'; Script = 'desktop-commander-remote\start-dc-remote.ps1'; Args = '-Show'; Icon = 137 }
    @{ Name = 'Desktop Commander Remote Stop';  Script = 'desktop-commander-remote\stop-dc-remote.ps1';  Icon = 131 }
  )

  # Sign-in links that ShortcutsInstaller puts in the user's Startup folder (install.ps1 passes -StartupDir).
  # Hidden = start through desktop-commander-remote\run-hidden.vbs (wscript, no window). A link of the same name
  # is only replaced when it already runs the same script file name (from any folder: older copies under
  # %LOCALAPPDATA% or a worktree); it is backed up first. Anything else is left alone with a warning.
  StartupLinks       = @(
    @{ Name = 'Desktop Commander Remote'; Script = 'desktop-commander-remote\start-dc-remote.ps1'; Hidden = $true }
    @{ Name = 'Dashboard';                Script = 'dashboard\start-dashboard.ps1'; Args = '-NoPause' }
  )

  # Old Desktop shortcut folders: 'Bridge' (before the rename) and 'Workstation' (Desktop location before the links
  # moved into the package). Preflight reports them as legacy (WARN); the shortcuts installer removes only links in
  # them that run the toolkit scripts, then the folder once it is empty.
  LegacyShortcutFolders = @('Bridge', 'Workstation')
  LegacyShortcutNames   = @('Bridge Start', 'Bridge Stop', 'Bridge Status', 'Pull All', 'Push All')
  # Old script file names: shortcuts\bridge-start/stop/status/common, pull-all, push-all; root sync-pull, sync-status, git-branch.
  LegacyScripts         = @('bridge-start.ps1', 'bridge-stop.ps1', 'bridge-status.ps1', 'bridge-common.ps1', 'pull-all.ps1', 'push-all.ps1', 'sync-pull.ps1', 'sync-status.ps1', 'git-branch.ps1')
}
