@echo off
rem Run this clone's install.ps1. Path-independent. Arguments go through unchanged.
cd /d "%~dp0"
echo.
echo Installing %CD% ...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 %*
set "EXITCODE=%ERRORLEVEL%"
echo.
echo install.ps1 exit %EXITCODE%
echo.
pause
exit /b %EXITCODE%
