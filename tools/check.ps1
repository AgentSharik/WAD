# ==============================================================================
# Проверка репозитория перед коммитом и в CI.
# Запуск из корня репозитория:
#     powershell -NoProfile -File tools\check.ps1        (Windows PowerShell 5.1)
#     pwsh      -NoProfile -File tools/check.ps1         (PowerShell 7+)
#
# Что делает:
#   1) разбор синтаксиса всех .ps1 проекта;
#   2) статический анализ PSScriptAnalyzer (только ошибки), если модуль доступен;
#   3) проверка кодировки UTF-8 с BOM (без BOM в Windows PowerShell 5.1
#      кириллица превращается в кракозябры).
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

# --- 2. Кодировка -------------------------------------------------------------
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

# --- 3. Статический анализ ----------------------------------------------------
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

Write-Host "ПРОВЕРКА ПРОЙДЕНА."
exit 0
