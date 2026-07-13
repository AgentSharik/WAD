# ==============================================================================
# Скрипт: clean-and-photo.ps1
# Описание: Очистка UWP-мусора, удаление OneDrive, возврат классического 
#           просмотрщика фото, настройка файла подкачки и отсрочка обновлений.
# ==============================================================================

Write-Host ">>> Начало очистки встроенного мусора..."

$BloatList = @(
    "Yandex.Music",
    "Microsoft.ZuneMusic",
    "office.outlook",
    "microsoft.windowscommunicationsapps",
    "Microsoft.3DViewer",
    "Microsoft.MixedReality.Portal",
    "Microsoft.BingNews",
    "Microsoft.BingWeather",
    "Microsoft.BingFinance",
    "Microsoft.BingSports",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",
    "Microsoft.YourPhone",
    "Microsoft.MicrosoftTeams",
    "Microsoft.SkypeApp",
    "Microsoft.54958562F4433",
    "Microsoft.WindowsCamera",
    "Microsoft.Windows.Ai.Copilot.Provider",
    "Microsoft.Office.OneNote",
    "Microsoft.OutlookForWindows",
    "Microsoft.People",
    "Microsoft.Wallet",
    "Microsoft.BingSearch",
    "Clipchamp.Clipchamp",
    "MicrosoftCorporationII.MicrosoftFamily",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.MicrosoftStickyNotes",
    "Microsoft.Todos",
    "Microsoft.Windows.DevHome",
    "Microsoft.WindowsMaps",
    "Microsoft.WindowsSoundRecorder"
)

# Кешируем установленные пакеты один раз для скорости
$AllAppx = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
$AllProv = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

foreach ($App in $BloatList) {
    # Ищем совпадения в памяти
    $Package = $AllAppx | Where-Object Name -match $App
    $ProvPackage = $AllProv | Where-Object DisplayName -match $App
    
    if ($Package -or $ProvPackage) {
        Write-Host "Удаление пакета: $App"
        
        # 1. Удаляем у текущих пользователей
        if ($Package) {
            $Package | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue 2>$null
        }
        
        # 2. Вырезаем из образа
        if ($ProvPackage) {
            $ProvPackage | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue 2>$null | Out-Null
        }
    }
}

Write-Host ">>> Очистка UWP-приложений завершена."


# ==============================================================================
# Удаление OneDrive
# ==============================================================================
Write-Host ">>> Удаление OneDrive..."

# Убиваем процесс, если он запущен
taskkill.exe /F /IM "OneDrive.exe" /T 2>$null

# Ищем деинсталлятор (зависит от разрядности ОС)
$oneDriveSetup = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
if (!(Test-Path $oneDriveSetup)) { 
    $oneDriveSetup = "$env:SystemRoot\System32\OneDriveSetup.exe" 
}

if (Test-Path $oneDriveSetup) {
    Start-Process -FilePath $oneDriveSetup -ArgumentList "/uninstall" -Wait -NoNewWindow
}

# Очистка остатков в реестре
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDriveSetup" -ErrorAction SilentlyContinue 2>$null


# ==============================================================================
# Активация классического Просмотра фотографий Windows 7
# ==============================================================================
Write-Host ">>> Активация Просмотра фотографий Windows 7..."

$RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations"
$Extensions = @(".jpg", ".jpeg", ".jpe", ".png", ".bmp", ".dib", ".gif", ".tif", ".tiff")

# Создаем ветку, если ее вдруг нет
if (!(Test-Path $RegistryPath)) {
    New-Item -Path $RegistryPath -Force | Out-Null
}

# Прописываем ассоциации
foreach ($ext in $Extensions) {
    New-ItemProperty -Path $RegistryPath -Name $ext -Value "PhotoViewer.FileAssoc.Tiff" -PropertyType String -Force | Out-Null
}

Write-Host ">>> Просмотр фотографий успешно настроен по умолчанию!"


# ==============================================================================
# Проверка ОЗУ и настройка файла подкачки
# ==============================================================================
Write-Host ">>> Проверка объема ОЗУ и настройка файла подкачки..."

# Получаем объем оперативной памяти в ГБ
$RAM_Bytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
$RAM_GB = [math]::Round($RAM_Bytes / 1GB)

Write-Host "Установлено оперативной памяти: $RAM_GB ГБ"

if ($RAM_GB -lt 32) {
    Write-Host "ОЗУ меньше 32 ГБ. Включаем автоматический объем файла подкачки..."
    
    # Включаем автоматическое управление файлом подкачки
    $ComputerSystem = Get-CimInstance Win32_ComputerSystem
    if ($ComputerSystem.AutomaticManagedPagefile -eq $false) {
        Set-CimInstance -Query "Select * from Win32_ComputerSystem" -Property @{AutomaticManagedPagefile=$true}
    }
    
    Write-Host ">>> Файл подкачки переведен в автоматический режим."
} else {
    Write-Host "ОЗУ 32 ГБ или больше. Оставляем настройки файла подкачки без изменений."
}


# ==============================================================================
# Задача планировщика: Пауза обновлений Windows
# ==============================================================================
Write-Host ">>> Настройка задачи отсрочки обновлений Windows..."

$TaskName = "PauseWindowsUpdate"
# Проверяем, существует ли уже такая задача
$TaskExists = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if ($TaskExists) {
    Write-Host "Задача '$TaskName' уже существует в Планировщике. Пропускаем создание."
} else {
    Write-Host "Задача '$TaskName' не найдена. Начинаем создание..."
    
    # Используем одинарные кавычки (@' ... '@), чтобы PowerShell не пытался
    # обработать переменные $format, $now и другие внутри XML-текста
    $TaskXml = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <URI>\PauseWindowsUpdate</URI>
  </RegistrationInfo>
  <Triggers>
    <BootTrigger>
      <Repetition>
        <Interval>P1D</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <Enabled>true</Enabled>
    </BootTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-19</UserId>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe</Command>
      <Arguments>-WindowStyle Hidden -NoProfile -NonInteractive -Command "$format = 'yyyy-MM-ddTHH\:mm\:ssK'; $now = [datetime]::UtcNow; $start = $now.ToString($format); $end = $now.AddDays(7).ToString($format); $params = @{ LiteralPath = 'Registry::HKLM\Software\Microsoft\WindowsUpdate\UX\Settings'; Type = 'String'; Force = $true; Verbose = $true; }; 'PauseFeatureUpdatesStartTime', 'PauseQualityUpdatesStartTime', 'PauseUpdatesStartTime' | foreach { Set-ItemProperty @params -Name $_ -Value $start; }; 'PauseFeatureUpdatesEndTime', 'PauseQualityUpdatesEndTime', 'PauseUpdatesExpiryTime' | foreach { Set-ItemProperty @params -Name $_ -Value $end; };"</Arguments>
    </Exec>
  </Actions>
</Task>
'@

    # Регистрируем задачу в Планировщике напрямую из XML-строки
    Register-ScheduledTask -Xml $TaskXml -TaskName $TaskName -Force | Out-Null
    Write-Host ">>> Задача '$TaskName' успешно создана!"
}

Write-Host ">>> Все операции успешно завершены!"
