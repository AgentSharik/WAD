# ==============================================================================
# Скрипт: clean-and-photo.ps1
# Описание: Очистка UWP-мусора, полное удаление OneDrive, возврат фото,
#           файл подкачки.
# ==============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# Логи в Документы Администратора
$UserProfile = $env:USERPROFILE
$LogDir = Join-Path $UserProfile "Documents"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
Start-Transcript -Path (Join-Path $LogDir "System_Optimization.log") -Append

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
$Extensions = @(".jpg", ".jpeg", ".jpe", ".png", ".bmp", ".dib", ".gif", ".tif", ".tiff")
if (!(Test-Path $RegistryPath)) { New-Item -Path $RegistryPath -Force | Out-Null }
foreach ($ext in $Extensions) { New-ItemProperty -Path $RegistryPath -Name $ext -Value "PhotoViewer.FileAssoc.Tiff" -PropertyType String -Force | Out-Null }

# ==============================================================================
# 4. Проверка ОЗУ и настройка файла подкачки
# ==============================================================================
Write-Host ">>> Проверка объема ОЗУ и настройка файла подкачки..."
$RAM_Bytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
$RAM_GB = [math]::Round($RAM_Bytes / 1GB)
Write-Host "Установлено оперативной памяти: $RAM_GB ГБ"
if ($RAM_GB -lt 32) {
    Write-Host "ОЗУ меньше 32 ГБ. Включаем автоматический объем файла подкачки..."
    $ComputerSystem = Get-CimInstance Win32_ComputerSystem
    if ($ComputerSystem.AutomaticManagedPagefile -eq $false) {
        Set-CimInstance -Query "Select * from Win32_ComputerSystem" -Property @{AutomaticManagedPagefile=$true}
    }
}

# ==============================================================================
# Финализация
# ==============================================================================
Write-Host "========================================================="
Write-Host " ВСЕ ЭТАПЫ ВЫПОЛНЕНЫ. ЗАКРЫТИЕ ЛОГА."
Write-Host "========================================================="
Stop-Transcript