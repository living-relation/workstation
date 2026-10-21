' Launch a PowerShell script with no window at all (wscript has no console, so nothing flashes).
' Usage: wscript.exe //B //Nologo run-hidden.vbs "C:\path\script.ps1"
Set sh = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & WScript.Arguments(0) & """"
WScript.Quit sh.Run(cmd, 0, False)
