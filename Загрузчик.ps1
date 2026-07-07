# =========================================================================
# Назначение: Автономный загрузчик с авто-исправлением кодировки и переносов
# Папка назначения: C:\Windows\Setup\Scripts
# =========================================================================

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$targetDir = 'C:\Windows\Setup\Scripts'
if (!(Test-Path $targetDir)) { 
    New-Item $targetDir -ItemType Directory -Force | Out-Null 
}

$LogFile = Join-Path $targetDir "Download_Bootstrapper.log"
Start-Transcript -Path $LogFile -Append -Force

try {
    Write-Host "========================================================="
    Write-Host " СТАРТ МОДУЛЯ ЗАГРУЗКИ С АВТО-ЛЕЧЕНИЕМ СКРИПТОВ"
    Write-Host "========================================================="

    $baseUrl = 'https://raw.githubusercontent.com/alexejnekrasov/powershell-scripts/main/Scripts/'
    $fileList = @('manager.ps1', 'apps-install.ps1', 'clean-and-photo.ps1', 'install-sys-components.ps1', 'office-install.ps1', 'reset-setup-scripts.ps1')

    # Попытка получить свежий список файлов через API GitHub
    try {
        $apiUrl = 'https://api.github.com/repos/alexejnekrasov/powershell-scripts/contents/Scripts'
        $apiResponse = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
        if ($apiResponse) {
            $fileList = $apiResponse | Where-Object { $_.type -eq 'file' } | Select-Object -ExpandProperty name
        }
    } catch {
        Write-Warning "-> GitHub API недоступен. Используем резервный список файлов."
    }

    Write-Host "`n[1/2] Скачивание и исправление синтаксиса..."
    foreach ($fileName in $fileList) {
        $outPath = Join-Path $targetDir $fileName
        $url = $baseUrl + $fileName
        
        Write-Host "Обработка: $fileName ... " -NoNewline
        try {
            # 1. Скачиваем файл как чистую UTF-8 строку в память
            $webClient = New-Object System.Net.WebClient
            $webClient.Encoding = [System.Text.Encoding]::UTF8
            $rawContent = $webClient.DownloadString($url)
            
            # 2. ИСПРАВЛЕНИЕ 1: Лечим текстовые '\r\n', превращая их в системные маркеры строк
            if ($rawContent -match '\\r\\n') {
                $rawContent = $rawContent -replace '\\r\\n', "`r`n"
            }
            
            # 3. ИСПРАВЛЕНИЕ 2: Принудительно сохраняем файл на диск в UTF-8 с сигнатурой BOM.
            # Это полностью убирает кракозябры и защищает кириллицу в PowerShell 5.1
            [System.IO.File]::WriteAllText($outPath, $rawContent, [System.Text.Encoding]::UTF8)
            
            Write-Host "УСПЕШНО ИСПРАВЛЕН" -ForegroundColor Green
        } catch {
            Write-Host "ОШИБКА" -ForegroundColor Red
            Write-Warning "Не удалось обработать файл $fileName : $($_.Exception.Message)"
        }
    }

    $managerPath = Join-Path $targetDir 'manager.ps1'
    if (Test-Path $managerPath) {
        Write-Host "`n[2/2] Все файлы вылечены. Запуск Диспетчера в новом окне..." -ForegroundColor Green
        Stop-Transcript
        
        # Запуск менеджера в отдельном чистом интерактивном окне
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$managerPath`"" -WindowStyle Normal
    } else {
        Write-Error "Критический сбой: Файл manager.ps1 отсутствует!"
        Stop-Transcript
    }
} catch {
    Write-Error "Глобальная ошибка: $($_.Exception.Message)"
    try { Stop-Transcript } catch {}
}