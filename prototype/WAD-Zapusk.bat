@echo off
rem ===========================================================================
rem  WAD prototype launcher.
rem  Starts the full demo flow: intro titles -> install window -> report in
rem  Documents -> simulated reboot -> post-boot window with user creation.
rem  Nothing is downloaded, installed or changed in the system.
rem  Press Esc at any moment to quit the demo.
rem  (ASCII only on purpose: cmd.exe misreads Cyrillic in .bat files.)
rem ===========================================================================

cd /d "%~dp0"
chcp 65001 >nul

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell"

"%PS%" -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0WAD-Prototype.ps1" %*

echo.
echo Demo finished. Press any key to close this window.
pause >nul
