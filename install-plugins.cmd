@echo off
rem Manual plugin install. Path-independent. Does not start at sign-in.
cd /d "%~dp0"
echo.
echo Opening claude.ai Plugins and copying the Cursor plugin from %CD% ...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File install-plugins.ps1 %*
set "EXITCODE=%ERRORLEVEL%"
echo.
echo install-plugins.ps1 exit %EXITCODE%
echo.
pause
exit /b %EXITCODE%
