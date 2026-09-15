@echo off
rem ===========================================================================
rem  WAD prototype launcher.
rem  Starts the full demo flow: intro titles -> install window -> report in
rem  Documents -> simulated reboot -> post-boot window with user creation.
rem  Nothing is downloaded, installed or changed in the system.
rem  Press Esc at any moment to quit the demo.
rem ===========================================================================

cd /d "%~dp0"
chcp 65001 >nul

set "SCRIPT=%~dp0WAD-Prototype.ps1"
if not exist "%SCRIPT%" if exist "%~dp0prototype\WAD-Prototype.ps1" set "SCRIPT=%~dp0prototype\WAD-Prototype.ps1"

if not exist "%SCRIPT%" (
    echo.
    echo Рядом с WAD-Zapusk.bat не найден WAD-Prototype.ps1.
    echo.
    echo Это пара файлов: bat только запускает скрипт, сам он лежит рядом.
    echo Положи WAD-Prototype.ps1 в ту же папку, что и bat, и запусти снова.
    echo Если файл сохранился как "WAD-Prototype.ps1.txt" - переименуй,
    echo убрав ".txt" на конце.
    echo.
    echo Ожидался файл: %~dp0WAD-Prototype.ps1
    echo.
    pause
    exit /b 1
)

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell"

"%PS%" -NoProfile -ExecutionPolicy Bypass -STA -File "%SCRIPT%" %*

echo.
echo Демо завершено. Любая клавиша - закрыть это окно.
pause >nul
