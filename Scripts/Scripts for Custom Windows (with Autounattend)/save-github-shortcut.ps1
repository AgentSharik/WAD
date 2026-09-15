# =============================================================================
# save-github-shortcut.ps1 — модальное окно кнопки «Сайт разработчика».
#
# Кнопка «Сохранить ярлык» кладёт на рабочий стол интернет-ярлык, ведущий на
# GitHub проекта; подсказка поясняет, куда он сохранится.
# Поведение на Windows здесь не проверяется (песочница Linux) — см. VM-PROTOCOL.
# =============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$Url = 'https://github.com/AgentSharik/WAD'

$Form = New-Object System.Windows.Forms.Form
$Form.FormBorderStyle = 'FixedDialog'
$Form.StartPosition = 'CenterScreen'
$Form.Size = New-Object System.Drawing.Size(480, 250)
$Form.MaximizeBox = $false
$Form.MinimizeBox = $false
$Form.BackColor = [System.Drawing.Color]::FromArgb(252, 253, 255)
$Form.ForeColor = [System.Drawing.Color]::FromArgb(26, 28, 32)

$Title = New-Object System.Windows.Forms.Label
$Title.Text = 'Сайт разработчика'
$Title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 14, [System.Drawing.FontStyle]::Bold)
$Title.Location = New-Object System.Drawing.Point(24, 22)
$Title.AutoSize = $true

$Sub = New-Object System.Windows.Forms.Label
$Sub.Text = 'Репозиторий проекта на GitHub'
$Sub.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$Sub.ForeColor = [System.Drawing.Color]::FromArgb(96, 104, 116)
$Sub.Location = New-Object System.Drawing.Point(24, 52)
$Sub.AutoSize = $true

$BtnSave = New-Object System.Windows.Forms.Button
$BtnSave.Text = 'Сохранить ярлык'
$BtnSave.Location = New-Object System.Drawing.Point(24, 110)
$BtnSave.Size = New-Object System.Drawing.Size(170, 40)
$BtnSave.FlatStyle = 'Flat'
$BtnSave.BackColor = [System.Drawing.Color]::FromArgb(0, 103, 192)
$BtnSave.ForeColor = [System.Drawing.Color]::White
$BtnSave.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10, [System.Drawing.FontStyle]::Bold)
$BtnSave.Add_Click({
    try {
        $Desktop = [Environment]::GetFolderPath('Desktop')
        $Path = Join-Path $Desktop 'WAD — сайт разработчика.url'
        # интернет-ярлык Windows: .url с секцией [InternetShortcut]
        "[InternetShortcut]`r`nURL=$Url`r`nIconIndex=0" | Set-Content -Path $Path -Encoding ASCII
        $Status.Text = 'Ярлык сохранён на рабочий стол'
        $Status.ForeColor = [System.Drawing.Color]::FromArgb(16, 124, 65)
    } catch {
        $Status.Text = 'Не удалось сохранить ярлык'
        $Status.ForeColor = [System.Drawing.Color]::FromArgb(196, 43, 28)
    }
})

$Status = New-Object System.Windows.Forms.Label
$Status.Location = New-Object System.Drawing.Point(24, 165)
$Status.Size = New-Object System.Drawing.Size(420, 30)
$Status.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
$Status.ForeColor = [System.Drawing.Color]::FromArgb(138, 146, 160)
$Status.Text = 'Сохранит ярлык на рабочий стол'

$Form.Controls.AddRange(@($Title, $Sub, $BtnSave, $Status))
[System.Windows.Forms.Application]::Run($Form)
