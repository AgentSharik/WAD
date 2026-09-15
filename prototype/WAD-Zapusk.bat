@echo off
rem ===========================================================================
rem  WAD prototype launcher.
rem  Demo: titles -> install window -> report -> fake reboot -> user window.
rem  Nothing is downloaded or installed. Esc - quit.
rem  Saved in cp866 on purpose: cmd.exe misparses UTF-8 Cyrillic inside blocks.
rem ===========================================================================

cd /d "%~dp0"

set "SCRIPT=%~dp0WAD-Prototype.ps1"
if not exist "%SCRIPT%" if exist "%~dp0prototype\WAD-Prototype.ps1" set "SCRIPT=%~dp0prototype\WAD-Prototype.ps1"

if not exist "%SCRIPT%" (
    echo.
    echo Рядом с WAD-Zapusk.bat не найден WAD-Prototype.ps1.
    echo Положи оба файла в одну папку и запусти снова.
    echo Если файл сохранился как "WAD-Prototype.ps1.txt" - переименуй, убрав ".txt".
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
