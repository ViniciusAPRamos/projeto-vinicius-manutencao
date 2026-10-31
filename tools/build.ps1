#Requires -Version 5.1
<#
    Monta o TechPulse: pasta pronta (dist\app) + instalador (dist\TechPulse-Setup-<versão>.exe).
    Usado aqui e no GitHub Actions (.github\workflows\release.yml).

      powershell -NoProfile -ExecutionPolicy Bypass -File tools\build.ps1                 (versão do versao.txt)
      powershell -NoProfile -ExecutionPolicy Bypass -File tools\build.ps1 -Versao 2.1.0.15 -Canal teste
      -SemInstalador   só monta dist\app (não precisa do Inno Setup)
#>
param(
    [string]$Versao,
    [ValidateSet('estavel', 'teste')][string]$Canal = 'estavel',
    [switch]$SemInstalador
)
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
if (-not $Versao) { $Versao = ([IO.File]::ReadAllText((Join-Path $raiz 'versao.txt'))).Trim() }
if ($Versao -notmatch '^\d+\.\d+\.\d+(\.\d+)?$') { throw "Versão inválida: '$Versao' (use 2.1.0 ou 2.1.0.15)" }

$dist = Join-Path $raiz 'dist'
$stage = Join-Path $dist 'app'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

Write-Host "TechPulse $Versao ($Canal)" -ForegroundColor Cyan

# 1. Arquivos do app
Copy-Item (Join-Path $raiz 'src') (Join-Path $stage 'src') -Recurse
Get-ChildItem (Join-Path $stage 'src') -Filter 'winget-lista.txt' -Recurse | Remove-Item -Force
[IO.File]::WriteAllText((Join-Path $stage 'src\versao.txt'), $Versao)
[IO.File]::WriteAllText((Join-Path $stage 'src\canal.txt'), $Canal)
Copy-Item (Join-Path $raiz 'CHANGELOG.md') $stage
Copy-Item (Join-Path $raiz 'assets\techpulse.ico') $stage

# 2. TechPulse.exe (C# 5 do .NET Framework que já vem no Windows)
$csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $csc /nologo /target:winexe /optimize+ "/out:$(Join-Path $stage 'TechPulse.exe')" `
    "/win32icon:$(Join-Path $raiz 'assets\techpulse.ico')" "/win32manifest:$(Join-Path $raiz 'installer\TechPulse.manifest')" `
    /reference:System.Windows.Forms.dll /reference:System.Core.dll (Join-Path $raiz 'installer\Launcher.cs')
if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar o TechPulse.exe' }
Write-Host '  TechPulse.exe compilado' -ForegroundColor Green
if ($SemInstalador) { Write-Host "Pronto: $stage"; return }

# 3. Instalador (Inno Setup 6)
$iscc = @(
    (Get-Command iscc.exe -ErrorAction SilentlyContinue).Source
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 não encontrado. Instale com: winget install --id JRSoftware.InnoSetup -e' }
& $iscc /Q "/DAppVersion=$Versao" "/DStage=$stage" "/DOutDir=$dist" (Join-Path $raiz 'installer\TechPulse.iss')
if ($LASTEXITCODE -ne 0) { throw 'Falha ao gerar o instalador' }
$setup = Join-Path $dist "TechPulse-Setup-$Versao.exe"
Write-Host "Pronto: $setup ($([math]::Round((Get-Item $setup).Length / 1MB, 1)) MB)" -ForegroundColor Green
