# ==============================================================================
# Проверка прав администратора
# ==============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ==============================================================================
# Функции и интерфейс (WPF)
# ==============================================================================
Add-Type -AssemblyName PresentationFramework

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="#151720"
        WindowStartupLocation="CenterScreen" Width="650" Height="340" Topmost="True">
    <Border BorderBrush="#4C7BB0" BorderThickness="1" CornerRadius="0">
        <Grid Margin="30,25,30,25">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            
            <Grid Grid.Row="0">
                <TextBlock Text="ЗАГРУЗЧИК АВТОМАТИЧЕСКОЙ НАСТРОЙКИ" Foreground="#7A9EEB" FontSize="18" FontWeight="Bold" VerticalAlignment="Center" />
                <Button Name="BtnCloseTop" Content="✕" HorizontalAlignment="Right" VerticalAlignment="Center" Width="30" Height="30" FontSize="16" Cursor="Hand" ToolTip="Закрыть">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border Name="Border" BorderBrush="#4C7BB0" BorderThickness="1" Background="Transparent">
                                <TextBlock Text="{TemplateBinding Content}" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,0,0,2"/>
                            </Border>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
            </Grid>
            
            <Rectangle Grid.Row="1" Height="1" Fill="#4C7BB0" Margin="0,20,0,25"/>
            <TextBlock Name="TxtMessage" Grid.Row="2" Foreground="White" FontSize="15" TextWrapping="Wrap" LineHeight="24" VerticalAlignment="Top" />
            <TextBlock Name="TxtNote" Grid.Row="3" Foreground="#888888" FontSize="12" TextWrapping="Wrap" HorizontalAlignment="Center" Margin="0,10,0,0"/>
            
            <Button Name="BtnExit" Grid.Row="4" Content="ВЫХОД" Height="40" Margin="0,15,0,0" Cursor="Hand" FontWeight="Bold" FontSize="13" Foreground="White">
                <Button.Template>
                    <ControlTemplate TargetType="Button">
                        <Border Name="Border" Background="#353746">
                            <TextBlock Text="{TemplateBinding Content}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Button.Template>
            </Button>
        </Grid>
    </Border>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$txtMessage  = $window.FindName("TxtMessage")
$txtNote     = $window.FindName("TxtNote")
$btnCloseTop = $window.FindName("BtnCloseTop")
$btnExit     = $window.FindName("BtnExit")

$btnCloseTop.Add_Click({ $window.Close(); exit })
$btnExit.Add_Click({ $window.Close(); exit })

function Test-Internet {
    try {
        $request = [System.Net.WebRequest]::Create("http://clients3.google.com/generate_204")
        $request.Timeout = 3000
        $response = $request.GetResponse()
        $response.Close()
        return $true
    } catch { return $false }
}

$desktopPath   = [Environment]::GetFolderPath('Desktop')
$loaderPs1Path = Join-Path $desktopPath "loader.ps1"
$loaderCmdPath = Join-Path $desktopPath "Loader.cmd"

if (-not (Test-Internet)) {
    # Логика работы без интернета (создание лоадера на рабочем столе)
    $txtMessage.Text = "Нет интернета. Подключите сеть и запустите Loader.cmd с рабочего стола."
    $txtMessage.Foreground = "#E57373"
    $window.ShowDialog() | Out-Null
    exit
}

# --- ИНТЕРНЕТ ЕСТЬ: НАЧИНАЕМ ЗАГРУЗКУ ---
$txtMessage.Text = "✓ Соединение установлено.`n`nЗагрузка всех скриптов (Clean Windows)...`nПожалуйста, подождите."
$txtMessage.Foreground = "#81C784"
$window.Show()
$window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $targetBasePath = "C:\Windows\Setup"
    $finalScriptsPath = Join-Path -Path $targetBasePath -ChildPath "Scripts"
    $zipPath = Join-Path -Path $env:TEMP -ChildPath "repo.zip"
    $tempExtractPath = Join-Path -Path $env:TEMP -ChildPath "repo_temp"

    # Полная очистка перед установкой
    if (Test-Path $tempExtractPath) { Remove-Item -Path $tempExtractPath -Recurse -Force }
    if (Test-Path $finalScriptsPath) { Remove-Item -Path $finalScriptsPath -Recurse -Force }
    if (-not (Test-Path $targetBasePath)) { New-Item -Path $targetBasePath -ItemType Directory -Force }
    New-Item -Path $finalScriptsPath -ItemType Directory -Force | Out-Null

    # Скачивание архива
    $url = "https://github.com/AgentSharik/powershell-scripts/archive/refs/heads/main.zip"
    Invoke-WebRequest -Uri $url -OutFile $zipPath

    # Распаковка
    Expand-Archive -Path $zipPath -DestinationPath $tempExtractPath -Force

    # Находим корень репозитория в архиве и путь к нужной папке
    $repoRoot = Get-ChildItem -Path $tempExtractPath -Directory | Select-Object -First 1
    $sourcePath = Join-Path -Path $repoRoot.FullName -ChildPath "Scripts\Scripts for Clean Windows"

    if (Test-Path $sourcePath) {
        # ВАЖНО: Копируем именно СОДЕРЖИМОЕ папки (*), чтобы не пропустить ни один файл
        Copy-Item -Path "$sourcePath\*" -Destination $finalScriptsPath -Recurse -Force
        
        # Исправление кодировки для всех скачанных .ps1 (включая initial-setup.ps1)
        $psFiles = Get-ChildItem -Path $finalScriptsPath -Filter "*.ps1" -Recurse
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        foreach ($file in $psFiles) {
            $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
            [System.IO.File]::WriteAllText($file.FullName, $content, $utf8Bom)
        }

        # Запуск главного меню
        $managerScript = Join-Path -Path $finalScriptsPath -ChildPath "manager.ps1"
        if (Test-Path $managerScript) {
            Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoExit -File `"$managerScript`""
        }
    }

    # Очистка временных файлов
    Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
    
} catch {
    [System.Windows.MessageBox]::Show("Ошибка: $($_.Exception.Message)")
} finally {
    $window.Close()
}