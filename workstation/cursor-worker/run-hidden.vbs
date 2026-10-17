' Launch a PowerShell script with no window at all (wscript has no console, so nothing flashes).
' Usage: wscript.exe //B //Nologo run-hidden.vbs "C:\path\script.ps1" [script args...]
Set sh = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & WScript.Arguments(0) & """"
For i = 1 To WScript.Arguments.Count - 1
  cmd = cmd & " " & WScript.Arguments(i)
Next
WScript.Quit sh.Run(cmd, 0, True)
