# ==============================================================================
# Script: initial-setup.ps1
# Описание: Ультимативная настройка Windows 10/11 (Edge Edition Fix)
# ==============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# --- НАСТРОЙКА ЛОГИРОВАНИЯ ---
$LogDir = Join-Path $env:USERPROFILE "Documents"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
Start-Transcript -Path (Join-Path $LogDir "Initial_Setup.log") -Append
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " ЗАПУСК УЛЬТИМАТИВНОЙ НАСТРОЙКИ СИСТЕМЫ" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# ==============================================================================
# 1. Задача планировщика: Пауза обновлений Windows
# ==============================================================================
Write-Host "`n>>> Шаг 1: Настройка задачи отсрочки обновлений..."
try {
    $TaskName = "PauseWindowsUpdate"
    $TaskXml = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><URI>\PauseWindowsUpdate</URI></RegistrationInfo>
  <Triggers><BootTrigger><Repetition><Interval>P1D</Interval></Repetition><Enabled>true</Enabled></BootTrigger></Triggers>
  <Principals><Principal id="Author"><UserId>S-1-5-18</UserId><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><AllowHardTerminate>true</AllowHardTerminate><StartWhenAvailable>true</StartWhenAvailable><Enabled>true</Enabled></Settings>
  <Actions Context="Author"><Exec><Command>powershell.exe</Command><Arguments>-WindowStyle Hidden -NoProfile -Command "$now = [datetime]::UtcNow; $start = $now.ToString('yyyy-MM-ddTHH:mm:ssK'); $end = $now.AddDays(7).ToString('yyyy-MM-ddTHH:mm:ssK'); $p = 'Registry::HKLM\Software\Microsoft\WindowsUpdate\UX\Settings'; Set-ItemProperty $p -Name PauseUpdatesStartTime -Value $start; Set-ItemProperty $p -Name PauseUpdatesExpiryTime -Value $end;"</Arguments></Exec></Actions>
</Task>
'@
    Register-ScheduledTask -Xml $TaskXml -TaskName $TaskName -Force | Out-Null
    Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Write-Host "  [УСПЕШНО] Задача создана."
} catch { Write-Host "  [ОШИБКА] Обновления: $_" }

# ==============================================================================
# 2. Укрощение Microsoft Edge (КРИТИЧЕСКИЙ БЛОК)
# ==============================================================================
Write-Host "`n>>> Шаг 2: Полная блокировка Microsoft Edge..." -ForegroundColor Yellow
try {
    # 2.1 Политики HKLM
    $EdgePol = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    if (!(Test-Path $EdgePol)) { New-Item -Path $EdgePol -Force | Out-Null }
    $EdgeSettings = @{
        "HideFirstRunExperience"          = 1
        "CreateDesktopShortcut"           = 0
        "WelcomePageOnFirstLaunchEnabled" = 0
        "StartupBoostEnabled"             = 0
        "BackgroundModeEnabled"           = 0
        "AllowPrelaunch"                  = 0
        "AutoImportAtFirstRun"            = 0
        "HubsSidebarEnabled"              = 0
    }
    foreach ($name in $EdgeSettings.Keys) {
        Set-ItemProperty -Path $EdgePol -Name $name -Value $EdgeSettings[$name] -Type DWord -Force
    }

    # 2.2 Отключение служб обновления Edge
    $EdgeServices = @("edgeupdate", "edgeupdatem", "MicrosoftEdgeElevationService")
    foreach ($svc in $EdgeServices) {
        if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc -StartupType Disabled
        }
    }

    # 2.3 Удаление задач Edge в планировщике
    Get-ScheduledTask -TaskPath "\" -ErrorAction SilentlyContinue | 
        Where-Object { $_.TaskName -like "*MicrosoftEdge*" } | 
        Disable-ScheduledTask -ErrorAction SilentlyContinue

    # 2.4 Обход Active Setup (предотвращает создание ярлыков при входе)
    $ActiveSetup = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components"
    Get-ChildItem $ActiveSetup | Where-Object { (Get-ItemProperty $_.PsPath).StubPath -like "*MicrosoftEdge*" } | ForEach-Object {
        Set-ItemProperty -Path $_.PsPath -Name "StubPath" -Value "" -Force
    }

    Write-Host "  [УСПЕШНО] Edge максимально подавлен."
} catch { Write-Host "  [ОШИБКА] Edge: $_" }

# ==============================================================================
# 3. Интерфейс, Панель задач, Виджеты
# ==============================================================================
Write-Host "`n>>> Шаг 3: Очистка Панели задач..."
try {
    $SearchPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
    Set-ItemProperty -Path $SearchPath -Name "SearchboxTaskbarMode" -Value 1 -Force

    $AdvPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $UIConfigs = @{ "ShowTaskViewButton"=0; "TaskbarDa"=0; "TaskbarMn"=0; "TaskbarAl"=0 }
    foreach ($n in $UIConfigs.Keys) { Set-ItemProperty -Path $AdvPath -Name $n -Value $UIConfigs[$n] -Force }

    $Feeds = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"
    if (!(Test-Path $Feeds)) { New-Item -Path $Feeds -Force | Out-Null }
    Set-ItemProperty -Path $Feeds -Name "EnableFeeds" -Value 0 -Type DWord -Force

    Write-Host "  [УСПЕШНО] Виджеты и лишние кнопки скрыты."
} catch { Write-Host "  [ОШИБКА] Интерфейс: $_" }

# ==============================================================================
# 4. Настройка Рабочего стола
# ==============================================================================
Write-Host "`n>>> Шаг 4: Настройка Рабочего стола..."
try {
    # Удаление ярлыков Edge/Teams с общего стола
    Get-ChildItem -Path "$env:PUBLIC\Desktop" -Filter "*.lnk" | Where-Object { $_.Name -match "Edge|Teams" } | Remove-Item -Force -ErrorAction SilentlyContinue
    
    $Icons = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
    if (!(Test-Path $Icons)) { New-Item -Path $Icons -Force | Out-Null }
    Set-ItemProperty -Path $Icons -Name "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" -Value 0 -Force # Этот компьютер
    Write-Host "  [УСПЕШНО] Значки настроены."
} catch { Write-Host "  [ОШИБКА] Стол: $_" }

# ==============================================================================
# 5. Макет Пуска и Панели задач (XML)
# ==============================================================================
Write-Host "`n>>> Шаг 5: Применение чистого макета..."
try {
    $LayoutXml = @"
<LayoutModificationTemplate xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification" xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout" Version="1">
  <LayoutOptions StartTileGroupCellWidth="6" />
  <DefaultLayoutOverride><StartLayoutCollection><defaultlayout:StartLayout GroupCellWidth="6" /></StartLayoutCollection></DefaultLayoutOverride>
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout><taskbar:TaskbarPinList>
        <taskbar:DesktopApp DesktopApplicationID="Microsoft.Windows.Explorer" />
    </taskbar:TaskbarPinList></defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@
    $ShellPath = "$env:LOCALAPPDATA\Microsoft\Windows\Shell"
    if (!(Test-Path $ShellPath)) { New-Item -Path $ShellPath -Force | Out-Null }
    $LayoutXml | Out-File -FilePath "$ShellPath\LayoutModification.xml" -Encoding UTF8 -Force
    Write-Host "  [УСПЕШНО] XML макет создан."
} catch { Write-Host "  [ОШИБКА] Макет: $_" }

# ==============================================================================
# 6. Отключение телеметрии и мусора (Copilot, Consumer Features)
# ==============================================================================
Write-Host "`n>>> Шаг 6: Отключение мусора и телеметрии..."
try {
    $Cloud = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (!(Test-Path $Cloud)) { New-Item -Path $Cloud -Force | Out-Null }
    Set-ItemProperty -Path $Cloud -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force
    
    $Cdm = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    Set-ItemProperty -Path $Cdm -Name "SilentInstalledAppsEnabled" -Value 0 -Type DWord -Force
    
    Write-Host "  [УСПЕШНО] Реклама и автоустановка приложений отключены."
} catch { Write-Host "  [ОШИБКА] Мусор: $_" }

# ==============================================================================
# 7. Глобализация: Применение к Default User (Для новых пользователей)
# ==============================================================================
Write-Host "`n>>> Шаг 7: Настройка профиля по умолчанию (Default User)..." -ForegroundColor Yellow
$DefaultUserMounted = $false
try {
    # Подготовка
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    
    # Монтируем куст реестра нового пользователя
    reg load "HKU\DefaultUser" "C:\Users\Default\NTUSER.DAT" | Out-Null
    $DefaultUserMounted = $true

    # 1. Запрет Edge в Default User
    $D_Edge = "HKU\DefaultUser\Software\Policies\Microsoft\Edge"
    if (!(Test-Path "Registry::$D_Edge")) { New-Item -Path "Registry::$D_Edge" -Force | Out-Null }
    Set-ItemProperty -Path "Registry::$D_Edge" -Name "HideFirstRunExperience" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path "Registry::$D_Edge" -Name "CreateDesktopShortcut" -Value 0 -Type DWord -Force

    # 2. Настройки интерфейса
    $D_Adv = "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    if (Test-Path "Registry::$D_Adv") {
        Set-ItemProperty -Path "Registry::$D_Adv" -Name "ShowTaskViewButton" -Value 0 -Force
        Set-ItemProperty -Path "Registry::$D_Adv" -Name "TaskbarDa" -Value 0 -Force
    }

    # 3. Копируем LayoutModification.xml в папку Default
    $D_Shell = "C:\Users\Default\AppData\Local\Microsoft\Windows\Shell"
    if (!(Test-Path $D_Shell)) { New-Item -Path $D_Shell -ItemType Directory -Force | Out-Null }
    Copy-Item -Path "$env:LOCALAPPDATA\Microsoft\Windows\Shell\LayoutModification.xml" -Destination $D_Shell -Force

    Write-Host "  [УСПЕШНО] Настройки Default User применены."
} catch {
    Write-Host "  [ОШИБКА] Глобализация: $_"
} finally {
    if ($DefaultUserMounted) {
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        Start-Sleep -Seconds 2
        reg unload "HKU\DefaultUser" | Out-Null
    }
}

# ==============================================================================
# Финализация
# ==============================================================================
Write-Host "`n>>> Финализация..."
try {
    # Отключение OOBE конфиденциальности
    $Oobe = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE"
    if (!(Test-Path $Oobe)) { New-Item -Path $Oobe -Force | Out-Null }
    Set-ItemProperty -Path $Oobe -Name "DisablePrivacyExperience" -Value 1 -Type DWord -Force

    Write-Host "Перезапуск Проводника..."
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host " НАСТРОЙКА ЗАВЕРШЕНА! Рекомендуется перезагрузка." -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
} catch { Write-Host "Ошибка при завершении." }

Stop-Transcript