# =============================================================================
#  Проверки-логики.ps1 — прогоняет ЧИСТУЮ логику прототипа без окон.
#  Работает и вне Windows (pwsh), и в Windows PowerShell 5.1.
#  Запуск:  pwsh -NoProfile -File .\Проверки-логики.ps1
#           powershell -NoProfile -ExecutionPolicy Bypass -File .\Проверки-логики.ps1
# =============================================================================

$ErrorActionPreference = 'Stop'
$script:Pass = 0
$script:Fail = 0

function Assert-That {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:Pass++
        Write-Host "  ок   $Name" -ForegroundColor Green
    } else {
        $script:Fail++
        Write-Host "  ПРОВАЛ  $Name $(if ($Detail) { "→ $Detail" })" -ForegroundColor Red
    }
}

# подгружаем только функции (точка в начале — окна не открываются)
. (Join-Path $PSScriptRoot 'WAD-Prototype.ps1')

Write-Host ''
Write-Host 'WAD-прототип: проверка логики' -ForegroundColor White
Write-Host ''

# --- 1. Прогресс установки ----------------------------------------------------
$p0   = Get-WadProgress -Elapsed 0 -Total 30
$pMid = Get-WadProgress -Elapsed 15 -Total 30
$pEnd = Get-WadProgress -Elapsed 30 -Total 30
$pOver= Get-WadProgress -Elapsed 99 -Total 30

Assert-That 'в начале 0 %'          ($p0 -eq 0)                    "получено $p0"
Assert-That 'в середине ~50 %'      ($pMid -gt 40 -and $pMid -lt 60) "получено $pMid"
Assert-That 'в конце 100 %'         ($pEnd -eq 100)                "получено $pEnd"
Assert-That 'после конца не больше 100 %' ($pOver -le 100)         "получено $pOver"

$mono = $true
$prev = -1.0
foreach ($e in 0..30) {
    $v = Get-WadProgress -Elapsed $e -Total 30
    if ($v -lt $prev) { $mono = $false }
    $prev = $v
}
Assert-That 'прогресс только растёт' $mono

# --- 2. Состояния категорий ---------------------------------------------------
$end = Get-WadRowStatus -Elapsed 31 -Total 30
Assert-That 'категорий 4'                 ($end.Count -eq 4)
Assert-That 'три категории «готово»'      (($end | Where-Object State -eq 'ok').Count -eq 3)
Assert-That 'одна «пропущено» (софт)'     (($end | Where-Object State -eq 'warn').Count -eq 1)
Assert-That 'пропущена именно «Установка софта»' (($end | Where-Object State -eq 'warn').Name -eq 'Установка софта')

$start = Get-WadRowStatus -Elapsed 0 -Total 30
Assert-That 'в начале первая уже выполняется'  (($start | Where-Object State -eq 'run').Count -eq 1)
Assert-That 'в начале остальные три ждут'      (($start | Where-Object State -eq 'wait').Count -eq 3)

$mid = Get-WadRowStatus -Elapsed 3 -Total 30
Assert-That 'в процессе есть «выполняется»' (($mid | Where-Object State -eq 'run').Count -ge 1)

# --- 3. Пути: отчёт в «Документы», ярлык на рабочий стол ----------------------
$paths = Get-WadPaths
Assert-That 'папка отчёта — внутри «Документов»' ($paths.ReportDir.StartsWith($paths.Documents)) "получено $($paths.ReportDir)"
Assert-That 'файл отчёта — .html'                ($paths.ReportFile.EndsWith('.html'))
$lnk = Get-WadShortcutPath -DesktopPath $paths.Desktop
Assert-That 'ярлык — .lnk на рабочем столе'      ($lnk.EndsWith('.lnk') -and $lnk.StartsWith($paths.Desktop)) "получено $lnk"

# --- 4. Отчёт реально пишется на диск ----------------------------------------
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wad-report-" + [guid]::NewGuid().ToString('N') + '.html')
$rep = Save-WadReport -Started (Get-Date).AddMinutes(-1) -Finished (Get-Date) -ReportFile $tmp

Assert-That 'файл отчёта создан'      (Test-Path -LiteralPath $tmp)
Assert-That 'отчёт не пустой'         ($rep.Bytes -gt 3000)                    "байт: $($rep.Bytes)"
$bytes = [System.IO.File]::ReadAllBytes($tmp)
Assert-That 'отчёт в UTF-8 с BOM'     ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

$html = [System.IO.File]::ReadAllText($tmp)
Assert-That 'в отчёте «Всё готово»'        ($html.Contains('Всё готово'))
Assert-That 'в отчёте метка прототипа'     ($html.Contains('ТЕСТОВАЯ СБОРКА'))
Assert-That 'в отчёте все 4 категории'     ($html.Contains('Установка и активация Microsoft Office'))
Assert-That 'в отчёте замечание про софт'  ($html.Contains('ShareX'))
Assert-That 'в отчёте «Подробный отчёт»'   ($html.Contains('Подробный отчёт'))
Assert-That 'в отчёте ссылка на GitHub'    ($html.Contains('github.com/AgentSharik/WAD'))
Assert-That 'отчёт честно пишет про имитацию' ($html.Contains('не создавался'))
Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue

# --- 5. Ярлык: вне Windows честно сообщает об ошибке, а не врёт ---------------
$res = Save-WadShortcut -LinkPath (Join-Path ([System.IO.Path]::GetTempPath()) 'wad-test.lnk')
if ($IsWindows -or $PSVersionTable.PSEdition -ne 'Core') {
    Assert-That 'ярлык создан' $res.Success $res.Error
} else {
    Assert-That 'вне Windows ярлык не создан и это сообщено' ((-not $res.Success) -and $res.Error)
}

# --- 6. Обещания прототипа: ничего не качает, ничего не создаёт в системе -----
# Проверяем по дереву разбора (AST): комментарии не в счёт, только реальные вызовы.
$srcPath = Join-Path $PSScriptRoot 'WAD-Prototype.ps1'
$src = Get-Content -LiteralPath $srcPath -Raw
$toks = $null; $perr = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($srcPath, [ref]$toks, [ref]$perr)

$cmds = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
    ForEach-Object { $_.GetCommandName() })
$members = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.MemberExpressionAst] }, $true) |
    ForEach-Object { $_.Member.Name })
$used = @($cmds + $members | Where-Object { $_ })

$banned = @('Invoke-WebRequest', 'Invoke-RestMethod', 'Start-BitsTransfer', 'DownloadFile', 'DownloadString',
            'New-LocalUser', 'Add-LocalGroupMember', 'Set-LocalUser', 'Remove-LocalUser',
            'winget', 'choco', 'schtasks', 'reg')
$hit = @($used | Where-Object { $banned -contains $_ } | Sort-Object -Unique)
Assert-That 'нет сетевых загрузок и правок системы' ($hit.Count -eq 0) ("вызовы: " + ($hit -join ', '))

# реестр, автологон и RunOnce в коде отсутствуют (в комментариях — только как «не трогаем»)
$strings = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) |
    ForEach-Object { $_.Value })
$bannedStr = @('HKLM', 'HKCU', 'Winlogon', 'RunOnce', 'AutoAdminLogon', 'DefaultUserName')
$hitStr = @()
foreach ($s in $strings) { foreach ($b in $bannedStr) { if ($s -like "*$b*") { $hitStr += $b } } }
Assert-That 'реестр и автологон в коде не фигурируют' (($hitStr | Sort-Object -Unique).Count -eq 0) ("найдено: " + ($hitStr -join ', '))

# --- 7. Все требуемые экраны присутствуют ------------------------------------
$need = @('Здравствуйте', 'Вас приветствует WAD', 'Приступаем', 'Сайт разработчика', 'Сохранить ярлык',
          'Свернуть в фон', 'Перезагрузка через', 'Установка системы окончена.',
          'Теперь давайте создадим вам пользователя', 'Пользователь создаётся как администратор',
          'Создать и продолжить', 'Перезагрузка…')
$missing = @()
foreach ($n in $need) { if (-not $src.Contains($n)) { $missing += $n } }
Assert-That 'все экраны и надписи на месте' ($missing.Count -eq 0) ("нет: " + ($missing -join ', '))


# --- 9. Кривые титров возвращают числа, а не строки (баг 5.1) -----------------
$ra = @(Get-TitleAlpha 0.8 0.4 1.3 4.1 5.0)
Assert-That 'фаза входа: пара чисел' ($ra.Count -eq 2 -and $ra[0] -is [double] -and $ra[1] -is [double]) ("типы: " + (($ra | ForEach-Object { $_.GetType().Name }) -join ','))
$mid = @(Get-TitleAlpha 2.5 0.4 1.3 4.1 5.0)
Assert-That 'фаза выдержки: альфа 1, сдвиг 0' ($mid[0] -eq 1.0 -and $mid[1] -eq 0.0)
$outp = @(Get-TitleAlpha 4.5 0.4 1.3 4.1 5.0)
Assert-That 'фаза выхода: альфа < 1 и уход вверх' ($outp[0] -lt 1.0 -and $outp[1] -lt 0.0)
Assert-That 'ease_io на краях: 0 и 1' ((ease_io -1) -eq 0.0 -and (ease_io 2) -eq 1.0)

# --- 10. [math]::Min/Max — всегда ровно два аргумента (по дереву разбора) ----
$tok2 = $null; $err2 = $null
$astP = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'WAD-Prototype.ps1'), [ref]$tok2, [ref]$err2)
$badMath = @($astP.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true) | Where-Object {
        $isMath = $_.Expression -is [System.Management.Automation.Language.TypeExpressionAst] -and $_.Expression.TypeName.Name -match 'math'
        $isMM = $_.Member.Value -in @('Min', 'Max')
        $isMath -and $isMM -and (@($_.Arguments).Count -ne 2)
    })
Assert-That '[math]::Min/Max только с 2 аргументами' ($badMath.Count -eq 0) ("найдено: " + @($badMath | ForEach-Object { $_.Extent.StartLineNumber }) -join ', ')

# --- 8. Кодировка: без BOM Windows PowerShell 5.1 прочитает кириллицу как ANSI ---
foreach ($f in @('WAD-Prototype.ps1', 'Проверки-логики.ps1')) {
    $fp = Join-Path $PSScriptRoot $f
    $b = [System.IO.File]::ReadAllBytes($fp)
    Assert-That "$f — UTF-8 с BOM" ($b.Length -gt 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
}

Write-Host ''
Write-Host ("Итог: {0} ок, {1} провал" -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
Write-Host ''
if ($script:Fail) { exit 1 } else { exit 0 }
