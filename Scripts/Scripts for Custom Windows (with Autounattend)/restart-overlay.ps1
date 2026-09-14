# =============================================================================
# restart-overlay.ps1 — наш экран перезагрузки вместо стандартного окна Windows
#
# Зачем: стандартный экран «Выполняется перезагрузка» рисует сама ОС, приложение
# не может его «перехватить». Но можно сделать так, чтобы он был виден как можно
# меньше: до самой teardown-фазы держим свой полноэкранный слой поверх всего,
# а сразу после включения показываем свой слой снова. Стандартный экран остаётся
# виден только в неустранимом промежутке (POST + логотип загрузки), ~15-35 с.
#
# Два режима (определяются автоматически):
#   pre  — перед перезагрузкой: полноэкранный отсчёт, затем shutdown /r /t 0 /f
#   post — сразу после включения (через RunOnce): короткая плашка «готово»
#
# ВАЖНО: поведение на реальной Windows здесь не проверяется (песочница Linux).
# Перед выпуском прогнать по extras/VM-PROTOCOL.md (пункт «экран перезагрузки»).
# =============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

try {
    Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class WadDpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
    [WadDpi]::SetProcessDPIAware() | Out-Null
} catch {}

$CountdownSeconds = 60
$FlagPath = Join-Path $env:TEMP 'wad-restart-overlay-postboot'

# --- режим: если флаг стоит, мы запущены сразу после включения -----------------
$IsPostBoot = Test-Path $FlagPath
if ($IsPostBoot) { Remove-Item $FlagPath -Force -ErrorAction SilentlyContinue }

# --- общий полноэкранный слой -------------------------------------------------
$Screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$Form = New-Object System.Windows.Forms.Form
$Form.FormBorderStyle = 'None'
$Form.StartPosition = 'Manual'
$Form.Location = $Screen.Location
$Form.Size = $Screen.Size
$Form.TopMost = $true
$Form.ShowInTaskbar = $false
$Form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 46)   # #1E1E2E, как в manager.ps1
$Form.ForeColor = [System.Drawing.Color]::FromArgb(205, 214, 244)
$Form.KeyPreview = $true

$LblTitle = New-Object System.Windows.Forms.Label
$LblTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 34, [System.Drawing.FontStyle]::Bold)
$LblTitle.ForeColor = [System.Drawing.Color]::FromArgb(137, 180, 250)
$LblTitle.AutoSize = $true
$LblTitle.Text = if ($IsPostBoot) { 'С возвращением' } else { 'Перезагрузка' }

$LblSub = New-Object System.Windows.Forms.Label
$LblSub.Font = New-Object System.Drawing.Font('Segoe UI', 13)
$LblSub.ForeColor = [System.Drawing.Color]::FromArgb(166, 173, 200)
$LblSub.AutoSize = $true
$LblSub.Text = if ($IsPostBoot) { 'WAD завершил настройку — система готова' } else { 'WAD завершает настройку — компьютер включится снова сам' }

$LblCount = New-Object System.Windows.Forms.Label
$LblCount.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 64, [System.Drawing.FontStyle]::Bold)
$LblCount.ForeColor = [System.Drawing.Color]::FromArgb(205, 214, 244)
$LblCount.AutoSize = $true

$Form.Controls.AddRange(@($LblTitle, $LblSub, $LblCount))
$Form.Add_Resize({
    $LblTitle.Location = [System.Drawing.Point]::new([int](($Form.Width - $LblTitle.Width) / 2), [int]($Form.Height / 2 - 140))
    $LblSub.Location    = [System.Drawing.Point]::new([int](($Form.Width - $LblSub.Width) / 2), [int]($Form.Height / 2 - 60))
    $LblCount.Location  = [System.Drawing.Point]::new([int](($Form.Width - $LblCount.Width) / 2), [int]($Form.Height / 2 + 10))
})

# --- режим post: показали плашку и вышли --------------------------------------
if ($IsPostBoot) {
    $LblCount.Text = ''
    $Form.Add_Shown({ $Form.Size = $Screen.Size })
    $Timer = New-Object System.Windows.Forms.Timer
    $Timer.Interval = 2500
    $Timer.Add_Tick({ $Timer.Stop(); $Form.Close() })
    $Timer.Start()
    [System.Windows.Forms.Application]::Run($Form)
    exit 0
}

# --- режим pre: отсчёт, затем перезагрузка ------------------------------------
# Регистрируем показ себя после включения (RunOnce + текущий пользователь).
# Автологон на этом этапе уже настроен файлом ответов, поэтому слой успеет мелькнуть.
$RunOnce = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
$Self = $MyInvocation.MyCommand.Path
New-Item -Path $RunOnce -Force | Out-Null
Set-ItemProperty -Path $RunOnce -Name 'WadRestartOverlay' `
    -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Self`""
New-Item -Path (Split-Path $FlagPath) -ItemType Directory -Force | Out-Null
New-Item -Path $FlagPath -ItemType File -Force | Out-Null

$Left = $CountdownSeconds
$Tick = New-Object System.Windows.Forms.Timer
$Tick.Interval = 1000
$Tick.Add_Tick({
    $Left--
    if ($Left -le 0) {
        $Tick.Stop()
        $Form.Close()
        # /f — закрыть приложения, /t 0 — без системной задержки: стандартный экран
        # появляется только когда ОС уже teardown-ит сессию, наш слой держится до последнего.
        Start-Process shutdown.exe -ArgumentList '/r', '/t', '0', '/f'
        exit 0
    }
    $LblCount.Text = "$Left"
    $Form.Size = $Screen.Size
})

$Form.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $Tick.Stop(); $Form.Close(); exit 0 } })
$Form.Add_Shown({ $LblCount.Text = "$Left"; $Form.Size = $Screen.Size; $Tick.Start() })
[System.Windows.Forms.Application]::Run($Form)
