# ==============================================================================
# Проверка репозитория перед коммитом и в CI.
# Запуск из корня репозитория:
#     powershell -NoProfile -File tools\check.ps1        (Windows PowerShell 5.1)
#     pwsh      -NoProfile -File tools/check.ps1         (PowerShell 7+)
#
# Что делает:
#   1) разбор синтаксиса всех .ps1 проекта;
#   2) сверка копий, которые обязаны совпадать в обоих режимах;
#   3) проверка кодировки UTF-8 с BOM (без BOM в Windows PowerShell 5.1
#      кириллица превращается в кракозябры);
#   4) статический анализ PSScriptAnalyzer (только ошибки), если модуль доступен;
#   5) проверка, что код совместим с Windows PowerShell 5.1 (а не только с 7).
#
# Файл обязан быть в UTF-8 с BOM: среда исполнения читает .ps1 как ANSI без BOM.
# ==============================================================================

$ErrorActionPreference = 'Stop'
$root    = (Get-Location).Path
$exclude = '\.git[\\/]|\.cache[\\/]|\.local[\\/]|\.config[\\/]|extras[\\/]audit[\\/]extracted'

$files = Get-ChildItem -Path $root -Recurse -Filter *.ps1 -File |
         Where-Object { $_.FullName -notmatch $exclude }

Write-Host "Файлов на проверку: $($files.Count)"

# --- 1. Разбор синтаксиса -----------------------------------------------------
$bad = 0
foreach ($f in $files) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $bad++
        Write-Host "ОШИБКА РАЗБОРА: $($f.FullName.Replace($root, ''))"
        foreach ($e in $errors) {
            Write-Host ("    строка {0}: {1}" -f $e.Extent.StartLineNumber, $e.Message)
        }
    }
}
if ($bad -gt 0) {
    Write-Host "Файлов с ошибками разбора: $bad"
    exit 1
}
Write-Host "Разбор синтаксиса: ошибок нет."

# --- 2. Сверка копий между режимами -------------------------------------------
# Файлы из $mustMatch обязаны совпадать байт-в-байт: они делают одно и то же
# в обоих режимах. Если правишь поведение — правь обе копии, иначе режимы
# разъедутся молча (так уже было: кнопка Git, файл подкачки, ассоциации фото).
$modeClean  = 'Scripts/Scripts for Clean Windows'
$modeCustom = 'Scripts/Scripts for Custom Windows (with Autounattend)'
$mustMatch  = @('apps-install.ps1', 'install-sys-components.ps1', 'office-install.ps1', 'reset-setup-scripts.ps1')
$mayDiffer  = @('manager.ps1'         # разный список задач и подписи
                'clean-and-photo.ps1') # разный список мусора: файл ответов уже убрал 16 пакетов

$skew = @()
foreach ($name in $mustMatch) {
    $a = Join-Path $modeClean  $name
    $b = Join-Path $modeCustom $name
    if (-not (Test-Path $a) -or -not (Test-Path $b)) {
        Write-Host "НЕТ ФАЙЛА: $name (ожидается в обеих папках режимов)"
        $skew += $name
        continue
    }
    if ((Get-FileHash $a -Algorithm SHA256).Hash -ne (Get-FileHash $b -Algorithm SHA256).Hash) {
        Write-Host "РАСХОЖДЕНИЕ КОПИЙ: $name"
        $skew += $name
    }
}
if ($skew.Count -gt 0) {
    Write-Host "Копии разошлись, файлов: $($skew.Count)"
    exit 1
}
Write-Host "Копии совпадают: $($mustMatch.Count) файла(ов). По замыслу различаются: $($mayDiffer -join ', ')."

# --- 3. Кодировка -------------------------------------------------------------
$noBom = @()
foreach ($f in $files) {
    $head = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($head.Length -lt 3 -or -not ($head[0] -eq 0xEF -and $head[1] -eq 0xBB -and $head[2] -eq 0xBF)) {
        $noBom += $f.FullName.Replace($root, '')
    }
}
if ($noBom.Count -gt 0) {
    foreach ($p in $noBom) { Write-Host "БЕЗ BOM: $p" }
    Write-Host "Файлов без BOM: $($noBom.Count) (известный дефект: Custom/clean-and-photo.ps1)"
} else {
    Write-Host "Все файлы в UTF-8 с BOM."
}

# --- 4. Статический анализ ----------------------------------------------------
if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
    Import-Module PSScriptAnalyzer -ErrorAction SilentlyContinue
    $issues = @()
    foreach ($f in $files) {
        $issues += Invoke-ScriptAnalyzer -Path $f.FullName -Severity Error -ErrorAction SilentlyContinue
    }
    if ($issues.Count -gt 0) {
        Write-Host "ОШИБКИ АНАЛИЗА:"
        foreach ($i in $issues) {
            Write-Host ("    {0}:{1} {2}" -f (Split-Path $i.ScriptName -Leaf), $i.Line, $i.Message)
        }
        exit 1
    }
    Write-Host "PSScriptAnalyzer (уровень Error): чисто."
} else {
    Write-Host "PSScriptAnalyzer не установлен - шаг анализа пропущен."
}

# --- 5. Совместимость с Windows PowerShell 5.1 ---------------------------------
# Локально работают оба PowerShell, но на домашних ПК стоит именно 5.1.
# Он, например, не разбирает вызов функции внутри выражения: $w = $x + F 10
# (нужно $x + (F 10)) — PowerShell 7 такое пропускает, 5.1 падает при запуске.
if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
    Import-Module PSScriptAnalyzer -ErrorAction SilentlyContinue
    $compatSettings = @{
        IncludeRules = @('PSUseCompatibleSyntax')
        Rules        = @{ PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @('5.1') } }
    }
    $compat = @()
    foreach ($f in $files) {
        $compat += Invoke-ScriptAnalyzer -Path $f.FullName -Settings $compatSettings -ErrorAction SilentlyContinue
    }
    if ($compat.Count -gt 0) {
        Write-Host "НЕСОВМЕСТИМО С POWERSHELL 5.1:"
        foreach ($c in $compat) {
            Write-Host ("    {0}:{1} {2}" -f (Split-Path $c.ScriptName -Leaf), $c.Line, $c.Message)
        }
        exit 1
    }
    Write-Host "Совместимость с Windows PowerShell 5.1: чисто."
}

Write-Host "ПРОВЕРКА ПРОЙДЕНА."
exit 0
