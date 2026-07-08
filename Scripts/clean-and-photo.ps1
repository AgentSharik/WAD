# =========================================================================
# Имя файла: clean-and-photo.ps1
# Назначение: Очистка системы, классический Photo Viewer + умный файл подкачки
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
    Write-Host ">>> Начало очистки встроенного мусора..."

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
    Write-Host ">>> Очистка UWP-приложений завершена."

    # Полное удаление OneDrive
    Write-Host ">>> Удаление OneDrive..."
    Stop-Process -Name 'OneDrive' -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (Test-Path "$env:SystemRoot\System32\OneDriveSetup.exe") { Start-Process "$env:SystemRoot\System32\OneDriveSetup.exe" -ArgumentList '/uninstall' -Wait }
    if (Test-Path "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") { Start-Process "$env:SystemRoot\SysWOW64\OneDriveSetup.exe" -ArgumentList '/uninstall' -Wait }

    # ----------------------------------------------------
    # ЭТАП 2: АКТИВАЦИЯ КЛАССИЧЕСКОГО ПРОСМОТРА ФОТО
    # ----------------------------------------------------
    Write-Host "`n>>> Активация Просмотра фотографий Windows 7..."
    
    $assocPath = "HKLM:\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations"
    if (-not (Test-Path $assocPath)) { New-Item -Path $assocPath -Force | Out-Null }
    @(".jpg",".jpeg",".png",".bmp",".gif",".tif",".tiff",".jfif",".wdp") | ForEach-Object {
        Set-ItemProperty -Path $assocPath -Name $_ -Value "PhotoViewer.FileAssoc.Tiff" -Force
    }

    $daaPath = "C:\Windows\Setup\Scripts\DefaultAppAssociations.xml"
    New-Item -ItemType Directory -Force -Path (Split-Path $daaPath) | Out-Null
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
    if ($p.ExitCode -ne 0) { throw "DISM завершился с кодом $($p.ExitCode)." }

    Set-ItemProperty -Path "HKLM:\SOFTWARE\RegisteredApplications" -Name "Windows Photo Viewer" -Value "SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities" -Force
    Write-Host ">>> Просмотр фотографий успешно настроен по умолчанию!"

    # ----------------------------------------------------
    # ЭТАП 3: АВТОМАТИЧЕСКАЯ НАСТРОЙКА ФАЙЛА ПОДКАЧКИ (PAGEFILE)
    # ----------------------------------------------------
    Write-Host "`n>>> Проверка объема ОЗУ и настройка файла подкачки..."
    
    $ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    # Получаем точный объем ОЗУ в ГБ
    $TotalRAM_GB = [Math]::Round($ComputerSystem.TotalPhysicalMemory / 1GB)
    Write-Host "Установлено оперативной памяти: $TotalRAM_GB ГБ"

    if ($TotalRAM_GB -lt 32) {
        Write-Host "ОЗУ меньше 32 ГБ. Включаем автоматический объем файла подкачки..."
        if (-not $ComputerSystem.AutomaticManagedPagefile) {
            $ComputerSystem.AutomaticManagedPagefile = $true
            Set-CimInstance -CimInstance $ComputerSystem
        }
        Write-Host ">>> Файл подкачки переведен в автоматический режим."
    } else {
        Write-Host "ОЗУ больше 31 ГБ ($TotalRAM_GB ГБ). Полностью отключаем файл подкачки..."
        # 1. Отключаем автоматическое управление, чтобы разблокировать удаление
        if ($ComputerSystem.AutomaticManagedPagefile) {
            $ComputerSystem.AutomaticManagedPagefile = $false
            Set-CimInstance -CimInstance $ComputerSystem
        }
        # 2. Очищаем все существующие файлы подкачки на накопителях
        $PageFiles = Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue
        if ($PageFiles) {
            $PageFiles | Remove-CimInstance
            Write-Host ">>> Старые конфигурации файлов подкачки удалены."
        }
        Write-Host ">>> Файл подкачки успешно отключен. Изменения вступят в силу после ребута."
    }

} catch {
    Write-Warning "Ошибка во время оптимизации: $($_.Exception.Message)"
} finally {
    Stop-Transcript
}
