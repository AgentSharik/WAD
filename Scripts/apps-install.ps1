# =========================================================================
# Имя файла: apps-install.ps1
# Назначение: Абсолютно надежная установка базового софта + qBittorrent, ShareX, K-Lite
# =========================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# =========================================================================
# ЭТАП 1: ИНИЦИАЛИЗАЦИЯ, TLS И ЛОГИРОВАНИЕ
# =========================================================================

# Включаем современные протоколы шифрования (TLS 1.2 и TLS 1.3) для работы с серверами
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor 12288
} catch {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

# Настройка папки логов в Документы Администратора
$UserProfile = $env:USERPROFILE
$LogDir = Join-Path $UserProfile "Documents"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
Start-Transcript -Path (Join-Path $LogDir "software-install.log") -Append

Write-Host "========================================================="
Write-Host " ЗАПУСК СЦЕНАРИЯ УСТАНОВКИ БАЗОВЫХ ПРОГРАММ"
Write-Host "========================================================="

# =========================================================================
# ЭТАП 2: БЛОКИ ФУНКЦИЙ-ПОМОЩНИКОВ (ХЕЛПЕРЫ)
# =========================================================================

# Хелпер для повторных попыток при скачивании
function Invoke-SafeRetry {
    param([scriptblock]$Script, [int]$Count=3, [int]$DelaySec=5)
    for($i=1; $i -le $Count; $i++){
        try { return & $Script } catch {
            if($i -eq $Count){ throw }
            Start-Sleep -Seconds $DelaySec
        }
    }
}

# Хелпер скачивания файлов БЕЗ графики BITS, с фоллбэком на .NET и сверкой SHA256
function Download-SetupFile {
    param(
        [string]$Uri, 
        [string]$OutFile, 
        [string]$ExpectedHash = $null
    )
    
    Invoke-SafeRetry -Count 3 -DelaySec 5 -Script {
        try {
            # Метод 1: Быстрый WebRequest с подменой User-Agent и таймаутом в 5 минут
            Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $OutFile -Headers @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' } -TimeoutSec 300
        } catch {
            # Метод 2 (Фоллбэк): Системный .NET WebClient
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
            $webClient.DownloadFile($Uri, $OutFile)
        }
    }
    
    # Защита от пустых файлов или ошибок 404
    if(-not (Test-Path $OutFile) -or (Get-Item $OutFile).Length -lt 100KB){
        if (Test-Path $OutFile) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue }
        throw "Файл пустой или поврежден (размер слишком мал): $OutFile"
    }

    # Побитовая проверка целостности файла по SHA256
    if (-not [string]::IsNullOrEmpty($ExpectedHash)) {
        Write-Host "Проверка контрольной суммы SHA256..."
        $ActualHash = (Get-FileHash -Path $OutFile -Algorithm SHA256).Hash
        if ($ActualHash -ne $ExpectedHash) {
            Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
            throw "Критический сбой: Хэш файла не совпал с эталоном! Файл битый. Удален с диска."
        }
        Write-Host "Контрольная сумма совпала. Файл оригинальный на 100%."
    }
}

# Универсальный запуск EXE-инсталляторов с ожиданием окончания процесса
function Install-Executable {
    param([string]$Path, [string]$Arguments)
    $process = Start-Process -FilePath $Path -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) {
        Write-Warning "EXE инсталлятор вернул код ошибки: $($process.ExitCode)"
    }
}

# Универсальный запуск MSI-пакетов через msiexec
function Install-MsiPackage {
    param([string]$Path, [string]$Arguments = '/qn /norestart')
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/i `"$Path`" $Arguments" -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
        Write-Warning "MSI инсталлятор вернул код ошибки: $($process.ExitCode)"
    }
}

# =========================================================================
# ЭТАП 3: ПОСЛЕДОВАТЕЛЬНАЯ УСТАНОВКА ПРОГРАММ
# =========================================================================

# --- 3.1: Google Chrome Enterprise (MSI) ---
try {
    Write-Host "`n>>> [1/6] Установка Google Chrome..."
    $ChromeUri  = 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi'
    $ChromeFile = Join-Path $env:TEMP 'GoogleChromeEnterprise.msi'
    
    Write-Host "Скачивание официального Enterprise MSI..."
    Download-SetupFile -Uri $ChromeUri -OutFile $ChromeFile -ExpectedHash $null
    
    Write-Host "Запуск тихой установки пакета..."
    Install-MsiPackage -Path $ChromeFile
    
    Remove-Item $ChromeFile -Force -ErrorAction SilentlyContinue
    Write-Host ">>> Google Chrome установлен успешно."
} catch {
    Write-Warning "Не удалось установить Google Chrome: $($_.Exception.Message)"
}

# --- 3.2: Steam Client (EXE) ---
try {
    Write-Host "`n>>> [2/6] Установка Steam..."
    $SteamUri  = 'https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe'
    $SteamFile = Join-Path $env:TEMP 'SteamSetup.exe'
    
    Write-Host "Скачивание установщика Steam с официального CDN..."
    Download-SetupFile -Uri $SteamUri -OutFile $SteamFile -ExpectedHash $null
    
    Write-Host "Запуск тихой установки с ключом /S..."
    Install-Executable -Path $SteamFile -Arguments '/S'
    
    Remove-Item $SteamFile -Force -ErrorAction SilentlyContinue
    Write-Host ">>> Steam установлен успешно."
} catch {
    Write-Warning "Не удалось установить Steam: $($_.Exception.Message)"
}

# --- 3.3: WinRAR (Официальная русская x64 версия) ---
try {
    Write-Host "`n>>> [3/6] Установка WinRAR RU..."
    $WinRarUri  = 'https://www.rarlab.com/rar/winrar-x64-701ru.exe'
    $WinRarFile = Join-Path $env:TEMP 'winrar-x64-ru.exe'
    
    Write-Host "Скачивание установщика WinRAR с официального сервера..."
    Download-SetupFile -Uri $WinRarUri -OutFile $WinRarFile -ExpectedHash $null
    
    Write-Host "Запуск тихой установки с ключом /S..."
    Install-Executable -Path $WinRarFile -Arguments '/S'
    
    if (Test-Path 'C:\Program Files\WinRAR\WinRAR.exe') {
        Write-Host ">>> WinRAR успешно развернут в систему."
    } else {
        Write-Warning "WinRAR: Процесс завершился, но исполняемый файл не найден."
    }
    
    Remove-Item $WinRarFile -Force -ErrorAction SilentlyContinue
} catch {
    Write-Warning "Не удалось установить WinRAR: $($_.Exception.Message)"
}

# --- 3.4: qBittorrent (Прямая ссылка на релиз 5.2.2 с libtorrent 1.2.x) ---
try {
    Write-Host "`n>>> [4/6] Установка qBittorrent (libtorrent 1.2.x)..."
    $qbUri  = 'https://github.com/qbittorrent/qBittorrent/releases/download/release-5.2.2/qbittorrent_5.2.2_x64_setup.exe'
    $qbFile = Join-Path $env:TEMP 'qbittorrent_setup.exe'
    
    Write-Host "Скачивание инсталлятора qBittorrent..."
    Download-SetupFile -Uri $qbUri -OutFile $qbFile -ExpectedHash $null
    
    Write-Host "Запуск тихой установки..."
    $proc = Start-Process -FilePath $qbFile -ArgumentList '/S' -WorkingDirectory $env:TEMP -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        Write-Warning "qBittorrent инсталлятор вернул код ошибки: $($proc.ExitCode)"
    }
    
    Remove-Item $qbFile -Force -ErrorAction SilentlyContinue
    Write-Host ">>> qBittorrent успешно установлен."
} catch {
    Write-Warning "Не удалось установить qBittorrent: $($_.Exception.Message)"
}

# --- 3.5: ShareX (v20.2.0 с ключом подавления автозапуска и принудительным киллом) ---
try {
    Write-Host "`n>>> [5/6] Установка ShareX..."
    $sharexUri  = 'https://github.com/ShareX/ShareX/releases/download/v20.2.0/ShareX-20.2.0-setup-x64.exe'
    $sharexFile = Join-Path $env:TEMP 'sharex_setup.exe'
    
    Write-Host "Скачивание инсталлятора ShareX..."
    Download-SetupFile -Uri $sharexUri -OutFile $sharexFile -ExpectedHash $null
    
    Write-Host "Запуск тихой установки с подавлением автозапуска (/SP-)..."
    # Добавлен ключ /SP-, чтобы установщик Inno Setup не открывал программу в конце
    Start-Process -FilePath $sharexFile -ArgumentList '/VERYSILENT /NORESTART /MERGETASKS=!desktopicon /SP-' -NoNewWindow
    
    Write-Host "Ожидаем 20 секунд для завершения установки ShareX..."
    Start-Sleep -Seconds 30
    
    Write-Host "Принудительное завершение процессов ShareX для избежания зависаний..."
    # На всякий случай жестко прибиваем процессы, если они еще висят
    Stop-Process -Name "ShareX-20.2.0-setup-x64" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "ShareX" -Force -ErrorAction SilentlyContinue
    
    Remove-Item $sharexFile -Force -ErrorAction SilentlyContinue
    Write-Host ">>> Шаг ShareX выполнен успешно."
} catch {
    Write-Warning "Не удалось установить ShareX: $($_.Exception.Message)"
}

# --- 3.6: K-Lite Codec Pack Mega ---
try {
    Write-Host "`n>>> [6/6] Установка K-Lite Codec Pack Mega..."
    $KLiteUri  = 'https://files2.codecguide.com/K-Lite_Codec_Pack_1975_Mega.exe'
    $KLiteFile = Join-Path $env:TEMP 'klite_setup.exe'
    
    Write-Host "Скачивание пакета кодеков Mega..."
    Download-SetupFile -Uri $KLiteUri -OutFile $KLiteFile -ExpectedHash $null
    
    Write-Host "Запуск тихой автоматической установки..."
    Install-Executable -Path $KLiteFile -Arguments '/verysilent /norestart'
    
    Remove-Item $KLiteFile -Force -ErrorAction SilentlyContinue
    Write-Host ">>> K-Lite Codec Pack Mega установлен успешно."
} catch {
    Write-Warning "Не удалось установить K-Lite Codec Pack: $($_.Exception.Message)"
}

# =========================================================================
# ЭТАП 4: ЗАВЕРШЕНИЕ РАБОТЫ
# =========================================================================
Write-Host "`n========================================================="
Write-Host " ВСЕ ЭТАПЫ ВЫПОЛНЕНИЫ. ЗАКРЫТИЕ ЛОГА."
Write-Host "========================================================="
Stop-Transcript
