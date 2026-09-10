# Проверка репозитория перед коммитом: разбор синтаксиса + статический анализ.
# Запуск (из корня репозитория):  ~/.cache/ps/pwsh -NoProfile -File extras/audit/tools/check.ps1
$root = (Get-Location).Path
# Проверяем только файлы проекта: исключаем .git, кэши инструментов и распакованные
# из autounattend.xml копии (они внутри XML и проверяются в CI).
$exclude = '\\.git\\|\\.cache\\|\\.local\\|\\.config\\|extras[\\/]audit[\\/]extracted'
$files = Get-ChildItem -Path $root -Recurse -Filter *.ps1 -File | Where-Object { $_.FullName -notmatch $exclude }

Write-Host "Файлов на проверку: $($files.Count)" -ForegroundColor Cyan
$fail = 0
foreach ($f in $files) {
    $tokens = $null; $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errs)
    if ($errs.Count) {
        $fail++
        Write-Host "ОШИБКА РАЗБОРА: $($f.FullName.Replace($root,''))" -ForegroundColor Red
        $errs | ForEach-Object { Write-Host ("   строка {0}: {1}" -f $_.Extent.StartLineNumber, $_.Message) }
    }
}
if ($fail -eq 0) { Write-Host "Разбор синтаксиса: ошибок нет." -ForegroundColor Green } else { exit 1 }

$bom = 0
foreach ($f in $files) {
    $b = [System.IO.File]::ReadAllBytes($f.FullName)[0..2]
    if (-not ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) {
        Write-Host "БЕЗ BOM: $($f.FullName.Replace($root,''))" -ForegroundColor Yellow
        $bom++
    }
}
Write-Host "Файлов без BOM: $bom (ожидается 1 - Custom/clean-and-photo.ps1, известный дефект)"

if (Get-Module -ListAvailable PSScriptAnalyzer) {
    $issues = $files | ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Severity Error }
    if ($issues) {
        Write-Host "ОШИБКИ АНАЛИЗА:" -ForegroundColor Red
        $issues | ForEach-Object { Write-Host ("   {0}:{1} {2}" -f (Split-Path $_.ScriptName -Leaf), $_.Line, $_.Message) }
        exit 1
    }
    Write-Host "PSScriptAnalyzer (Error): чисто." -ForegroundColor Green
} else {
    Write-Host "PSScriptAnalyzer не установлен - шаг пропущен." -ForegroundColor Yellow
}
