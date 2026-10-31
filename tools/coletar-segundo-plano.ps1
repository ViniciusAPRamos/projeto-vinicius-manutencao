#Requires -Version 5.1
<#
    Coleta (SÓ LEITURA) do que roda em segundo plano, para calibrar a
    "Limpar o segundo plano". Não altera nada no PC.

    Uso (PowerShell como administrador, de preferência 3 min depois de ligar):
      powershell -NoProfile -ExecutionPolicy Bypass -File tools\coletar-segundo-plano.ps1

    Gera segundo-plano-<PC>.json na Área de Trabalho.
    -SemAssinatura pula a conferência de assinatura digital (mais rápido;
    use se travar sem internet).
#>
param([switch]$SemAssinatura)

$ErrorActionPreference = 'SilentlyContinue'
$inicioGeral = Get-Date
$saida = Join-Path ([Environment]::GetFolderPath('Desktop')) "segundo-plano-$env:COMPUTERNAME.json"

function Write-Etapa([string]$Texto) { Write-Host ("[{0:mm\:ss}] {1}" -f ((Get-Date) - $inicioGeral), $Texto) -ForegroundColor Cyan }

function Get-Exe([string]$Linha) {
    if (-not $Linha) { return '' }
    $l = [Environment]::ExpandEnvironmentVariables($Linha.Trim())
    if ($l -match '^"([^"]+)"') { return $Matches[1] }
    if ($l -match '^(.+?\.exe)') { return $Matches[1] }
    return $l
}

# Fabricante e assinatura, com cache por arquivo (o mesmo .exe aparece em serviço, processo e inicialização)
$cacheArquivo = @{}
function Get-InfoArquivo([string]$Caminho) {
    if (-not $Caminho) { $Caminho = '' }
    if ($cacheArquivo.ContainsKey($Caminho)) { return $cacheArquivo[$Caminho] }
    $r = [ordered]@{}
    $r.Empresa = ''; $r.Descricao = ''; $r.Assinante = ''; $r.Assinatura = ''
    if ($Caminho -and (Test-Path -LiteralPath $Caminho -PathType Leaf)) {
        $v = (Get-Item -LiteralPath $Caminho).VersionInfo
        $r.Empresa = [string]$v.CompanyName
        $r.Descricao = [string]$v.FileDescription
        if (-not $SemAssinatura) {
            # Assinatura embutida no arquivo: não consulta a internet
            try {
                $cert = [Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($Caminho)
                $r.Assinante = ([Security.Cryptography.X509Certificates.X509Certificate2]$cert).GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
                $r.Assinatura = 'embutida'
            } catch { $r.Assinatura = 'sem assinatura embutida' }
        }
    }
    $cacheArquivo[$Caminho] = $r
    return $r
}

Write-Etapa 'Memoria dos processos...'
$mem = @{}
foreach ($p in Get-CimInstance Win32_PerfRawData_PerfProc_Process -Property IDProcess, WorkingSetPrivate -OperationTimeoutSec 30) { $mem[[int]$p.IDProcess] = [double]$p.WorkingSetPrivate }
# Memória por executável (para os serviços, sem depender do WMI)
$memPorExe = @{}
foreach ($p in Get-Process) {
    if (-not $p.Path) { continue }
    $k = $p.Path.ToLowerInvariant()
    if (-not $memPorExe.ContainsKey($k)) { $memPorExe[$k] = 0.0 }
    $memPorExe[$k] += $mem[[int]$p.Id]
}

# Serviços pelo Gerenciador de Serviços + registro. O Win32_Service (WMI) trava
# em alguns PCs quando um serviço/driver de terceiros não responde.
Write-Etapa 'Servicos...'
$servicos = New-Object System.Collections.Generic.List[object]
$modos = @{ 2 = 'Auto'; 3 = 'Manual'; 4 = 'Disabled' }
$n = 0
foreach ($s in Get-Service) {
    $n++
    if ($n % 50 -eq 0) { Write-Etapa "  ... $n lidos" }
    $reg = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.Name)"
    $imagem = [string]$reg.ImagePath
    if ($imagem -match 'svchost\.exe') { continue }
    $inicioModo = $modos[[int]$reg.Start]
    if (-not $inicioModo) { $inicioModo = [string]$reg.Start }
    if ($inicioModo -ne 'Auto' -and [string]$s.Status -ne 'Running') { continue }
    $exe = Get-Exe $imagem
    $r = [ordered]@{}
    $r.Nome = $s.Name; $r.Exibicao = $s.DisplayName; $r.Inicio = $inicioModo; $r.Estado = [string]$s.Status
    $r.AtrasoAuto = ([int]$reg.DelayedAutostart -eq 1); $r.Exe = $exe
    $r.MB = 0
    if ($exe -and $memPorExe.ContainsKey($exe.ToLowerInvariant())) { $r.MB = [math]::Round($memPorExe[$exe.ToLowerInvariant()] / 1MB) }
    $r.Dependentes = @($s.DependentServices | ForEach-Object Name)
    $r.Arquivo = Get-InfoArquivo $exe
    $servicos.Add([pscustomobject]$r)
}
Write-Etapa "  $($servicos.Count) servico(s)"

Write-Etapa 'Inicializacao...'
$aprovados = @{}
foreach ($raiz in 'HKCU:', 'HKLM:') {
    foreach ($sub in 'Run', 'Run32', 'StartupFolder') {
        $item = Get-Item "$raiz\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\$sub"
        if (-not $item) { continue }
        foreach ($n in $item.GetValueNames()) {
            $b = $item.GetValue($n)
            if ($b -and $b.Length) { $aprovados["$raiz|$sub|$n"] = '{0:X2}' -f $b[0] }
        }
    }
}
$inicio = New-Object System.Collections.Generic.List[object]
$chavesRun = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
)
foreach ($k in $chavesRun) {
    $item = Get-Item $k
    if (-not $item) { continue }
    foreach ($n in $item.GetValueNames()) {
        $cmd = [string]$item.GetValue($n)
        $exe = Get-Exe $cmd
        $r = [ordered]@{}
        $r.Nome = $n; $r.Comando = $cmd; $r.Local = $k; $r.Exe = $exe
        $r.Arquivo = Get-InfoArquivo $exe
        $inicio.Add([pscustomobject]$r)
    }
}
foreach ($pasta in @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup'))) {
    foreach ($f in @(Get-ChildItem -LiteralPath $pasta -File)) {
        $r = [ordered]@{}
        $r.Nome = $f.Name; $r.Comando = $f.FullName; $r.Local = $pasta; $r.Exe = $f.FullName
        $r.Arquivo = Get-InfoArquivo ''
        $inicio.Add([pscustomobject]$r)
    }
}
Write-Etapa "  $($inicio.Count) item(ns)"

Write-Etapa 'Tarefas agendadas (fora da Microsoft)...'
$tarefas = New-Object System.Collections.Generic.List[object]
foreach ($t in Get-ScheduledTask) {
    if ($t.TaskPath -like '\Microsoft\*') { continue }
    $r = [ordered]@{}
    $r.Nome = $t.TaskName; $r.Pasta = $t.TaskPath; $r.Estado = [string]$t.State; $r.Autor = [string]$t.Author
    $r.Acoes = @($t.Actions | ForEach-Object { ("$($_.Execute) $($_.Arguments)").Trim() })
    $r.Gatilhos = @($t.Triggers | ForEach-Object { $_.CimClass.CimClassName })
    $tarefas.Add([pscustomobject]$r)
}
Write-Etapa "  $($tarefas.Count) tarefa(s)"

Write-Etapa 'Processos...'
$processos = New-Object System.Collections.Generic.List[object]
foreach ($g in (Get-Process | Group-Object ProcessName)) {
    $soma = 0.0; $janela = $false; $caminho = ''
    foreach ($p in $g.Group) {
        $soma += $mem[[int]$p.Id]
        if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $janela = $true }
        if (-not $caminho -and $p.Path) { $caminho = $p.Path }
    }
    $r = [ordered]@{}
    $r.Nome = $g.Name; $r.Qtd = $g.Count; $r.MB = [math]::Round($soma / 1MB); $r.Janela = $janela; $r.Exe = $caminho
    $r.Arquivo = Get-InfoArquivo $caminho
    $processos.Add([pscustomobject]$r)
}
Write-Etapa "  $($processos.Count) programa(s) em execucao"

Write-Etapa 'Programas instalados e apps...'
$programas = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' |
    Where-Object { $_.DisplayName -and -not $_.SystemComponent } | Select-Object DisplayName, Publisher, DisplayVersion, EstimatedSize, InstallDate)
$apps = @(Get-AppxPackage | Where-Object { -not $_.IsFramework } | ForEach-Object Name)

$os = Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 20
$pm = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -OperationTimeoutSec 20
$resumo = [ordered]@{}
$resumo.PC = $env:COMPUTERNAME
$resumo.Data = (Get-Date).ToString('s')
$resumo.Windows = [string](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion
$resumo.Modelo = [string](Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 20).Model
$resumo.MinutosLigado = [int]((Get-Date) - $os.LastBootUpTime).TotalMinutes
$resumo.TotalMB = [int]($os.TotalVisibleMemorySize / 1KB)
$resumo.DisponivelMB = [int]$pm.AvailableMBytes
$resumo.ComprometidaMB = [int]($pm.CommittedBytes / 1MB)
$resumo.PoolNaoPaginadoMB = [int]($pm.PoolNonpagedBytes / 1MB)
$resumo.PoolPaginadoMB = [int]($pm.PoolPagedBytes / 1MB)

$tudo = [ordered]@{}
$tudo.Resumo = $resumo
$tudo.Servicos = $servicos.ToArray()
$tudo.Inicializacao = $inicio.ToArray()
$tudo.Aprovados = $aprovados
$tudo.Tarefas = $tarefas.ToArray()
$tudo.Processos = $processos.ToArray()
$tudo.Programas = $programas
$tudo.Apps = $apps
$resumo.WmiServicos = 'nao testado'
[IO.File]::WriteAllText($saida, (ConvertTo-Json -InputObject $tudo -Depth 6), (New-Object Text.UTF8Encoding $false))
Write-Etapa "Arquivo salvo: $saida"

# Diagnóstico por último (o arquivo já está salvo se travar aqui):
# o WMI de serviços responde neste PC? O otimizador usa essa consulta.
Write-Etapa 'Testando a consulta de servicos do WMI (ate 20 s; pode fechar se travar)...'
$cron = [Diagnostics.Stopwatch]::StartNew()
$teste = @(Get-CimInstance Win32_Service -Property Name -OperationTimeoutSec 20 -ErrorVariable errWmi)
$resumo.WmiServicos = if ($errWmi -or -not $teste.Count) { "falhou: $($errWmi | Select-Object -First 1)" } else { "ok, $($teste.Count) servicos" }
$resumo.WmiServicos += " em $([math]::Round($cron.Elapsed.TotalSeconds, 1)) s"
[IO.File]::WriteAllText($saida, (ConvertTo-Json -InputObject $tudo -Depth 6), (New-Object Text.UTF8Encoding $false))
Write-Etapa "  WMI de servicos: $($resumo.WmiServicos)"
Write-Etapa "Pronto: $saida"
