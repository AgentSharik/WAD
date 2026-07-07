# =========================================================================
# Имя файла: reset-setup-scripts.ps1
# Назначение: Очистка системы и приведение папки Setup\Scripts к состоянию чистой Windows
# Оптимизация: Полное удаление сторонних скриптов автоматизации и твиков
# Режим работы: Камикадзе (полное самоуничтожение вместе с родительской папкой)
# =========================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# =========================================================================
# ЭТАП 1: ИНИЦИАЛИЗАЦИЯ И ЛОГИРОВАНИЕ
# =========================================================================

# Проверка прав Администратора
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "ОШИБКА: Скрипт необходимо запустить от имени Администратора!"
    Start-Sleep -Seconds 5
    Exit
}

# Настройка папки логов в безопасном месте (Документы текущего профиля)
$UserProfile = $env:USERPROFILE
$LogDir = Join-Path $UserProfile "Documents"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
Start-Transcript -Path (Join-Path $LogDir "windows-clean-scripts.log") -Append

Write-Host "========================================================="
Write-Host " СБРОС И ОЧИСТКА ПАПКИ WINDOWS\SETUP\SCRIPTS"
Write-Host "========================================================="

# =========================================================================
# ЭТАП 2: АНАЛИЗ И САМОУНИЧТОЖЕНИЕ (ДЛЯ ЗАПУСКА ИЗ ФАЙЛА ОТВЕТОВ UNATTEND.XML)
# =========================================================================

try {
    $TargetDir = "C:\Windows\Setup\Scripts"

    Write-Host "`n>>> [1/2] Анализ состояния директории перед удалением..."
    if (Test-Path $TargetDir) {
        $Files = Get-ChildItem -Path $TargetDir -Recurse -File
        Write-Host "Обнаружено файлов в очереди очистки: $($Files.Count)"
        foreach ($File in $Files) {
            Write-Host " - Будет удален: $($File.Name)"
        }
    } else {
        Write-Host "Папка Setup\Scripts отсутствует. Очистка не требуется."
        Exit
    }

    Write-Host "`n>>> [2/2] Инициализация скрытого процесса самоликвидации..."

    # Формируем команду для фонового CMD. 
    # 1. cd /d C:\  -> Уводим CMD из целевой папки, чтобы он сам её не блокировал.
    # 2. timeout /t 2 -> Ждем 2 секунды, пока закроется этот PowerShell процесс.
    # 3. takeown и icacls -> Сбрасываем права, если файлы заблокированы системой.
    # 4. rmdir -> Жестко сносим всю папку Scripts.
    # Использование & вместо && гарантирует, что даже если schtasks выдаст ошибку,
    # скрипт пойдет дальше и удалит папку.
    $CmdArgs = "/c cd /d C:\ & schtasks /delete /tn `"UnlockStartLayout`" /f >nul 2>&1 & timeout /t 5 /nobreak >nul & takeown /F `"$TargetDir`" /R /D Y >nul & icacls `"$TargetDir`" /grant *S-1-5-32-544:F /T /C /Q >nul & rmdir /s /q `"$TargetDir`""    # Настраиваем фоновый скрытый процесс, чтобы на экране не мелькали окна CMD
    $StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $StartInfo.FileName = "cmd.exe"
    $StartInfo.Arguments = $CmdArgs
    $StartInfo.WindowStyle = "Hidden" 
    $StartInfo.CreateNoWindow = $true

    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo = $StartInfo
    
    # Запуск фонового «уборщика»
    [void]$Process.Start()

    Write-Host ">>> Скрытая команда удаления отправлена. PowerShell завершает сессию для освобождения файлов..."

} catch {
    Write-Warning "Произошел сбой при подготовке самоликвидации: $($_.Exception.Message)"
}

# =========================================================================
# ЭТАП 3: ЗАВЕРШЕНИЕ РАБОТЫ (ЗАКРЫТИЕ ЛОГА ПЕРЕД УДАЛЕНИЕМ ПАПКИ)
# =========================================================================
Write-Host "`n========================================================="
Write-Host " ОЧИСТКА ЗАПУЩЕНА. ПЕРЕДАЧА УПРАВЛЕНИЯ ФОНОВОМУ ПРОЦЕССУ."
Write-Host "========================================================="
Stop-Transcript
