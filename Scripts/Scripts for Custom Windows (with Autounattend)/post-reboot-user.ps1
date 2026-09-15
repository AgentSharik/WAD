# =============================================================================
# post-reboot-user.ps1 — первый вход после перезагрузки: ПК попадает в НАШЕ окно.
#
# Установка шла из встроенного администратора, поэтому после перезагрузки мы
# сами встречаем пользователя: то же интро (Здравствуйте → установка окончена →
# создадим пользователя), затем форма создания пользователя: логин, пароль
# (пусто = без пароля), «Дополнительно» с галочкой «администратор» (включена).
#
# Запускается один раз через RunOnce (прописывается заранее), после создания
# пользователя убирает автологон и свой RunOnce-ключ.
# Поведение на Windows здесь не проверяется (песочница Linux) — см. VM-PROTOCOL.
# =============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

try {
    Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class WadDpi2 { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
    [WadDpi2]::SetProcessDPIAware() | Out-Null
} catch {}

$Screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

# --- интро: те же фразы и порядок, что в видео -------------------------------
$Intro = New-Object System.Windows.Forms.Form
$Intro.FormBorderStyle = 'None'
$Intro.StartPosition = 'Manual'
$Intro.Location = $Screen.Location
$Intro.Size = $Screen.Size
$Intro.TopMost = $true
$Intro.ShowInTaskbar = $false
$Intro.BackColor = [System.Drawing.Color]::FromArgb(240, 245, 252)

$Lbl = New-Object System.Windows.Forms.Label
$Lbl.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 44, [System.Drawing.FontStyle]::Bold)
$Lbl.ForeColor = [System.Drawing.Color]::FromArgb(26, 28, 32)
$Lbl.AutoSize = $true
$Lbl.Location = [System.Drawing.Point]::new([int]($Screen.Width / 2), [int]($Screen.Height / 2))
$Intro.Controls.Add($Lbl)

$Phrases = @('Здравствуйте', 'Установка системы окончена.', 'Теперь давайте создадим вам пользователя')
$Idx = 0
$ShowNext = {
    if ($Idx -lt $Phrases.Count) {
        $Lbl.Text = $Phrases[$Idx]
        $Lbl.Location = [System.Drawing.Point]::new([int](($Intro.Width - $Lbl.Width) / 2), [int]($Intro.Height / 2 - 40))
        $Idx++
    } else {
        $Timer.Stop()
        $Intro.Close()
    }
}
$Timer = New-Object System.Windows.Forms.Timer
$Timer.Interval = 2600
$Timer.Add_Tick($ShowNext)
$Intro.Add_Shown($ShowNext)

# --- форма создания пользователя --------------------------------------------
$Form = New-Object System.Windows.Forms.Form
$Form.FormBorderStyle = 'FixedDialog'
$Form.StartPosition = 'CenterScreen'
$Form.Size = New-Object System.Drawing.Size(560, 420)
$Form.MaximizeBox = $false
$Form.BackColor = [System.Drawing.Color]::FromArgb(252, 253, 255)

$T = New-Object System.Windows.Forms.Label
$T.Text = 'Теперь давайте создадим вам пользователя'
$T.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15, [System.Drawing.FontStyle]::Bold)
$T.Location = New-Object System.Drawing.Point(30, 24)
$T.AutoSize = $true

$LoginLbl = New-Object System.Windows.Forms.Label; $LoginLbl.Text = 'Логин'; $LoginLbl.Location = New-Object System.Drawing.Point(30, 78)
$Login = New-Object System.Windows.Forms.TextBox; $Login.Location = New-Object System.Drawing.Point(30, 100); $Login.Size = New-Object System.Drawing.Size(230, 30); $Login.Text = 'User'
$PassLbl = New-Object System.Windows.Forms.Label; $PassLbl.Text = 'Пароль (необязательно)'; $PassLbl.Location = New-Object System.Drawing.Point(290, 78)
$Pass = New-Object System.Windows.Forms.TextBox; $Pass.Location = New-Object System.Drawing.Point(290, 100); $Pass.Size = New-Object System.Drawing.Size(230, 30)

$Adv = New-Object System.Windows.Forms.Label; $Adv.Text = 'Дополнительно'; $Adv.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11); $Adv.Location = New-Object System.Drawing.Point(30, 150)
$Admin = New-Object System.Windows.Forms.CheckBox
$Admin.Text = 'Пользователь создаётся как администратор'
$Admin.Location = New-Object System.Drawing.Point(30, 178)
$Admin.AutoSize = $true
$Admin.Checked = $true          # по умолчанию — админ, галочка стоит

$Status = New-Object System.Windows.Forms.Label
$Status.Location = New-Object System.Drawing.Point(30, 250)
$Status.Size = New-Object System.Drawing.Size(490, 60)
$Status.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
$Status.ForeColor = [System.Drawing.Color]::FromArgb(138, 146, 160)

$Btn = New-Object System.Windows.Forms.Button
$Btn.Text = 'Создать и продолжить'
$Btn.Size = New-Object System.Drawing.Size(200, 44)
$Btn.Location = New-Object System.Drawing.Point(320, 310)
$Btn.FlatStyle = 'Flat'
$Btn.BackColor = [System.Drawing.Color]::FromArgb(0, 103, 192)
$Btn.ForeColor = [System.Drawing.Color]::White
$Btn.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10, [System.Drawing.FontStyle]::Bold)
$Btn.Add_Click({
    $name = $Login.Text.Trim()
    if (-not $name) { $Status.Text = 'Укажите логин'; $Status.ForeColor = [System.Drawing.Color]::FromArgb(196, 43, 28); return }
    try {
        if ($Pass.Text) {
            $sec = ConvertTo-SecureString $Pass.Text -AsPlainText -Force
            New-LocalUser -Name $name -Password $sec -FullName $name | Out-Null
        } else {
            New-LocalUser -Name $name -FullName $name -NoPassword | Out-Null
        }
        if ($Admin.Checked) { Add-LocalGroupMember -Group 'Administrators' -Member $name }
        # зачищаем автозапуск: автологон и RunOnce больше не нужны
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoLogonCount' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'WadPostRebootUser' -ErrorAction SilentlyContinue
        $Status.ForeColor = [System.Drawing.Color]::FromArgb(16, 124, 65)
        $Status.Text = "Пользователь $name создан. $(if ($Admin.Checked) {'Группа: администраторы.'} else {'Группа: обычные пользователи.'}) Можно выходить из системы."
    } catch {
        $Status.ForeColor = [System.Drawing.Color]::FromArgb(196, 43, 28)
        $Status.Text = "Не удалось создать пользователя: $_"
    }
})

$Form.Controls.AddRange(@($T, $LoginLbl, $Login, $PassLbl, $Pass, $Adv, $Admin, $Status, $Btn))

# интро → форма
[System.Windows.Forms.Application]::Run($Intro)
[System.Windows.Forms.Application]::Run($Form)
