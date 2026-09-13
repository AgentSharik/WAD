# ==============================================================================
# Файл: manager-preview.ps1
# Назначение: ПРЕДПРОСМОТР нового интерфейса менеджера WAD.
#
# Это не рабочий менеджер, а окно-макет, собранное настоящим кодом WinForms:
# так автор видит будущий вид вживую, не дожидаясь внедрения.
#
# Запуск (права администратора НЕ нужны):
#     powershell -ExecutionPolicy Bypass -File manager-preview.ps1
#     powershell -ExecutionPolicy Bypass -File manager-preview.ps1 -Seconds 12
#
# Что показывает: фоновый узор на весь экран, окно по центру со стеклянной
# подложкой, счётчик процентов, список задач с состояниями и баннер с причиной
# сбоя. Прогресс имитируется, реальные задачи не запускаются.
#
# Выход: клавиша Esc или крестик в правом верхнем углу окна.
# ==============================================================================

param(
    [int]$Seconds = 26,          # сколько длится имитация
    [switch]$Windowed            # окно вместо полного экрана (для отладки)
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Отключаем масштабирование системы: рисуем сами, в пикселях
try {
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public class WadDpi {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@ -ErrorAction Stop
    [WadDpi]::SetProcessDPIAware() | Out-Null
} catch {
    # сбой DPI не критичен: продолжаем без него
}

# ----------------------------------------------------------------------------- цвета
$Script:C = @{
    Text    = [System.Drawing.Color]::FromArgb(233, 237, 251)
    Muted   = [System.Drawing.Color]::FromArgb(142, 150, 184)
    Dim     = [System.Drawing.Color]::FromArgb(104, 112, 145)
    Accent1 = [System.Drawing.Color]::FromArgb(122, 162, 247)
    Accent2 = [System.Drawing.Color]::FromArgb(167, 139, 250)
    Ok      = [System.Drawing.Color]::FromArgb(134, 214, 160)
    Run     = [System.Drawing.Color]::FromArgb(125, 211, 252)
    Warn    = [System.Drawing.Color]::FromArgb(240, 196, 120)
    Err     = [System.Drawing.Color]::FromArgb(240, 142, 160)
    Card    = [System.Drawing.Color]::FromArgb(16, 17, 27)
    Ink     = [System.Drawing.Color]::FromArgb(11, 11, 18)
}

# ----------------------------------------------------------------------------- размеры
$Screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
if ($Windowed) { $Screen = New-Object System.Drawing.Rectangle(0, 0, 1280, 800) }

$Script:W = $Screen.Width
$Script:H = $Screen.Height
$Script:S = [Math]::Min(1.0, [Math]::Min(($Script:W - 100) / 1180.0, ($Script:H - 100) / 700.0))

function Sc([double]$v) { return [int]($v * $Script:S) }           # масштаб: размеры макета -> экран
function Pt([double]$v) { return [double]($v * 0.75 * $Script:S) } # пиксели -> пункты шрифта

$CardW = Sc 1180
$CardH = Sc 700
$CardX = [int](($Script:W - $CardW) / 2)
$CardY = [int](($Script:H - $CardH) / 2)
$Pad   = Sc 48
$Inner = $CardW - $Pad          # правый край содержимого — в координатах окна, не экрана

# ----------------------------------------------------------------------------- шрифт
$Script:Family = 'Segoe UI'
try { $null = New-Object System.Drawing.FontFamily($Script:Family) } catch { $Script:Family = 'SansSerif' }

function F([string]$style, [double]$px) {
    $fs = [System.Drawing.FontStyle]::Regular
    if ($style -eq 'semibold' -or $style -eq 'bold') { $fs = [System.Drawing.FontStyle]::Bold }
    return New-Object System.Drawing.Font($Script:Family, (Pt $px), $fs, [System.Drawing.GraphicsUnit]::Point)
}

# ----------------------------------------------------------------------------- задачи
# Времена начала и окончания — правдоподобные, как их увидит человек в реальном прогоне
$Script:Tasks = @(
    @{ Name = 'Первоначальная настройка ОС';            T0 = 1.6;  T1 = 3.6;  Start = '12:41:03'; End = '12:47:21' }
    @{ Name = 'Оптимизация и настройка ОС';             T0 = 3.6;  T1 = 5.6;  Start = '12:47:21'; End = '12:55:02' }
    @{ Name = 'Установка системных компонентов';        T0 = 5.6;  T1 = 10.6; Start = '12:55:02'; End = '13:07:44' }
    @{ Name = 'Установка софта';                        T0 = 10.6; T1 = 16.6; Start = '13:07:44'; End = '13:21:10' }
    @{ Name = 'Установка и активация Microsoft Office'; T0 = 17.4; T1 = 21.4; Start = '13:21:40'; End = '13:34:55' }
)
$Script:TaskSubs = @(
    @('Настройки Edge', 'Панель задач и меню Пуск', 'Телеметрия', 'Макет профиля по умолчанию')
    @('Удаление 33 приложений', 'OneDrive', 'Просмотр фотографий', 'Файл подкачки')
    @('Visual C++ 2015-2022', 'DirectX', '.NET Framework 3.5', '.NET 8.0', 'OpenAL')
    @('Google Chrome', 'Steam', 'WinRAR', 'qBittorrent', 'ShareX', 'K-Lite Codec Pack')
    @('Скачивание Office Deployment Tool', 'Установка Word, Excel, PowerPoint', 'Привязка KMS', 'Активация')
)
$Script:WarnLines = @('ShareX — установщик вернул код 1603', 'K-Lite Codec Pack — ссылка не отвечает')
$Script:TaskResult = @('ok', 'ok', 'ok', 'warn', 'ok')

function Get-TaskState([int]$i, [double]$t) {
    $task = $Script:Tasks[$i]
    if ($t -lt $task.T0) { return @('waiting', 0.0) }
    if ($t -lt $task.T1) {
        # долю считаем отдельно: в конструкции @('run', $a / $b) PowerShell делит сам массив
        $frac = ($t - $task.T0) / ($task.T1 - $task.T0)
        return @('run', $frac)
    }
    return @($Script:TaskResult[$i], 1.0)
}

function Get-Progress([double]$t) {
    $total = 0.0
    for ($i = 0; $i -lt $Script:Tasks.Count; $i++) {
        $state = (Get-TaskState $i $t)[0]
        if ($state -eq 'waiting') { continue }
        $frac = (Get-TaskState $i $t)[1]
        $total += [Math]::Min(1.0, $frac) / $Script:Tasks.Count
    }
    return [Math]::Min(1.0, [Math]::Max(0.0, $total))
}

# ----------------------------------------------------------------------------- фон
function New-Background([int]$w, [int]$h) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'

    # вертикальный градиент
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect,
        [System.Drawing.Color]::FromArgb(11, 11, 18),
        [System.Drawing.Color]::FromArgb(18, 18, 28), 90.0)
    $g.FillRectangle($grad, $rect)
    $grad.Dispose()

    # мягкие пятна свечения
    foreach ($spot in @(
        @{ X = 0.12; Y = 0.88; R = 0.55; A = 46; Col = [System.Drawing.Color]::FromArgb(40, 80, 160) }
        @{ X = 0.88; Y = 0.10; R = 0.60; A = 34; Col = [System.Drawing.Color]::FromArgb(30, 70, 120) }
    )) {
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $cx = $w * $spot.X; $cy = $h * $spot.Y; $r = $w * $spot.R
        $path.AddEllipse($cx - $r, $cy - $r, $r * 2, $r * 2)
        $pg = New-Object System.Drawing.Drawing2D.PathGradientBrush($path)
        $pg.CenterColor = [System.Drawing.Color]::FromArgb($spot.A, $spot.Col)
        $pg.SurroundColors = @([System.Drawing.Color]::FromArgb(0, $spot.Col))
        $g.FillPath($pg, $path)
        $pg.Dispose(); $path.Dispose()
    }

    # дорожки платы: только прямые углы, как на настоящей разводке
    $rnd = New-Object System.Random(7)
    $step = 60
    $penThin = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(30, 86, 110, 170), 1)
    $penMid  = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(46, 86, 110, 170), 1)
    $penLit  = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(70, 137, 180, 250), 1)
    $brushNode = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(90, 137, 180, 250))
    for ($seg = 0; $seg -lt 240; $seg++) {
        $x = $rnd.Next(0, [int]($w / $step)) * $step
        $y = $rnd.Next(0, [int]($h / $step)) * $step
        $len = $rnd.Next(2, 8)
        for ($k = 0; $k -lt $len; $k++) {
            $dir = $rnd.Next(0, 4)
            $dx = 0; $dy = 0
            if ($dir -eq 0) { $dx = $step } elseif ($dir -eq 1) { $dx = -$step }
            elseif ($dir -eq 2) { $dy = $step } else { $dy = -$step }
            $nx = $x + $dx; $ny = $y + $dy
            if ($nx -lt 0 -or $nx -gt $w -or $ny -lt 0 -or $ny -gt $h) { break }
            $r = $rnd.Next(0, 100)
            if ($r -lt 10) { $pen = $penLit } elseif ($r -lt 55) { $pen = $penMid } else { $pen = $penThin }
            $g.DrawLine($pen, $x, $y, $nx, $ny)
            $x = $nx; $y = $ny
        }
        $g.FillEllipse($brushNode, $x - 2, $y - 2, 4, 4)
    }
    $penThin.Dispose(); $penMid.Dispose(); $penLit.Dispose(); $brushNode.Dispose()

    # затемнение центра: окно по центру должно читаться, фон — не спорить с ним
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddEllipse(-$w * 0.35, -$h * 0.35, $w * 1.7, $h * 1.7)
    $pg = New-Object System.Drawing.Drawing2D.PathGradientBrush($path)
    $pg.CenterColor = [System.Drawing.Color]::FromArgb(150, 5, 5, 9)
    $pg.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 5, 5, 9))
    $g.FillPath($pg, $path)
    $pg.Dispose(); $path.Dispose()

    $g.Dispose()
    return $bmp
}

# ----------------------------------------------------------------------------- помощники рисования
function New-RoundedPath([double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    if ($r -le 0) { $path.AddRectangle((New-Object System.Drawing.RectangleF($x, $y, $w, $h))); return $path }
    $d = $r * 2
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

function Get-TextSize($g, [string]$text, $font) {
    return $g.MeasureString($text, $font)
}

function New-LinearGradient($rect, $c1, $c2) {
    return New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, 0.0)
}

function Draw-Chip($g, [double]$x, [double]$y, [double]$w, [double]$h, [string]$text, $color, $font) {
    $path = New-RoundedPath $x $y $w $h ($h / 2)
    $fill = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(26, $color))
    $pen  = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(90, $color), 1)
    $g.FillPath($fill, $path)
    $g.DrawPath($pen, $path)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $brush = New-Object System.Drawing.SolidBrush($color)
    $g.DrawString($text, $font, $brush, (New-Object System.Drawing.RectangleF($x, $y, $w, $h)), $sf)
    $sf.Dispose(); $brush.Dispose(); $fill.Dispose(); $pen.Dispose(); $path.Dispose()
}

function Draw-StateIcon($g, [double]$cx, [double]$cy, [double]$r, [string]$state, [double]$t) {
    if ($state -eq 'waiting') {
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150, $Script:C.Dim), 2)
        $g.DrawEllipse($pen, $cx - $r, $cy - $r, $r * 2, $r * 2)
        $pen.Dispose()
    } elseif ($state -eq 'run') {
        $pen = New-Object System.Drawing.Pen($Script:C.Run, 3)
        $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
        $start = [int](($t * 220) % 360)
        $g.DrawArc($pen, $cx - $r, $cy - $r, $r * 2, $r * 2, $start, 250)
        $pen.Dispose()
    } elseif ($state -eq 'ok') {
        $brush = New-Object System.Drawing.SolidBrush($Script:C.Ok)
        $g.FillEllipse($brush, $cx - $r, $cy - $r, $r * 2, $r * 2)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(12, 14, 24), 3)
        $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
        $g.DrawLines($pen, @(
            (New-Object System.Drawing.PointF(($cx - $r * 0.45), ($cy + $r * 0.05))),
            (New-Object System.Drawing.PointF(($cx - $r * 0.08), ($cy + $r * 0.45))),
            (New-Object System.Drawing.PointF(($cx + $r * 0.50), ($cy - $r * 0.42)))
        ))
        $pen.Dispose(); $brush.Dispose()
    } else {
        $brush = New-Object System.Drawing.SolidBrush($Script:C.Warn)
        $g.FillEllipse($brush, $cx - $r, $cy - $r, $r * 2, $r * 2)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(12, 14, 24), 3)
        $g.DrawLine($pen, $cx, ($cy - $r * 0.5), $cx, ($cy + $r * 0.15))
        $g.FillEllipse((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(12, 14, 24))),
            $cx - 2, ($cy + $r * 0.42), 4, 4)
        $pen.Dispose(); $brush.Dispose()
    }
}

function Draw-Text($g, [string]$text, $font, $brush, [double]$x, [double]$y) {
    $g.DrawString($text, $font, $brush, (New-Object System.Drawing.PointF($x, $y)))
}

function Draw-TextRight($g, [string]$text, $font, $brush, [double]$right, [double]$y) {
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Far'
    $size = $g.MeasureString($text, $font)
    $rect = New-Object System.Drawing.RectangleF(($right - $size.Width - 4), $y, ($size.Width + 8), $size.Height)
    $g.DrawString($text, $font, $brush, $rect, $sf)
    $sf.Dispose()
}

# ----------------------------------------------------------------------------- окно
$Form = New-Object System.Windows.Forms.Form
$Form.Text = 'WAD — предпросмотр интерфейса'
$Form.FormBorderStyle = 'None'
$Form.StartPosition = 'Manual'
$Form.Bounds = $Screen
$Form.BackColor = $Script:C.Ink
$Form.KeyPreview = $true
$Form.ShowInTaskbar = -not $Windowed

# двойная буферизация — иначе анимация мерцает
$flags = [System.Reflection.BindingFlags]([System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance)
$Form.GetType().GetProperty('DoubleBuffered', $flags).SetValue($Form, $true)

$Script:Bg = New-Background ($Script:W + 60) ($Script:H + 60)
$Script:Watch = [System.Diagnostics.Stopwatch]::StartNew()
$Script:PreviewFont = F 'regular' 15
$Script:SmallFont = F 'regular' 11

$Form.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

    $t = $Script:Watch.Elapsed.TotalSeconds
    if ($t -gt $Script:LoopSeconds) { $t = $Script:LoopSeconds }

    # --- фон с медленным смещением (живой, но не отвлекающий)
    $dx = [int](30 + 14 * [Math]::Sin($t * 0.25))
    $dy = [int](30 + 10 * [Math]::Cos($t * 0.21))
    $g.DrawImage($Script:Bg, (New-Object System.Drawing.Rectangle(0, 0, $Script:W, $Script:H)),
                 $dx, $dy, $Script:W, $Script:H, [System.Drawing.GraphicsUnit]::Pixel)

    # --- стеклянная подложка: уменьшить и растянуть (в GDI+ нет настоящего размытия)
    $cardRect = New-Object System.Drawing.Rectangle($CardX, $CardY, $CardW, $CardH)
    $path = New-RoundedPath $CardX $CardY $CardW $CardH (Sc 30)
    $g.SetClip($path)

    $smallW = [int]($CardW / 16); $smallH = [int]($CardH / 16)
    $small = New-Object System.Drawing.Bitmap($smallW, $smallH)
    $gs = [System.Drawing.Graphics]::FromImage($small)
    $gs.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
    $gs.DrawImage($Script:Bg,
        (New-Object System.Drawing.Rectangle(0, 0, $smallW, $smallH)),
        ($CardX + $dx), ($CardY + $dy), $CardW, $CardH, [System.Drawing.GraphicsUnit]::Pixel)
    $gs.Dispose()
    $g.DrawImage($small, $cardRect)
    $small.Dispose()

    $tint = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(204, $Script:C.Card))
    $g.FillRectangle($tint, $cardRect)
    $tint.Dispose()
    $g.ResetClip()

    # рамка и подсветка сверху
    $framePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(30, 255, 255, 255), 1)
    $g.DrawPath($framePen, $path)
    $framePen.Dispose()
    $glowPath = New-RoundedPath $CardX $CardY $CardW (Sc 40) (Sc 30)
    $glowBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Rectangle($CardX, $CardY, $CardW, (Sc 40))),
        [System.Drawing.Color]::FromArgb(18, 255, 255, 255),
        [System.Drawing.Color]::FromArgb(0, 255, 255, 255), 90.0)
    $g.FillPath($glowBrush, $glowPath)
    $glowBrush.Dispose(); $glowPath.Dispose(); $path.Dispose()

    # --- содержимое окна -----------------------------------------------------
    # Сдвигаем начало отсчёта в левый верхний угол окна: вся разметка ниже
    # задана в координатах окна. Без этого текст рисуется в углу экрана.
    $g.TranslateTransform($CardX, $CardY)
    $prog = Get-Progress $t
    $textBrush = New-Object System.Drawing.SolidBrush($Script:C.Text)
    $mutedBrush = New-Object System.Drawing.SolidBrush($Script:C.Muted)
    $dimBrush = New-Object System.Drawing.SolidBrush($Script:C.Dim)

    # логотип
    $logoSize = Sc 46
    $logoPath = New-RoundedPath $Pad (Sc 44) $logoSize $logoSize (Sc 13)
    $logoBrush = New-LinearGradient(
        (New-Object System.Drawing.Rectangle($Pad, (Sc 44), $logoSize, $logoSize)),
        $Script:C.Accent1, $Script:C.Accent2)
    $g.FillPath($logoBrush, $logoPath)
    $logoBrush.Dispose(); $logoPath.Dispose()
    $logoFont = F 'bold' 26
    $logoText = New-Object System.Drawing.StringFormat
    $logoText.Alignment = 'Center'; $logoText.LineAlignment = 'Center'
    $darkBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(12, 14, 24))
    $g.DrawString('W', $logoFont, $darkBrush,
        (New-Object System.Drawing.RectangleF($Pad, (Sc 44), $logoSize, $logoSize)), $logoText)
    $logoText.Dispose(); $logoFont.Dispose()

    $titleFont = F 'semibold' 27
    Draw-Text $g 'WAD — автоматическая установка Windows' $titleFont $textBrush (Sc 110) (Sc 44)
    $subFont = F 'regular' 16.5
    Draw-Text $g 'Режим Clean · Windows 11 · запуск с GitHub' $subFont $mutedBrush (Sc 110) (Sc 80)
    $titleFont.Dispose(); $subFont.Dispose()

    # состояние справа
    if ($t -ge 17.2)     { $pillText = 'Завершено с замечаниями'; $pillColor = $Script:C.Warn }
    elseif ($t -ge 16.6) { $pillText = 'Нужно внимание';          $pillColor = $Script:C.Warn }
    else                 { $pillText = 'Идёт установка';          $pillColor = $Script:C.Run }
    $pillFont = F 'regular' 16.5
    $pillSize = Get-TextSize $g $pillText $pillFont
    $pillW = $pillSize.Width + (Sc 62)
    $pillX = $Inner - $pillW
    Draw-Chip $g $pillX (Sc 52) $pillW (Sc 40) $pillText $pillColor $pillFont
    $dotBrush = New-Object System.Drawing.SolidBrush($pillColor)
    $dotR = Sc (5 + (1.6 * [Math]::Sin($t * 4)))
    $g.FillEllipse($dotBrush, ($pillX + (Sc 18) - $dotR), ((Sc 72) - $dotR), ($dotR * 2), ($dotR * 2))
    $dotBrush.Dispose(); $pillFont.Dispose()

    # процент и счётчик
    $pctFont = F 'bold' 76
    Draw-Text $g ("{0}%" -f [int]($prog * 100)) $pctFont $textBrush $Pad (Sc 108)
    $pctFont.Dispose()
    $done = 0
    for ($i = 0; $i -lt $Script:Tasks.Count; $i++) {
        $st = (Get-TaskState $i $t)[0]
        if ($st -eq 'ok' -or $st -eq 'warn') { $done++ }
    }
    $countFont = F 'regular' 19
    Draw-Text $g ("{0} из 5 задач" -f $done) $countFont $mutedBrush $Pad (Sc 196)
    $countFont.Dispose()

    # текущий шаг и полоса
    $stepX = $Pad + (Sc 290)
    $stepW = $Inner - $stepX
    $current = -1
    for ($i = 0; $i -lt $Script:Tasks.Count; $i++) {
        if ((Get-TaskState $i $t)[0] -eq 'run') { $current = $i; break }
    }
    if ($current -ge 0) {
        $frac = (Get-TaskState $current $t)[1]
        $subs = $Script:TaskSubs[$current]
        $subIndex = [Math]::Min($subs.Count - 1, [int]($frac * $subs.Count))
        $step = "$($Script:Tasks[$current].Name) · $($subs[$subIndex])"
    } elseif ($t -gt 21.6) {
        $step = 'Все задачи выполнены'
    } else {
        $step = 'Подготовка…'
    }
    $stepFont = F 'regular' 19
    while ((Get-TextSize $g $step $stepFont).Width -gt $stepW -and $step.Length -gt 8) {
        $step = $step.Substring(0, $step.Length - 2)
    }
    Draw-Text $g $step $stepFont $textBrush $stepX (Sc 120)
    $stepFont.Dispose()

    $barY = Sc 156; $barH = Sc 12
    $trackBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(22, 255, 255, 255))
    $g.FillRectangle($trackBrush, $stepX, $barY, $stepW, $barH)
    $trackBrush.Dispose()
    $fillW = [int]($stepW * $prog)
    if ($fillW -gt 4) {
        $fillRect = New-Object System.Drawing.Rectangle($stepX, $barY, $fillW, $barH)
        $fillBrush = New-LinearGradient $fillRect $Script:C.Accent1 $Script:C.Accent2
        $g.FillRectangle($fillBrush, $fillRect)
        $fillBrush.Dispose()

        # блик: градиент, подрезанный по области заливки
        $sheenRect = New-Object System.Drawing.RectangleF(0, 0, (Sc 220), $barH)
        $sheen = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            $sheenRect,
            [System.Drawing.Color]::FromArgb(0, 255, 255, 255),
            [System.Drawing.Color]::FromArgb(110, 255, 255, 255), 0.0)
        $blend = New-Object System.Drawing.Drawing2D.ColorBlend
        $blend.Colors = @(
            [System.Drawing.Color]::FromArgb(0, 255, 255, 255),
            [System.Drawing.Color]::FromArgb(110, 255, 255, 255),
            [System.Drawing.Color]::FromArgb(0, 255, 255, 255))
        $blend.Positions = @(0.0, 0.5, 1.0)
        $sheen.InterpolationColors = $blend
        $sheenX = (($t * 0.35) % 1.0) * ($fillW + (Sc 220)) - (Sc 110)
        $g.SetClip((New-Object System.Drawing.Rectangle($stepX, $barY, $fillW, $barH)))
        $g.FillRectangle($sheen, ($stepX + $sheenX), $barY, (Sc 220), $barH)
        $g.ResetClip()
        $sheen.Dispose()
    }

    $timeFont = F 'regular' 16
    $elapsed = [int]($prog * 54)
    if ($prog -ge 0.999) {
        $timeText = "Всего заняло $elapsed мин"
    } else {
        $leftMin = [Math]::Max(1, [int]((1 - $prog) * 48))
        $timeText = "Прошло $elapsed мин · осталось примерно $leftMin мин"
    }
    Draw-TextRight $g $timeText $timeFont $dimBrush $Inner (Sc 180)
    $timeFont.Dispose()

    # баннер предупреждения
    $bannerY = Sc 544
    if ($t -ge 16.6) {
        $bannerEase = [Math]::Min(1.0, ($t - 16.6) / 0.5)
        $by = $bannerY + [int]((1 - $bannerEase) * (Sc 14))
        $bh = Sc 80
        $bannerPath = New-RoundedPath $Pad $by ($Inner - $Pad) $bh (Sc 14)
        $bannerFill = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(30, $Script:C.Warn))
        $bannerPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(110, $Script:C.Warn), 1)
        $g.FillPath($bannerFill, $bannerPath)
        $g.DrawPath($bannerPen, $bannerPath)
        $stripe = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, $Script:C.Warn))
        $g.FillRectangle($stripe, $Pad, ($by + (Sc 10)), (Sc 4), ($bh - (Sc 20)))
        $stripe.Dispose(); $bannerFill.Dispose(); $bannerPen.Dispose(); $bannerPath.Dispose()

        Draw-StateIcon $g ($Pad + (Sc 34)) ($by + $bh / 2) (Sc 13) 'warn' $t
        $bannerFont = F 'semibold' 19
        Draw-Text $g 'Установка софта завершилась с замечаниями: 2 программы не установились' `
            $bannerFont $textBrush ($Pad + (Sc 62)) ($by + (Sc 20))
        $bannerFont.Dispose()
        $warnFont = F 'regular' 16.5
        $warnBrush = New-Object System.Drawing.SolidBrush($Script:C.Warn)
        Draw-Text $g ($Script:WarnLines -join ' · ') $warnFont $warnBrush ($Pad + (Sc 62)) ($by + (Sc 48))
        $warnFont.Dispose(); $warnBrush.Dispose()
        $openFont = F 'regular' 16.5
        $openBrush = New-Object System.Drawing.SolidBrush($Script:C.Warn)
        Draw-TextRight $g 'Открыть журнал' $openFont $openBrush ($Inner - (Sc 20)) ($by + $bh / 2 - (Sc 11))
        $openFont.Dispose(); $openBrush.Dispose()
    }

    # список задач
    $rowY = Sc 234
    $rowH = Sc 54
    $rowGap = Sc 6
    $nameFont = F 'semibold' 21
    $chipFont = F 'regular' 16.5
    for ($i = 0; $i -lt $Script:Tasks.Count; $i++) {
        $y = $rowY + $i * ($rowH + $rowGap)
        $state = (Get-TaskState $i $t)[0]
        $rowPath = New-RoundedPath $Pad $y ($Inner - $Pad) $rowH (Sc 12)
        if ($state -eq 'run') {
            $rowFill = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(24, $Script:C.Accent1))
            $rowPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(70, $Script:C.Accent1), 1)
            $g.FillPath($rowFill, $rowPath); $g.DrawPath($rowPen, $rowPath)
            $rowFill.Dispose(); $rowPen.Dispose()
        } else {
            $rowFill = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(8, 255, 255, 255))
            $g.FillPath($rowFill, $rowPath)
            $rowFill.Dispose()
        }
        $rowPath.Dispose()

        Draw-StateIcon $g ($Pad + (Sc 30)) ($y + $rowH / 2) (Sc 12) $state $t
        $nameBrush = $textBrush
        if ($state -eq 'waiting') { $nameBrush = $mutedBrush }
        $sfCenter = New-Object System.Drawing.StringFormat
        $sfCenter.LineAlignment = 'Center'
        $g.DrawString($Script:Tasks[$i].Name, $nameFont, $nameBrush,
            (New-Object System.Drawing.RectangleF(($Pad + (Sc 58)), $y, ($Inner - $Pad - (Sc 200)), $rowH)), $sfCenter)
        $sfCenter.Dispose()

        if ($state -eq 'run')          { $chipText = "идёт · с $($Script:Tasks[$i].Start.Substring(0, 5))"; $chipColor = $Script:C.Run }
        elseif ($state -eq 'ok')       { $chipText = "готово · $($Script:Tasks[$i].End.Substring(0, 5))";   $chipColor = $Script:C.Ok }
        elseif ($state -eq 'warn')     { $chipText = "замечания · $($Script:Tasks[$i].End.Substring(0, 5))"; $chipColor = $Script:C.Warn }
        else                           { $chipText = 'ждёт'; $chipColor = $Script:C.Dim }
        $chipW = (Get-TextSize $g $chipText $chipFont).Width + (Sc 30)
        Draw-Chip $g ($Inner - (Sc 18) - $chipW) ($y + (Sc 14)) $chipW ($rowH - (Sc 28)) $chipText $chipColor $chipFont
    }
    $nameFont.Dispose(); $chipFont.Dispose()

    # низ окна: подсказка и кнопки
    $hintFont = F 'regular' 16.5
    Draw-Text $g 'Окно можно свернуть — установка продолжится' $hintFont $dimBrush $Pad (Sc 660)
    $hintFont.Dispose()

    $final = $t -ge 17.2
    if ($final) { $btn2Text = 'Перезагрузить компьютер' } else { $btn2Text = 'Свернуть в фон' }
    $btnFont = F 'semibold' 17
    $btn2W = (Get-TextSize $g $btn2Text $btnFont).Width + (Sc 52)
    $btn2X = $Inner - $btn2W
    $btn2Path = New-RoundedPath $btn2X (Sc 640) $btn2W (Sc 42) (Sc 12)
    $btn2Fill = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, $Script:C.Accent1))
    $g.FillPath($btn2Fill, $btn2Path)
    $btnTextFmt = New-Object System.Drawing.StringFormat
    $btnTextFmt.Alignment = 'Center'; $btnTextFmt.LineAlignment = 'Center'
    $g.DrawString($btn2Text, $btnFont, $darkBrush,
        (New-Object System.Drawing.RectangleF($btn2X, (Sc 640), $btn2W, (Sc 42))), $btnTextFmt)
    $btn2Fill.Dispose(); $btn2Path.Dispose()

    $btn1Text = 'Открыть журнал'
    $btn1W = (Get-TextSize $g $btn1Text $btnFont).Width + (Sc 48)
    $btn1X = $btn2X - (Sc 14) - $btn1W
    $btn1Path = New-RoundedPath $btn1X (Sc 640) $btn1W (Sc 42) (Sc 12)
    $btn1Fill = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(14, 255, 255, 255))
    $btn1Pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(46, 255, 255, 255), 1)
    $g.FillPath($btn1Fill, $btn1Path); $g.DrawPath($btn1Pen, $btn1Path)
    $g.DrawString($btn1Text, $btnFont, $textBrush,
        (New-Object System.Drawing.RectangleF($btn1X, (Sc 640), $btn1W, (Sc 42))), $btnTextFmt)
    $btn1Fill.Dispose(); $btn1Pen.Dispose(); $btn1Path.Dispose()
    $btnTextFmt.Dispose(); $btnFont.Dispose()

    # крестик закрытия
    $closeFont = F 'regular' 16
    $closeX = $CardW - (Sc 34)
    $closeY = (Sc 18)
    $closeBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160, $Script:C.Muted))
    $g.DrawString('✕', $closeFont, $closeBrush, (New-Object System.Drawing.PointF($closeX, $closeY)))
    $closeBrush.Dispose(); $closeFont.Dispose()

    # подпись о том, что это предпросмотр
    $previewFont = F 'regular' 13
    $previewBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(140, $Script:C.Dim))
    Draw-Text $g ('Предпросмотр интерфейса · прогресс имитируется · Esc — выход') $previewFont $previewBrush `
        $Pad ($CardH + (Sc 14))
    $previewBrush.Dispose(); $previewFont.Dispose()

    $textBrush.Dispose(); $mutedBrush.Dispose(); $dimBrush.Dispose(); $darkBrush.Dispose()
    $g.ResetTransform()
})

$Script:LoopSeconds = $Seconds
$Timer = New-Object System.Windows.Forms.Timer
$Timer.Interval = 33
$Timer.Add_Tick({ $Form.Invalidate() })
$Timer.Start()

$Form.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq 'Escape') { $Form.Close() }
})
$Form.Add_MouseDown({
    param($s, $e)
    # крестик в правом верхнем углу окна
    $closeX = $CardX + $CardW - (Sc 50)
    $closeY = $CardY + (Sc 10)
    if ($e.X -ge $closeX -and $e.X -le $closeX + (Sc 50) -and $e.Y -ge $closeY -and $e.Y -le $closeY + (Sc 50)) {
        $Form.Close()
    }
})

[void]$Form.ShowDialog()
$Timer.Stop(); $Timer.Dispose()
$Script:Bg.Dispose()
