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
#  Дальше — только Windows/WinForms. Все окна рисуются попиксельно (GDI+),
#  геометрия 1:1 с роликом (окно 1180x720, скругление 10, отступы 56) и
#  автоматически масштабируется под экран — DPI и автомасштаб WinForms
#  не могут сломать раскладку, потому что дочерних контролов с вёрсткой нет.
# =============================================================================
if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
    Write-Warning 'Прототип показывает окна и работает только в Windows. Запустите WAD-Zapusk.bat на Windows-машине.'
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
try {
    Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class WadDpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
    [WadDpi]::SetProcessDPIAware() | Out-Null
} catch { Write-Verbose 'DPI-режим не выставлен — не критично' }

# --- дизайн-пространство ролика ------------------------------------------------
$script:DW = 1180; $script:DH = 720        # как в ролике
$script:K  = 1.0; $script:OX = 0; $script:OY = 0
$script:Hits = @()                          # кликабельные зоны текущего окна
$script:WadExit = $false
$script:WadUserChoice = $null
$script:WadTray = $null

$C = @{
    Text   = [System.Drawing.Color]::FromArgb(26, 28, 32)
    Text2  = [System.Drawing.Color]::FromArgb(96, 104, 116)
    Text3  = [System.Drawing.Color]::FromArgb(138, 146, 160)
    Accent = [System.Drawing.Color]::FromArgb(0, 103, 192)
    Accent2= [System.Drawing.Color]::FromArgb(116, 92, 231)
    Ok     = [System.Drawing.Color]::FromArgb(16, 124, 65)
    Err    = [System.Drawing.Color]::FromArgb(196, 43, 28)
    Warn   = [System.Drawing.Color]::FromArgb(157, 93, 0)
    Line   = [System.Drawing.Color]::FromArgb(216, 220, 228)
    Card   = [System.Drawing.Color]::FromArgb(252, 253, 255)
    Track  = [System.Drawing.Color]::FromArgb(230, 233, 239)
    White  = [System.Drawing.Color]::White
}

$Screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

function SX($v) { [int]($script:OX + $v * $script:K) }
function SY($v) { [int]($script:OY + $v * $script:K) }
function SS($v) { [math]::Max(1, [int]($v * $script:K)) }

function New-WadFont([single]$size, [string]$style) {
    New-Object System.Drawing.Font('Segoe UI', [single]($size * $script:K), [System.Drawing.FontStyle]::Parse($style))
}

function Draw-RR {
    param($g, $x, $y, $w, $h, $r, $fill, $outline, [single]$ow = 1)
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddArc($x, $y, $r * 2, $r * 2, 180, 90)
    $p.AddArc($x + $w - $r * 2, $y, $r * 2, $r * 2, 270, 90)
    $p.AddArc($x + $w - $r * 2, $y + $h - $r * 2, $r * 2, $r * 2, 0, 90)
    $p.AddArc($x, $y + $h - $r * 2, $r * 2, $r * 2, 90, 90)
    $p.CloseFigure()
    if ($fill)    { $b = New-Object System.Drawing.SolidBrush($fill); $g.FillPath($b, $p); $b.Dispose() }
    if ($outline) { $pen = New-Object System.Drawing.Pen($outline, $ow); $g.DrawPath($pen, $p); $pen.Dispose() }
    $p.Dispose()
}

function Draw-Text {
    param($g, $text, $x, $y, $w, $h, [single]$size, [string]$style, $color, [string]$halign = 'left', [string]$valign = 'top')
    $f = New-WadFont $size $style
    $b = New-Object System.Drawing.SolidBrush($color)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = switch ($halign) { 'center' { 'Center' } 'right' { 'Far' } default { 'Near' } }
    $sf.LineAlignment = switch ($valign) { 'center' { 'Center' } default { 'Near' } }
    $rect = [System.Drawing.RectangleF]::new([single]$x, [single]$y, [single]$w, [single]$h)
    $g.DrawString($text, $f, $b, $rect, $sf)
    $f.Dispose(); $b.Dispose(); $sf.Dispose()
}

function Measure-W($g, $text, [single]$size, [string]$style) {
    $f = New-WadFont $size $style
    $w = $g.MeasureString($text, $f).Width
    $f.Dispose()
    return $w
}

function Add-Hit($id, $x, $y, $w, $h) {
    $script:Hits += [pscustomobject]@{ Id = $id; Rect = [System.Drawing.Rectangle]::new([int]$x, [int]$y, [int]$w, [int]$h) }
}

function Get-Hit($pt) {
    for ($i = $script:Hits.Count - 1; $i -ge 0; $i--) {
        if ($script:Hits[$i].Rect.Contains($pt)) { return $script:Hits[$i].Id }
    }
    return $null
}

function Draw-StatusIcon {
    param($g, $cx, $cy, [string]$kind, [int]$spin, [double]$e = 1)
    $r = $(SS (11))
    switch ($kind) {
        'wait' {
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb([int](120 * $e), 138, 146, 160), [single]($(SS (2))))
            $g.DrawEllipse($pen, $cx - $r, $cy - $r, $r * 2, $r * 2); $pen.Dispose()
        }
        'run' {
            for ($j = 0; $j -lt 8; $j++) {
                $ang = ($spin * 0.35) + $j * ([math]::PI / 4)
                $al = [int]((50 + 200 * ($j / 8)) * $e)
                $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($al, $C.Accent), [single]($(SS (2))))
                $x1 = $cx + ($(SS (6))) * [math]::Cos($ang); $y1 = $cy + ($(SS (6))) * [math]::Sin($ang)
                $x2 = $cx + ($(SS (11))) * [math]::Cos($ang); $y2 = $cy + ($(SS (11))) * [math]::Sin($ang)
                $g.DrawLine($pen, [single]$x1, [single]$y1, [single]$x2, [single]$y2)
                $pen.Dispose()
            }
        }
        'ok' {
            $b = New-Object System.Drawing.SolidBrush((ColA $C.Ok $e)); $g.FillEllipse($b, $cx - $r, $cy - $r, $r * 2, $r * 2); $b.Dispose()
            $pen = New-Object System.Drawing.Pen((ColA $C.White $e), [single]($(SS (2))))
            $g.DrawLines($pen, @(
                [System.Drawing.Point]::new($cx - $(SS (5)), $cy),
                [System.Drawing.Point]::new($cx - $(SS (1)), $cy + $(SS (4))),
                [System.Drawing.Point]::new($cx + $(SS (6)), $cy - $(SS (5)))))
            $pen.Dispose()
        }
        'warn' {
            $b = New-Object System.Drawing.SolidBrush((ColA $C.Err $e)); $g.FillEllipse($b, $cx - $r, $cy - $r, $r * 2, $r * 2); $b.Dispose()
            $pen = New-Object System.Drawing.Pen((ColA $C.White $e), [single]($(SS (2))))
            $g.DrawLine($pen, $cx - $(SS (4)), $cy - $(SS (4)), $cx + $(SS (4)), $cy + $(SS (4)))
            $g.DrawLine($pen, $cx + $(SS (4)), $cy - $(SS (4)), $cx - $(SS (4)), $cy + $(SS (4)))
            $pen.Dispose()
        }
    }
}

function ease_io($x) { $x = [math]::Max(0.0, [math]::Min(1.0, $x)); return 3 * $x * $x - 2 * $x * $x * $x }
function ease_out($x) { $x = [math]::Max(0.0, [math]::Min(1.0, $x)); return 1 - (1 - $x) * (1 - $x) * (1 - $x) }
function Get-TitleAlpha {
    # прозрачность и вертикальный «доезд» строки: вошла снизу, постояла, ушла выше
    param([double]$t, [double]$t0, [double]$t1, [double]$t2, [double]$t3)
    if ($t -le $t0 -or $t -ge $t3) { return @(0.0, 0.0) }
    if ($t -lt $t1) { $k = ease_io (($t - $t0) / ($t1 - $t0)); return @($k, (1 - $k) * 34) }
    if ($t -le $t2) { return @(1.0, 0.0) }
    $k = ease_io (($t - $t2) / ($t3 - $t2)); return @(1 - $k, -$k * 24)
}
function ColA($col, [double]$a) {
    [System.Drawing.Color]::FromArgb([int][math]::Max(0, [math]::Min(255, 255 * $a)), $col)
}

function Get-WadWallpaper {
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

function New-WadForm {
    param([bool]$Fullscreen = $false, [int]$W = 0, [int]$H = 0)
    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'
    $f.ShowInTaskbar = $false
    $f.TopMost = $true
    $f.KeyPreview = $true
    $f.BackColor = $C.Card
    if ($Fullscreen) {
        $f.StartPosition = 'Manual'
        $f.Bounds = $Screen
    } else {
        $f.StartPosition = 'CenterScreen'
        $f.ClientSize = New-Object System.Drawing.Size($W, $H)
    }
    $p = $f.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic')
    if ($p) { $p.SetValue($f, $true, $null) }
    $f.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $script:WadExit = $true; $f.Close() } })
    return $f
}

function Show-WadTitles {
    param([Parameter(Mandatory)][string[]]$Lines, [double]$Hold, [bool]$WithBlack = $true)

    $form = New-WadForm -Fullscreen $true
    $wall = Get-WadWallpaper
    if ($wall) { $form.BackgroundImage = $wall; $form.BackgroundImageLayout = 'Stretch' }
    else { $form.BackColor = [System.Drawing.Color]::FromArgb(240, 245, 252) }

    $script:K = [math]::Min($Screen.Width / 1920.0, $Screen.Height / 1080.0)
    if ($script:K -le 0) { $script:K = 1 }

    $fade = $CFG.IntroFade
    $seg = $fade * 2 + $Hold
    $gap = $CFG.IntroGap
    $blackFade = 0.85
    $starts = @()
    $tcur = 0.4
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $starts += $tcur
        $tcur += $seg + $gap
        if ($i -eq 0 -and $WithBlack) { $tcur += $blackFade / 2 }
    }
    $total = $starts[$Lines.Count - 1] + $seg + 0.3
    $blackEnd = $starts[0] + $seg

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $CFG.TickMs
    $timer.Add_Tick({ $form.Invalidate(); if ($sw.Elapsed.TotalSeconds -gt $total) { $timer.Stop(); $form.Close() } })

    $form.Add_Paint({
        $g = $_.Graphics
        $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
        $t = $sw.Elapsed.TotalSeconds

        # чёрный фон, перетекающий в наш (только в первом интро)
        if ($WithBlack) {
            $b = 0.0
            if ($t -le $blackEnd) { $b = 1.0 }
            elseif ($t -lt $blackEnd + $blackFade) { $b = 1.0 - $(ease_io (($t - $blackEnd) / $blackFade)) }
            if ($b -gt 0.001) {
                $bb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb([int](255 * $b), 0, 0, 0))
                $g.FillRectangle($bb, 0, 0, $form.Width, $form.Height); $bb.Dispose()
            }
            $bk = $b
        } else { $bk = 0.0 }

        for ($k = 0; $k -lt $Lines.Count; $k++) {
            $t0 = $starts[$k]
            $ar = Get-TitleAlpha $t $t0 ($t0 + $fade) ($t0 + $fade + $Hold) ($t0 + $seg)
            $a = $ar[0]; $rise = $ar[1]
            if ($a -le 0.01) { continue }

            $isGo = ($Lines[$k] -eq 'Приступаем')
            $f = New-WadFont 84 'Bold'
            $sz = $g.MeasureString($Lines[$k], $f)
            $w = [int]$sz.Width + 40; $h = [int]$sz.Height + 20
            $x = [int](($form.Width - $w) / 2)
            $y = [int](($form.Height - $h) / 2 + $rise * $script:K)

            if ($isGo) {
                # градиентный текст + растущее подчёркивание, как в ролике
                $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                    [System.Drawing.Rectangle]::new($x, $y, $w, $h), (ColA $C.Accent $a), (ColA $C.Accent2 $a), 0.0)
                $rect = [System.Drawing.RectangleF]::new($x, $y, $w, $h)
                $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
                $g.DrawString($Lines[$k], $f, $gb, $rect, $sf)
                $gb.Dispose(); $sf.Dispose()
                $sweep = ease_io ([math]::Max(0.0, [math]::Min(1.0, ($t - ($t0 + 0.35)) / 1.0)))
                $uw = $w * 0.9 * $sweep
                $pen = New-Object System.Drawing.Pen((ColA $C.Accent ($a * 0.8)), [single]$(SS 3))
                $g.DrawLine($pen, [single]($x + ($w - $uw) / 2), [single]($y + $h * 0.86), [single]($x + ($w - $uw) / 2 + $uw), [single]($y + $h * 0.86))
                $pen.Dispose()
            } else {
                # цвет: белый на чёрном, тёмный на нашем фоне; плавный микс по мере ухода чёрного
                $white = [System.Drawing.Color]::FromArgb([int](255 * $a * $bk), 255, 255, 255)
                $inkA = [int](255 * $a * (1 - $bk))
                $ink = [System.Drawing.Color]::FromArgb($inkA, $C.Text)
                # мягкая белая подсветка под тёмным текстом — как в ролике
                if ((1 - $bk) -gt 0.05) {
                    $gl = [System.Drawing.Color]::FromArgb([int](150 * $a * (1 - $bk)), 255, 255, 255)
                    Draw-Text $g $Lines[$k] ($x + $(SS 2)) ($y + $(SS 3)) $w $h 84 'Bold' $gl 'center' 'center'
                }
                if ($bk -gt 0.01) { Draw-Text $g $Lines[$k] $x $y $w $h 84 'Bold' $white 'center' 'center' }
                if ($inkA -gt 2)  { Draw-Text $g $Lines[$k] $x $y $w $h 84 'Bold' $ink 'center' 'center' }
            }
            $f.Dispose()
        }
    })

    $timer.Start()
    [System.Windows.Forms.Application]::Run($form)
    $timer.Dispose(); $form.Dispose()
    return (-not $script:WadExit)
}

function Show-WadRebootScreen([double]$Seconds) {
    $form = New-WadForm -Fullscreen $true
    $form.BackColor = [System.Drawing.Color]::Black
    $form.Add_Paint({
        $g = $_.Graphics
        $g.TextRenderingHint = 'AntiAliasGridFit'
        Draw-Text $g 'Перезагрузка…' 0 ([int]($form.Height / 2 - 40)) $form.Width 60 22 'Regular' $C.White 'center' 'center'
        Draw-Text $g 'это имитация — компьютер не перезагружается' 0 ([int]($form.Height / 2 + 30)) $form.Width 30 11 'Regular' ([System.Drawing.Color]::FromArgb(140, 140, 150)) 'center' 'center'
    })
    $t = New-Object System.Windows.Forms.Timer
    $t.Interval = [int]($Seconds * 1000)
    $t.Add_Tick({ $t.Stop(); $form.Close() })
    $t.Start()
    [System.Windows.Forms.Application]::Run($form)
    $t.Dispose(); $form.Dispose()
}

function Draw-MainWindow {
    param($g, $S)
    $script:Hits = @()
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
    $DW = $script:DW; $DH = $script:DH
    $PAD = 56
    $te = $S.T
    $appear = ease_out ([math]::Min(1.0, $te / 0.75))

    Draw-RR $g 0 0 $DW $DH 10 $C.Card $null
    Draw-RR $g 0.5 0.5 ($DW - 1) ($DH - 1) 10 $null ([System.Drawing.Color]::FromArgb(40, 0, 0, 0)) 1

    # шапка: знак WAD + раздел
    $ix = $PAD; $iy = 14; $isz = 26
    $rect = [System.Drawing.Rectangle]::new($(SX $ix), $(SY $iy), $(SS $isz), $(SS $isz))
    $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $C.Accent, $C.Accent2, 45.0)
    $pp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $rr = $(SS 7)
    $pp.AddArc($rect.X, $rect.Y, $rr * 2, $rr * 2, 180, 90)
    $pp.AddArc($rect.Right - $rr * 2, $rect.Y, $rr * 2, $rr * 2, 270, 90)
    $pp.AddArc($rect.Right - $rr * 2, $rect.Bottom - $rr * 2, $rr * 2, $rr * 2, 0, 90)
    $pp.AddArc($rect.X, $rect.Bottom - $rr * 2, $rr * 2, $rr * 2, 90, 90)
    $pp.CloseFigure()
    $g.FillPath($gb, $pp)
    $gb.Dispose(); $pp.Dispose()
    Draw-Text $g 'W' $ix $iy $isz $isz 14 'Bold' (ColA $C.White $appear) 'center' 'center'
    Draw-Text $g 'WAD' ($ix + $isz + 12) ($iy + 2) 60 24 16 'Bold' (ColA $C.Text $appear) 'left' 'center'
    Draw-Text $g '· установка Windows' ($ix + $isz + 12 + 44) ($iy + 3) 220 24 13 'Regular' (ColA $C.Text3 $appear) 'left' 'center'

    # управление: свернуть и закрыть (справа), сайт разработчика
    $cx = $DW - $PAD
    Add-Hit 'close' ($(SX ($cx - 30))) ($(SY (8))) ($(SS (30))) ($(SS (34)))
    Add-Hit 'min'   ($(SX ($cx - 68))) ($(SY (8))) ($(SS (30))) ($(SS (34)))
    Draw-Text $g '✕' ($cx - 30) 8 30 34 13 'Regular' (ColA $C.Text2 $appear) 'center' 'center'
    Draw-Text $g '—' ($cx - 68) 8 30 34 13 'Regular' (ColA $C.Text2 $appear) 'center' 'center'

    $sbw = (Measure-W $g 'Сайт разработчика' 13 'Bold') + 46
    $sbx = $cx - 100 - $sbw
    Draw-RR $g $sbx 10 $sbw 32 16 ([System.Drawing.Color]::FromArgb([int](26 * $appear), 0, 103, 192)) ([System.Drawing.Color]::FromArgb([int](90 * $appear), 0, 103, 192)) 1
    $gx = $sbx + 17
    $gb2 = New-Object System.Drawing.SolidBrush((ColA $C.Accent $appear))
    $g.FillEllipse($gb2, $(SX $gx) - $(SS 6), $(SY 26) - $(SS 6), $(SS 12), $(SS 12)); $gb2.Dispose()
    Draw-Text $g 'Сайт разработчика' ($sbx + 32) 10 $sbw 32 13 'Bold' (ColA $C.Accent $appear) 'left' 'center'
    Add-Hit 'site' ($(SX ($sbx))) ($(SY (10))) ($(SS ($sbw))) ($(SS (32)))

    # заголовок и бейдж
    Draw-Text $g 'Менеджер автоматической настройки' $PAD 62 ($DW - 2 * $PAD) 40 24 'Bold' (ColA $C.Text $appear)
    Draw-Text $g $CFG.Badge $PAD 104 ($DW - 2 * $PAD) 22 11 'Bold' (ColA $C.Warn $appear)

    # 4 категории
    $ry = 148; $rh = 74
    $states = Get-WadRowStatus -Elapsed $S.Elapsed -Total $CFG.InstallSec
    for ($i = 0; $i -lt $states.Count; $i++) {
        $s = $states[$i]
        $e = ease_out ([math]::Max(0.0, [math]::Min(1.0, ($te - 0.10 - $i * 0.06) / 0.5)))
        if ($e -le 0.01) { continue }
        $yy = $ry + $i * ($rh + 12)
        Draw-RR $g $PAD $yy ($DW - 2 * $PAD) $rh 10 ([System.Drawing.Color]::FromArgb([int](150 * $e), 255, 255, 255)) ([System.Drawing.Color]::FromArgb([int](16 * $e), 0, 0, 0)) 1
        $icx = $PAD + 34; $icy = $yy + $rh / 2
        Draw-StatusIcon $g ($(SX ($icx))) ($(SY ($icy))) $s.State $S.Spin $e
        Draw-Text $g $WadRows[$i].Name ($PAD + 66) ($yy + 14) ($DW - 2 * $PAD - 160) 26 15 'Bold' (ColA $C.Text $e)
        $subc = switch ($s.State) { 'ok' { $C.Ok } 'warn' { $C.Err } 'run' { $C.Text3 } default { $C.Text3 } }
        $subt = switch ($s.State) { 'ok' { 'готово' } 'warn' { 'пропущено / ошибка' } 'run' { 'выполняется…' } default { 'ожидание' } }
        Draw-Text $g $subt ($PAD + 66) ($yy + 42) ($DW - 2 * $PAD - 160) 20 12 'Regular' (ColA $subc $e)
        if ($s.State -in @('ok', 'warn')) {
            $dur = $s.End - $s.Start
            $tm = if ($s.State -eq 'warn') { '—' } else { '[{0:00}:{1:00}]' -f [math]::Floor($dur / 60), [math]::Floor($dur % 60) }
            Draw-Text $g $tm ($DW - $PAD - 90) ($yy + $rh / 2 - 10) 90 20 12 'Regular' (ColA $C.Text3 $e) 'right' 'center'
        }
    }

    # нижний бар
    $by = $DH - $PAD - 46
    $barw = $DW - $PAD - 190 - $PAD
    if ($S.Phase -eq 'countdown') {
        $left = $S.CountLeft
        $cap = if ($left -gt 0) { 'Перезагрузка через {0} сек' -f $left } else { 'Перезагрузка…' }
        Draw-Text $g $cap $PAD ($by - 34) 400 26 15 'Bold' (ColA $C.Text $appear)
        Draw-Text $g 'можно ничего не нажимать' ($DW - $PAD - 200) ($by - 30) 190 22 11.5 'Regular' (ColA $C.Text3 $appear) 'right' 'center'
        $k = 1.0 - ($S.CountLeft / $CFG.CountdownSec)
    } else {
        Draw-Text $g 'Установка…' $PAD ($by - 34) 300 26 15 'Bold' (ColA $C.Text $appear)
        Draw-Text $g ('{0}%' -f [int]($S.Progress * 100)) ($DW - $PAD - 200) ($by - 46) 190 40 26 'Bold' (ColA $C.Accent $appear) 'right' 'center'
        $k = $S.Progress
    }
    Draw-RR $g $PAD $by $barw 8 4 (ColA $C.Track $appear) $null
    $fill = [math]::Max($(SS (6)), [int]($barw * $k))
    if ($fill -gt 2) {
        $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            [System.Drawing.Rectangle]::new($(SX ($PAD)), $(SY ($by)), [int]($fill * $script:K), $(SS (8))), $C.Accent, $C.Accent2, 0.0)
        Draw-RR $g $PAD $by ($fill / $script:K) 8 4 $null $null
        $g.FillRectangle($gb, $(SX ($PAD)), $(SY ($by)), [int]($fill * $script:K), $(SS (8))); $gb.Dispose()
        $sx = [int](($S.Spin * 7) % ($barw + 120)) - 60
        $shine = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb([int](70 * $appear), 255, 255, 255))
        $g.FillRectangle($shine, $(SX ($PAD + $sx)), $(SY ($by)), $(SS (60)), $(SS (8))); $shine.Dispose()
    }

    # кнопка «Свернуть в фон»
    $lb = 'Свернуть в фон'
    $bw = (Measure-W $g $lb 13 'Bold') + 44
    $bx = $DW - $PAD - $bw
    Draw-RR $g $bx ($by - 8) $bw 42 8 (ColA $C.Accent $appear) $null
    Draw-Text $g $lb $bx ($by - 8) $bw 42 13 'Bold' (ColA $C.White $appear) 'center' 'center'
    Add-Hit 'collapse' ($(SX ($bx))) ($(SY ($by - 8))) ($(SS ($bw))) ($(SS (42)))
}

function Show-WadMainWindow {
    $k = [math]::Min(($Screen.Width - 24) / $script:DW, ($Screen.Height - 24) / $script:DH, 1.0)
    if ($k -le 0.2) { $k = 0.2 }
    $script:K = $k
    $cw = [int]($script:DW * $k); $ch = [int]($script:DH * $k)

    $form = New-WadForm -W $cw -H $ch
    $form.Add_Shown({ $script:BaseTop = $form.Top; $p = New-Object System.Drawing.Drawing2D.GraphicsPath; $r = $(SS (10))
        $w = $form.Width; $h = $form.Height
        $p.AddArc(0, 0, $r * 2, $r * 2, 180, 90); $p.AddArc($w - $r * 2, 0, $r * 2, $r * 2, 270, 90)
        $p.AddArc($w - $r * 2, $h - $r * 2, $r * 2, $r * 2, 0, 90); $p.AddArc(0, $h - $r * 2, $r * 2, $r * 2, 90, 90)
        $p.CloseFigure(); $form.Region = New-Object System.Drawing.Region($p) })

    $st = @{
        Started = Get-Date; Elapsed = 0.0; Progress = 0.0
        Phase = 'install'; CountLeft = [int]$CFG.CountdownSec
        Spin = 0; T = 0.0; Finished = $false; Aborted = $false
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $form.Add_Paint({ Draw-MainWindow $_.Graphics $st })

    $form.Add_MouseClick({
        $id = Get-Hit $_.Location
        if (-not $id) { return }
        switch ($id) {
            'site' { Show-WadSiteDialog }
            'min'  { $form.WindowState = 'Minimized' }
            'collapse' { $form.WindowState = 'Minimized' }
            'close' {
                $r = [System.Windows.Forms.MessageBox]::Show('Прервать прототип WAD?', 'WAD',
                    [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
                if ($r -eq [System.Windows.Forms.DialogResult]::Yes) { $st.Aborted = $true; $form.Close() }
            }
        }
    })

    $form.Add_MouseMove({
        $id = Get-Hit $_.Location
        $form.Cursor = if ($id) { [System.Windows.Forms.Cursors]::Hand } else { [System.Windows.Forms.Cursors]::Default }
    })

    $form.Add_Resize({
        if ($form.WindowState -eq 'Minimized' -and -not $script:WadTray) {
            try {
                $script:WadTray = New-Object System.Windows.Forms.NotifyIcon
                $script:WadTray.Icon = [System.Drawing.SystemIcons]::Application
                $script:WadTray.Text = 'WAD работает в фоне (прототип)'
                $script:WadTray.Visible = $true
                $script:WadTray.Add_Click({ $form.WindowState = 'Normal'; $form.Activate() })
            } catch { Write-Verbose 'значок в трее не создан — не критично' }
        }
        if ($form.WindowState -eq 'Normal' -and $script:WadTray) { $script:WadTray.Visible = $false; $script:WadTray.Dispose(); $script:WadTray = $null }
    })

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $CFG.TickMs
    $lastCd = [int]$CFG.CountdownSec
    $timer.Add_Tick({
        $st.Elapsed += ($CFG.TickMs / 1000.0)
        $st.Spin++
        $st.T = $sw.Elapsed.TotalSeconds
        $ap = ease_out ([math]::Min(1.0, $st.T / 0.75))
        if ($ap -lt 1) { $form.Opacity = [math]::Max(0.05, $ap); if ($script:BaseTop) { $form.Top = [int]($script:BaseTop + (1 - $ap) * 20) } } elseif ($form.Opacity -lt 1) { $form.Opacity = 1.0; $form.Top = [int]$script:BaseTop }
        if ($st.Phase -eq 'install') {
            $st.Progress = (Get-WadProgress -Elapsed $st.Elapsed -Total $CFG.InstallSec) / 100.0
            if ($st.Elapsed -ge $CFG.InstallSec) {
                $st.Phase = 'countdown'; $st.CountLeft = [int]$CFG.CountdownSec
                Write-Host '[WAD] установка (имитация) завершена — пошёл отсчёт до перезагрузки' -ForegroundColor Cyan
                if ($form.WindowState -eq 'Minimized') { $form.WindowState = 'Normal'; $form.Activate() }
            }
        } else {
            $left = [int][math]::Ceiling($CFG.CountdownSec - ($st.Elapsed - $CFG.InstallSec))
            if ($left -lt 0) { $left = 0 }
            if ($left -ne $lastCd) { $lastCd = $left; $st.CountLeft = $left }
            if ($left -le 0) { $timer.Stop(); $st.Finished = $true; $form.Close() }
        }
        $form.Invalidate()
    })

    $form.Add_FormClosed({ $timer.Stop(); $timer.Dispose(); if ($script:WadTray) { $script:WadTray.Visible = $false; $script:WadTray.Dispose(); $script:WadTray = $null } })

    Write-Host '[WAD] окно установки — пошёл имитационный прогон (ничего не качается)' -ForegroundColor Cyan
    $timer.Start()
    [System.Windows.Forms.Application]::Run($form)
    $form.Dispose()
    if ($st.Aborted) { return $null }
    return $st
}

function Show-WadSiteDialog {
    $script:K = 1.0
    $form = New-WadForm -W 480 -H 260
    $res = @{ Saved = $null }   # $null = ещё не жали

    $form.Add_Paint({
        $g = $_.Graphics
        $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
        $script:Hits = @()
        Draw-RR $g 0 0 480 260 14 $C.White $null
        Draw-Text $g 'Сайт разработчика' 26 22 400 30 17 'Bold' $C.Text
        Draw-Text $g 'Репозиторий проекта на GitHub' 26 60 400 24 12 'Regular' $C.Text2
        Draw-Text $g $CFG.RepoUrl 26 84 430 22 11 'Regular' $C.Text3

        $bw = (Measure-W $g 'Сохранить ярлык' 13 'Bold') + 40
        Draw-RR $g 26 132 $bw 42 8 $C.Accent $null
        Draw-Text $g 'Сохранить ярлык' 26 132 $bw 42 13 'Bold' $C.White 'center' 'center'
        Add-Hit 'save' 26 132 $bw 42

        $cw2 = (Measure-W $g 'Закрыть' 12 'Regular') + 34
        Draw-RR $g (480 - 26 - $cw2) 132 $cw2 42 8 ([System.Drawing.Color]::FromArgb(240, 242, 246)) $null
        Draw-Text $g 'Закрыть' (480 - 26 - $cw2) 132 $cw2 42 12 'Regular' $C.Text2 'center' 'center'
        Add-Hit 'close' (480 - 26 - $cw2) 132 $cw2 42

        if ($null -ne $res.Saved) {
            if ($res.Saved.Success) {
                Draw-Text $g "Ярлык сохранён на рабочий стол:" 26 188 430 20 11 'Regular' $C.Ok
                Draw-Text $g $res.Saved.Path 26 208 430 20 10.5 'Regular' $C.Ok
            } else {
                Draw-Text $g "Не удалось сохранить ярлык: $($res.Saved.Error)" 26 188 430 40 11 'Regular' $C.Err
            }
        } else {
            Draw-Text $g 'Сохранит ярлык на рабочий стол' 26 188 430 20 11 'Regular' $C.Text3
        }
    })

    $form.Add_MouseClick({
        $id = Get-Hit $_.Location
        if ($id -eq 'save') {
            $res.Saved = Save-WadShortcut
            if ($res.Saved.Success) { Write-Host "[WAD] ярлык сохранён: $($res.Saved.Path)" -ForegroundColor Green }
            else { Write-Host "[WAD] ярлык НЕ сохранён: $($res.Saved.Error)" -ForegroundColor Red }
            $form.Invalidate()
        } elseif ($id -eq 'close') { $form.Close() }
    })
    $form.Add_MouseMove({ $form.Cursor = if (Get-Hit $_.Location) { [System.Windows.Forms.Cursors]::Hand } else { [System.Windows.Forms.Cursors]::Default } })

    [System.Windows.Forms.Application]::Run($form)
    $form.Dispose()
}

function Show-WadUserDialog {
    $script:K = 1.0
    $form = New-WadForm -W 620 -H 470
    $form.BackColor = $C.Card

    $login = New-Object System.Windows.Forms.TextBox
    $login.Location = New-Object System.Drawing.Point(30, 118); $login.Size = New-Object System.Drawing.Size(255, 30)
    $login.Font = New-Object System.Drawing.Font('Segoe UI', 11); $login.Text = 'User'
    $form.Controls.Add($login)
    $pass = New-Object System.Windows.Forms.TextBox
    $pass.Location = New-Object System.Drawing.Point(315, 118); $pass.Size = New-Object System.Drawing.Size(255, 30)
    $pass.Font = New-Object System.Drawing.Font('Segoe UI', 11); $pass.UseSystemPasswordChar = $true
    $form.Controls.Add($pass)

    $st = @{ Msg = 'Прототип: пользователь не создаётся — только показ результата.'; Color = $C.Text3; Done = $false }

    $form.Add_Paint({
        $g = $_.Graphics
        $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
        $script:Hits = @()
        Draw-Text $g 'создание пользователя' 20 12 400 22 11 'Regular' $C.Text2
        Draw-Text $g 'Теперь давайте создадим вам пользователя' 30 42 560 30 16 'Bold' $C.Text
        Draw-Text $g 'Логин обязателен, пароль — по желанию: пусто значит без пароля' 30 78 560 22 11 'Regular' $C.Text2
        Draw-Text $g 'Логин' 30 96 200 20 11 'Regular' $C.Text2
        Draw-Text $g 'Пароль' 315 96 200 20 11 'Regular' $C.Text2
        Draw-Text $g 'необязательно' 315 150 200 18 10 'Regular' $C.Text3
        Draw-Text $g 'Дополнительно' 30 186 300 22 12 'Bold' $C.Text

        # чекбокс «админ»
        $cbx = 30; $cby = 216
        Draw-RR $g $cbx $cby 20 20 5 $C.Accent $null
        $pen = New-Object System.Drawing.Pen($C.White, 2)
        $g.DrawLines($pen, @([System.Drawing.Point]::new($cbx + 5, $cby + 10), [System.Drawing.Point]::new($cbx + 9, $cby + 14), [System.Drawing.Point]::new($cbx + 15, $cby + 6)))
        $pen.Dispose()
        Draw-Text $g 'Пользователь создаётся как администратор' ($cbx + 30) ($cby - 1) 400 24 12 'Regular' $C.Text
        Add-Hit 'admin' $cbx ($cby - 4) 430 28
        Draw-Text $g 'снимите галочку — будет обычный пользователь с ограниченными правами' 30 246 540 18 10 'Regular' $C.Text3

        Draw-Text $g $st.Msg 30 288 540 70 11 'Regular' $st.Color

        $bl = if ($st.Done) { 'Готово' } else { 'Создать и продолжить' }
        $bc = if ($st.Done) { $C.Ok } else { $C.Accent }
        $bw = (Measure-W $g $bl 13 'Bold') + 46
        $bx = 620 - 30 - $bw
        Draw-RR $g $bx 366 $bw 46 8 $bc $null
        Draw-Text $g $bl $bx 366 $bw 46 13 'Bold' $C.White 'center' 'center'
        Add-Hit 'create' $bx 366 $bw 46
    })

    $form.Add_MouseClick({
        $id = Get-Hit $_.Location
        if (-not $id) { return }
        if ($id -eq 'admin') { $script:WadAdmin = -not $script:WadAdmin; $form.Invalidate(); return }
        if ($id -eq 'create') {
            if ($st.Done) { $form.Close(); return }
            $name = $login.Text.Trim()
            if (-not $name) { $st.Color = $C.Err; $st.Msg = 'Укажите логин'; $form.Invalidate(); return }
            $role = if ($script:WadAdmin) { 'администратор' } else { 'обычный пользователь' }
            $pwdNote = if ($pass.Text) { 'с паролем' } else { 'без пароля' }
            $st.Color = $C.Ok
            $st.Msg = "Пользователь $name создан ($role, $pwdNote). ИМИТАЦИЯ: в системе ничего не создавалось."
            $st.Done = $true
            $script:WadUserChoice = [pscustomobject]@{ Name = $name; Admin = [bool]$script:WadAdmin; HasPassword = [bool]$pass.Text }
            Write-Host "[WAD] показан результат создания пользователя: $name ($role, $pwdNote) — без реального создания" -ForegroundColor Cyan
            $form.Invalidate()
        }
    })
    $form.Add_MouseMove({ $form.Cursor = if (Get-Hit $_.Location) { [System.Windows.Forms.Cursors]::Hand } else { [System.Windows.Forms.Cursors]::Default } })

    $script:WadAdmin = $true
    [System.Windows.Forms.Application]::Run($form)
    $form.Dispose()
}

function Show-WadPostBoot([string]$ReportPath = '') {
    $bg = New-WadForm -Fullscreen $true
    $wall = Get-WadWallpaper
    if ($wall) { $bg.BackgroundImage = $wall; $bg.BackgroundImageLayout = 'Stretch' }
    $bg.Add_Paint({
        $g = $_.Graphics
        $g.TextRenderingHint = 'AntiAliasGridFit'
        $script:K = [math]::Min($bg.Width / 1920.0, $bg.Height / 1080.0); if ($script:K -le 0) { $script:K = 1 }
        Draw-Text $g $CFG.Badge 24 20 700 20 11 'Bold' $C.Warn
        if ($ReportPath) { Draw-Text $g "Отчёт: $ReportPath" 24 44 900 18 10 'Regular' $C.Text2 }
    })
    $shown = $false
    $bg.Add_Shown({ if ($shown) { return }; $shown = $true; Show-WadUserDialog; $bg.Close() })
    [System.Windows.Forms.Application]::Run($bg)
    $bg.Dispose()
}

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

    if (-not $SkipIntro) {
        $ok = Show-WadTitles -Lines @('Здравствуйте', 'Вас приветствует WAD',
            "WAD настроит Windows для вас,`nможете отдохнуть", 'Приступаем') -Hold $CFG.IntroHold
        if (-not $ok -or $script:WadExit) { Write-Host '[WAD] прототип прерван на заставке'; return }
    }

    $res = Show-WadMainWindow
    if (-not $res) { Write-Host '[WAD] прототип прерван в окне установки'; return }

    $finished = Get-Date
    $report = $null
    try {
        $report = Save-WadReport -Started $started -Finished $finished
        Write-Host "[WAD] отчёт создан: $($report.Path) ($($report.Bytes) байт)" -ForegroundColor Green
        Start-Process -FilePath $report.Path
    } catch {
        Write-Host "[WAD] отчёт НЕ создан: $($_.Exception.Message)" -ForegroundColor Red
    }

    if ($NoRebootSim) { Write-Host '[WAD] -NoRebootSim: пропускаем имитацию перезагрузки'; return }
    Show-WadRebootScreen -Seconds $CFG.RebootSec

    Write-Host "[WAD] показываю рабочий стол $($CFG.DesktopPause) с (наши окна скрыты)" -ForegroundColor Cyan
    Start-Sleep -Seconds $CFG.DesktopPause

    $ok = Show-WadTitles -Lines @('Здравствуйте', 'Установка системы окончена.',
        'Теперь давайте создадим вам пользователя') -Hold $CFG.PostHold -WithBlack:$false
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
