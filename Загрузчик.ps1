# =========================================================================
# Назначение: Автономный загрузчик с авто-исправлением кодировки и переносов
# Оптимизировано для запуска на чистой ("свежей") Windows
# Папка назначения: C:\Windows\Setup\Scripts
# =========================================================================

# 1. ПРОВЕРКА ПРАВ АДМИНИСТРАТОРА
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Скрипт запущен без прав Администратора! Пытаемся перезапустить с правами..."
    try {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    } catch {
        Write-Error "Не удалось получить права Администратора. Запустите скрипт от имени Администратора вручную."
        Pause
        exit
    }
}

# 2. БАЗОВЫЕ НАСТРОЙКИ СЕТИ ДЛЯ ЧИСТОЙ ОС
# Включаем TLS 1.2 (обязательно для GitHub) и игнорируем возможные ошибки сертификатов на старых сборках Windows
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

$targetDir = 'C:\Windows\Setup\Scripts'
if (!(Test-Path $targetDir)) { 
    New-Item $targetDir -ItemType Directory -Force | Out-Null 
}

$LogFile = Join-Path $targetDir "Download_Bootstrapper.log"
Start-Transcript -Path $LogFile -Append -Force

try {
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host " СТАРТ МОДУЛЯ ЗАГРУЗКИ С АВТО-ЛЕЧЕНИЕМ СКРИПТОВ" -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan

    $baseUrl = 'https://raw.githubusercontent.com/AgentSharik/powershell-scripts/main/Scripts/'
    $apiUrl  = 'https://api.github.com/repos/AgentSharik/powershell-scripts/contents/Scripts'
    
    $fileList = @('manager.ps1', 'apps-install.ps1', 'clean-and-photo.ps1', 'install-sys-components.ps1', 'office-install.ps1', 'reset-setup-scripts.ps1')

    # 3. ОЖИДАНИЕ СЕТИ (Защита от запуска быстрее, чем поднимется сеть)
    Write-Host "`n[0/3] Проверка подключения к интернету..."
    $networkUp = $false
    for ($i = 1; $i -le 10; $i++) {
        try {
            $null = Invoke-RestMethod -Uri "https://api.github.com" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            $networkUp = $true
            Write-Host "Сеть доступна!" -ForegroundColor Green
            break
        } catch {
            Write-Host "Попытка $i из 10: Сеть пока недоступна, ждем 3 секунды..." -ForegroundColor Yellow
            Start-Sleep -Seconds 3
        }
    }

    if (-not $networkUp) {
        Write-Error "Не удалось установить соединение с GitHub. Проверьте интернет."
        throw "Network initialization timeout."
    }

    # 4. ПОЛУЧЕНИЕ СПИСКА ФАЙЛОВ
    Write-Host "`n[1/3] Получение актуального списка файлов..."
    try {
        $apiResponse = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
        if ($apiResponse) {
            $fileList = $apiResponse | Where-Object { $_.type -eq 'file' } | Select-Object -ExpandProperty name
            Write-Host "Список файлов успешно получен через API." -ForegroundColor Green
        }
    } catch {
        Write-Warning "-> GitHub API недоступен (возможно, лимит запросов). Используем резервный список файлов."
    }

    # 5. СКАЧИВАНИЕ И ЛЕЧЕНИЕ
    Write-Host "`n[2/3] Скачивание и исправление синтаксиса..."
    foreach ($fileName in $fileList) {
        $outPath = Join-Path $targetDir $fileName
        $url = $baseUrl + $fileName
        
        Write-Host "Обработка: $fileName ... " -NoNewline
        try {
            # Используем Invoke-RestMethod вместо WebClient, он лучше работает на новых сборках
            $rawContent = Invoke-RestMethod -Uri $url -UseBasicParsing -ErrorAction Stop
            
            # Если файл скачался как байты (иногда бывает с Invoke-RestMethod), конвертируем в строку
            if ($rawContent -is [byte[]]) {
                $rawContent = [System.Text.Encoding]::UTF8.GetString($rawContent)
            }
            
            # ИСПРАВЛЕНИЕ 1: Лечим текстовые '\r\n' (буквальные символы)
            if ($rawContent -match '\\r\\n') {
                $rawContent = $rawContent -replace '\\r\\n', "`r`n"
            }
            
            # ИСПРАВЛЕНИЕ 2: Принудительное сохранение в UTF-8 с BOM для PS 5.1
            # Класс UTF8Encoding($true) гарантирует запись сигнатуры BOM
            $utf8Bom = New-Object System.Text.UTF8Encoding($true)
            [System.IO.File]::WriteAllText($outPath, $rawContent, $utf8Bom)
            
            Write-Host "УСПЕШНО" -ForegroundColor Green
        } catch {
            Write-Host "ОШИБКА" -ForegroundColor Red
            Write-Warning "Не удалось обработать $fileName : $($_.Exception.Message)"
        }
    }

    # 6. ЗАПУСК ДИСПЕТЧЕРА
    $managerPath = Join-Path $targetDir 'manager.ps1'
    if (Test-Path $managerPath) {
        Write-Host "`n[3/3] Все файлы вылечены. Запуск Диспетчера в новом окне..." -ForegroundColor Green
        Stop-Transcript
        
        # Запуск менеджера в отдельном чистом окне
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$managerPath`"" -WindowStyle Normal
    } else {
        Write-Error "Критический сбой: Файл manager.ps1 отсутствует! Скачивание не удалось."
        Stop-Transcript
        Pause
    }
} catch {
    Write-Error "Глобальная ошибка: $($_.Exception.Message)"
    try { Stop-Transcript } catch {}
    Pause
}
