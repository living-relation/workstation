# Workstation toolkit names: the ONE place to change when the toolkit or its scripts are renamed.
# Read by install.ps1, install-admin.ps1, uninstall.ps1 and preflight.ps1. Script paths are relative to the toolkit.
@{
  # Folder under <Projects> the toolkit is copied to, and the folder inside this package that holds it.
  ToolkitFolder      = '_workstation'
  PackageFolder      = 'workstation'
  # Older names of the toolkit folder (it was _bridge until 2026-10-08). If one still exists next to the current
  # one, preflight WARNs (legacy); install never moves or deletes it.
  LegacyFolders      = @('_bridge')

  # Scripts inside the toolkit.
  ShortcutsInstaller = 'shortcuts\install-shortcuts.ps1'
  LatchRegister      = 'latch\register-ensure-grokbot-task.ps1'
  CommonScript       = 'shortcuts\workstation-common.ps1'
  PullScript         = ''  # was repo-pull.ps1; do not recreate batch pull
  StatusScript       = 'repo-status.ps1'
  WorkerFolder       = 'cursor-worker'

  # Shortcuts that ShortcutsInstaller creates (link name -> script). ShortcutFolder is a folder INSIDE this package
  # (the workstation repo clone), relative to the package root, so no personal path is stored; the generated .lnk
  # files are gitignored. install.ps1 passes the resolved folder to ShortcutsInstaller as -LinkDir.
  ShortcutFolder     = 'shortcuts'
  Shortcuts          = @(
    @{ Name = 'Workers Start';      Script = 'shortcuts\workers-start.ps1' }
    @{ Name = 'Workers Stop';       Script = 'shortcuts\workers-stop.ps1' }
    @{ Name = 'Workstation Status'; Script = 'shortcuts\workstation-status.ps1' }
  )

  # Old Desktop shortcut folders: 'Bridge' (before the rename) and 'Workstation' (Desktop location before the links
  # moved into the package). Preflight reports them as legacy (WARN); the shortcuts installer removes only links in
  # them that run the toolkit scripts, then the folder once it is empty.
  LegacyShortcutFolders = @('Bridge', 'Workstation')
  LegacyShortcutNames   = @('Bridge Start', 'Bridge Stop', 'Bridge Status', 'Pull All', 'Push All')
  # Old script file names: shortcuts\bridge-start/stop/status/common, pull-all, push-all; root sync-pull, sync-status, git-branch.
  LegacyScripts         = @('bridge-start.ps1', 'bridge-stop.ps1', 'bridge-status.ps1', 'bridge-common.ps1', 'pull-all.ps1', 'push-all.ps1', 'sync-pull.ps1', 'sync-status.ps1', 'git-branch.ps1')
}
