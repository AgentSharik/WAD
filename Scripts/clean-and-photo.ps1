# =========================================================================
# Имя файла: clean-and-photo.ps1
# Назначение: Очистка системы и активация классического Photo Viewer
# =========================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# Логи в Документы Администратора (поддерживает русское имя пользователя)
$UserProfile = $env:USERPROFILE
$LogDir = Join-Path $UserProfile "Documents"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
Start-Transcript -Path (Join-Path $LogDir "System_Optimization.log") -Append

try {
    # ----------------------------------------------------
    # ЭТАП 1: ГЛУБОКАЯ ОЧИСТКА СИСТЕМЫ ОТ МУСОРА (DEBLOAT)
    # ----------------------------------------------------
    Write-Host ">>> Начало очистки встроенного мусора..."

    # Список масок приложений, которые нужно УДАЛИТЬ БЕЗЖАЛОСТНО
    # Магазин, Калькулятор, Заметки, Блокнот, Фото, Медиаплеер, Paint 3D и Xbox НЕ ТРОГАЕМ
    $BloatList = @(
        "Yandex.Music",                 # Превентивное удаление Яндекс.Музыки
        "Microsoft.ZuneMusic",          # Музыка Groove (Groove Music) - СНОСИМ!
        "office.outlook",               # Новый Outlook
        "windowscommunicationsapps",    # Почта и Календарь
        "Microsoft.3DViewer",           # 3D Просмотрщик
        "Microsoft.MixedReality.Portal",# Portal смешанной реальности
        "Microsoft.BingNews",           # Новости
        "Microsoft.BingWeather",        # Погода
        "Microsoft.BingFinance",        # Финансы
        "Microsoft.BingSports",         # Спорт
        "Microsoft.MicrosoftSolitaireCollection", # Пасьянсы с рекламой
        "Microsoft.WindowsFeedbackHub", # Центр отзывов (Телеметрия)
        "Microsoft.GetHelp",            # Справка / Получить помощь
        "Microsoft.Getstarted",         # Советы / Начало работы
        "Microsoft.YourPhone",          # Связь с телефоном
        "Microsoft.MicrosoftTeams",     # Teams
        "Microsoft.SkypeApp",           # Skype
        "Microsoft.54958562F4433"       # Clipchamp (Видеоредактор)
    )

    foreach ($App in $BloatList) {
        Write-Host "Удаление пакета: $App"
        # Удаляем у текущих пользователей
        Get-AppxPackage -AllUsers | Where-Object { $_.Name -match $App } | Remove-AppxPackage -ErrorAction SilentlyContinue
        # Удаляем из заготовок системы (чтобы не вернулся при обновлениях)
        Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -match $App } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    }
    Write-Host ">>> Очистка UWP-приложений завершена."

    # Полное удаление OneDrive из системы
    Write-Host ">>> Удаление OneDrive..."
    Stop-Process -Name 'OneDrive' -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (Test-Path "$env:SystemRoot\System32\OneDriveSetup.exe") { Start-Process "$env:SystemRoot\System32\OneDriveSetup.exe" -ArgumentList '/uninstall' -Wait }
    if (Test-Path "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") { Start-Process "$env:SystemRoot\SysWOW64\OneDriveSetup.exe" -ArgumentList '/uninstall' -Wait }

    # ----------------------------------------------------
    # ЭТАП 2: АКТИВАЦИЯ КЛАССИЧЕСКОГО ПРОСМОТРА ФОТО
    # ----------------------------------------------------
    Write-Host ">>> Активация Просмотра фотографий Windows 7..."
    
    # 1) Включаем ассоциации в HKLM
    $assocPath = "HKLM:\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations"
    if (-not (Test-Path $assocPath)) { New-Item -Path $assocPath -Force | Out-Null }
    @(".jpg",".jpeg",".png",".bmp",".gif",".tif",".tiff",".jfif",".wdp") | ForEach-Object {
        Set-ItemProperty -Path $assocPath -Name $_ -Value "PhotoViewer.FileAssoc.Tiff" -Force
    }

    # 2) Создаём DefaultAppAssociations.xml для DISM
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

    # 3) Импорт через DISM
    $dismArgs = @("/Online", "/Import-DefaultAppAssociations:$daaPath")
    $p = Start-Process -FilePath "dism.exe" -ArgumentList $dismArgs -PassThru -Wait -NoNewWindow
    if ($p.ExitCode -ne 0) { throw "DISM завершился с кодом $($p.ExitCode)." }

    # 4) Регистрация в RegisteredApplications
    Set-ItemProperty -Path "HKLM:\SOFTWARE\RegisteredApplications" -Name "Windows Photo Viewer" -Value "SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities" -Force
    
    Write-Host ">>> Просмотр фотографий успешно настроен по умолчанию!"

} catch {
    Write-Warning "Ошибка во время оптимизации: $($_.Exception.Message)"
} finally {
    Stop-Transcript
}
