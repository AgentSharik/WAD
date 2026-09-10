# =========================================================================
# &#x418;&#x43C;&#x44F; &#x444;&#x430;&#x439;&#x43B;&#x430;: system-logon-init.ps1
# &#x41D;&#x430;&#x437;&#x43D;&#x430;&#x447;&#x435;&#x43D;&#x438;&#x435;: &#x411;&#x435;&#x441;&#x43A;&#x43E;&#x43C;&#x43F;&#x440;&#x43E;&#x43C;&#x438;&#x441;&#x441;&#x43D;&#x430;&#x44F; &#x431;&#x43B;&#x43E;&#x43A;&#x438;&#x440;&#x43E;&#x432;&#x43A;&#x430; &#x440;&#x435;&#x43A;&#x43B;&#x430;&#x43C;&#x44B;, &#x442;&#x435;&#x43B;&#x435;&#x43C;&#x435;&#x442;&#x440;&#x438;&#x438;, Outlook, &#x42F;&#x43D;&#x434;&#x435;&#x43A;&#x441;.&#x41C;&#x443;&#x437;&#x44B;&#x43A;&#x438;, Edge &#x438; &#x43D;&#x430;&#x441;&#x442;&#x440;&#x43E;&#x439;&#x43A;&#x430; UI
# &#x42D;&#x442;&#x430;&#x43F;: System Logon / Pre-OOBE (&#x412;&#x44B;&#x43F;&#x43E;&#x43B;&#x43D;&#x44F;&#x435;&#x442;&#x441;&#x44F; &#x43E;&#x442; &#x438;&#x43C;&#x435;&#x43D;&#x438; SYSTEM)
# &#x41B;&#x43E;&#x433;&#x438;&#x440;&#x43E;&#x432;&#x430;&#x43D;&#x438;&#x435;: &#x414;&#x43E;&#x43A;&#x443;&#x43C;&#x435;&#x43D;&#x442;&#x44B; &#x434;&#x435;&#x444;&#x43E;&#x43B;&#x442;&#x43D;&#x43E;&#x433;&#x43E; &#x43F;&#x43E;&#x43B;&#x44C;&#x437;&#x43E;&#x432;&#x430;&#x442;&#x435;&#x43B;&#x44F;
# =========================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# &#x41D;&#x430;&#x441;&#x442;&#x440;&#x43E;&#x439;&#x43A;&#x430; &#x43B;&#x43E;&#x433;&#x438;&#x440;&#x43E;&#x432;&#x430;&#x43D;&#x438;&#x44F; &#x432; C:\Users\Default\Documents
$LogDir = "C:\Users\Default\Documents"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
Start-Transcript -Path (Join-Path $LogDir "System_Logon_Initialization.log") -Append

try {
    Write-Host "========================================================="
    Write-Host " &#x421;&#x422;&#x410;&#x420;&#x422; &#x420;&#x410;&#x421;&#x428;&#x418;&#x420;&#x415;&#x41D;&#x41D;&#x41E;&#x419; &#x41E;&#x41F;&#x422;&#x418;&#x41C;&#x418;&#x417;&#x410;&#x426;&#x418;&#x418; &#x421;&#x418;&#x421;&#x422;&#x415;&#x41C;&#x42B; (SYSTEM CONTEXT)"
    Write-Host "========================================================="

    # ----------------------------------------------------
    # 1. &#x413;&#x41B;&#x41E;&#x411;&#x410;&#x41B;&#x42C;&#x41D;&#x42B;&#x415; &#x41F;&#x41E;&#x41B;&#x418;&#x422;&#x418;&#x41A;&#x418; (HKLM) &#x41F;&#x420;&#x41E;&#x422;&#x418;&#x412; &#x420;&#x415;&#x41A;&#x41B;&#x410;&#x41C;&#x42B; &#x418; &#x41C;&#x423;&#x421;&#x41E;&#x420;&#x410;
    # ----------------------------------------------------
    Write-Host "&gt;&gt;&gt; &#x41D;&#x430;&#x441;&#x442;&#x440;&#x43E;&#x439;&#x43A;&#x430; &#x433;&#x43B;&#x43E;&#x431;&#x430;&#x43B;&#x44C;&#x43D;&#x44B;&#x445; &#x43F;&#x43E;&#x43B;&#x438;&#x442;&#x438;&#x43A; CloudContent &#x438; &#x432;&#x438;&#x434;&#x436;&#x435;&#x442;&#x43E;&#x432;..."
    $CloudContentPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (-not (Test-Path $CloudContentPath)) { New-Item -Path $CloudContentPath -Force | Out-Null }
    Set-ItemProperty -Path $CloudContentPath -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $CloudContentPath -Name "DisableWindowsSpotlightFeatures" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $CloudContentPath -Name "DisableThirdPartySuggestions" -Value 1 -Type DWord -Force

    # &#x41E;&#x442;&#x43A;&#x43B;&#x44E;&#x447;&#x435;&#x43D;&#x438;&#x435; &#x432;&#x438;&#x434;&#x436;&#x435;&#x442;&#x43E;&#x432; (Feeds) &#x43D;&#x430; &#x43F;&#x430;&#x43D;&#x435;&#x43B;&#x438; &#x437;&#x430;&#x434;&#x430;&#x447; &#x434;&#x43B;&#x44F; &#x432;&#x441;&#x435;&#x445;
    $Feeds = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"
    if (!(Test-Path $Feeds)) { New-Item -Path $Feeds -Force | Out-Null }
    Set-ItemProperty -Path $Feeds -Name "EnableFeeds" -Value 0 -Type DWord -Force

    Write-Host "&gt;&gt;&gt; &#x413;&#x43B;&#x443;&#x431;&#x43E;&#x43A;&#x430;&#x44F; &#x43A;&#x43E;&#x43D;&#x444;&#x438;&#x433;&#x443;&#x440;&#x430;&#x446;&#x438;&#x44F; &#x433;&#x43B;&#x43E;&#x431;&#x430;&#x43B;&#x44C;&#x43D;&#x43E;&#x433;&#x43E; ContentDeliveryManager..."
    $CdmPathHKLM = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    if (-not (Test-Path $CdmPathHKLM)) { New-Item -Path $CdmPathHKLM -Force | Out-Null }
    
    $CdmTweaks = @{
        "SilentInstalledAppsEnabled"       = 0
        "ContentDeliveryAllowed"           = 0
        "OemPreInstalledAppsEnabled"       = 0
        "PreInstalledAppsEnabled"          = 0
        "PreInstalledAppsReady"            = 0
        "SubscribedContentEnabled"         = 0
        "SystemPaneSuggestionsEnabled"     = 0
        "SubscribedContent-310093Enabled"  = 0
        "SubscribedContent-338387Enabled"  = 0
        "SubscribedContent-338388Enabled"  = 0
        "SubscribedContent-338389Enabled"  = 0
        "SubscribedContent-353475Enabled"  = 0
    }
    foreach ($Key in $CdmTweaks.Keys) {
        Set-ItemProperty -Path $CdmPathHKLM -Name $Key -Value $CdmTweaks[$Key] -Type DWord -Force
    }

    # ----------------------------------------------------
    # 1.5. &#x423;&#x41A;&#x420;&#x41E;&#x429;&#x415;&#x41D;&#x418;&#x415; MICROSOFT EDGE &#x418; &#x41E;&#x411;&#x429;&#x415;&#x413;&#x41E; &#x420;&#x410;&#x411;&#x41E;&#x427;&#x415;&#x413;&#x41E; &#x421;&#x422;&#x41E;&#x41B;&#x410;
    # ----------------------------------------------------
    Write-Host "&gt;&gt;&gt; &#x41F;&#x43E;&#x43B;&#x43D;&#x430;&#x44F; &#x431;&#x43B;&#x43E;&#x43A;&#x438;&#x440;&#x43E;&#x432;&#x43A;&#x430; Microsoft Edge &#x438; &#x43E;&#x447;&#x438;&#x441;&#x442;&#x43A;&#x430; &#x43E;&#x431;&#x449;&#x435;&#x433;&#x43E; &#x441;&#x442;&#x43E;&#x43B;&#x430;..."
    
    # &#x41F;&#x43E;&#x43B;&#x438;&#x442;&#x438;&#x43A;&#x438; HKLM &#x434;&#x43B;&#x44F; Edge
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

    # &#x41E;&#x442;&#x43A;&#x43B;&#x44E;&#x447;&#x435;&#x43D;&#x438;&#x435; &#x441;&#x43B;&#x443;&#x436;&#x431; &#x43E;&#x431;&#x43D;&#x43E;&#x432;&#x43B;&#x435;&#x43D;&#x438;&#x44F; Edge
    $EdgeServices = @("edgeupdate", "edgeupdatem", "MicrosoftEdgeElevationService")
    foreach ($svc in $EdgeServices) {
        if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc -StartupType Disabled
        }
    }

    # &#x423;&#x434;&#x430;&#x43B;&#x435;&#x43D;&#x438;&#x435; &#x437;&#x430;&#x434;&#x430;&#x447; Edge &#x432; &#x43F;&#x43B;&#x430;&#x43D;&#x438;&#x440;&#x43E;&#x432;&#x449;&#x438;&#x43A;&#x435;
    Get-ScheduledTask -TaskPath "\" -ErrorAction SilentlyContinue | 
        Where-Object { $_.TaskName -like "*MicrosoftEdge*" } | 
        Disable-ScheduledTask -ErrorAction SilentlyContinue

    # &#x41E;&#x431;&#x445;&#x43E;&#x434; Active Setup (&#x43F;&#x440;&#x435;&#x434;&#x43E;&#x442;&#x432;&#x440;&#x430;&#x449;&#x430;&#x435;&#x442; &#x441;&#x43E;&#x437;&#x434;&#x430;&#x43D;&#x438;&#x435; &#x44F;&#x440;&#x43B;&#x44B;&#x43A;&#x43E;&#x432; Edge &#x43F;&#x440;&#x438; &#x432;&#x445;&#x43E;&#x434;&#x435; &#x43B;&#x44E;&#x431;&#x43E;&#x433;&#x43E; &#x43F;&#x43E;&#x43B;&#x44C;&#x437;&#x43E;&#x432;&#x430;&#x442;&#x435;&#x43B;&#x44F;)
    $ActiveSetup = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components"
    Get-ChildItem $ActiveSetup -ErrorAction SilentlyContinue | Where-Object { (Get-ItemProperty $_.PsPath -ErrorAction SilentlyContinue).StubPath -like "*MicrosoftEdge*" } | ForEach-Object {
        Set-ItemProperty -Path $_.PsPath -Name "StubPath" -Value "" -Force
    }

    # &#x423;&#x434;&#x430;&#x43B;&#x435;&#x43D;&#x438;&#x435; &#x44F;&#x440;&#x43B;&#x44B;&#x43A;&#x43E;&#x432; Edge &#x438; Teams &#x441; &#x43E;&#x431;&#x449;&#x435;&#x433;&#x43E; &#x420;&#x430;&#x431;&#x43E;&#x447;&#x435;&#x433;&#x43E; &#x441;&#x442;&#x43E;&#x43B;&#x430;
    Get-ChildItem -Path "$env:PUBLIC\Desktop" -Filter "*.lnk" | Where-Object { $_.Name -match "Edge|Teams" } | Remove-Item -Force -ErrorAction SilentlyContinue

    # &#x421;&#x43E;&#x437;&#x434;&#x430;&#x43D;&#x438;&#x435; &#x43A;&#x430;&#x441;&#x442;&#x43E;&#x43C;&#x43D;&#x43E;&#x433;&#x43E; &#x43C;&#x430;&#x43A;&#x435;&#x442;&#x430; &#x41F;&#x430;&#x43D;&#x435;&#x43B;&#x438; &#x437;&#x430;&#x434;&#x430;&#x447; (XML) &#x441;&#x440;&#x430;&#x437;&#x443; &#x432; &#x43F;&#x430;&#x43F;&#x43A;&#x435; Default User
    Write-Host "&gt;&gt;&gt; &#x421;&#x43E;&#x437;&#x434;&#x430;&#x43D;&#x438;&#x435; &#x447;&#x438;&#x441;&#x442;&#x43E;&#x433;&#x43E; XML &#x43C;&#x430;&#x43A;&#x435;&#x442;&#x430; &#x41F;&#x430;&#x43D;&#x435;&#x43B;&#x438; &#x437;&#x430;&#x434;&#x430;&#x447;..."
    $LayoutXml = @"
&lt;LayoutModificationTemplate xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification" xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout" Version="1"&gt;
  &lt;LayoutOptions StartTileGroupCellWidth="6" /&gt;
  &lt;DefaultLayoutOverride&gt;&lt;StartLayoutCollection&gt;&lt;defaultlayout:StartLayout GroupCellWidth="6" /&gt;&lt;/StartLayoutCollection&gt;&lt;/DefaultLayoutOverride&gt;
  &lt;CustomTaskbarLayoutCollection PinListPlacement="Replace"&gt;
    &lt;defaultlayout:TaskbarLayout&gt;&lt;taskbar:TaskbarPinList&gt;
        &lt;taskbar:DesktopApp DesktopApplicationID="Microsoft.Windows.Explorer" /&gt;
    &lt;/taskbar:TaskbarPinList&gt;&lt;/defaultlayout:TaskbarLayout&gt;
  &lt;/CustomTaskbarLayoutCollection&gt;
&lt;/LayoutModificationTemplate&gt;
"@
    $D_Shell = "C:\Users\Default\AppData\Local\Microsoft\Windows\Shell"
    if (!(Test-Path $D_Shell)) { New-Item -Path $D_Shell -ItemType Directory -Force | Out-Null }
    $LayoutXml | Out-File -FilePath "$D_Shell\LayoutModification.xml" -Encoding UTF8 -Force


    # ----------------------------------------------------
    # 2. &#x416;&#x415;&#x421;&#x422;&#x41A;&#x418;&#x419; &#x410;&#x41D;&#x422;&#x418;&#x414;&#x41E;&#x422; &#x41F;&#x420;&#x41E;&#x422;&#x418;&#x412; &#x41E;&#x411;&#x425;&#x41E;&#x414;&#x410; &#x41D;&#x41E;&#x412;&#x41E;&#x413;&#x41E; OUTLOOK (&#x424;&#x438;&#x448;&#x43A;&#x430; 2025/2026 &#x433;&#x433;.)
    # ----------------------------------------------------
    Write-Host "&gt;&gt;&gt; &#x410;&#x43F;&#x43F;&#x430;&#x440;&#x430;&#x442;&#x43D;&#x43E;&#x435; &#x43E;&#x442;&#x43A;&#x43B;&#x44E;&#x447;&#x435;&#x43D;&#x438;&#x435; OOBE-&#x430;&#x43F;&#x434;&#x435;&#x439;&#x442;&#x435;&#x440;&#x430; &#x434;&#x43B;&#x44F; Outlook..."
    $USchedulerPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe"
    if (-not (Test-Path $USchedulerPath)) { New-Item -Path $USchedulerPath -Force | Out-Null }
    Set-ItemProperty -Path $USchedulerPath -Name "BlockedOobeUpdaters" -Value '["MS_Outlook"]' -Type String -Force
    
    $OutlookUpdateTask = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate"
    if (Test-Path $OutlookUpdateTask) { Remove-Item -Path $OutlookUpdateTask -Recurse -Force }

    $OutlookPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Outlook\Options\General"
    if (-not (Test-Path $OutlookPolicyPath)) { New-Item -Path $OutlookPolicyPath -Force | Out-Null }
    Set-ItemProperty -Path $OutlookPolicyPath -Name "HideNewOutlookToggle" -Value 1 -Type DWord -Force
    
    $OutlookPrefPath = "HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Outlook\Preferences"
    if (-not (Test-Path $OutlookPrefPath)) { New-Item -Path $OutlookPrefPath -Force | Out-Null }
    Set-ItemProperty -Path $OutlookPrefPath -Name "NewOutlookMigrationUserSetting" -Value 0 -Type DWord -Force


    # ----------------------------------------------------
    # 3. &#x41D;&#x410;&#x421;&#x422;&#x420;&#x41E;&#x419;&#x41A;&#x410; &#x414;&#x415;&#x424;&#x41E;&#x41B;&#x422;&#x41D;&#x41E;&#x413;&#x41E; &#x41F;&#x420;&#x41E;&#x424;&#x418;&#x41B;&#x42F; &#x41F;&#x41E;&#x41B;&#x42C;&#x417;&#x41E;&#x412;&#x410;&#x422;&#x415;&#x41B;&#x42F; (NTUSER.DAT)
    # ----------------------------------------------------
    Write-Host "&gt;&gt;&gt; &#x41C;&#x43E;&#x43D;&#x442;&#x438;&#x440;&#x43E;&#x432;&#x430;&#x43D;&#x438;&#x435; &#x434;&#x435;&#x444;&#x43E;&#x43B;&#x442;&#x43D;&#x43E;&#x433;&#x43E; &#x43A;&#x443;&#x441;&#x442;&#x430; &#x440;&#x435;&#x435;&#x441;&#x442;&#x440;&#x430; &#x434;&#x43B;&#x44F; &#x43D;&#x430;&#x441;&#x442;&#x440;&#x43E;&#x439;&#x43A;&#x438; &#x43F;&#x440;&#x43E;&#x444;&#x438;&#x43B;&#x435;&#x439;..."
    $DefaultHivePath = "C:\Users\Default\NTUSER.DAT"
    
    if (-not (Test-Path "HKLM:\TargetUser")) {
        reg load "HKLM\TargetUser" $DefaultHivePath | Out-Null
    }

    $PathsToTweak = @(
        "HKLM:\TargetUser\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager",
        "HKLM:\TargetUser\Software\Policies\Microsoft\Windows\CloudContent",
        "HKLM:\TargetUser\Software\Policies\Microsoft\Edge",
        "HKLM:\TargetUser\Software\Microsoft\Windows\CurrentVersion\Search",
        "HKLM:\TargetUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced",
        "HKLM:\TargetUser\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
    )
    foreach ($Path in $PathsToTweak) {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    }

    # &#x41F;&#x440;&#x438;&#x43C;&#x435;&#x43D;&#x44F;&#x435;&#x43C; &#x432;&#x435;&#x441;&#x44C; &#x441;&#x43F;&#x435;&#x43A;&#x442;&#x440; &#x431;&#x43B;&#x43E;&#x43A;&#x438;&#x440;&#x43E;&#x432;&#x43E;&#x43A; &#x440;&#x435;&#x43A;&#x43B;&#x430;&#x43C;&#x44B; &#x438; &#x430;&#x432;&#x442;&#x43E;&#x443;&#x441;&#x442;&#x430;&#x43D;&#x43E;&#x432;&#x43E;&#x43A;
    Set-ItemProperty -Path "HKLM:\TargetUser\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path "HKLM:\TargetUser\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsSpotlightFeatures" -Value 1 -Type DWord -Force
    foreach ($Key in $CdmTweaks.Keys) {
        Set-ItemProperty -Path "HKLM:\TargetUser\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name $Key -Value $CdmTweaks[$Key] -Type DWord -Force
    }

    # &#x41D;&#x430;&#x441;&#x442;&#x440;&#x43E;&#x439;&#x43A;&#x438; Edg