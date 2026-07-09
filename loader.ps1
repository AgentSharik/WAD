# Определяем пути
$targetBasePath = "C:\Windows\Setup"
$finalScriptsPath = Join-Path -Path $targetBasePath -ChildPath "Scripts"

# Временные пути для скачивания и распаковки (используем системную папку Temp)
$zipPath = Join-Path -Path $env:TEMP -ChildPath "powershell-scripts.zip"
$tempExtractPath = Join-Path -Path $env:TEMP -ChildPath "temp-repo-extract"

# Создаем папку C:\Windows\Setup, если её вдруг не существует
if (-not (Test-Path $targetBasePath)) {
    New-Item -Path $targetBasePath -ItemType Directory -Force | Out-Null
}

# URL для скачивания веток
$urlMain = "https://github.com/AgentSharik/powershell-scripts/archive/refs/heads/main.zip"
$urlMaster = "https://github.com/AgentSharik/powershell-scripts/archive/refs/heads/master.zip"

Write-Host "Скачивание репозитория..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $urlMain -OutFile $zipPath -ErrorAction Stop
} catch {
    Write-Host "Ветка 'main' не найдена, пробуем 'master'..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $urlMaster -OutFile $zipPath
}

# Очищаем папки, если скрипт запускается не в первый раз
if (Test-Path $tempExtractPath) { Remove-Item -Path $tempExtractPath -Recurse -Force }
if (Test-Path $finalScriptsPath) { Remove-Item -Path $finalScriptsPath -Recurse -Force }

Write-Host "Распаковка архива..." -ForegroundColor Cyan
Expand-Archive -Path $zipPath -DestinationPath $tempExtractPath -Force

# Находим корневую папку в архиве
$repoFolder = Get-ChildItem -Path $tempExtractPath -Directory | Select-Object -First 1
$extractedScriptsFolder = Join-Path -Path $repoFolder.FullName -ChildPath "Scripts"

if (Test-Path $extractedScriptsFolder) {
    # Перемещаем папку Scripts в C:\Windows\Setup
    Move-Item -Path $extractedScriptsFolder -Destination $targetBasePath -Force
    
    Write-Host "Исправление кодировки файлов (добавление BOM)..." -ForegroundColor Yellow
    # Ищем все .ps1 файлы и принудительно пересохраняем их в UTF-8 с BOM
    $psFiles = Get-ChildItem -Path $finalScriptsPath -Filter "*.ps1" -Recurse
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    foreach ($file in $psFiles) {
        $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        [System.IO.File]::WriteAllText($file.FullName, $content, $utf8Bom)
    }

    Write-Host "Папка 'Scripts' успешно скачана и размещена: $finalScriptsPath" -ForegroundColor Green
    
    $managerScript = Join-Path -Path $finalScriptsPath -ChildPath "manager.ps1"
    
    if (Test-Path $managerScript) {
        Write-Host "Запуск файла manager.ps1..." -ForegroundColor Cyan
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoExit -File `"$managerScript`""
    } else {
        Write-Host "Файл manager.ps1 не найден внутри папки Scripts!" -ForegroundColor Red
    }
} else {
    Write-Host "Папка 'Scripts' не найдена в репозитории!" -ForegroundColor Red
}

# Уборка за собой
Write-Host "Очистка временных файлов..." -ForegroundColor Cyan
if (Test-Path $zipPath) { Remove-Item -Path $zipPath -Force }
if (Test-Path $tempExtractPath) { Remove-Item -Path $tempExtractPath -Recurse -Force }

Write-Host "Готово!" -ForegroundColor Green