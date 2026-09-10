# ==============================================================================
# &#x41F;&#x440;&#x43E;&#x432;&#x435;&#x440;&#x43A;&#x430; &#x43F;&#x440;&#x430;&#x432; &#x430;&#x434;&#x43C;&#x438;&#x43D;&#x438;&#x441;&#x442;&#x440;&#x430;&#x442;&#x43E;&#x440;&#x430;
# ==============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    # &#x41F;&#x435;&#x440;&#x435;&#x437;&#x430;&#x43F;&#x443;&#x441;&#x43A; &#x441; &#x43F;&#x440;&#x430;&#x432;&#x430;&#x43C;&#x438; &#x430;&#x434;&#x43C;&#x438;&#x43D;&#x430; &#x438; &#x441;&#x43A;&#x440;&#x44B;&#x442;&#x438;&#x435;&#x43C; &#x447;&#x435;&#x440;&#x43D;&#x43E;&#x433;&#x43E; &#x43E;&#x43A;&#x43D;&#x430; &#x43A;&#x43E;&#x43D;&#x441;&#x43E;&#x43B;&#x438; (-WindowStyle Hidden)
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ==============================================================================
# &#x424;&#x443;&#x43D;&#x43A;&#x446;&#x438;&#x438; &#x438; &#x438;&#x43D;&#x442;&#x435;&#x440;&#x444;&#x435;&#x439;&#x441; (WPF)
# ==============================================================================
Add-Type -AssemblyName PresentationFramework

# XAML-&#x434;&#x438;&#x437;&#x430;&#x439;&#x43D; &#x43E;&#x43A;&#x43D;&#x430; (&#x442;&#x435;&#x43C;&#x43D;&#x430;&#x44F; &#x442;&#x435;&#x43C;&#x430;, &#x443;&#x432;&#x435;&#x43B;&#x438;&#x447;&#x435;&#x43D;&#x430; &#x432;&#x44B;&#x441;&#x43E;&#x442;&#x430; &#x434;&#x43E; 340 &#x434;&#x43B;&#x44F; &#x432;&#x43C;&#x435;&#x449;&#x435;&#x43D;&#x438;&#x44F; &#x442;&#x435;&#x43A;&#x441;&#x442;&#x430;)
[xml]$xaml = @"
&lt;Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="#151720"
        WindowStartupLocation="CenterScreen" Width="650" Height="340" Topmost="True"&gt;
    &lt;Border BorderBrush="#4C7BB0" BorderThickness="1" CornerRadius="0"&gt;
        &lt;Grid Margin="30,25,30,25"&gt;
            &lt;Grid.RowDefinitions&gt;
                &lt;RowDefinition Height="Auto"/&gt;
                &lt;RowDefinition Height="Auto"/&gt;
                &lt;RowDefinition Height="*"/&gt;
                &lt;RowDefinition Height="Auto"/&gt;
                &lt;RowDefinition Height="Auto"/&gt;
            &lt;/Grid.RowDefinitions&gt;
            
            &lt;Grid Grid.Row="0"&gt;
                &lt;TextBlock Text="&#x417;&#x410;&#x413;&#x420;&#x423;&#x417;&#x427;&#x418;&#x41A; &#x410;&#x412;&#x422;&#x41E;&#x41C;&#x410;&#x422;&#x418;&#x427;&#x415;&#x421;&#x41A;&#x41E;&#x419; &#x41D;&#x410;&#x421;&#x422;&#x420;&#x41E;&#x419;&#x41A;&#x418;" Foreground="#7A9EEB" FontSize="18" FontWeight="Bold" VerticalAlignment="Center" /&gt;
                
                &lt;!-- &#x41A;&#x430;&#x441;&#x442;&#x43E;&#x43C;&#x43D;&#x430;&#x44F; &#x43A;&#x43D;&#x43E;&#x43F;&#x43A;&#x430; &#x437;&#x430;&#x43A;&#x440;&#x44B;&#x442;&#x438;&#x44F; (&#x41A;&#x440;&#x435;&#x441;&#x442;&#x438;&#x43A; &#x441;&#x432;&#x435;&#x440;&#x445;&#x443;) --&gt;
                &lt;Button Name="BtnCloseTop" Content="&#x2715;" HorizontalAlignment="Right" VerticalAlignment="Center" Width="30" Height="30" FontSize="16" Cursor="Hand" ToolTip="&#x417;&#x430;&#x43A;&#x440;&#x44B;&#x442;&#x44C;"&gt;
                    &lt;Button.Template&gt;
                        &lt;ControlTemplate TargetType="Button"&gt;
                            &lt;Border Name="Border" BorderBrush="#4C7BB0" BorderThickness="1" Background="Transparent"&gt;
                                &lt;TextBlock Text="{TemplateBinding Content}" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,0,0,2"/&gt;
                            &lt;/Border&gt;
                            &lt;ControlTemplate.Triggers&gt;
                                &lt;Trigger Property="IsMouseOver" Value="True"&gt;
                                    &lt;Setter TargetName="Border" Property="Background" Value="#4C7BB0" /&gt;
                                    &lt;Setter Property="Foreground" Value="White" /&gt;
                                &lt;/Trigger&gt;
                                &lt;Trigger Property="IsMouseOver" Value="False"&gt;
                                    &lt;Setter Property="Foreground" Value="#7A9EEB" /&gt;
                                &lt;/Trigger&gt;
                            &lt;/ControlTemplate.Triggers&gt;
                        &lt;/ControlTemplate&gt;
                    &lt;/Button.Template&gt;
                &lt;/Button&gt;
            &lt;/Grid&gt;
            
            &lt;Rectangle Grid.Row="1" Height="1" Fill="#4C7BB0" Margin="0,20,0,25"/&gt;
            
            &lt;TextBlock Name="TxtMessage" Grid.Row="2" Foreground="White" FontSize="15" TextWrapping="Wrap" LineHeight="24" VerticalAlignment="Top" /&gt;
            
            &lt;TextBlock Name="TxtNote" Grid.Row="3" Foreground="#888888" FontSize="12" TextWrapping="Wrap" HorizontalAlignment="Center" Margin="0,10,0,0"/&gt;
            
            &lt;!-- &#x411;&#x43E;&#x43B;&#x44C;&#x448;&#x430;&#x44F; &#x43F;&#x43B;&#x43E;&#x441;&#x43A;&#x430;&#x44F; &#x43A;&#x43D;&#x43E;&#x43F;&#x43A;&#x430; &#x412;&#x42B;&#x425;&#x41E;&#x414; &#x441;&#x43D;&#x438;&#x437;&#x443; --&gt;
            &lt;Button Name="BtnExit" Grid.Row="4" Content="&#x412;&#x42B;&#x425;&#x41E;&#x414;" Height="40" Margin="0,15,0,0" Cursor="Hand" FontWeight="Bold" FontSize="13" Foreground="White"&gt;
                &lt;Button.Template&gt;
                    &lt;ControlTemplate TargetType="Button"&gt;
                        &lt;!-- &#x426;&#x432;&#x435;&#x442; &#x444;&#x43E;&#x43D;&#x430; &#x43A;&#x430;&#x43A; &#x43D;&#x430; &#x432;&#x430;&#x448;&#x435;&#x43C; &#x441;&#x43A;&#x440;&#x438;&#x43D;&#x448;&#x43E;&#x442;&#x435; --&gt;
                        &lt;Border Name="Border" Background="#353746" BorderThickness="0"&gt;
                            &lt;TextBlock Text="{TemplateBinding Content}" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,0,0,1"/&gt;
                        &lt;/Border&gt;
                        &lt;ControlTemplate.Triggers&gt;
                            &lt;Trigger Property="IsMouseOver" Value="True"&gt;
                                &lt;!-- &#x41F;&#x43E;&#x434;&#x441;&#x432;&#x435;&#x442;&#x43A;&#x430; &#x43F;&#x440;&#x438; &#x43D;&#x430;&#x432;&#x435;&#x434;&#x435;&#x43D;&#x438;&#x438; --&gt;
                                &lt;Setter TargetName="Border" Property="Background" Value="#4A4D62" /&gt;
                            &lt;/Trigger&gt;
                        &lt;/ControlTemplate.Triggers&gt;
                    &lt;/ControlTemplate&gt;
                &lt;/Button.Template&gt;
            &lt;/Button&gt;
        &lt;/Grid&gt;
    &lt;/Border&gt;
&lt;/Window&gt;
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$txtMessage  = $window.FindName("TxtMessage")
$txtNote     = $window.FindName("TxtNote")
$btnCloseTop = $window.FindName("BtnCloseTop")
$btnExit     = $window.FindName("BtnExit")

# &#x41E;&#x431;&#x440;&#x430;&#x431;&#x43E;&#x442;&#x447;&#x438;&#x43A;&#x438; &#x437;&#x430;&#x43A;&#x440;&#x44B;&#x442;&#x438;&#x44F; &#x43D;&#x430; &#x43E;&#x431;&#x435; &#x43A;&#x43D;&#x43E;&#x43F;&#x43A;&#x438;
$btnCloseTop.Add_Click({ $window.Close(); exit })
$btnExit.Add_Click({ $window.Close(); exit })

# &#x424;&#x443;&#x43D;&#x43A;&#x446;&#x438;&#x44F; &#x43F;&#x440;&#x43E;&#x432;&#x435;&#x440;&#x43A;&#x438; &#x438;&#x43D;&#x442;&#x435;&#x440;&#x43D;&#x435;&#x442;&#x430;
function Test-Internet {
    try {
        $request = [System.Net.WebRequest]::Create("http://clients3.google.com/generate_204")
        $request.Timeout = 3000
        $response = $request.GetResponse()
        $response.Close()
        return $true
    } catch {
        return $false
    }
}

# &#x41F;&#x443;&#x442;&#x438; &#x434;&#x43B;&#x44F; &#x441;&#x43E;&#x437;&#x434;&#x430;&#x43D;&#x438;&#x44F; &#x444;&#x430;&#x439;&#x43B;&#x43E;&#x432; &#x43D;&#x430; &#x420;&#x430;&#x431;&#x43E;&#x447;&#x435;&#x43C; &#x441;&#x442;&#x43E;&#x43B;&#x435;
$desktopPath   = [Environment]::GetFolderPath('Desktop')
$loaderPs1Path = Join-Path $desktopPath "loader.ps1"
$loaderCmdPath = Join-Path $desktopPath "Loader.cmd"

# &#x41D;&#x430;&#x434;&#x435;&#x436;&#x43D;&#x43E;&#x435; &#x43E;&#x43F;&#x440;&#x435;&#x434;&#x435;&#x43B;&#x435;&#x43D;&#x438;&#x435; &#x43F;&#x443;&#x442;&#x438; &#x442;&#x435;&#x43A;&#x443;&#x449;&#x435;&#x433;&#x43E; &#x437;&#x430;&#x43F;&#x443;&#x449;&#x435;&#x43D;&#x43D;&#x43E;&#x433;&#x43E; &#x441;&#x43A;&#x440;&#x438;&#x43F;&#x442;&#x430;
$currentScriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($currentScriptPath)) {
    $currentScriptPath = $MyInvocation.MyCommand.Definition
}

# ==============================================================================
# &#x41B;&#x43E;&#x433;&#x438;&#x43A;&#x430;: &#x418;&#x43D;&#x442;&#x435;&#x440;&#x43D;&#x435;&#x442; &#x41E;&#x422;&#x421;&#x423;&#x422;&#x421;&#x422;&#x412;&#x423;&#x415;&#x422;
# ==============================================================================
if (-not (Test-Internet)) {
    if (Test-Path $currentScriptPath) {
        # 1. &#x41A;&#x43E;&#x43F;&#x438;&#x440;&#x443;&#x435;&#x43C; &#x441;&#x430;&#x43C; &#x441;&#x43A;&#x440;&#x438;&#x43F;&#x442; (.ps1)
        Copy-Item -Path $currentScriptPath -Destination $loaderPs1Path -Force
        
        # &#x414;&#x435;&#x43B;&#x430;&#x435;&#x43C; &#x444;&#x430;&#x439;&#x43B; loader.ps1 &#x441;&#x43A;&#x440;&#x44B;&#x442;&#x44B;&#x43C;
        $ps1File = Get-Item -Path $loaderPs1Path -Force
        $ps1File.Attributes = $ps1File.Attributes -bor [System.IO.FileAttributes]::Hidden
        
        # 2. &#x421;&#x43E;&#x437;&#x434;&#x430;&#x435;&#x43C; &#x437;&#x430;&#x43F;&#x443;&#x441;&#x43A;&#x430;&#x442;&#x43E;&#x440; Loader.cmd (&#x432;&#x43D;&#x443;&#x442;&#x440;&#x438; &#x441;&#x43A;&#x440;&#x438;&#x43F;&#x442; &#x437;&#x430;&#x43F;&#x443;&#x441;&#x43A;&#x430;&#x435;&#x442; powershell &#x441;&#x43A;&#x440;&#x44B;&#x442;&#x43D;&#x43E;)
        $cmdContent = "@echo off`r`nPowerShell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"%~dp0loader.ps1`""
        Set-Content -Path $loaderCmdPath -Value $cmdContent -Force
    }
    
    # &#x41D;&#x430;&#x441;&#x442;&#x440;&#x430;&#x438;&#x432;&#x430;&#x435;&#x43C; &#x442;&#x435;&#x43A;&#x441;&#x442; &#x43E;&#x43A;&#x43D;&#x430;
    $txtMessage.Text = "&#x421;&#x43E;&#x435;&#x434;&#x438;&#x43D;&#x435;&#x43D;&#x438;&#x435; &#x441; &#x438;&#x43D;&#x442;&#x435;&#x440;&#x43D;&#x435;&#x442;&#x43E;&#x43C; &#x43D;&#x435; &#x43E;&#x431;&#x43D;&#x430;&#x440;&#x443;&#x436;&#x435;&#x43D;&#x43E;!`n`n&#x41F;&#x43E;&#x436;&#x430;&#x43B;&#x443;&#x439;&#x441;&#x442;&#x430;, &#x43F;&#x43E;&#x434;&#x43A;&#x43B;&#x44E;&#x447;&#x438;&#x442;&#x435;&#x441;&#x44C; &#x43A; &#x441;&#x435;&#x442;&#x438; (&#x432;&#x43A;&#x43B;&#x44E;&#x447;&#x438;&#x442;&#x435; Wi-Fi &#x438;&#x43B;&#x438; &#x432;&#x441;&#x442;&#x430;&#x432;&#x44C;&#x442;&#x435; Ethernet-&#x43A;&#x430;&#x431;&#x435;&#x43B;&#x44C;) &#x438; &#x437;&#x430;&#x43F;&#x443;&#x441;&#x442;&#x438;&#x442;&#x435; &#x43F;&#x43E;&#x44F;&#x432;&#x438;&#x432;&#x448;&#x438;&#x439;&#x441;&#x44F; &#x444;&#x430;&#x439;&#x43B; &#xAB;Loader.cmd&#xBB; &#x441; &#x420;&#x430;&#x431;&#x43E;&#x447;&#x435;&#x433;&#x43E; &#x441;&#x442;&#x43E;&#x43B;&#x430;."
    $txtMessage.Foreground = "#E57373" # &#x41A;&#x440;&#x430;&#x441;&#x43D;&#x44B;&#x439; &#x43E;&#x442;&#x442;&#x435;&#x43D;&#x43E;&#x43A;
    
    # &#x41E;&#x447;&#x438;&#x449;&#x430;&#x435;&#x43C; &#x43D;&#x438;&#x436;&#x43D;&#x44E;&#x44E; &#x43D;&#x430;&#x434;&#x43F;&#x438;&#x441;&#x44C;, &#x43A;&#x43D;&#x43E;&#x43F;&#x43A;&#x430; &#x412;&#x42B;&#x425;&#x41E;&#x414; &#x43E;&#x441;&#x442;&#x430;&#x435;&#x442;&#x441;&#x44F; &#x432;&#x438;&#x434;&#x438;&#x43C;&#x43E;&#x439;
    $txtNote.Text = "" 
    
    # &#x41F;&#x43E;&#x43A;&#x430;&#x437;&#x44B;&#x432;&#x430;&#x435;&#x43C; &#x43E;&#x43A;&#x43D;&#x43E; &#x438; &#x436;&#x434;&#x435;&#x43C; &#x437;&#x430;&#x43A;&#x440;&#x44B;&#x442;&#x438;&#x44F;
    $window.ShowDialog() | Out-Null
    exit
}

# ==============================================================================
# &#x41B;&#x43E;&#x433;&#x438;&#x43A;&#x430;: &#x418;&#x43D;&#x442;&#x435;&#x440;&#x43D;&#x435;&#x442; &#x415;&#x421;&#x422;&#x42C;
# ==============================================================================

# &#x423;&#x434;&#x430;&#x43B;&#x44F;&#x435;&#x43C; &#x432;&#x440;&#x435;&#x43C;&#x435;&#x43D;&#x43D;&#x44B;&#x435; &#x444;&#x430;&#x439;&#x43B;&#x44B; &#x441; &#x440;&#x430;&#x431;&#x43E;&#x447;&#x435;&#x433;&#x43E; &#x441;&#x442;&#x43E;&#x43B;&#x430;, &#x442;&#x430;&#x43A; &#x43A;&#x430;&#x43A; &#x43E;&#x43D;&#x438; &#x431;&#x43E;&#x43B;&#x44C;&#x448;&#x435; &#x43D;&#x435; &#x43D;&#x443;&#x436;&#x43D;&#x44B; (&#x438;&#x43D;&#x442;&#x435;&#x440;&#x43D;&#x435;&#x442; &#x435;&#x441;&#x442;&#x44C;)
if (Test-Path $loaderPs1Path) { Remove-Item -Path $loaderPs1Path -Force -ErrorAction SilentlyContinue }
if (Test-Path $loaderCmdPath) { Remove-Item -Path $loaderCmdPath -Force -ErrorAction SilentlyContinue }

# &#x41D;&#x430;&#x441;&#x442;&#x440;&#x430;&#x438;&#x432;&#x430;&#x435;&#x43C; &#x43E;&#x43A;&#x43D;&#x43E; &#x43F;&#x43E;&#x434; &#x437;&#x430;&#x433;&#x440;&#x443;&#x437;&#x43A;&#x443; (&#x43F;&#x440;&#x44F;&#x447;&#x435;&#x43C; &#x43A;&#x440;&#x435;&#x441;&#x442;&#x438;&#x43A; &#x441;&#x432;&#x435;&#x440;&#x445;&#x443; &#x438; &#x43A;&#x43D;&#x43E;&#x43F;&#x43A;&#x443; &#x441;&#x43D;&#x438;&#x437;&#x443;)
$btnCloseTop.Visibility = "Hidden" 
$btnExit.Visibility = "Collapsed" # &#x421;&#x445;&#x43B;&#x43E;&#x43F;&#x44B;&#x432;&#x430;&#x435;&#x43C; &#x43A;&#x43D;&#x43E;&#x43F;&#x43A;&#x443; &#x412;&#x42B;&#x425;&#x41E;&#x414;, &#x447;&#x442;&#x43E;&#x431;&#x44B; &#x43E;&#x43D;&#x430; &#x43D;&#x435; &#x437;&#x430;&#x43D;&#x438;&#x43C;&#x430;&#x43B;&#x430; &#x43C;&#x435;&#x441;&#x442;&#x43E;

$txtMessage.Text = "&#x2713; &#x421;&#x43E;&#x435;&#x434;&#x438;&#x43D;&#x435;&#x43D;&#x438;&#x435; &#x443;&#x441;&#x442;&#x430;&#x43D;&#x43E;&#x432;&#x43B;&#x435;&#x43D;&#x43E;.`n`n&#x418;&#x434;&#x435;&#x442; &#x441;&#x43A;&#x430;&#x447;&#x438;&#x432;&#x430;&#x43D;&#x438;&#x435; &#x440;&#x435;&#x43F;&#x43E;&#x437;&#x438;&#x442;&#x43E;&#x440;&#x438;&#x44F; &#x438; &#x440;&#x430;&#x441;&#x43F;&#x430;&#x43A;&#x43E;&#x432;&#x43A;&#x430; &#x444;&#x430;&#x439;&#x43B;&#x43E;&#x432;...`n&#x41F;&#x43E;&#x436;&#x430;&#x43B;&#x443;&#x439;&#x441;&#x442;&#x430;, &#x43F;&#x43E;&#x434;&#x43E;&#x436;&#x434;&#x438;&#x442;&#x435;."
$txtMessage.Foreground = "#81C784" # &#x417;&#x435;&#x43B;&#x435;&#x43D;&#x44B;&#x439; &#x43E;&#x442;&#x442;&#x435;&#x43D;&#x43E;&#x43A;
$txtNote.Text = "&#x41F;&#x43E;&#x436;&#x430;&#x43B;&#x443;&#x439;&#x441;&#x442;&#x430;, &#x43D;&#x435; &#x437;&#x430;&#x43A;&#x440;&#x44B;&#x432;&#x430;&#x439;&#x442;&#x435; &#x44D;&#x442;&#x43E; &#x43E;&#x43A;&#x43D;&#x43E; &#x434;&#x43E; &#x437;&#x430;&#x432;&#x435;&#x440;&#x448;&#x435;&#x43D;&#x438;&#x44F; &#x441;&#x43A;&#x430;&#x447;&#x438;&#x432;&#x430;&#x43D;&#x438;&#x44F;."

# &#x41F;&#x43E;&#x43A;&#x430;&#x437;&#x44B;&#x432;&#x430;&#x435;&#x43C; &#x43E;&#x43A;&#x43D;&#x43E; &#x430;&#x441;&#x438;&#x43D;&#x445;&#x440;&#x43E;&#x43D;&#x43D;&#x43E;
$window.Show()
$window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

# --- &#x41F;&#x420;&#x41E;&#x426;&#x415;&#x421;&#x421; &#x417;&#x410;&#x413;&#x420;&#x423;&#x417;&#x41A;&#x418; ---
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $targetBasePath = "C:\Windows\Setup"
    $finalScriptsPath = Join-Path -Path $targetBasePath -ChildPath "Scripts"
    $zipPath = Join-Path -Path $env:TEMP -ChildPath "powershell-scripts.zip"
    $tempExtractPath = Join-Path -Path $env:TEMP -ChildPath "temp-repo-extract"

    if (-not (Test-Path $targetBasePath)) { New-Item -Path $targetBasePath -ItemType Directory -Force | Out-Null }
    if (Test-Path $tempExtractPath) { Remove-Item -Path $tempExtractPath -Recurse -Force }
    if (Test-Path $finalScriptsPath) { Remove-Item -Path $finalScriptsPath -Recurse -Force }

    $urlMain = "https://github.com/AgentSharik/powershell-scripts/archive/refs/heads/main.zip"
    $urlMaster = "https://github.com/AgentSharik/powershell-scripts/archive/refs/heads/master.zip"

    try {
        Invoke-WebRequest -Uri $urlMain -OutFile $zipPath -ErrorAction Stop
    } catch {
        Invoke-WebRequest -Uri $urlMaster -OutFile $zipPath
    }

    Expand-Archive -Path $zipPath -DestinationPath $tempExtractPath -Force

    $repoFolder = Get-ChildItem -Path $tempExtractPath -Directory | Select-Object -First 1
    $extractedScriptsFolder = Join-Path -Path $repoFolder.FullName -ChildPath "Scripts\Scripts for Custom Windows (with Autounattend)"

    if (Test-Path $extractedScriptsFolder) {
        Move-Item -Path $extractedScriptsFolder -Destination $finalScriptsPath -Force
        
        # &#x418;&#x441;&#x43F;&#x440;&#x430;&#x432;&#x43B;&#x435;&#x43D;&#x438;&#x435; &#x43A;&#x43E;&#x434;&#x438;&#x440;&#x43E;&#x432;&#x43A;&#x438; (BOM)
        $psFiles = Get-ChildItem -Path $finalScriptsPath -Filter "*.ps1" -Recurse
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        foreach ($file in $psFiles) {
            $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
            [System.IO.File]::WriteAllText($file.FullName, $content, $utf8Bom)
        }

        $managerScript = Join-Path -Path $finalScriptsPath -ChildPath "manager.ps1"
        if (Test-Path $managerScript) {
            # &#x417;&#x430;&#x43F;&#x443;&#x441;&#x43A;&#x430;&#x435;&#x43C; &#x43E;&#x441;&#x43D;&#x43E;&#x432;&#x43D;&#x43E;&#x439; &#x441;&#x43A;&#x440;&#x438;&#x43F;&#x442;
            Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoExit -File `"$managerScript`""
        }
    }

    # &#x41E;&#x447;&#x438;&#x441;&#x442;&#x43A;&#x430; Temp
    if (Test-Path $zipPath) { Remove-Item -Path $zipPath -Force }
    if (Test-Path $tempExtractPath) { Remove-Item -Path $tempExtractPath -Recurse -Force }
    
} catch {
    Write-Error "&#x41E;&#x448;&#x438;&#x431;&#x43A;&#x430; &#x43F;&#x440;&#x438; &#x437;&#x430;&#x433;&#x440;&#x443;&#x437;&#x43A;&#x435;: $($_.Exception.Message)"
    Start-Sleep -Seconds 5
} finally {
    $window.Close()
}