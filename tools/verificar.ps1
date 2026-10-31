#Requires -Version 5.1
<#
    Verificação do projeto (rode antes de cada commit):
      1. Garante UTF-8 COM BOM + CRLF em .ps1/.psm1/.psd1/.xaml/.cs
         (sem BOM o PowerShell 5.1 lê como ANSI e quebra os acentos)
      2. Analisa a sintaxe de todos os .ps1 sem executar nada
      3. Carrega cada .xaml para pegar erros de marcação

    Uso:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\verificar.ps1
#>
$raiz = Split-Path -Parent $PSScriptRoot
$utf8Bom = New-Object Text.UTF8Encoding $true
$falhas = 0

$arquivos = Get-ChildItem $raiz -Recurse -File -Include *.ps1, *.psm1, *.psd1, *.xaml, *.cs |
    Where-Object { $_.FullName -notmatch '\\(\.git|dist)\\' }

foreach ($a in $arquivos) {
    $bytes = [IO.File]::ReadAllBytes($a.FullName)
    $temBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $texto = [Text.Encoding]::UTF8.GetString($bytes, $(if ($temBom) { 3 } else { 0 }), $bytes.Length - $(if ($temBom) { 3 } else { 0 }))
    $normal = ($texto -replace "`r`n", "`n") -replace "`n", "`r`n"
    if (-not $temBom -or $normal -ne $texto) {
        [IO.File]::WriteAllText($a.FullName, $normal, $utf8Bom)
        Write-Host "  corrigido (BOM/CRLF): $($a.FullName.Substring($raiz.Length + 1))" -ForegroundColor Yellow
    }
}

foreach ($a in $arquivos | Where-Object Extension -in '.ps1', '.psm1') {
    $erros = $null
    [void][Management.Automation.Language.Parser]::ParseFile($a.FullName, [ref]$null, [ref]$erros)
    foreach ($e in $erros) {
        $falhas++
        Write-Host "  ERRO $($a.Name):$($e.Extent.StartLineNumber)  $($e.Message)" -ForegroundColor Red
    }
}

Add-Type -AssemblyName PresentationFramework
foreach ($a in $arquivos | Where-Object Extension -eq '.xaml') {
    try {
        $xml = [xml][IO.File]::ReadAllText($a.FullName, [Text.Encoding]::UTF8)
        [void][Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xml))
    } catch {
        $falhas++
        Write-Host "  ERRO XAML $($a.Name): $($_.Exception.InnerException.Message) $($_.Exception.Message)" -ForegroundColor Red
    }
}

if ($falhas -eq 0) { Write-Host "OK: $($arquivos.Count) arquivos verificados." -ForegroundColor Green; exit 0 }
Write-Host "$falhas problema(s) encontrado(s)." -ForegroundColor Red
exit 1
