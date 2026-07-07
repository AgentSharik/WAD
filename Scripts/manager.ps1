# =========================================================================
# Назначение: Модернизированный GUI Диспетчер автоматизации (Cyberpunk UI)
# Режим запуска: Полное скрытие собственного окна консоли + Живой не лагающий GUI
# Кодировка: UTF-8 с BOM (Обязательно для корректной кириллицы)
# =========================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# --- МАГИЯ: СКРЫВАЕМ СОБСТВЕННОЕ ОКНО КОНСОЛИ POWERSHELL ПРИ СТАРТЕ ---
$Win32Code = @'
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
'@
$WindowManager = Add-Type -MemberDefinition $Win32Code -Name "Win32ShowWindow" -Namespace "Win32" -PassThru
$ConsoleHandle = $WindowManager::GetConsoleWindow()
if ($ConsoleHandle -ne [System.IntPtr]::Zero) {
    $null = $WindowManager::ShowWindow($ConsoleHandle, 0)
}

# Подгружаем библиотеки графического интерфейса
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Настройка логирования
$UserProfile = $env:USERPROFILE
$LogDir = Join-Path $UserProfile "Documents"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
Start-Transcript -Path (Join-Path $LogDir "Main_Setup_GUI_Dispatcher.log") -Append

# --- СПИСОК ОПЕРАЦИЙ ---
$ScriptsToRun = @(
    @{ Name = "clean-and-photo.ps1";        Title = "Оптимизация ОС и просмотр фото";      Status = "Ожидание" },
    @{ Name = "install-sys-components.ps1"; Title = "Установка системных компонентов"; Status = "Ожидание" },
    @{ Name = "apps-install.ps1";           Title = "Установка софта";                 Status = "Ожидание" },
    @{ Name = "office-install.ps1";         Title = "Установка и активация Microsoft Office"; Status = "Ожидание" }
)

# --- СОЗДАНИЕ И СТИЛИЗАЦИЯ GUI ИНТЕРФЕЙСА (DARK MODE) ---
$Form = New-Object System.Windows.Forms.Form
$Form.Text = " Системная автоматизация Windows"
$Form.Size = New-Object System.Drawing.Size(960, 480)
$Form.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 37) 
$Form.ForeColor = [System.Drawing.Color]::FromArgb(205, 214, 244)
$Form.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$Form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$Form.MaximizeBox = $false

# Шапка (Заголовок)
$HeaderPanel = New-Object System.Windows.Forms.Panel
$HeaderPanel.Size = New-Object System.Drawing.Size(960, 60)
$HeaderPanel.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 46)
$Form.Controls.Add($HeaderPanel)

$TitleLabel = New-Object System.Windows.Forms.Label
$TitleLabel.Text = "МЕНЕДЖЕР АВТОМАТИЧЕСКОЙ НАСТРОЙКИ"
$TitleLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 14, [System.Drawing.FontStyle]::Bold)
$TitleLabel.ForeColor = [System.Drawing.Color]::FromArgb(137, 180, 250) 
$TitleLabel.Location = New-Object System.Drawing.Point(20, 15)
$TitleLabel.AutoSize = $true
$HeaderPanel.Controls.Add($TitleLabel)

# Общий контейнер для списка задач (Левая сторона)
$TasksContainer = New-Object System.Windows.Forms.Panel
$TasksContainer.Location = New-Object System.Drawing.Point(20, 80)
$TasksContainer.Size = New-Object System.Drawing.Size(540, 200)
$TasksContainer.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 46)
$Form.Controls.Add($TasksContainer)

# --- ПРАВАЯ СТИЛИЗОВАННАЯ КИБЕРПАНК-ПАНЕЛЬ ЛОГА ---
$LogContainer = New-Object System.Windows.Forms.Panel
$LogContainer.Location = New-Object System.Drawing.Point(580, 80)
$LogContainer.Size = New-Object System.Drawing.Size(340, 275)
$LogContainer.BackColor = [System.Drawing.Color]::FromArgb(17, 17, 27) 
$Form.Controls.Add($LogContainer)

# Тонкая неоновая полоска сверху лога для стиля
$NeonLine = New-Object System.Windows.Forms.Panel
$NeonLine.Location = New-Object System.Drawing.Point(0, 0)
$NeonLine.Size = New-Object System.Drawing.Size(340, 3)
$NeonLine.BackColor = [System.Drawing.Color]::FromArgb(137, 180, 250)
$LogContainer.Controls.Add($NeonLine)

# Текстовое поле для терминального вывода (Включен вертикальный скроллбар)
$LogTextBox = New-Object System.Windows.Forms.RichTextBox
$LogTextBox.Location = New-Object System.Drawing.Point(15, 15)
$LogTextBox.Size = New-Object System.Drawing.Size(310, 245)
$LogTextBox.BackColor = [System.Drawing.Color]::FromArgb(17, 17, 27)
$LogTextBox.ForeColor = [System.Drawing.Color]::FromArgb(166, 173, 200)
$LogTextBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$LogTextBox.Font = New-Object System.Drawing.Font("Consolas", 9.5, [System.Drawing.FontStyle]::Bold)
$LogTextBox.ReadOnly = $true
$LogTextBox.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical # РАЗРЕШАЕМ СКРОЛЛИНГ
$LogContainer.Controls.Add($LogTextBox)

# СТИЛИЗОВАННАЯ ФУНКЦИЯ ЛОГА
function Add-LogLine ($Prefix, $Message, $ColorRGB = @(166, 173, 200)) {
    $Time = (Get-Date).ToString("HH:mm:ss")

    Write-Output "[$Time] [$Prefix] $Message"
    
    $LogTextBox.SelectionStart = $LogTextBox.TextLength
    $LogTextBox.SelectionColor = [System.Drawing.Color]::FromArgb(108, 112, 134)
    $LogTextBox.AppendText("[$Time] ")

    $LogTextBox.SelectionStart = $LogTextBox.TextLength
    $LogTextBox.SelectionColor = [System.Drawing.Color]::FromArgb($ColorRGB[0], $ColorRGB[1], $ColorRGB[2])
    $LogTextBox.AppendText("[$Prefix] ")

    $LogTextBox.SelectionStart = $LogTextBox.TextLength
    $LogTextBox.SelectionColor = [System.Drawing.Color]::FromArgb(205, 214, 244) 
    $LogTextBox.AppendText("$Message`r`n")
    
    $LogTextBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 50 # Уменьшил задержку анимации для отзывчивости
}

# Отрисовка элементов задач на левой панели
$ScriptControls = @()
$YOffset = 15

for ($i = 0; $i -lt $ScriptsToRun.Count; $i++) {
    $CurrentScript = $ScriptsToRun[$i]

    $TaskLabel = New-Object System.Windows.Forms.Label
    $TaskLabel.Text = $CurrentScript.Title
    $TaskLabel.Location = New-Object System.Drawing.Point(20, $YOffset)
    $TaskLabel.Size = New-Object System.Drawing.Size(360, 25)
    $TaskLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $TasksContainer.Controls.Add($TaskLabel)

    $StatusLabel = New-Object System.Windows.Forms.Label
    $StatusLabel.Text = "• Ожидание"
    $StatusLabel.Location = New-Object System.Drawing.Point(400, $YOffset)
    $StatusLabel.Size = New-Object System.Drawing.Size(130, 25)
    $StatusLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
    $StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(166, 173, 200)
    $TasksContainer.Controls.Add($StatusLabel)

    $ScriptControls += [PSCustomObject]@{
        TaskLabel   = $TaskLabel
        StatusLabel = $StatusLabel
    }
    $YOffset += 40
}

# Строка текущего действия (Мини-лог снизу)
$CurrentActionLabel = New-Object System.Windows.Forms.Label
$CurrentActionLabel.Text = "Инициализация подсистем..."
$CurrentActionLabel.Location = New-Object System.Drawing.Point(20, 300)
$CurrentActionLabel.Size = New-Object System.Drawing.Size(540, 25)
$CurrentActionLabel.Font = New-Object System.Drawing.Font("Segoe UI Italic", 10, [System.Drawing.FontStyle]::Italic)
$CurrentActionLabel.ForeColor = [System.Drawing.Color]::FromArgb(245, 194, 231)
$Form.Controls.Add($CurrentActionLabel)

# Нативный прогресс-бар
$ProgressBar = New-Object System.Windows.Forms.ProgressBar
$ProgressBar.Location = New-Object System.Drawing.Point(20, 330)
$ProgressBar.Size = New-Object System.Drawing.Size(540, 25)
$ProgressBar.Minimum = 0
$ProgressBar.Maximum = $ScriptsToRun.Count
$ProgressBar.Value = 0
$Form.Controls.Add($ProgressBar)

# Нижний колонтитул
$FooterLabel = New-Object System.Windows.Forms.Label
$FooterLabel.Text = "Пожалуйста, не закрывайте это окно до завершения всех процессов."
$FooterLabel.Location = New-Object System.Drawing.Point(20, 390)
$FooterLabel.Size = New-Object System.Drawing.Size(900, 25)
$FooterLabel.ForeColor = [System.Drawing.Color]::FromArgb(147, 153, 178)
$FooterLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$Form.Controls.Add($FooterLabel)


# --- ЛОГИКА АВТОМАТИЧЕСКОГО ВЫПОЛНЕНИЯ ---
$Form.Add_Shown({
    $ScriptsDir = "C:\Windows\Setup\Scripts"
    
    $Cyan   = @(137, 220, 235)
    $Purple = @(203, 166, 247)
    $Green  = @(166, 227, 161)
    $Red    = @(243, 139, 168)
    $Yellow = @(249, 226, 175)

    Add-LogLine "CORE" "Запуск планировщика..." $Cyan
    
    for ($i = 0; $i -lt $ScriptsToRun.Count; $i++) {
        $Script = $ScriptsToRun[$i]
        $Controls = $ScriptControls[$i]
        $ScriptPath = Join-Path $ScriptsDir $Script.Name

        # Статус на "Выполняется"
        $Controls.StatusLabel.Text = "▶ Выполняется..."
        $Controls.StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(137, 220, 235)
        $CurrentActionLabel.Text = "Запуск: $($Script.Name)..."
        
        switch ($Script.Name) {
            "clean-and-photo.ps1"        { Add-LogLine "TASK" "Запуск оптимизации ОС" $Purple }
            "install-sys-components.ps1" { Add-LogLine "TASK" "Настройка компонентов" $Purple }
            "apps-install.ps1"           { Add-LogLine "TASK" "Установка ПО" $Purple }
            "office-install.ps1"         { Add-LogLine "TASK" "Установка Office" $Purple }
        }

        if (Test-Path $ScriptPath) {
            try {
                # ЗАПУСКАЕМ БЕЗ -WAIT (чтобы поток формы не зависал)
                $Proc = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" -WindowStyle Hidden -PassThru
                
                # ЖИВОЙ ЦИКЛ ОЖИДАНИЯ: Скрипт выполняется, но форма продолжает жить
                while (-not $Proc.HasExited) {
                    [System.Windows.Forms.Application]::DoEvents() # Магия: держим окно живым
                    Start-Sleep -Milliseconds 100
                }
                
                if ($Proc.ExitCode -eq 0) {
                    $Controls.StatusLabel.Text = "✓ Готово"
                    $Controls.StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(166, 227, 161)
                    Add-LogLine " OK " "Модуль завершен." $Green
                } else {
                    $Controls.StatusLabel.Text = "✗ Сбой (Код: $($Proc.ExitCode))"
                    $Controls.StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(243, 139, 168)
                    Add-LogLine "FAIL" "Ошибка (Код: $($Proc.ExitCode))" $Red
                }
            } catch {
                $Controls.StatusLabel.Text = "✗ Ошибка"
                $Controls.StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(243, 139, 168)
                Add-LogLine "ERR " "Критическая ошибка!" $Red
            }
        } else {
            $Controls.StatusLabel.Text = "⚠ Отсутствует"
            $Controls.StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(249, 226, 175)
            Add-LogLine "WARN" "Файл не найден!" $Yellow
        }

        $ProgressBar.Value = $i + 1
        [System.Windows.Forms.Application]::DoEvents()
    }

    # --- ЗАВЕРШАЮЩИЙ ЭТАП ---
    $CurrentActionLabel.Text = "Финальная зачистка временных директорий..."
    $CurrentActionLabel.ForeColor = [System.Drawing.Color]::FromArgb(166, 227, 161)
    
    Add-LogLine "DONE" "Все процессы завершены." $Green
    Add-LogLine "POST" "Очистка скриптов..." $Cyan
    [System.Windows.Forms.Application]::DoEvents()

    $ResetPath = Join-Path $ScriptsDir "reset-setup-scripts.ps1"
    if (Test-Path $ResetPath) {
        $ProcReset = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ResetPath`"" -WindowStyle Hidden -PassThru
        while (-not $ProcReset.HasExited) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }
    }

    Add-LogLine "EXIT" "Закрытие (3 сек)..." $Yellow
    
    # Плавное ожидание перед закрытием
    $Timeout = [System.Diagnostics.Stopwatch]::StartNew()
    while ($Timeout.Elapsed.TotalSeconds -lt 3) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
    }
    $Form.Close()
})

# Запуск GUI приложения
[System.Windows.Forms.Application]::Run($Form)
Stop-Transcript
