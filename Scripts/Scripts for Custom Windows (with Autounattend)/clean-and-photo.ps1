# =========================================================================
# Имя файла: clean-optimization-full.ps1
# Назначение: Очистка системы, Photo Viewer, файл подкачки и удаление Edge-ярлыков
# =========================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# Логи в Документы Администратора
$UserProfile = $env:USERPROFILE
$LogDir = Join-Path $UserProfile "Documents"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
Start-Transcript -Path (Join-Path $LogDir "System_Optimization.log") -Append

try {
    # ----------------------------------------------------
    # ЭТАП 1: ГЛУБОКАЯ ОЧИСТКА СИСТЕМЫ ОТ МУСОРА (DEBLOAT)
    # ----------------------------------------------------
    Write-Host ">>> Начало очистки встроенного мусора..." -ForegroundColor Cyan

    $BloatList = @(
        "Yandex.Music",                 
        "Microsoft.ZuneMusic",          
        "office.outlook",               
        "windowscommunicationsapps",    
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
        "Microsoft.54958562F4433"       
    )

    foreach ($App in $BloatList) {
        Write-Host "Удаление пакета: $App"
        Get-AppxPackage -AllUsers | Where-Object { $_.Name -match $App } | Remove-AppxPackage -ErrorAction SilentlyContinue
        Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -match $App } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    }

    # Полное удаление OneDrive
    Write-Host ">>> Удаление OneDrive..." -ForegroundColor Cyan
    Stop-Process -Name 'OneDrive' -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (Test-Path "$env:SystemRoot\System32\OneDriveSetup.exe") { Start-Process "$env:SystemRoot\System32\OneDriveSetup.exe" -ArgumentList '/uninstall' -Wait }
    if (Test-Path "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") { Start-Process "$env:SystemRoot\SysWOW64\OneDriveSetup.exe" -ArgumentList '/uninstall' -Wait }

    # ----------------------------------------------------
    # ЭТАП 2: АКТИВАЦИЯ КЛАССИЧЕСКОГО ПРОСМОТРА ФОТО
    # ----------------------------------------------------
    Write-Host "`n>>> Активация Просмотра фотографий Windows 7..." -ForegroundColor Cyan
    
    $assocPath = "HKLM:\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations"
    if (-not (Test-Path $assocPath)) { New-Item -Path $assocPath -Force | Out-Null }
    @(".jpg",".jpeg",".png",".bmp",".gif",".tif",".tiff",".jfif",".wdp") | ForEach-Object {
        Set-ItemProperty -Path $assocPath -Name $_ -Value "PhotoViewer.FileAssoc.Tiff" -Force
    }

    $daaPath = "C:\Windows\Setup\Scripts\DefaultAppAssociations.xml"
    if (!(Test-Path (Split-Path $daaPath))) { New-Item -ItemType Directory -Force -Path (Split-Path $daaPath) | Out-Null }
    
    $xmlContent = @'
<?xml version="1.0" encoding="UTF-8"?>
<DefaultAssociations>
  <Association Identifier=".jpg"  ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
  <Association Identifier=".jpeg" ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
  <Association Identifier=".jfif" ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
  <Association Identifier=".png"  ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
  <Association Identifier=".bmp"  ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
  <Association Identifier=".gif"  ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
  <Association Identifier=".tif"  ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
  <Association Identifier=".tiff" ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
  <Association Identifier=".wdp"  ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
</DefaultAssociations>
'@
    [System.IO.File]::WriteAllText($daaPath, $xmlContent, [System.Text.Encoding]::UTF8)

    $dismArgs = @("/Online", "/Import-DefaultAppAssociations:$daaPath")
    $p = Start-Process -FilePath "dism.exe" -ArgumentList $dismArgs -PassThru -Wait -NoNewWindow
    # Код 14 (нужен рестарт) или 0 считаем успехом
    if ($p.ExitCode -notin @(0, 14)) { Write-Warning "DISM завершился с кодом $($p.ExitCode)." }

    Set-ItemProperty -Path "HKLM:\SOFTWARE\RegisteredApplications" -Name "Windows Photo Viewer" -Value "SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities" -Force
    Write-Host ">>> Просмотр фотографий успешно настроен!"

    # ----------------------------------------------------
    # ЭТАП 3: АВТОМАТИЧЕСКАЯ НАСТРОЙКА ФАЙЛА ПОДКАЧКИ
    # ----------------------------------------------------
    Write-Host "`n>>> Проверка объема ОЗУ и настройка файла подкачки..." -ForegroundColor Cyan
    
    $ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    $TotalRAM_GB = [Math]::Round($ComputerSystem.TotalPhysicalMemory / 1GB)
    Write-Host "Установлено оперативной памяти: $TotalRAM_GB ГБ"

    if ($TotalRAM_GB -lt 32) {
        Write-Host "Включаем автоматический объем файла подкачки..."
        if (-not $ComputerSystem.AutomaticManagedPagefile) {
            $ComputerSystem.AutomaticManagedPagefile = $true
            Set-CimInstance -CimInstance $ComputerSystem
        }
    } else {
        Write-Host "ОЗУ >= 32 ГБ. Полностью отключаем файл подкачки..."
        if ($ComputerSystem.AutomaticManagedPagefile) {
            $ComputerSystem.AutomaticManagedPagefile = $false
            Set-CimInstance -CimInstance $ComputerSystem
        }
        $PageFiles = Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue
        if ($PageFiles) { $PageFiles | Remove-CimInstance }
    }

    # ----------------------------------------------------
    # ЭТАП 4: УДАЛЕНИЕ И БЛОКИРОВКА ЯРЛЫКОВ EDGE
    # ----------------------------------------------------
    Write-Host "`n>>> Очистка ярлыков Microsoft Edge (все пользователи + будущие)..." -ForegroundColor Cyan

    # 1. Удаление существующих ярлыков (включая профиль по умолчанию)
    $EdgeShortcutPaths = @(
        "C:\Users\*\Desktop\Microsoft Edge.lnk",
        "C:\Users\Public\Desktop\Microsoft Edge.lnk",
        "C:\Users\Default\Desktop\Microsoft Edge.lnk"
    )
    foreach ($path in $EdgeShortcutPaths) {
        if (Test-Path $path) {
            Remove-Item -Path $path -Force -ErrorAction SilentlyContinue
            Write-Host "Удалено: $path"
        }
    }

    # 2. Запрет на создание ярлыков через политики реестра
    $EdgeRegSettings = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate"; Name = "CreateDesktopShortcutDefault"; Value = 0 },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer"; Name = "DisableEdgeDesktopShortcutCreation"; Value = 1 }
    )

    foreach ($reg in $EdgeRegSettings) {
        if (!(Test-Path $reg.Path)) { New-Item -Path $reg.Path -Force | Out-Null }
        Set-ItemProperty -Path $reg.Path -Name $reg.Name -Value $reg.Value -Type DWord -Force
    }

    # Запрет для всех каналов обновления Edge (Stable, Dev, Beta)
    $EdgeUpdatePath = "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate"
    @("Stable", "Dev", "Beta") | ForEach-Object {
        Set-ItemProperty -Path $EdgeUpdatePath -Name "CreateDesktopShortcut{$_}" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    Write-Host ">>> Создание ярлыков Edge заблокировано в реестре."

} catch {
    Write-Warning "Ошибка во время выполнения скрипта: $($_.Exception.Message)"
} finally {
    Write-Host "`n>>> Оптимизация завершена. Рекомендуется перезагрузка." -ForegroundColor Yellow
    Stop-Transcript
}
