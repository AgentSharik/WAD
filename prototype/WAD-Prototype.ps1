<#
.SYNOPSIS
    WAD — тестовая сборка (прототип). Весь путь «ручками»: заставка → окно установки →
    отчёт в «Документах» → имитация перезагрузки → наше окно после входа.

.DESCRIPTION
    Что РЕАЛЬНО делает прототип:
      * показывает фуллскрин-заставку с титрами и окно установки (таймер, шаблон);
      * кнопка «Сайт разработчика» → «Сохранить ярлык» — честно кладёт .lnk на рабочий стол,
        ведущий на https://github.com/AgentSharik/WAD, и проверяет, что файл появился;
      * создаёт НАСТОЯЩИЙ HTML-отчёт и кладёт его в «Документы» (папка WAD), затем открывает;
      * имитирует перезагрузку: прячет окна, показывает ваш рабочий стол пару секунд,
        затем фуллскрин-фон и наше окно с приветствием.

    Чего прототип НЕ делает (никогда):
      * ничего не скачивает и не устанавливает — ни одного сетевого запроса;
      * не создаёт пользователя и не меняет систему: «Создать и продолжить» только
        показывает результат, помечая его как имитацию;
      * не трогает реестр, автологон, RunOnce, службы.

    Тайминги намеренно чуть медленнее ролика (см. $CFG) — чтобы успеть всё разглядеть.

.EXAMPLE
    .\WAD-Prototype.ps1
.EXAMPLE
    .\WAD-Prototype.ps1 -SkipIntro      # пропустить титры, сразу к окну установки
.EXAMPLE
    .\WAD-Prototype.ps1 -NoRebootSim    # без имитации перезагрузки (только установка и отчёт)
.EXAMPLE
    . .\WAD-Prototype.ps1               # точкой: подгружает только функции (для проверок)

.NOTES
    Выход в любой момент — клавиша Esc.
    Требуется Windows (WinForms). Проверка логики без Windows возможна через dot-source.
#>

[CmdletBinding()]
param(
    [switch]$SkipIntro,
    [switch]$NoRebootSim
)

# =============================================================================
#  Настройки темпа. Значения в секундах; в ролике титр стоял 2.1 с, установка 22 с.
# =============================================================================
$CFG = [pscustomobject]@{
    RepoUrl      = 'https://github.com/AgentSharik/WAD'
    Product      = 'WAD'
    Badge        = 'ТЕСТОВАЯ СБОРКА — ничего не устанавливается'

    IntroFade    = 0.9      # проявление / растворение титра
    IntroHold    = 2.8      # титр стоит (в ролике 2.1 — здесь медленнее)
    IntroGap     = 0.35     # пауза между титрами
    IntroSize    = 54       # кегль титров

    InstallSec   = 30.0     # имитация установки (в ролике 22)
    CountdownSec = 6        # «Перезагрузка через X сек» (в ролике 4.5)
    RebootSec    = 1.6      # чёрный экран «Перезагрузка…»
    DesktopPause = 2.5      # сколько показывать настоящий рабочий стол
    PostHold     = 2.8      # титр после входа стоит (в ролике 2.1)

    TickMs       = 50       # шаг анимации
    WinW         = 1100
    WinH         = 760
}

# 4 ключевые категории — как в ролике: доля от общего времени установки
$WadRows = @(
    [pscustomobject]@{ Name = 'Оптимизация и настройка ОС';              W = 5.0 }
    [pscustomobject]@{ Name = 'Установка системных компонентов';         W = 5.0 }
    [pscustomobject]@{ Name = 'Установка софта';                         W = 7.0 }
    [pscustomobject]@{ Name = 'Установка и активация Microsoft Office';  W = 5.0 }
)
# Демонстрационное «замечание» — как в ролике, чтобы отчёт был честным шаблоном
$WadWarnApps = 'ShareX · K-Lite Codec Pack'

# =============================================================================
#  Чистые функции: никаких окон, проверяются где угодно (в т.ч. вне Windows)
# =============================================================================

function Get-WadPaths {
    <# Папки, куда прототип реально пишет: отчёт в «Документы», ярлык на рабочий стол. #>
    [OutputType([pscustomobject])]
    param()

    $docs = [Environment]::GetFolderPath('MyDocuments')
    if (-not $docs) { $docs = [Environment]::GetFolderPath('UserProfile') }
    $desk = [Environment]::GetFolderPath('Desktop')
    if (-not $desk) { $desk = [Environment]::GetFolderPath('UserProfile') }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
    [pscustomobject]@{
        Documents  = $docs
        ReportDir  = (Join-Path $docs 'WAD')
        ReportFile = (Join-Path (Join-Path $docs 'WAD') "WAD-отчёт-$stamp.html")
        Desktop    = $desk
    }
}

function Get-WadShortcutPath {
    <# Полный путь к ярлыку на рабочем столе. Вынесено отдельно, чтобы проверялось без COM. #>
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$DesktopPath)

    Join-Path $DesktopPath 'WAD — сайт разработчика.lnk'
}

function Get-WadRowStatus {
    <# Состояние категории по прошедшему времени установки: wait / run / ok / warn. #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][double]$Elapsed,
        [Parameter(Mandatory)][double]$Total,
        [int]$WarnIndex = 2
    )

    $acc = 0.0
    $sum = 0.0
    foreach ($r in $WadRows) { $sum += $r.W }
    $out = @()
    for ($i = 0; $i -lt $WadRows.Count; $i++) {
        $dur = $Total * ($WadRows[$i].W / $sum)
        $t0 = $Total * ($acc / $sum)
        $acc += $WadRows[$i].W
        $t1 = $t0 + $dur
        if     ($Elapsed -lt $t0) { $st = 'wait'; $frac = 0.0 }
        elseif ($Elapsed -lt $t1) { $st = 'run';  $frac = ($Elapsed - $t0) / $dur }
        else                      { $st = if ($i -eq $WarnIndex) { 'warn' } else { 'ok' }; $frac = 1.0 }
        $out += [pscustomobject]@{
            Index = $i; Name = $WadRows[$i].Name; State = $st; Frac = $frac
            Start = $t0; End = $t1
        }
    }
    return $out
}

function Get-WadProgress {
    <# Общий процент: взвешенная сумма готовности категорий. #>
    [OutputType([double])]
    param([Parameter(Mandatory)][double]$Elapsed, [Parameter(Mandatory)][double]$Total)

    $states = Get-WadRowStatus -Elapsed $Elapsed -Total $Total
    $sum = 0.0
    foreach ($r in $WadRows) { $sum += $r.W }
    $acc = 0.0
    foreach ($s in $states) {
        $acc += $s.Frac * ($WadRows[$s.Index].W / $sum)
    }
    return [math]::Round([math]::Max(0.0, [math]::Min(1.0, $acc)) * 100, 1)
}

function Get-WadLogRows {
    <# Строки «Подробного отчёта»: длительность этапа + результат. #>
    [OutputType([object[]])]
    param([double]$Total = 30.0)

    $states = Get-WadRowStatus -Elapsed ($Total + 1) -Total $Total
    $rows = @()
    foreach ($s in $states) {
        $dur = $s.End - $s.Start
        $rows += [pscustomobject]@{
            Time     = ('{0:00}:{1:00}' -f [math]::Floor($dur / 60), [math]::Floor($dur % 60))
            Name     = $s.Name
            Result   = if ($s.State -eq 'warn') { 'пропущено' } else { 'готово' }
            Kind     = $s.State
            Detail   = if ($s.State -eq 'warn') { "$WadWarnApps — установка не выполнялась (прототип)" } else { '' }
        }
    }
    return $rows
}

function New-WadReportHtml {
    <# Настоящий HTML-отчёт: тот же dashboard, что в ролике, с честной пометкой о прототипе. #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][datetime]$Started,
        [Parameter(Mandatory)][datetime]$Finished,
        [string]$UserName = 'User',
        [bool]$AsAdmin = $true,
        [string]$RepoUrl = 'https://github.com/AgentSharik/WAD'
    )

    $logs = Get-WadLogRows -Total $CFG.InstallSec
    $okCount = ($logs | Where-Object { $_.Kind -eq 'ok' }).Count
    $warnCount = ($logs | Where-Object { $_.Kind -eq 'warn' }).Count
    $dur = $Finished - $Started

    $cards = ''
    foreach ($l in $logs) {
        $col = if ($l.Kind -eq 'warn') { '#c42b1c' } else { '#107c41' }
        $mark = if ($l.Kind -eq 'warn') { '&#10005;' } else { '&#10003;' }
        $cards += @"
      <div class="card">
        <div class="dot" style="background:$col">$mark</div>
        <div class="cname">$($l.Name)</div>
        <div class="cres" style="color:$col">$($l.Result)</div>
        <div class="ctime">$($l.Time)</div>
      </div>
"@
    }

    $logRows = ''
    foreach ($l in $logs) {
        $col = if ($l.Kind -eq 'warn') { '#c42b1c' } else { '#107c41' }
        $logRows += "        <tr><td class=`"t`">$($l.Time)</td><td>$($l.Name)</td><td class=`"r`" style=`"color:$col`">$($l.Result)</td></tr>`r`n"
        if ($l.Detail) {
            $logRows += "        <tr class=`"sub`"><td></td><td colspan=`"2`">$($l.Detail)</td></tr>`r`n"
        }
    }

    $userLine = "Пользователь <b>$UserName</b> — $(if ($AsAdmin) { 'администратор' } else { 'обычный пользователь' }) (в прототипе не создавался)"

    @"
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<title>WAD — отчёт об установке</title>
<style>
  body{margin:0;background:#f0f5fc;color:#1a1c20;font:15px/1.5 "Segoe UI",Arial,sans-serif}
  .wrap{max-width:1100px;margin:0 auto;padding:40px 32px 64px}
  .badge{display:inline-block;background:#fff4e5;border:1px solid #d97706;color:#9d5d00;
         padding:6px 12px;border-radius:8px;font-size:13px;font-weight:600;margin-bottom:20px}
  h1{font-size:34px;margin:0 0 6px}
  .meta{color:#606874;margin:0 0 24px}
  .promo{display:inline-block;background:#0067c0;color:#fff;text-decoration:none;
         padding:12px 22px;border-radius:10px;font-weight:600;float:right}
  .cards{display:flex;gap:16px;flex-wrap:wrap;margin:26px 0}
  .card{flex:1 1 210px;background:#fff;border:1px solid #e6e9ef;border-radius:12px;padding:16px}
  .dot{width:26px;height:26px;border-radius:50%;color:#fff;text-align:center;line-height:26px;font-size:14px}
  .cname{font-weight:600;margin:10px 0 4px}
  .cres{font-size:14px}
  .ctime{color:#8a92a0;font-size:13px;margin-top:6px}
  .warn{background:#fff9f0;border:1px solid #f0c8a0;border-left:4px solid #c42b1c;
        border-radius:10px;padding:14px 18px;margin:8px 0 26px}
  .warn b{display:block;margin-bottom:4px}
  h2{font-size:19px;margin:26px 0 10px}
  table{width:100%;border-collapse:collapse;background:#fff;border:1px solid #e6e9ef;border-radius:12px;overflow:hidden}
  td{padding:12px 16px;border-top:1px solid #f0f2f6}
  tr:first-child td{border-top:none}
  td.t{color:#8a92a0;width:70px}
  td.r{text-align:right;font-weight:600;width:120px}
  tr.sub td{color:#c42b1c;font-size:14px;padding-top:0}
  .foot{color:#8a92a0;font-size:13px;margin-top:28px}
</style>
</head>
<body>
<div class="wrap">
  <a class="promo" href="$RepoUrl">Сайт разработчика</a>
  <div class="badge">$($CFG.Badge)</div>
  <h1>Всё готово</h1>
  <p class="meta">Прогон завершён $($Finished.ToString('dd.MM.yyyy HH:mm')) · $($logs.Count) категории · замечаний: $warnCount · длилось $('{0:00}:{1:00}' -f [math]::Floor($dur.TotalMinutes), $dur.Seconds)</p>

  <div class="cards">
$cards
  </div>

  <div class="warn">
    <b>Установилось не всё: $warnCount программы</b>
    $WadWarnApps
  </div>

  <h2>Подробный отчёт</h2>
  <table>
$logRows  </table>

  <h2>Пользователь</h2>
  <table>
    <tr><td>$userLine</td></tr>
  </table>

  <p class="foot">Отчёт создан прототипом WAD. Успешных этапов: $okCount из $($logs.Count).
  Ни одна программа не скачивалась и не устанавливалась — это демонстрационный прогон.</p>
</div>
</body>
</html>
"@
}

function Save-WadReport {
    <# Реально пишет отчёт в «Документы» и возвращает путь. #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][datetime]$Started,
        [Parameter(Mandatory)][datetime]$Finished,
        [string]$UserName = 'User',
        [bool]$AsAdmin = $true,
        [string]$ReportFile
    )

    if (-not $ReportFile) { $ReportFile = (Get-WadPaths).ReportFile }
    $dir = Split-Path $ReportFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $html = New-WadReportHtml -Started $Started -Finished $Finished -UserName $UserName -AsAdmin $AsAdmin -RepoUrl $CFG.RepoUrl
    $enc = New-Object System.Text.UTF8Encoding($true)          # BOM — кириллица читается везде
    [System.IO.File]::WriteAllText($ReportFile, $html, $enc)

    [pscustomobject]@{
        Path  = $ReportFile
        Bytes = (Get-Item $ReportFile).Length
        Html  = $html
    }
}

function Save-WadShortcut {
    <# Реально кладёт ярлык на рабочий стол и проверяет, что файл появился. Только Windows. #>
    [OutputType([pscustomobject])]
    param([string]$Target, [string]$LinkPath)

    if (-not $Target)   { $Target = $CFG.RepoUrl }
    if (-not $LinkPath) { $LinkPath = Get-WadShortcutPath -DesktopPath (Get-WadPaths).Desktop }

    $result = [pscustomobject]@{ Success = $false; Path = $LinkPath; Error = '' }
    try {
        $sh = New-Object -ComObject WScript.Shell
        $lnk = $sh.CreateShortcut($LinkPath)
        $lnk.TargetPath = $Target
        $lnk.Description = 'WAD — репозиторий проекта на GitHub'
        $lnk.Save()
        if (Test-Path -LiteralPath $LinkPath) { $result.Success = $true }
        else { $result.Error = 'файл не появился на диске' }
    } catch {
        $result.Error = $_.Exception.Message
    }
    return $result
}

# Точка в начале = подгрузили только функции (проверки, тесты) — окна не показываем.
if ($MyInvocation.InvocationName -eq '.') { return }

# =============================================================================
#  Дальше — только Windows/WinForms: окна и анимация
# =============================================================================
if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
    Write-Warning 'Прототип показывает окна и работает только в Windows. Запустите WAD-Запуск.bat на Windows-машине.'
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
try {
    Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class WadDpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
    [WadDpi]::SetProcessDPIAware() | Out-Null
} catch { Write-Verbose 'DPI-режим не выставлен — не критично' }

# --- палитра как в ролике -----------------------------------------------------
$C = @{
    Text   = [System.Drawing.Color]::FromArgb(26, 28, 32)
    Text2  = [System.Drawing.Color]::FromArgb(96, 104, 116)
    Text3  = [System.Drawing.Color]::FromArgb(138, 146, 160)
    Accent = [System.Drawing.Color]::FromArgb(0, 103, 192)
    Accent2= [System.Drawing.Color]::FromArgb(116, 92, 231)
    Ok     = [System.Drawing.Color]::FromArgb(16, 124, 65)
    Err    = [System.Drawing.Color]::FromArgb(196, 43, 28)
    Line   = [System.Drawing.Color]::FromArgb(216, 220, 228)
    Card   = [System.Drawing.Color]::FromArgb(252, 253, 255)
    Warn   = [System.Drawing.Color]::FromArgb(157, 93, 0)
}

$Screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

function Get-WadWallpaper {
    <# Берёт обои из репозитория (не копируем файл — не раздуваем git); нет — градиент. #>
    $cands = @(
        (Join-Path $PSScriptRoot 'wallpaper-win11.png'),
        (Join-Path $PSScriptRoot '..\..\extras\design\demo\wallpaper-win11.png'),
        (Join-Path $PSScriptRoot '..\extras\design\demo\wallpaper-win11.png')
    )
    foreach ($c in $cands) {
        $full = [System.IO.Path]::GetFullPath($c)
        if (Test-Path -LiteralPath $full) {
            try { return [System.Drawing.Image]::FromFile($full) }
            catch { Write-Verbose "обои не читаются: $full" }
        }
    }
    return $null
}

function Set-WadDoubleBuffer($form) {
    try {
        $p = $form.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic')
        if ($p) { $p.SetValue($form, $true, $null) }
    } catch { Write-Verbose 'DoubleBuffered недоступен — не критично' }
}

function Add-WadRoundRegion($ctrl, [int]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $w = $ctrl.Width; $h = $ctrl.Height
    if ($w -lt $r * 2) { $w = $r * 2 }
    if ($h -lt $r * 2) { $h = $r * 2 }
    $p.AddArc(0, 0, $r * 2, $r * 2, 180, 90)
    $p.AddArc($w - $r * 2, 0, $r * 2, $r * 2, 270, 90)
    $p.AddArc($w - $r * 2, $h - $r * 2, $r * 2, $r * 2, 0, 90)
    $p.AddArc(0, $h - $r * 2, $r * 2, $r * 2, 90, 90)
    $p.CloseFigure()
    $ctrl.Region = New-Object System.Drawing.Region($p)
}

function New-WadLabel {
    param($Text, [int]$X, [int]$Y, [int]$Size = 12, [string]$Style = 'Regular', $Color, [bool]$Auto = $true)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.AutoSize = $Auto
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.Font = New-Object System.Drawing.Font('Segoe UI', $Size, [System.Drawing.FontStyle]::Parse($Style))
    if ($Color) { $l.ForeColor = $Color } else { $l.ForeColor = $C.Text }
    return $l
}

function New-WadFullscreen {
    <# Фуллскрин-основа: без рамки, поверх всех окон. #>
    param([bool]$TopMost = $true)
    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'
    $f.StartPosition = 'Manual'
    $f.Bounds = $Screen
    $f.TopMost = $TopMost
    $f.ShowInTaskbar = $false
    $f.KeyPreview = $true
    $f.BackColor = [System.Drawing.Color]::FromArgb(240, 245, 252)
    Set-WadDoubleBuffer $f
    $wall = Get-WadWallpaper
    if ($wall) { $f.BackgroundImage = $wall; $f.BackgroundImageLayout = 'Stretch' }
    $f.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $script:WadExit = $true; $f.Close() } })
    return $f
}

function Show-WadTitles {
    <# Титры на фуллскрине: проявление → пауза → растворение. Возвращает $true, если досмотрели. #>
    param([Parameter(Mandatory)][string[]]$Lines, [double]$Hold, [bool]$Dark = $false)

    $form = New-WadFullscreen -TopMost $true
    $ink = if ($Dark) { [System.Drawing.Color]::White } else { $C.Text }
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.AutoSize = $true
    $lbl.TextAlign = 'MiddleCenter'
    $lbl.Font = New-Object System.Drawing.Font('Segoe UI Semibold', $CFG.IntroSize, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = [System.Drawing.Color]::FromArgb(0, $ink)
    $form.Controls.Add($lbl)

    $st = @{ i = 0; done = $false; aborted = $false }
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $CFG.TickMs

    $fade = $CFG.IntroFade
    $total = $Lines.Count * ($fade * 2 + $Hold) + ($Lines.Count - 1) * $CFG.IntroGap
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    $timer.Add_Tick({
        $t = $sw.Elapsed.TotalSeconds
        $seg = $fade * 2 + $Hold
        $k = [math]::Floor($t / ($seg + $CFG.IntroGap))
        $lt = $t - $k * ($seg + $CFG.IntroGap)

        if ($k -ge $Lines.Count -or $t -gt $total) {
            $timer.Stop(); $sw.Stop(); $st.done = $true; $form.Close(); return
        }
        if ($k -ne $st.i -or $lbl.Text -ne $Lines[$k]) {
            $st.i = $k
            $lbl.Text = $Lines[$k]
            $lbl.Location = New-Object System.Drawing.Point(
                [int](($form.Width - $lbl.Width) / 2), [int]($form.Height / 2 - $lbl.Height / 2))
        }
        $a = 0.0
        if     ($lt -lt $fade)              { $a = $lt / $fade }
        elseif ($lt -lt $fade + $Hold)      { $a = 1.0 }
        else                                { $a = 1.0 - (($lt - $fade - $Hold) / $fade) }
        $a = [math]::Max(0.0, [math]::Min(1.0, $a))
        $lbl.ForeColor = [System.Drawing.Color]::FromArgb([int](255 * $a), $ink)
    })

    $form.Add_FormClosed({ $st.aborted = $script:WadExit -eq $true })
    $timer.Start()
    [System.Windows.Forms.Application]::Run($form)
    $timer.Dispose()
    $form.Dispose()
    return (-not $st.aborted)
}

function Show-WadRebootScreen {
    <# Чёрный экран «Перезагрузка…» — имитация ухода системы в рестарт. #>
    param([double]$Seconds)
    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.StartPosition = 'Manual'
    $form.Bounds = $Screen
    $form.TopMost = $true
    $form.ShowInTaskbar = $false
    $form.BackColor = [System.Drawing.Color]::Black
    $lbl = New-WadLabel 'Перезагрузка…' ([int]($Screen.Width / 2 - 140)) ([int]($Screen.Height / 2 - 20)) 20 'Regular' ([System.Drawing.Color]::White)
    $form.Controls.Add($lbl)
    $hint = New-WadLabel 'это имитация — компьютер не перезагружается' ([int]($Screen.Width / 2 - 200)) ([int]($Screen.Height / 2 + 30)) 11 'Regular' ([System.Drawing.Color]::FromArgb(140, 140, 150))
    $form.Controls.Add($hint)
    $t = New-Object System.Windows.Forms.Timer
    $t.Interval = [int]($Seconds * 1000)
    $t.Add_Tick({ $t.Stop(); $form.Close() })
    $t.Start()
    [System.Windows.Forms.Application]::Run($form)
    $t.Dispose(); $form.Dispose()
}

# =============================================================================
#  Главное окно установки
# =============================================================================
function Show-WadMainWindow {
    <# Окно установки: 4 категории, нижний бар, кнопка сайта. Возвращает $true, если дошло до «перезагрузки». #>

    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size($CFG.WinW, $CFG.WinH)
    $form.BackColor = $C.Card
    $form.KeyPreview = $true
    $form.TopMost = $true
    Set-WadDoubleBuffer $form
    $form.Add_Resize({ Add-WadRoundRegion $form 14 })
    $form.Add_Shown({ Add-WadRoundRegion $form 14 })

    $st = @{
        Started = Get-Date
        Elapsed = 0.0
        Progress = 0.0
        Phase = 'install'          # install → countdown
        CountLeft = [int]$CFG.CountdownSec
        Spin = 0
        Minimized = $false
        Finished = $false
        Aborted = $false
        Report = $null
    }

    # --- шапка окна
    $title = New-WadLabel 'установка Windows' 20 13 10.5 'Regular' $C.Text2
    $form.Controls.Add($title)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = '✕'; $btnClose.Size = New-Object System.Drawing.Size(38, 30)
    $btnClose.Location = New-Object System.Drawing.Point($CFG.WinW - 52, 6)
    $btnClose.FlatStyle = 'Flat'; $btnClose.FlatAppearance.BorderSize = 0
    $btnClose.BackColor = [System.Drawing.Color]::Transparent; $btnClose.ForeColor = $C.Text2
    $btnClose.TabStop = $false
    $btnClose.Add_Click({
        $r = [System.Windows.Forms.MessageBox]::Show('Прервать прототип WAD?', 'WAD',
            [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($r -eq [System.Windows.Forms.DialogResult]::Yes) { $st.Aborted = $true; $form.Close() }
    })
    $form.Controls.Add($btnClose)

    $btnMin = New-Object System.Windows.Forms.Button
    $btnMin.Text = '—'; $btnMin.Size = New-Object System.Drawing.Size(38, 30)
    $btnMin.Location = New-Object System.Drawing.Point($CFG.WinW - 92, 6)
    $btnMin.FlatStyle = 'Flat'; $btnMin.FlatAppearance.BorderSize = 0
    $btnMin.BackColor = [System.Drawing.Color]::Transparent; $btnMin.ForeColor = $C.Text2
    $btnMin.TabStop = $false
    $btnMin.Add_Click({ $st.Minimized = $true; $form.WindowState = 'Minimized' })
    $form.Controls.Add($btnMin)

    $btnSite = New-Object System.Windows.Forms.Button
    $btnSite.Text = '  Сайт разработчика'
    $btnSite.Size = New-Object System.Drawing.Size(180, 32)
    $btnSite.Location = New-Object System.Drawing.Point($CFG.WinW - 300, 5)
    $btnSite.FlatStyle = 'Flat'
    $btnSite.FlatAppearance.BorderColor = $C.Accent
    $btnSite.BackColor = [System.Drawing.Color]::FromArgb(232, 242, 252)
    $btnSite.ForeColor = $C.Accent
    $btnSite.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $btnSite.TabStop = $false
    $btnSite.Add_Click({ Show-WadSiteDialog -Owner $form })
    $form.Controls.Add($btnSite)

    # --- заголовок и бейдж прототипа
    $h = New-WadLabel 'Менеджер автоматической настройки' 40 66 22 'Bold'
    $form.Controls.Add($h)
    $badge = New-WadLabel $CFG.Badge 40 108 10.5 'Bold' $C.Warn
    $form.Controls.Add($badge)

    # --- 4 категории
    $rowPanels = @(); $rowIcons = @(); $rowSubs = @(); $rowTimes = @()
    $ry = 150; $rh = 74
    for ($i = 0; $i -lt $WadRows.Count; $i++) {
        $p = New-Object System.Windows.Forms.Panel
        $p.Size = New-Object System.Drawing.Size($CFG.WinW - 80, $rh)
        $p.Location = New-Object System.Drawing.Point(40, ($ry + $i * ($rh + 12)))
        $p.BackColor = [System.Drawing.Color]::White
        $p.BorderStyle = 'FixedSingle'
        $form.Controls.Add($p)

        $icon = New-Object System.Windows.Forms.PictureBox
        $icon.Size = New-Object System.Drawing.Size(26, 26)
        $icon.Location = New-Object System.Drawing.Point(16, [int](($rh - 26) / 2))
        $icon.SizeMode = 'AutoSize'
        $p.Controls.Add($icon)

        $nm = New-WadLabel $WadRows[$i].Name 60 14 13 'Bold'
        $p.Controls.Add($nm)
        $sub = New-WadLabel 'ожидание' 60 40 11 'Regular' $C.Text3
        $p.Controls.Add($sub)
        $tm = New-WadLabel '' ($CFG.WinW - 80 - 90) 28 11 'Regular' $C.Text3
        $p.Controls.Add($tm)

        $rowPanels += $p; $rowIcons += $icon; $rowSubs += $sub; $rowTimes += $tm
    }

    # --- нижний бар
    $barY = $CFG.WinH - 110
    $cap = New-WadLabel 'Установка…' 40 ($barY - 30) 13 'Bold'
    $form.Controls.Add($cap)
    $pct = New-WadLabel '0%' ($CFG.WinW - 160) ($barY - 42) 22 'Bold' $C.Accent
    $form.Controls.Add($pct)
    $hint = New-WadLabel '' ($CFG.WinW - 340) ($barY - 24) 10.5 'Regular' $C.Text3
    $form.Controls.Add($hint)

    $bar = New-Object System.Windows.Forms.Panel
    $bar.Size = New-Object System.Drawing.Size($CFG.WinW - 80 - 200, 8)
    $bar.Location = New-Object System.Drawing.Point(40, $barY)
    $bar.BackColor = [System.Drawing.Color]::FromArgb(230, 233, 239)
    $bar.Add_Paint({
        $g = $_.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $w = $bar.Width; $hh = $bar.Height
        $k = $st.Progress
        if ($st.Phase -eq 'countdown') { $k = 1.0 - ($st.CountLeft / $CFG.CountdownSec) }
        $fill = [math]::Max(6, [int]($w * $k))
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.Rectangle(0, 0, $fill, $hh)), $C.Accent, $C.Accent2, 0.0)
        $g.FillRectangle($brush, 0, 0, $fill, $hh)
        # плывущий блик
        $sx = [int](($st.Spin * 7) % ($w + 120)) - 60
        $shine = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(70, 255, 255, 255))
        $g.FillRectangle($shine, $sx, 0, 60, $hh)
        $brush.Dispose(); $shine.Dispose()
    })
    $form.Controls.Add($bar)

    $btnBg = New-Object System.Windows.Forms.Button
    $btnBg.Text = 'Свернуть в фон'
    $btnBg.Size = New-Object System.Drawing.Size(170, 38)
    $btnBg.Location = New-Object System.Drawing.Point($CFG.WinW - 210, ($barY - 16))
    $btnBg.FlatStyle = 'Flat'; $btnBg.FlatAppearance.BorderSize = 0
    $btnBg.BackColor = $C.Accent; $btnBg.ForeColor = [System.Drawing.Color]::White
    $btnBg.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $btnBg.TabStop = $false
    $btnBg.Add_Click({ $st.Minimized = $true; $form.WindowState = 'Minimized' })
    $form.Controls.Add($btnBg)

    # значок в трее, когда свёрнули (в $script: — иначе обработчик пишет в свою копию)
    $script:WadTray = $null

    # --- иконки статусов
    function Set-RowIcon($pb, [string]$kind, [int]$spin) {
        $bmp = New-Object System.Drawing.Bitmap(26, 26)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = 'AntiAlias'
        $cx = 13; $cy = 13
        switch ($kind) {
            'wait' {
                $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(120, 138, 146, 160), 2)
                $g.DrawEllipse($pen, 4, 4, 18, 18); $pen.Dispose()
            }
            'run' {
                for ($j = 0; $j -lt 8; $j++) {
                    $ang = ($spin * 0.35) + $j * ([math]::PI / 4)
                    $al = [int](50 + 200 * ($j / 8))
                    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($al, $C.Accent), 2)
                    $x1 = $cx + 6 * [math]::Cos($ang); $y1 = $cy + 6 * [math]::Sin($ang)
                    $x2 = $cx + 11 * [math]::Cos($ang); $y2 = $cy + 11 * [math]::Sin($ang)
                    $g.DrawLine($pen, [single]$x1, [single]$y1, [single]$x2, [single]$y2)
                    $pen.Dispose()
                }
            }
            'ok' {
                $b = New-Object System.Drawing.SolidBrush($C.Ok)
                $g.FillEllipse($b, 2, 2, 22, 22); $b.Dispose()
                $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2)
                $g.DrawLines($pen, @(
                    (New-Object System.Drawing.Point(7, 13)),
                    (New-Object System.Drawing.Point(11, 17)),
                    (New-Object System.Drawing.Point(19, 8))))
                $pen.Dispose()
            }
            'warn' {
                $b = New-Object System.Drawing.SolidBrush($C.Err)
                $g.FillEllipse($b, 2, 2, 22, 22); $b.Dispose()
                $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2)
                $g.DrawLine($pen, 8, 8, 18, 18); $g.DrawLine($pen, 18, 8, 8, 18); $pen.Dispose()
            }
        }
        $g.Dispose()
        $old = $pb.Image
        $pb.Image = $bmp
        if ($old) { $old.Dispose() }
    }

    function Update-Rows {
        $states = Get-WadRowStatus -Elapsed $st.Elapsed -Total $CFG.InstallSec
        for ($i = 0; $i -lt $states.Count; $i++) {
            $s = $states[$i]
            Set-RowIcon $rowIcons[$i] $s.State $st.Spin
            switch ($s.State) {
                'run'  { $rowSubs[$i].Text = 'выполняется…';                $rowSubs[$i].ForeColor = $C.Text3 }
                'ok'   { $rowSubs[$i].Text = 'готово';                      $rowSubs[$i].ForeColor = $C.Ok;
                         $rowTimes[$i].Text = ('[{0:00}:{1:00}]' -f [math]::Floor(($s.End - $s.Start) / 60), [math]::Floor(($s.End - $s.Start) % 60)) }
                'warn' { $rowSubs[$i].Text = 'пропущено / ошибка';          $rowSubs[$i].ForeColor = $C.Err;
                         $rowTimes[$i].Text = '—' }
                default{ $rowSubs[$i].Text = 'ожидание';                    $rowSubs[$i].ForeColor = $C.Text3 }
            }
        }
    }

    # --- главный таймер
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $CFG.TickMs
    $lastCd = [int]$CFG.CountdownSec

    $timer.Add_Tick({
        $st.Elapsed += ($CFG.TickMs / 1000.0)
        $st.Spin++

        if ($st.Phase -eq 'install') {
            $st.Progress = (Get-WadProgress -Elapsed $st.Elapsed -Total $CFG.InstallSec) / 100.0
            $pct.Text = '{0}%' -f [int]($st.Progress * 100)
            Update-Rows
            $bar.Invalidate()
            if ($st.Elapsed -ge $CFG.InstallSec) {
                $st.Phase = 'countdown'
                $st.CountLeft = [int]$CFG.CountdownSec
                $cap.Text = 'Перезагрузка через {0} сек' -f $st.CountLeft
                $pct.Text = '100%'
                $hint.Text = 'можно ничего не нажимать'
                Write-Host '[WAD] установка (имитация) завершена — пошёл отсчёт до перезагрузки' -ForegroundColor Cyan
                # если свёрнули — возвращаем окно, чтобы отсчёт было видно
                if ($form.WindowState -eq 'Minimized') { $form.WindowState = 'Normal'; $form.Activate() }
                if ($script:WadTray) { $script:WadTray.Visible = $false; $script:WadTray.Dispose(); $script:WadTray = $null }
            }
        }
        else {
            $left = [int][math]::Ceiling($CFG.CountdownSec - ($st.Elapsed - $CFG.InstallSec))
            if ($left -lt 0) { $left = 0 }
            if ($left -ne $lastCd) {
                $lastCd = $left
                $st.CountLeft = $left
                $cap.Text = if ($left -gt 0) { 'Перезагрузка через {0} сек' -f $left } else { 'Перезагрузка…' }
                $bar.Invalidate()
            }
            if ($left -le 0) {
                $timer.Stop()
                $st.Finished = $true
                $form.Close()
            }
        }
    })

    # трей-значок при сворачивании
    $form.Add_Resize({
        Add-WadRoundRegion $form 14
        if ($form.WindowState -eq 'Minimized' -and -not $script:WadTray) {
            try {
                $script:WadTray = New-Object System.Windows.Forms.NotifyIcon
                $script:WadTray.Icon = [System.Drawing.SystemIcons]::Application
                $script:WadTray.Text = 'WAD работает в фоне (прототип)'
                $script:WadTray.Visible = $true
                $script:WadTray.Add_Click({ $form.WindowState = 'Normal'; $form.Activate() })
            } catch { Write-Verbose 'значок в трее не создан — не критично' }
        }
    })

    $form.Add_FormClosed({
        $timer.Stop(); $timer.Dispose()
        if ($script:WadTray) { $script:WadTray.Visible = $false; $script:WadTray.Dispose(); $script:WadTray = $null }
    })

    $form.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $st.Aborted = $true; $form.Close() } })

    Write-Host '[WAD] окно установки — пошёл имитационный прогон (ничего не качается)' -ForegroundColor Cyan
    $st.Progress = 0.0
    Update-Rows
    $timer.Start()
    [System.Windows.Forms.Application]::Run($form)

    if ($script:WadTray) { $script:WadTray.Visible = $false; $script:WadTray.Dispose(); $script:WadTray = $null }
    $form.Dispose()

    if ($st.Aborted) { return $null }
    return $st
}

function Show-WadSiteDialog {
    <# Модалка «Сайт разработчика»: «Сохранить ярлык» реально кладёт .lnk на рабочий стол. #>
    param($Owner)

    $d = New-Object System.Windows.Forms.Form
    $d.FormBorderStyle = 'FixedDialog'
    $d.StartPosition = if ($Owner) { 'CenterParent' } else { 'CenterScreen' }
    $d.Size = New-Object System.Drawing.Size(500, 300)
    $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.Text = 'Сайт разработчика'
    $d.BackColor = [System.Drawing.Color]::White
    if ($Owner) { $d.Owner = $Owner }

    $t = New-WadLabel 'Сайт разработчика' 26 22 16 'Bold'
    $d.Controls.Add($t)
    $s1 = New-WadLabel 'Репозиторий проекта на GitHub' 26 58 11.5 'Regular' $C.Text2
    $d.Controls.Add($s1)
    $s2 = New-WadLabel $CFG.RepoUrl 26 82 10.5 'Regular' $C.Text3
    $d.Controls.Add($s2)

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Сохранить ярлык'
    $btn.Size = New-Object System.Drawing.Size(190, 42)
    $btn.Location = New-Object System.Drawing.Point(26, 130)
    $btn.FlatStyle = 'Flat'; $btn.FlatAppearance.BorderSize = 0
    $btn.BackColor = $C.Accent; $btn.ForeColor = [System.Drawing.Color]::White
    $btn.Font = New-Object System.Drawing.Font('Segoe UI', 10.5, [System.Drawing.FontStyle]::Bold)
    $d.Controls.Add($btn)

    $note = New-WadLabel 'Сохранит ярлык на рабочий стол' 26 190 10.5 'Regular' $C.Text3
    $note.AutoSize = $false
    $note.Size = New-Object System.Drawing.Size(440, 60)
    $d.Controls.Add($note)

    $btn.Add_Click({
        $note.Text = 'Сохраняем…'
        $note.ForeColor = $C.Text2
        $d.Refresh()
        $res = Save-WadShortcut
        if ($res.Success) {
            $note.ForeColor = $C.Ok
            $note.Text = "Ярлык сохранён на рабочий стол:`r`n$($res.Path)"
            Write-Host "[WAD] ярлык сохранён: $($res.Path)" -ForegroundColor Green
        } else {
            $note.ForeColor = $C.Err
            $note.Text = "Не удалось сохранить ярлык: $($res.Error)"
            Write-Host "[WAD] ярлык НЕ сохранён: $($res.Error)" -ForegroundColor Red
        }
    })

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Закрыть'
    $ok.Size = New-Object System.Drawing.Size(120, 42)
    $ok.Location = New-Object System.Drawing.Point(330, 130)
    $ok.FlatStyle = 'Flat'
    $ok.BackColor = [System.Drawing.Color]::FromArgb(240, 242, 246)
    $ok.Add_Click({ $d.Close() })
    $d.Controls.Add($ok)

    [System.Windows.Forms.Application]::Run($d)
    $d.Dispose()
}

# =============================================================================
#  После «перезагрузки»: фуллскрин-фон, приветствие, окно создания пользователя
# =============================================================================
function Show-WadPostBoot {
    <# Фуллскрин-фон + окно создания пользователя. Пользователь НЕ создаётся — только показ. #>
    param([string]$ReportPath = '')

    $bg = New-WadFullscreen -TopMost $true
    $stamp = New-WadLabel $CFG.Badge 24 20 10 'Bold' $C.Warn
    $bg.Controls.Add($stamp)
    if ($ReportPath) {
        $rl = New-WadLabel "Отчёт: $ReportPath" 24 44 9.5 'Regular' $C.Text2
        $bg.Controls.Add($rl)
    }

    $bgShown = $false
    $bg.Add_Shown({
        if ($bgShown) { return }
        $bgShown = $true
        Show-WadUserDialog -Owner $bg
        $bg.Close()
    })

    [System.Windows.Forms.Application]::Run($bg)
    $bg.Dispose()
}

function Show-WadUserDialog {
    <# Окно «создание пользователя». Реального создания нет — интерфейс честно это пишет. #>
    param($Owner)

    $d = New-Object System.Windows.Forms.Form
    $d.FormBorderStyle = 'FixedDialog'
    $d.StartPosition = 'CenterParent'
    $d.Size = New-Object System.Drawing.Size(620, 470)
    $d.MaximizeBox = $false
    $d.Text = 'создание пользователя'
    $d.BackColor = $C.Card
    if ($Owner) { $d.Owner = $Owner }

    $h = New-WadLabel 'Теперь давайте создадим вам пользователя' 30 20 15 'Bold'
    $d.Controls.Add($h)
    $sub = New-WadLabel 'Логин обязателен, пароль — по желанию: пусто значит без пароля' 30 56 10.5 'Regular' $C.Text2
    $d.Controls.Add($sub)

    $ll = New-WadLabel 'Логин' 30 96 10.5 'Regular' $C.Text2
    $d.Controls.Add($ll)
    $login = New-Object System.Windows.Forms.TextBox
    $login.Location = New-Object System.Drawing.Point(30, 118); $login.Size = New-Object System.Drawing.Size(255, 30)
    $login.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    $login.Text = 'User'
    $d.Controls.Add($login)

    $pl = New-WadLabel 'Пароль' 315 96 10.5 'Regular' $C.Text2
    $d.Controls.Add($pl)
    $pass = New-Object System.Windows.Forms.TextBox
    $pass.Location = New-Object System.Drawing.Point(315, 118); $pass.Size = New-Object System.Drawing.Size(255, 30)
    $pass.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    $pass.UseSystemPasswordChar = $true
    $d.Controls.Add($pass)
    $ph = New-WadLabel 'необязательно' 315 150 9.5 'Regular' $C.Text3
    $d.Controls.Add($ph)

    $adv = New-WadLabel 'Дополнительно' 30 186 11.5 'Bold'
    $d.Controls.Add($adv)
    $admin = New-Object System.Windows.Forms.CheckBox
    $admin.Text = 'Пользователь создаётся как администратор'
    $admin.Location = New-Object System.Drawing.Point(30, 214)
    $admin.AutoSize = $true
    $admin.Checked = $true
    $admin.Font = New-Object System.Drawing.Font('Segoe UI', 10.5)
    $d.Controls.Add($admin)
    $ah = New-WadLabel 'снимите галочку — будет обычный пользователь с ограниченными правами' 30 244 9.5 'Regular' $C.Text3
    $d.Controls.Add($ah)

    $status = New-Object System.Windows.Forms.Label
    $status.Location = New-Object System.Drawing.Point(30, 288)
    $status.Size = New-Object System.Drawing.Size(540, 70)
    $status.Font = New-Object System.Drawing.Font('Segoe UI', 10.5)
    $status.ForeColor = $C.Text3
    $status.Text = 'Прототип: пользователь не создаётся — только показ результата.'
    $d.Controls.Add($status)

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Создать и продолжить'
    $btn.Size = New-Object System.Drawing.Size(230, 46)
    $btn.Location = New-Object System.Drawing.Point(340, 366)
    $btn.FlatStyle = 'Flat'; $btn.FlatAppearance.BorderSize = 0
    $btn.BackColor = $C.Accent; $btn.ForeColor = [System.Drawing.Color]::White
    $btn.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $d.Controls.Add($btn)

    $done = @{ Flag = $false }          # второе нажатие кнопки просто закрывает окно
    $btn.Add_Click({
        if ($done.Flag) { $d.Close(); return }
        $name = $login.Text.Trim()
        if (-not $name) {
            $status.ForeColor = $C.Err
            $status.Text = 'Укажите логин'
            return
        }
        $role = if ($admin.Checked) { 'администратор' } else { 'обычный пользователь' }
        $pwdNote = if ($pass.Text) { 'с паролем' } else { 'без пароля' }
        $status.ForeColor = $C.Ok
        $status.Text = "Пользователь $name создан ($role, $pwdNote).`r`nИМИТАЦИЯ: в системе ничего не создавалось."
        $btn.Text = 'Готово'
        $btn.BackColor = $C.Ok
        $done.Flag = $true
        $script:WadUserChoice = [pscustomobject]@{ Name = $name; Admin = [bool]$admin.Checked; HasPassword = [bool]$pass.Text }
        Write-Host "[WAD] показан результат создания пользователя: $name ($role, $pwdNote) — без реального создания" -ForegroundColor Cyan
    })

    $d.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $d.Close() } })
    [System.Windows.Forms.Application]::Run($d)
    $d.Dispose()
}

# =============================================================================
#  Сборка всего сценария
# =============================================================================
function Start-WadPrototype {
    param(
        [switch]$SkipIntro,
        [switch]$NoRebootSim
    )

    $script:WadExit = $false
    $script:WadUserChoice = $null

    Write-Host ''
    Write-Host '  WAD — тестовая сборка (прототип)' -ForegroundColor White
    Write-Host "  $($CFG.Badge)" -ForegroundColor Yellow
    Write-Host '  Выход в любой момент — Esc' -ForegroundColor DarkGray
    Write-Host ''

    $started = Get-Date

    # 1. Заставка с титрами (фуллскрин)
    if (-not $SkipIntro) {
        $ok = Show-WadTitles -Lines @('Здравствуйте', 'Вас приветствует WAD',
            'WAD настроит Windows для вас,', 'можете отдохнуть', 'Приступаем') -Hold $CFG.IntroHold
        if (-not $ok -or $script:WadExit) { Write-Host '[WAD] прототип прерван на заставке'; return }
    }

    # 2. Окно установки
    $res = Show-WadMainWindow
    if (-not $res) { Write-Host '[WAD] прототип прерван в окне установки'; return }

    # 3. Настоящий отчёт в «Документы»
    $finished = Get-Date
    try {
        $report = Save-WadReport -Started $started -Finished $finished
        Write-Host "[WAD] отчёт создан: $($report.Path) ($($report.Bytes) байт)" -ForegroundColor Green
        Start-Process -FilePath $report.Path
    } catch {
        Write-Host "[WAD] отчёт НЕ создан: $($_.Exception.Message)" -ForegroundColor Red
        $report = $null
    }

    # 4. Имитация перезагрузки
    if ($NoRebootSim) {
        Write-Host '[WAD] -NoRebootSim: пропускаем имитацию перезагрузки'
        return
    }
    Show-WadRebootScreen -Seconds $CFG.RebootSec

    # 4a. Ваш настоящий рабочий стол — пару секунд
    Write-Host "[WAD] показываю рабочий стол $($CFG.DesktopPause) с (наши окна скрыты)" -ForegroundColor Cyan
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Seconds $CFG.DesktopPause

    # 5. После входа: фуллскрин-фон + титры + окно пользователя
    $ok = Show-WadTitles -Lines @('Здравствуйте', 'Установка системы окончена.',
        'Теперь давайте создадим вам пользователя') -Hold $CFG.PostHold
    if (-not $ok -or $script:WadExit) { Write-Host '[WAD] прототип прерван после перезагрузки'; return }

    $reportPath = if ($report) { $report.Path } else { '' }
    Show-WadPostBoot -ReportPath $reportPath

    Write-Host ''
    Write-Host '  Готово. Что реально сделано:' -ForegroundColor White
    if ($report) { Write-Host "    · отчёт: $($report.Path)" -ForegroundColor Green }
    $lnk = Get-WadShortcutPath -DesktopPath (Get-WadPaths).Desktop
    if (Test-Path -LiteralPath $lnk) { Write-Host "    · ярлык: $lnk" -ForegroundColor Green }
    else { Write-Host '    · ярлык не сохраняли (кнопка «Сайт разработчика» → «Сохранить ярлык»)' -ForegroundColor DarkGray }
    Write-Host '    · пользователь НЕ создавался, ничего не скачивалось' -ForegroundColor DarkGray
    Write-Host ''
}

Start-WadPrototype -SkipIntro:$SkipIntro -NoRebootSim:$NoRebootSim
