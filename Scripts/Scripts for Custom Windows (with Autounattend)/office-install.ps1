# =========================================================================
# Имя файла: office-install-full.ps1
# Назначение: Автоматическая установка и активация Microsoft Office LTSC 2024
# Оптимизация: Только Word, Excel, PowerPoint + Авто-KMS
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

# Включение TLS 1.2 и 1.3 для работы с серверами Microsoft
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor 12288
} catch {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

# Настройка папки логов
$UserProfile = $env:USERPROFILE
$LogDir = Join-Path $UserProfile "Documents"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
Start-Transcript -Path (Join-Path $LogDir "office2024-install.log") -Append

Write-Host "========================================================="
Write-Host " ЗАПУСК ПОЛНОЙ УСТАНОВКИ И АКТИВАЦИИ MICROSOFT OFFICE 2024"
Write-Host "========================================================="

# =========================================================================
# ЭТАП 2: ФУНКЦИИ-ПОМОЩНИКИ
# =========================================================================

function Invoke-SafeRetry {
    param([scriptblock]$Script, [int]$Count=3, [int]$DelaySec=5)
    for($i=1; $i -le $Count; $i++){
        try { return & $Script } catch {
            if($i -eq $Count){ throw }
            Start-Sleep -Seconds $DelaySec
        }
    }
}

function Download-SetupFile {
    param([string]$Uri, [string]$OutFile)
    Invoke-SafeRetry -Count 3 -DelaySec 5 -Script {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $OutFile -Headers @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' } -TimeoutSec 300
        } catch {
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
            $webClient.DownloadFile($Uri, $OutFile)
        }
    }
    if(-not (Test-Path $OutFile) -or (Get-Item $OutFile).Length -lt 100KB){
        if (Test-Path $OutFile) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue }
        throw "Файл поврежден при скачивании: $OutFile"
    }
}

function Install-Executable {
    param([string]$Path, [string]$Arguments)
    $process = Start-Process -FilePath $Path -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) {
        Write-Warning "Процесс вернул код: $($process.ExitCode)"
    }
}

# =========================================================================
# ЭТАП 3: СКАЧИВАНИЕ И УСТАНОВКА
# =========================================================================

try {
    $TempDir = "C:\Office2024_Temp"
    if (-not (Test-Path $TempDir)) { New-Item -Path $TempDir -ItemType Directory -Force | Out-Null }

    # 3.1: Патч региональной блокировки
    Write-Host "`n>>> [1/5] Обход региональных ограничений..."
    $RegPath = "HKCU:\Software\Microsoft\Office\16.0\Common\ExperimentConfigs\Ecs"
    if (!(Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
    Set-ItemProperty -Path $RegPath -Name "CountryCode" -Value "std::wstring|US" -Type String

    # 3.2: Скачивание ODT
    Write-Host "`n>>> [2/5] Скачивание компонентов развертывания Microsoft ODT..."
    $OdtUrl = "https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_20026-20112.exe"
    $OdtExe = Join-Path $TempDir "odt_setup.exe"
    Download-SetupFile -Uri $OdtUrl -OutFile $OdtExe

    # 3.3: Распаковка ODT
    Write-Host "`n>>> [3/5] Распаковка файлов установщика..."
    Install-Executable -Path $OdtExe -Arguments "/extract:`"$TempDir`" /quiet"
    Start-Sleep -Seconds 2

    # 3.4: Генерация XML (Конфигурация без BOM-байтов)
    Write-Host "`n>>> [4/5] Создание конфигурационного файла (Только Word, Excel, PowerPoint)..."
    $XmlContent = @"
<Configuration>
  <Add OfficeClientEdition="64" Channel="PerpetualVL2024">
    <Product ID="ProPlus2024Volume" PIDKEY="FXYTK-NJJ8C-GB6DW-3DYQT-6F7TH">
      <Language ID="ru-ru" />
      <ExcludeApp ID="Outlook" />
      <ExcludeApp ID="Access" />
      <ExcludeApp ID="OneNote" />
      <ExcludeApp ID="Publisher" />
      <ExcludeApp ID="Teams" />
      <ExcludeApp ID="OneDrive" />
      <ExcludeApp ID="Lync" />
      <ExcludeApp ID="Bing" />
    </Product>
  </Add>
  <RemoveMSI />
  <Property Name="AUTOACTIVATE" Value="1" />
</Configuration>
"@
    $XmlPath = Join-Path $TempDir "configuration.xml"
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($XmlPath, $XmlContent, $Utf8NoBom)

    # 3.5: Запуск фоновой установки Office
    Write-Host "`n>>> [5/5] Запуск установки финальной версии Office 2024 LTSC..."
    Write-Host "Внимание: Идет скачивание файлов напрямую с серверов Microsoft. Подождите..."
    $SetupPath = Join-Path $TempDir "setup.exe"
    
    if (Test-Path $SetupPath) {
        Install-Executable -Path $SetupPath -Arguments "/configure `"$XmlPath`""
        Write-Host ">>> Установка файлов завершена."
    } else {
        throw "Критическая ошибка: setup.exe не найден."
    }

    # =========================================================================
    # АВТОМАТИЧЕСКАЯ НАСТРОЙКА АКТИВАЦИИ (KMS)
    # =========================================================================
    Write-Host "`n>>> [Активация] Подключение к удаленному серверу лицензирования..."
    
    # Проверяем стандартный путь установки Office (64-бит)
    $OfficePath = "C:\Program Files\Microsoft Office\Office16"
    if (Test-Path $OfficePath) {
        Set-Location -Path $OfficePath
        
        # Задаем адрес публичного KMS-сервера
        Write-Host "Привязка KMS-сервера: kms.digiboy.ir..."
        cscript ospp.vbs /sethst:kms.digiboy.ir | Out-Null
        
        # Отправляем запрос на немедленную активацию
        Write-Host "Отправка запроса на активацию..."
        cscript ospp.vbs /act
    } else {
        Write-Warning "Папка программы не найдена, пропуск шага автоматической активации."
    }

} catch {
    Write-Warning "Произошел сбой: $($_.Exception.Message)"
} finally {
    # Очистка временных файлов
    Write-Host "`n>>> Очистка временного мусора установки..."
    if (Test-Path $TempDir) {
        Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
 
# =========================================================================
# ЭТАП 4: ЗАВЕРШЕНИЕ РАБОТЫ
# =========================================================================
Write-Host "`n========================================================="
Write-Host " ВСЕ ЭТАПЫ ВЫПОЛНЕНЫ. ЗАКРЫТИЕ ЛОГА."
Write-Host "========================================================="
Stop-Transcript
