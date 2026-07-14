# =========================================================================
# Назначение: Модернизированный GUI Диспетчер автоматизации (Cyberpunk UI)
# Режим запуска: Полное скрытие собственного окна консоли + Живой GUI
# Кодировка: UTF-8 с BOM (Обязательно для корректной кириллицы)
# =========================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# --- 1. СИСТЕМНЫЙ API: СКРЫТИЕ КОНСОЛИ И ДВИЖЕНИЕ ОКНА ---
$Win32Code = @'
using System;
using System.Runtime.InteropServices;

namespace Win32 {
    public class Win32Native {
        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("kernel32.dll")]
        public static extern IntPtr GetConsoleWindow();

        [DllImport("user32.dll")]
        public static extern bool ReleaseCapture();

        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);
    }
}
'@
try { Add-Type -TypeDefinition $Win32Code -ErrorAction SilentlyContinue } catch {}

# Скрываем родное окно консоли при старте
$ConsoleHandle = [Win32.Win32Native]::GetConsoleWindow()
if ($ConsoleHandle -ne [System.IntPtr]::Zero) {
    $null = [Win32.Win32Native]::ShowWindow($ConsoleHandle, 0)
}

# Подгружаем библиотеки графического интерфейса
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Настройка логирования (пишем в Документы)
$UserProfile = $env:USERPROFILE
$LogDir = Join-Path $UserProfile "Documents"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }

function Add-LogLine ($Prefix, $Message) {
    $Time = (Get-Date).ToString("HH:mm:ss")
    Write-Output "[$Time] [$Prefix] $Message"
}

# --- СПИСОК ОПЕРАЦИЙ ---
$ScriptsToRun = @(
    @{ Name = "clean-and-photo.ps1";        Title = "Оптимизация и настройка ОС";      Status = "Ожидание" },
    @{ Name = "install-sys-components.ps1"; Title = "Установка системных компонентов"; Status = "Ожидание" },
    @{ Name = "apps-install.ps1";           Title = "Установка софта";                 Status = "Ожидание" },
    @{ Name = "office-install.ps1";         Title = "Установка и активация Microsoft Office"; Status = "Ожидание" }
)

# --- 2. ФУНКЦИЯ ДИАЛОГА ВЫХОДА ---
function Show-ExitDialog {
    $Script:Diag = New-Object System.Windows.Forms.Form
    $Script:Diag.Size = New-Object System.Drawing.Size(500, 300)
    $Script:Diag.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $Script:Diag.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $Script:Diag.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 46)

    $DragAction = {
        param($sender, $e)
        if ($e.Button -eq 'Left') {
            [Win32.Win32Native]::ReleaseCapture()
            [Win32.Win32Native]::SendMessage($Script:Diag.Handle, 0xA1, 0x2, 0)
        }
    }
    $Script:Diag.Add_MouseDown($DragAction)

    $Border = New-Object System.Windows.Forms.Panel
    $Border.Size = New-Object System.Drawing.Size(496, 296)
    $Border.Location = New-Object System.Drawing.Point(2, 2)
    $Border.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 37)
    $Border.Add_MouseDown($DragAction)
    $Script:Diag.Controls.Add($Border)

    $Title = New-Object System.Windows.Forms.Label
    $Title.Text = "СИСТЕМА НАСТРОЕНА"
    $Title.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 14, [System.Drawing.FontStyle]::Bold)
    $Title.ForeColor = [System.Drawing.Color]::FromArgb(137, 180, 250)
    $Title.Location = New-Object System.Drawing.Point(30, 30)
    $Title.AutoSize = $true
    $Title.Add_MouseDown($DragAction)
    $Border.Controls.Add($Title)

    $Msg = New-Object System.Windows.Forms.Label
    $Msg.Text = "Все операции успешно отработали. Для корректного завершения процесса установки перезагрузите ПК."
    $Msg.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $Msg.ForeColor = [System.Drawing.Color]::FromArgb(205, 214, 244)
    $Msg.Location = New-Object System.Drawing.Point(30, 80)
    $Msg.Size = New-Object System.Drawing.Size(440, 60)
    $Msg.Add_MouseDown($DragAction)
    $Border.Controls.Add($Msg)

    $BtnGit = New-Object System.Windows.Forms.Button
    $BtnGit.Text = "GITHUB РАЗРАБОТЧИКА"
    $BtnGit.Location = New-Object System.Drawing.Point(30, 160)
    $BtnGit.Size = New-Object System.Drawing.Size(440, 45)
    $BtnGit.BackColor = [System.Drawing.Color]::FromArgb(137, 180, 250)
    $BtnGit.ForeColor = [System.Drawing.Color]::FromArgb(24, 24, 37)
    $BtnGit.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $BtnGit.FlatAppearance.BorderSize = 0
    $BtnGit.Cursor = [System.Windows.Forms.Cursors]::Hand
    $BtnGit.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
    $BtnGit.Add_Click({ [System.Diagnostics.Process]::Start("https://github.com/alexejnekrasov/powershell-scripts/tree/main") })
    $Border.Controls.Add($BtnGit)

    $BtnOk = New-Object System.Windows.Forms.Button
    $BtnOk.Text = "ВЫХОД"
    $BtnOk.Location = New-Object System.Drawing.Point(30, 220)
    $BtnOk.Size = New-Object System.Drawing.Size(440, 40)
    $BtnOk.BackColor = [System.Drawing.Color]::FromArgb(49, 50, 68)
    $BtnOk.ForeColor = [System.Drawing.Color]::FromArgb(205, 214, 244)
    $BtnOk.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $BtnOk.FlatAppearance.BorderSize = 0
    $BtnOk.Cursor = [System.Windows.Forms.Cursors]::Hand
    $BtnOk.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
    
    $BtnOk.Add_Click({ 
        $Global:AnimTimer.Stop()
        $Form.Hide()
        $Script:Diag.Close()
        $Form.Close()
    })
    $Border.Controls.Add($BtnOk)

    $Script:Diag.Show($Form)
}

# --- 3. ДИРЕКТОРИЯ СКРИПТОВ ---
$ScriptsDir = "C:\Windows\Setup\Scripts"

# --- 4. ОСНОВНАЯ ФОРМА ---
$Form = New-Object System.Windows.Forms.Form
$Form.Size = New-Object System.Drawing.Size(580, 480)
$Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$Form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$Form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 46) 
$Form.Add_FormClosing({ 
    if (-not $Global:ExitDialogOpen) {
        $Global:ExitDialogOpen = $true
        Show-ExitDialog
    }
})

$MainDragAction = {
    param($sender, $e)
    if ($e.Button -eq 'Left') {
        [Win32.Win32Native]::ReleaseCapture()
        [Win32.Win32Native]::SendMessage($Form.Handle, 0xA1, 0x2, 0)
    }
}
$Form.Add_MouseDown($MainDragAction)

$MainPanel = New-Object System.Windows.Forms.Panel
$MainPanel.Size = New-Object System.Drawing.Size(576, 476)
$MainPanel.Location = New-Object System.Drawing.Point(2, 2)
$MainPanel.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 37)
$MainPanel.Add_MouseDown($MainDragAction)
$Form.Controls.Add($MainPanel)

# Главный Заголовок
$MainTitle = New-Object System.Windows.Forms.Label
$MainTitle.Text = "МЕНЕДЖЕР АВТОМАТИЧЕСКОЙ НАСТРОЙКИ"
$MainTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 14, [System.Drawing.FontStyle]::Bold)
$MainTitle.ForeColor = [System.Drawing.Color]::FromArgb(137, 180, 250) # Цвет заголовка (#89B4FA)
$MainTitle.Location = New-Object System.Drawing.Point(20, 20)
$MainTitle.AutoSize = $true
$MainTitle.Add_MouseDown($MainDragAction)
$MainPanel.Controls.Add($MainTitle)

# Синяя линия
$TitleLine = New-Object System.Windows.Forms.Panel
$TitleLine.Location = New-Object System.Drawing.Point(20, 56)
$TitleLine.Size = New-Object System.Drawing.Size(540, 2)
$TitleLine.BackColor = [System.Drawing.Color]::FromArgb(137, 180, 250)
$MainPanel.Controls.Add($TitleLine)

# Синяя рамка крестика
$CloseBtnFrame = New-Object System.Windows.Forms.Panel
$CloseBtnFrame.Size = New-Object System.Drawing.Size(32, 32)
$CloseBtnFrame.Location = New-Object System.Drawing.Point(528, 18)
$CloseBtnFrame.BackColor = [System.Drawing.Color]::FromArgb(137, 180, 250)
$MainPanel.Controls.Add($CloseBtnFrame)

# Крестик
$CloseBtn = New-Object System.Windows.Forms.Label
$CloseBtn.Text = "✕"
$CloseBtn.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$CloseBtn.ForeColor = [System.Drawing.Color]::FromArgb(166, 173, 200)
$CloseBtn.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 37)
$CloseBtn.Location = New-Object System.Drawing.Point(2, 2)
$CloseBtn.Size = New-Object System.Drawing.Size(28, 28)
$CloseBtn.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$CloseBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
$CloseBtn.Add_MouseEnter({ $CloseBtn.ForeColor = [System.Drawing.Color]::FromArgb(243, 139, 168) })
$CloseBtn.Add_MouseLeave({ $CloseBtn.ForeColor = [System.Drawing.Color]::FromArgb(166, 173, 200) })
$CloseBtn.Add_Click({ $Form.Close() })
$CloseBtnFrame.Controls.Add($CloseBtn)

# Контейнер задач
$TasksContainer = New-Object System.Windows.Forms.Panel
$TasksContainer.Location = New-Object System.Drawing.Point(20, 75)
$TasksContainer.Size = New-Object System.Drawing.Size(540, 200)
$TasksContainer.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 46)
$MainPanel.Controls.Add($TasksContainer)

$YOffset = 20
foreach ($Script in $ScriptsToRun) {
    $TaskLabel = New-Object System.Windows.Forms.Label
    $TaskLabel.Text = $Script.Title
    $TaskLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $TaskLabel.Location = New-Object System.Drawing.Point(20, $YOffset)
    $TaskLabel.Size = New-Object System.Drawing.Size(320, 25)
    $TaskLabel.ForeColor = [System.Drawing.Color]::FromArgb(205, 214, 244)
    $TasksContainer.Controls.Add($TaskLabel)

    $StatusLabel = New-Object System.Windows.Forms.Label
    $StatusLabel.Text = "• Ожидание"
    $StatusLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
    $StatusLabel.Location = New-Object System.Drawing.Point(350, $YOffset)
    $StatusLabel.Size = New-Object System.Drawing.Size(180, 25)
    $StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(166, 173, 200)
    $TasksContainer.Controls.Add($StatusLabel)
    
    $Script.LabelRef = $StatusLabel
    $YOffset += 40
}

# ИСПРАВЛЕНО: Текст текущего действия теперь в цвет заголовка окна (#89B4FA)
$CurrentActionLabel = New-Object System.Windows.Forms.Label
$CurrentActionLabel.Location = New-Object System.Drawing.Point(20, 305)
$CurrentActionLabel.Size = New-Object System.Drawing.Size(540, 25)
$CurrentActionLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
$CurrentActionLabel.ForeColor = [System.Drawing.Color]::FromArgb(137, 180, 250) 
$CurrentActionLabel.Text = "Инициализация подсистем..."
$MainPanel.Controls.Add($CurrentActionLabel)


# =========================================================================
# ТЕХНОЛОГИЯ: НЕЗАВИСИМЫЙ GDI+ КИНЕТИЧЕСКИЙ ПРОГРЕСС-БАР С ГРАДИЕНТНЫМ БЛИКОМ
# =========================================================================
$ProgressContainer = New-Object System.Windows.Forms.Panel
$ProgressContainer.Location = New-Object System.Drawing.Point(20, 332)
$ProgressContainer.Size = New-Object System.Drawing.Size(540, 20)
$ProgressContainer.BackColor = [System.Drawing.Color]::FromArgb(49, 50, 68)
$MainPanel.Controls.Add($ProgressContainer)

# Переменные анимации
$Global:CurrentFillWidth = 0
$Global:GlarePositionX = -100
$Global:GlareWidth = 150 

$Flags = [System.Reflection.BindingFlags]([System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance)
$ProgressContainer.GetType().GetProperty("DoubleBuffered", $Flags).SetValue($ProgressContainer, $true)

# Отрисовщик GDI+ (ИСПРАВЛЕНЫ ЦВЕТА НА СИНЮЮ ПАЛИТРУ ЗАГОЛОВКА)
$ProgressContainer.Add_Paint({
    param($sender, $e)
    $G = $e.Graphics
    $G.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    # 1. Рисуем основную СИНЮЮ шкалу заполнения (цвет заголовка 137, 180, 250)
    if ($Global:CurrentFillWidth -gt 0) {
        $FillBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(137, 180, 250))
        $G.FillRectangle($FillBrush, 0, 0, $Global:CurrentFillWidth, $sender.Height)
        $FillBrush.Dispose()

        # 2. Накладываем динамический градиентный блик
        $ClipRect = New-Object System.Drawing.Rectangle(0, 0, $Global:CurrentFillWidth, $sender.Height)
        $G.SetClip($ClipRect)

        $GBrushRect = New-Object System.Drawing.Rectangle($Global:GlarePositionX, 0, $Global:GlareWidth, $sender.Height)
        if ($GBrushRect.Width -gt 0 -and $GBrushRect.Height -gt 0) {
            $LinearGradientBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($GBrushRect, [System.Drawing.Color]::Transparent, [System.Drawing.Color]::Transparent, 0.0)
            
            # Цветовая карта: Прозрачно-синий -> Мягкий Белый блик -> Прозрачно-синий
            $ColorBlend = New-Object System.Drawing.Drawing2D.ColorBlend
            $ColorBlend.Colors = @(
                [System.Drawing.Color]::FromArgb(0, 137, 180, 250),    # Прозрачный старт
                [System.Drawing.Color]::FromArgb(210, 255, 255, 255),  # Насыщенное белое ядро вспышки
                [System.Drawing.Color]::FromArgb(0, 137, 180, 250)     # Прозрачный конец
            )
            $ColorBlend.Positions = @(0.0, 0.5, 1.0)
            $LinearGradientBrush.InterpolationColors = $ColorBlend

            $G.FillRectangle($LinearGradientBrush, $GBrushRect)
            $LinearGradientBrush.Dispose()
        }
        $G.ResetClip()
    }
})

# Таймер анимации
$Global:AnimTimer = New-Object System.Windows.Forms.Timer
$AnimTimer.Interval = 20 
$AnimTimer.Add_Tick({
    if ($Global:CurrentFillWidth -gt 0) {
        $Global:GlarePositionX += 6 
        if ($Global:GlarePositionX -gt $Global:CurrentFillWidth) {
            $Global:GlarePositionX = -$Global:GlareWidth
        }
    } else {
        $Global:GlarePositionX = -$Global:GlareWidth
    }
    $ProgressContainer.Invalidate()
})
$AnimTimer.Start()


# Текст внизу формы
$BottomWarning = New-Object System.Windows.Forms.Label
$BottomWarning.Text = "Пожалуйста, не закрывайте это окно до завершения всех процессов."
$BottomWarning.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$BottomWarning.ForeColor = [System.Drawing.Color]::FromArgb(147, 153, 178)
$BottomWarning.Location = New-Object System.Drawing.Point(0, 420)
$BottomWarning.Size = New-Object System.Drawing.Size(576, 20)
$BottomWarning.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$MainPanel.Controls.Add($BottomWarning)

# --- 5. ТАЙМЕР ВЫПОЛНЕНИЯ ПЛАНИРОВЩИКА ---
$LaunchTimer = New-Object System.Windows.Forms.Timer
$LaunchTimer.Interval = 150
$LaunchTimer.Add_Tick({
    $LaunchTimer.Stop()

    Add-LogLine "CORE" "Запуск планировщика..."
    
    for ($i = 0; $i -lt $ScriptsToRun.Count; $i++) {
        $Script = $ScriptsToRun[$i]
        $StatusLabel = $Script.LabelRef
        $ScriptPath = Join-Path $ScriptsDir $Script.Name

        $StatusLabel.Text = "▶ Выполняется..."
        $StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(137, 220, 235)
        $CurrentActionLabel.Text = "Запуск: $($Script.Name)..."
        # Во время работы скриптов держим текст в основном синем цвете
        $CurrentActionLabel.ForeColor = [System.Drawing.Color]::FromArgb(137, 180, 250)
        [System.Windows.Forms.Application]::DoEvents()
        
        switch ($Script.Name) {
            "clean-and-photo.ps1"        { Add-LogLine "TASK" "Запуск оптимизации ОС" }
            "install-sys-components.ps1" { Add-LogLine "TASK" "Настройка компонентов" }
            "apps-install.ps1"           { Add-LogLine "TASK" "Установка ПО" }
            "office-install.ps1"         { Add-LogLine "TASK" "Установка Office" }
        }

        if (Test-Path $ScriptPath) {
            try {
                $Proc = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" -WindowStyle Hidden -PassThru
                
                while (-not $Proc.HasExited) {
                    [System.Windows.Forms.Application]::DoEvents()
                    Start-Sleep -Milliseconds 50
                }
                
                if ($Proc.ExitCode -eq 0) {
                    $TimeFinished = (Get-Date).ToString("HH:mm:ss")
                    $StatusLabel.Text = "✓ Готово [$TimeFinished]"
                    $StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(166, 227, 161)
                    Add-LogLine " OK " "Модуль завершен."
                } else {
                    $StatusLabel.Text = "✗ Сбой (Код: $($Proc.ExitCode))"
                    $StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(243, 139, 168)
                    Add-LogLine "FAIL" "Ошибка (Код: $($Proc.ExitCode))"
                }
            } catch {
                $StatusLabel.Text = "✗ Ошибка"
                $StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(243, 139, 168)
                Add-LogLine "ERR " "Критическая ошибка!"
            }
        } else {
            $TimeFinished = (Get-Date).ToString("HH:mm:ss")
            $StatusLabel.Text = "⚠ Отсутствует [$TimeFinished]"
            $StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(249, 226, 175)
            Add-LogLine "WARN" "Файл не найден!"
        }

        $ProgressPercent = ($i + 1) / $ScriptsToRun.Count
        $Global:CurrentFillWidth = [int]($ProgressContainer.Width * $ProgressPercent)
        [System.Windows.Forms.Application]::DoEvents()
    }

    # --- ЗАВЕРШАЮЩИЙ ЭТАП ---
    $CurrentActionLabel.Text = "Финальная зачистка временных директорий..."
    $CurrentActionLabel.ForeColor = [System.Drawing.Color]::FromArgb(137, 180, 250)
    [System.Windows.Forms.Application]::DoEvents()

    $ResetPath = Join-Path $ScriptsDir "reset-setup-scripts.ps1"
    if (Test-Path $ResetPath) {
        $ProcReset = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ResetPath`"" -WindowStyle Hidden -PassThru
        while (-not $ProcReset.HasExited) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 40
        }
    }

    $Global:CurrentFillWidth = $ProgressContainer.Width
    $CurrentActionLabel.Text = "Все операции успешно завершены!"
    # Финальный текст успеха подсветим зеленым для наглядности
    $CurrentActionLabel.ForeColor = [System.Drawing.Color]::FromArgb(166, 227, 161)
    Add-LogLine "DONE" "Все процессы завершены."
    [System.Windows.Forms.Application]::DoEvents()

    $Global:ExitDialogOpen = $true
    Show-ExitDialog
})

$Global:ExitDialogOpen = $false
$Form.Add_Load({ $LaunchTimer.Start() })

# Запуск GUI приложения
[System.Windows.Forms.Application]::Run($Form)
