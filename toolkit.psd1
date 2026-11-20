# Workstation toolkit names: the ONE place to change when the toolkit or its scripts are renamed.
# Read by install.ps1, uninstall.ps1 and preflight.ps1. Script paths are relative to the toolkit.
@{
  # The toolkit runs straight from this package (the workstation repo clone, normally <Projects>\active\workstation):
  # PackageFolder is the folder inside the package that holds the scripts. Nothing is copied under <Projects>.
  PackageFolder      = 'workstation'
  # Folders under <Projects> that held an installed COPY of the toolkit in older setups: '_bridge' (until 2026-10-08)
  # and '_workstation' (until the toolkit ran from the repo clone). Preflight and Health check WARN while one
  # still exists; install never moves or deletes it (stop anything still running from it, then archive it by hand).
  LegacyFolders      = @('_bridge', '_workstation')

  # Per-user runtime folder under %LOCALAPPDATA% (never inside the clone): the config file install.ps1 writes
  # (ConfigFile: projectsRoot) and logs.
  StateFolder        = 'Workstation'
  ConfigFile         = 'workstation.json'

  CommonScript       = 'health\workstation-common.ps1'
  HealthScript       = 'health\workstation-status.ps1'
  StatusScript       = 'repo-status.ps1'
  ShortcutsInstaller = 'make-shortcuts.ps1'

  # Manual shortcuts only. make-shortcuts.ps1 writes them in ShortcutFolder (gitignored .lnk files).
  # Nothing in this list starts at sign-in. No Startup item and no Run key.
  # No scheduled task either: the Fusion add-in updater is manual only (Update Fusion add-ins).
  ShortcutFolder     = 'shortcuts'
  Shortcuts          = @(
    @{ Name = 'Health check'; Script = 'health\workstation-status.ps1'; Icon = 23 }
    @{ Name = 'Start Cursor worker'; Script = 'cursor-worker\start-cursor-worker.ps1'; Icon = 137 }
    @{ Name = 'Stop Cursor worker';  Script = 'cursor-worker\stop-cursor-worker.ps1'; Icon = 131 }
    @{ Name = 'Start Desktop Commander'; Script = 'desktop-commander-remote\start-dc-remote.ps1'; Args = '-Show'; Icon = 137 }
    @{ Name = 'Stop Desktop Commander';  Script = 'desktop-commander-remote\stop-dc-remote.ps1'; Icon = 131 }
    @{ Name = 'DC remote status';        Script = 'desktop-commander-remote\dc-remote-status.ps1'; Icon = 23 }
    @{ Name = 'Kill orphaned remote processes'; Script = 'kill-orphans.ps1'; Icon = 131 }
    @{ Name = 'Skills drift'; Script = 'skills-drift.ps1'; Icon = 23 }
    @{ Name = 'Update Fusion add-ins'; Script = 'fusion-addins\update-fusion-addins.ps1'; Args = '-Pause'; Icon = 238 }
  )

  # No sign-in links. An old Startup link that still runs the start script is removed (backup first).
  StartupLinks        = @()
  RetiredStartupLinks = @(
    @{ Name = 'Desktop Commander Remote'; Script = 'start-dc-remote.ps1' }
  )

  LegacyShortcutFolders = @('Bridge', 'Workstation')
  LegacyShortcutNames   = @('Bridge Start', 'Bridge Stop', 'Bridge Status')
  LegacyScripts         = @('bridge-start.ps1', 'bridge-stop.ps1', 'bridge-status.ps1', 'bridge-common.ps1')
}
