' Runs the Claude-to-Cursor memory sync with no window (wscript has no console, so nothing flashes).
' Used by the scheduled task Claude-Memory-To-Cursor-Sync. Modeled on _workstation\run-hidden.vbs.
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
script = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "sync-claude-memory-to-cursor.ps1")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & script & """"
WScript.Quit sh.Run(cmd, 0, True)