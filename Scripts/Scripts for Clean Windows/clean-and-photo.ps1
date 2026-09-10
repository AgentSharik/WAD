# ==============================================================================
# Скрипт: clean-and-photo.ps1
# Описание: Очистка UWP-мусора, полное удаление OneDrive, возврат фото
#           (реестр + DISM-ассоциации), файл подкачки по объёму ОЗУ.
# ==============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# Логи в Документы Администратора
$UserProfile = $env:USERPROFILE
$LogDir = Join-Path $UserProfile "Documents"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
Start-Transcript -Path (Join-Path $LogDir "System_Optimization.log") -Append

# Менеджер судит о результате по коду возврата процесса, а не по тексту лога.
# Без этого любой сбой выглядел как «✓ Готово».
trap {
    Write-Host "ОШИБКА: $($_.Exception.Message)"
    try { Stop-Transcript } catch { }
    exit 1
}

# ==============================================================================
# 1. Очистка встроенного мусора
# ==============================================================================
Write-Host ">>> Начало очистки встроенного мусора..."

$BloatList = @(
    "Yandex.Music", "Microsoft.ZuneMusic", "office.outlook",
    "microsoft.windowscommunicationsapps", "Microsoft.3DViewer",
    "Microsoft.MixedReality.Portal", "Microsoft.BingNews",
    "Microsoft.BingWeather", "Microsoft.BingFinance", "Microsoft.BingSports",
    "Microsoft.MicrosoftSolitaireCollection", "Microsoft.WindowsFeedbackHub",
    "Microsoft.GetHelp", "Microsoft.Getstarted", "Microsoft.YourPhone",
    "Microsoft.MicrosoftTeams", "Microsoft.SkypeApp", "Microsoft.54958562F4433",
    "Microsoft.WindowsCamera", "Microsoft.Windows.Ai.Copilot.Provider",
    "Microsoft.Office.OneNote", "Microsoft.OutlookForWindows", "Microsoft.People",
    "Microsoft.Wallet", "Microsoft.BingSearch", "Clipchamp.Clipchamp",
    "MicrosoftCorporationII.MicrosoftFamily", "Microsoft.MicrosoftOfficeHub",
    "Microsoft.MicrosoftStickyNotes", "Microsoft.Todos", "Microsoft.Windows.DevHome",
    "Microsoft.WindowsMaps", "Microsoft.WindowsSoundRecorder"
)

$AllAppx = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
$AllProv = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

foreach ($App in $BloatList) {
    $Package = $AllAppx | Where-Object Name -match $App
    $ProvPackage = $AllProv | Where-Object DisplayName -match $App
    
    if ($Package -or $ProvPackage) {
        Write-Host "Удаление пакета: $App"
        if ($Package) { $Package | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue 2>$null }
        if ($ProvPackage) { $ProvPackage | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue 2>$null | Out-Null }
    }
}
Write-Host ">>> Очистка UWP-приложений завершена."


# ==============================================================================
# 2. Тотальное удаление и блокировка OneDrive
# ==============================================================================
Write-Host ">>> Удаление и полная блокировка OneDrive..."

if (Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue) { taskkill.exe /F /IM "OneDrive.exe" /T 2>$null }

$oneDriveSetup = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
if (!(Test-Path $oneDriveSetup)) { $oneDriveSetup = "$env:SystemRoot\System32\OneDriveSetup.exe" }

if (Test-Path $oneDriveSetup) {
    if ((Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") -or (Test-Path "$env:PROGRAMFILES\Microsoft OneDrive\OneDrive.exe") -or (Test-Path "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe")) {
        Start-Process -FilePath $oneDriveSetup -ArgumentList "/uninstall" -Wait -NoNewWindow
        Start-Sleep -Seconds 2
    }
}

$ODPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
if (!(Test-Path $ODPolicyPath)) { New-Item -Path $ODPolicyPath -Force | Out-Null }
New-ItemProperty -Path $ODPolicyPath -Name "DisableFileSyncNGSC" -Value 1 -PropertyType DWord -Force | Out-Null

$ODExplorerPath = "HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
if (Test-Path $ODExplorerPath) { Set-ItemProperty -Path $ODExplorerPath -Name "System.IsPinnedToNameSpaceTree" -Value 0 -Force -ErrorAction SilentlyContinue }
$ODExplorerPath32 = "HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
if (Test-Path $ODExplorerPath32) { Set-ItemProperty -Path $ODExplorerPath32 -Name "System.IsPinnedToNameSpaceTree" -Value 0 -Force -ErrorAction SilentlyContinue }

Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDriveSetup" -ErrorAction SilentlyContinue 2>$null
Get-ScheduledTask -TaskName "OneDrive Standalone Update Task*" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue

$Shortcuts = @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk", "$env:ALLUSERSPROFILE\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk")
foreach ($shortcut in $Shortcuts) { if (Test-Path $shortcut) { Remove-Item -Path $shortcut -Force -ErrorAction SilentlyContinue } }

$FoldersToClean = @("$env:LOCALAPPDATA\Microsoft\OneDrive", "$env:PROGRAMDATA\Microsoft OneDrive", "C:\OneDriveTemp")
foreach ($dir in $FoldersToClean) { if (Test-Path $dir) { Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue 2>$null } }
Write-Host ">>> OneDrive удален с ПК"

# ==============================================================================
# 3. Активация классического Просмотра фотографий Windows 7
# ==============================================================================
Write-Host ">>> Активация Просмотра фотографий Windows 7..."
$RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations"
$Extensions = @(".jpg", ".jpeg", ".jpe", ".png", ".bmp", ".dib", ".gif", ".tif", ".tiff", ".jfif", ".wdp")
if (!(Test-Path $RegistryPath)) { New-Item -Path $RegistryPath -Force | Out-Null }
foreach ($ext in $Extensions) { New-ItemProperty -Path $RegistryPath -Name $ext -Value "PhotoViewer.FileAssoc.Tiff" -PropertyType String -Force | Out-Null }
New-ItemProperty -Path "HKLM:\SOFTWARE\RegisteredApplications" -Name "Windows Photo Viewer" `
    -Value "SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities" -PropertyType String -Force | Out-Null

# Одного реестра мало: Windows 10/11 раздаёт ассоциации из файла ответов через DISM.
# Без этого шага двойной щелчок по фото открывает «Фотографии» (перенесено из Custom 25.07).
$DaaPath = "C:\Windows\Setup\Scripts\DefaultAppAssociations.xml"
New-Item -ItemType Directory -Force -Path (Split-Path $DaaPath) | Out-Null
$DaaXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<DefaultAssociations>
  <Association Identifier=".jpg"  ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
  <Association Identifier=".jpeg" ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
  <Association Identifier=".jpe"  ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
  <Association Identifier=".jfif" ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
  <Association Identifier=".png"  ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
  <Association Identifier=".bmp"  ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
  <Association Identifier=".dib"  ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
  <Association Identifier=".gif"  ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
  <Association Identifier=".tif"  ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
  <Association Identifier=".tiff" ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
  <Association Identifier=".wdp"  ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
</DefaultAssociations>
'@
[System.IO.File]::WriteAllText($DaaPath, $DaaXml, [System.Text.Encoding]::UTF8)

$DismProc = Start-Process -FilePath "dism.exe" `
    -ArgumentList @("/Online", "/Import-DefaultAppAssociations:$DaaPath") -PassThru -Wait -NoNewWindow
if ($DismProc.ExitCode -ne 0) { throw "DISM завершился с кодом $($DismProc.ExitCode)." }
Write-Host ">>> Фото назначены по умолчанию (реестр + DISM)."

# ==============================================================================
# 4. Проверка ОЗУ и настройка файла подкачки
# ==============================================================================
Write-Host ">>> Проверка объема ОЗУ и настройка файла подкачки..."
$ComputerSystem = Get-CimInstance Win32_ComputerSystem
$RAM_GB = [math]::Round($ComputerSystem.TotalPhysicalMemory / 1GB)
Write-Host "Установлено оперативной памяти: $RAM_GB ГБ"
if ($RAM_GB -lt 32) {
    Write-Host "ОЗУ меньше 32 ГБ. Включаем автоматический объем файла подкачки..."
    if ($ComputerSystem.AutomaticManagedPagefile -eq $false) {
        Set-CimInstance -Query "Select * from Win32_ComputerSystem" -Property @{AutomaticManagedPagefile=$true}
    }
    Write-Host ">>> Файл подкачки в автоматическом режиме."
} else {
    # Перенесено из Custom 25.07: на 32 ГБ и больше Windows сама не отключает подкачку.
    Write-Host "ОЗУ 32 ГБ и больше ($RAM_GB ГБ). Отключаем файл подкачки..."
    if ($ComputerSystem.AutomaticManagedPagefile -eq $true) {
        Set-CimInstance -Query "Select * from Win32_ComputerSystem" -Property @{AutomaticManagedPagefile=$false}
    }
    $PageFiles = Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue
    if ($PageFiles) {
        $PageFiles | Remove-CimInstance
        Write-Host ">>> Прежние настройки файла подкачки удалены."
    }
    Write-Host ">>> Файл подкачки отключен, изменения вступят в силу после перезагрузки."
}

# ==============================================================================
# Финализация
# ==============================================================================
Write-Host "========================================================="
Write-Host " ВСЕ ЭТАПЫ ВЫПОЛНЕНЫ. ЗАКРЫТИЕ ЛОГА."
Write-Host "========================================================="
Stop-Transcript