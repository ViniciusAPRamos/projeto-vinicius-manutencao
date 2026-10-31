#Requires -Version 5.1
<#
    Diagnóstico do Otimizador Vinicius v2.0
    Placa de vídeo, bateria, memória e a verificação de saúde do sistema.
    Só leitura (exceto a preferência de placa por programa). Depende do nucleo.ps1.
#>

# ===============================================================
#  Placa de vídeo
# ===============================================================
function Get-InfoGpu {
    $classe = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    $vram = @{}
    foreach ($k in Get-ChildItem $classe -ErrorAction SilentlyContinue) {
        $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
        if ($p.DriverDesc -and $p.'HardwareInformation.qwMemorySize') { $vram[[string]$p.DriverDesc] = [double]$p.'HardwareInformation.qwMemorySize' }
    }
    $placas = New-Object System.Collections.Generic.List[object]
    foreach ($g in Get-CimInstance Win32_VideoController) {
        $fab = 'outra'
        if ($g.Name -match 'NVIDIA') { $fab = 'nvidia' } elseif ($g.Name -match 'AMD|Radeon') { $fab = 'amd' } elseif ($g.Name -match 'Intel') { $fab = 'intel' }
        $mem = $null
        if ($vram.ContainsKey([string]$g.Name)) { $mem = $vram[[string]$g.Name] } elseif ($g.AdapterRAM -gt 0) { $mem = [double]$g.AdapterRAM }
        # Versão NVIDIA "de verdade": 32.0.16.1656 -> 616.56
        $versao = [string]$g.DriverVersion
        if ($fab -eq 'nvidia' -and $versao -match '\.(\d+)\.(\d+)$') {
            $d = ($Matches[1] + $Matches[2]); $d = $d.Substring([math]::Max(0, $d.Length - 5))
            $versao = $d.Substring(0, $d.Length - 2) + '.' + $d.Substring($d.Length - 2)
        }
        $dias = $null
        if ($g.DriverDate) { $dias = [int]((Get-Date) - $g.DriverDate).TotalDays }
        $dedicada = $g.Name -match 'NVIDIA|Radeon RX|Radeon Pro|Arc A|Arc B'
        $placas.Add([pscustomobject]@{
            Nome = $g.Name; Fabricante = $fab; Dedicada = [bool]$dedicada
            VramGB = $(if ($mem) { [math]::Round($mem / 1GB) } else { $null })
            Driver = $versao; DriverData = $g.DriverDate; DriverDias = $dias
        })
    }
    $principal = @($placas | Sort-Object @{ e = { -not $_.Dedicada } } | Select-Object -First 1)[0]
    $r = [ordered]@{}
    $r.Placas = $placas.ToArray()
    $r.Principal = $principal
    $r.Monitores = @([Otz.Tela]::Listar() | ForEach-Object { [pscustomobject]@{ Dispositivo = $_.Dispositivo; Principal = $_.Principal; Largura = $_.Largura; Altura = $_.Altura; Hz = $_.Hz; HzMaximo = $_.HzMaximo } })
    $r.PainelNvidiaApp = Test-Path "$env:ProgramFiles\NVIDIA Corporation\NVIDIA App\CEF\NVIDIA App.exe"
    $r.PainelNvidiaCp  = [bool](Get-AppxPackage -Name 'NVIDIACorp.NVIDIAControlPanel' -ErrorAction SilentlyContinue)
    $r.PainelAmd       = Test-Path "$env:ProgramFiles\AMD\CNext\CNext\RadeonSoftware.exe"
    return [pscustomobject]$r
}

$Script:SitesDriver = @{
    nvidia = 'https://www.nvidia.com/pt-br/drivers/'
    amd    = 'https://www.amd.com/pt/support/download/drivers.html'
    intel  = 'https://www.intel.com.br/content/www/br/pt/support/detect.html'
}

# O que conferir no painel da placa, por fabricante e modo.
# Nomes das opções como aparecem nos painéis em português.
function Get-DicasPainelGpu([string]$Fabricante, [string]$Modo) {
    $d = @{
        'nvidia-desempenho' = @(
            ,@('Modo de gerenciamento de energia', 'Preferir desempenho máximo')
            ,@('Modo de baixa latência', 'Ultra (nos jogos com NVIDIA Reflex, ligue o Reflex no jogo)')
            ,@('Filtragem de textura - qualidade', 'Alto desempenho')
            ,@('Sincronização vertical', 'Desligado. Com G-SYNC, use "Ligado" aqui e desligado no jogo')
            ,@('Taxa de quadros máxima', 'Hz do monitor menos 3 (ex.: 237 em 240 Hz), se usar G-SYNC')
        )
        'nvidia-balanceado' = @(
            ,@('Modo de gerenciamento de energia', 'Normal (padrão)')
            ,@('Modo de baixa latência', 'Ligado')
            ,@('Filtragem de textura - qualidade', 'Qualidade')
            ,@('G-SYNC', 'Ligado, se o monitor for compatível (Configurar G-SYNC)')
            ,@('DLSS (dentro do jogo)', 'Qualidade ou Balanceado')
        )
        'nvidia-qualidade'  = @(
            ,@('Filtragem de textura - qualidade', 'Alta qualidade')
            ,@('Filtragem anisotrópica', 'Controlado pelo aplicativo (16x no jogo)')
            ,@('Modo de baixa latência', 'Desligado')
            ,@('DLSS (dentro do jogo)', 'Qualidade ou DLAA')
            ,@('HDR', 'Ligue "Usar HDR" no Windows se o monitor for HDR')
        )
        'amd-desempenho'    = @(
            ,@('Radeon Anti-Lag', 'Ativado')
            ,@('Radeon Boost', 'Ativado (nos jogos compatíveis)')
            ,@('Radeon Chill', 'Desativado')
            ,@('Qualidade da filtragem de textura', 'Desempenho')
            ,@('Aguardar atualização vertical', 'Desativado, a menos que o aplicativo especifique')
        )
        'amd-balanceado'    = @(
            ,@('Perfil gráfico', 'Padrão')
            ,@('Radeon Anti-Lag', 'Ativado')
            ,@('AMD FreeSync', 'Ativado, se o monitor for compatível')
            ,@('FSR (dentro do jogo)', 'Qualidade ou Balanceado')
        )
        'amd-qualidade'     = @(
            ,@('Radeon Image Sharpening', 'Ativado')
            ,@('Qualidade da filtragem de textura', 'Alta')
            ,@('AMD FreeSync', 'Ativado')
            ,@('FSR (dentro do jogo)', 'Qualidade ou Nativo (AA)')
        )
        'intel-desempenho'  = @(
            ,@('Modo de baixa latência', 'Ativado')
            ,@('XeSS (dentro do jogo)', 'Desempenho')
            ,@('Sincronização vertical', 'Desligada no jogo')
        )
        'intel-balanceado'  = @(
            ,@('XeSS (dentro do jogo)', 'Balanceado')
            ,@('Adaptive Sync', 'Ativado, se o monitor for compatível')
        )
        'intel-qualidade'   = @(
            ,@('XeSS (dentro do jogo)', 'Qualidade')
            ,@('Adaptive Sync', 'Ativado')
        )
    }
    $lista = $d["$Fabricante-$Modo"]
    if (-not $lista) { $lista = @() }
    $comuns = @(
        ,@('Driver de vídeo', 'Sempre o mais recente do site do fabricante')
        ,@('Cabo do monitor', 'Ligado na placa de vídeo, não na placa-mãe; DisplayPort ou HDMI 2.0+')
    )
    return @(@($lista) + $comuns | ForEach-Object { [pscustomobject]@{ Opcao = $_[0]; Valor = $_[1] } })
}

# Preferência de placa por programa (Configurações > Tela > Gráficos)
function Get-AppsGpu {
    $r = Get-RegRaiz $Script:ChaveDx
    $k = $r.Base.OpenSubKey($r.Sub)
    if (-not $k) { return @() }
    try {
        @(foreach ($n in $k.GetValueNames()) {
            if ($n -eq 'DirectXUserGlobalSettings' -or $n -eq '') { continue }
            $v = [string]$k.GetValue($n)
            $pref = if ($v -match 'GpuPreference=(\d)') { [int]$Matches[1] } else { 0 }
            [pscustomobject]@{ Caminho = $n; Nome = [IO.Path]::GetFileName($n); Preferencia = $pref }
        })
    } finally { $k.Close() }
}

function Set-AppGpu([string]$Caminho, [int]$Preferencia = 2) {
    Write-RegValor $Script:ChaveDx $Caminho "GpuPreference=$Preferencia;" 'String'
    Write-Log "Placa por programa: $Caminho = $Preferencia"
}

function Remove-AppGpu([string]$Caminho) {
    Remove-RegValor $Script:ChaveDx $Caminho
    Write-Log "Placa por programa removida: $Caminho"
}

# ===============================================================
#  Bateria
# ===============================================================
function Get-InfoBateria {
    $b = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $b) { return $null }
    $projeto = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue | Select-Object -First 1).DesignedCapacity
    $cheia   = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue | Select-Object -First 1).FullChargedCapacity
    $saude = $null
    if ($projeto -gt 0 -and $cheia -gt 0) { $saude = [math]::Min(100, [math]::Round(100 * $cheia / $projeto)) }
    $naTomada = $b.BatteryStatus -in 2, 3, 6, 7, 8, 9, 11
    $restante = $null
    if (-not $naTomada -and $b.EstimatedRunTime -and $b.EstimatedRunTime -lt 6000) { $restante = [int]$b.EstimatedRunTime }
    $r = [ordered]@{}
    $r.Carga = [int]$b.EstimatedChargeRemaining
    $r.NaTomada = [bool]$naTomada
    $r.MinutosRestantes = $restante
    $r.CapacidadeProjeto = $projeto
    $r.CapacidadeAtual = $cheia
    $r.Saude = $saude
    return [pscustomobject]$r
}

# ===============================================================
#  Memória
# ===============================================================
function Get-MemoriaRam {
    $os = Get-CimInstance Win32_OperatingSystem
    $total = [double]$os.TotalVisibleMemorySize * 1KB
    $livre = [double]$os.FreePhysicalMemory * 1KB
    return [pscustomobject]@{ TotalGB = [math]::Round($total / 1GB, 1); UsoGB = [math]::Round(($total - $livre) / 1GB, 1); UsoPct = [math]::Round(100 * ($total - $livre) / $total); LivreBytes = $livre }
}

# ===============================================================
#  Verificação de saúde
#  Cada função devolve checagens @{ Titulo; Texto; Nivel = ok|medio|alto|info; Acao }
#  e também as envia (evento 'checagem') para a tela ir mostrando ao vivo.
# ===============================================================
function New-Checagem([string]$Titulo, [string]$Texto, [string]$Nivel = 'ok', [string]$Acao = '') {
    $c = [pscustomobject]@{ Titulo = $Titulo; Texto = $Texto; Nivel = $Nivel; Acao = $Acao }
    Send-Evento @{ Tipo = 'checagem'; Checagem = $c }
    return $c
}

function Get-SaudeSeguranca {
    # Antivírus
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        if ($mp.AntivirusEnabled -and $mp.RealTimeProtectionEnabled) {
            New-Checagem 'Antivírus' 'Microsoft Defender ativo, com proteção em tempo real.'
        } else { throw 'Defender desligado' }
    } catch {
        $outros = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue | Where-Object { $_.displayName -notmatch 'Windows Defender|Microsoft Defender' } | ForEach-Object displayName)
        if ($outros.Count) { New-Checagem 'Antivírus' "Protegido por: $($outros -join ', ')." }
        else { New-Checagem 'Antivírus' 'A proteção em tempo real parece desligada. Abra a Segurança do Windows e confira.' 'alto' 'defender' }
    }
    # Firewall
    try {
        $desl = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { [string]$_.Enabled -ne 'True' } | ForEach-Object Name)
        if ($desl.Count -eq 0) { New-Checagem 'Firewall' 'Ligado em todas as redes (domínio, privada e pública).' }
        else { New-Checagem 'Firewall' "Desligado em: $($desl -join ', '). Deixe ligado, principalmente em redes públicas." 'alto' 'firewall' }
    } catch { New-Checagem 'Firewall' 'Não foi possível ler o estado do firewall.' 'info' }
}

function Get-SaudeAtualizacoes {
    $pendente = (Test-RegChave 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
                (Test-RegChave 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
    if ($pendente) { New-Checagem 'Reinício pendente' 'Há atualizações instaladas esperando o PC reiniciar para concluir.' 'medio' 'reiniciar' }
    else { New-Checagem 'Reinício pendente' 'Nenhuma atualização esperando reinício.' }
    try {
        $ult = Get-HotFix -ErrorAction Stop | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1
        if ($ult) {
            $dias = [int]((Get-Date) - $ult.InstalledOn).TotalDays
            if ($dias -gt 45) { New-Checagem 'Windows Update' "A última atualização foi instalada há $dias dias ($($ult.InstalledOn.ToString('dd/MM/yyyy'))). Verifique se há novas." 'medio' 'windowsupdate' }
            else { New-Checagem 'Windows Update' "Atualizado: última atualização há $dias dia(s)." }
        }
    } catch { New-Checagem 'Windows Update' 'Não foi possível ler o histórico de atualizações.' 'info' 'windowsupdate' }
}

function Get-SaudeHardware($Info) {
    if ($Info.DiscoTipo -eq 'HDD') { New-Checagem 'Disco do sistema' 'O Windows está em HD mecânico. Trocar por SSD é a melhoria de maior impacto.' 'alto' }
    else { New-Checagem 'Disco do sistema' "Windows em $($Info.DiscoTipo)." }
    if ($null -ne $Info.DiscoLivre) {
        if ($Info.DiscoLivre -lt 15) { New-Checagem 'Espaço livre' "Só $($Info.DiscoLivreGB) GB livres ($($Info.DiscoLivre)%). Abaixo de 15% o Windows fica lento." 'alto' 'limpeza' }
        else { New-Checagem 'Espaço livre' "$($Info.DiscoLivreGB) GB livres ($($Info.DiscoLivre)%) no disco do sistema." }
    }
    $ruins = @($Info.Discos | Where-Object { $_.Saude -and $_.Saude -ne 'Healthy' })
    if ($ruins.Count) { New-Checagem 'Saúde dos discos' "Disco com problema: $(($ruins | ForEach-Object Nome) -join ', '). Faça backup." 'alto' 'relatorio' }
    else { New-Checagem 'Saúde dos discos' "$(@($Info.Discos).Count) disco(s) sem falhas relatadas." }
    $pentes = @($Info.Pentes)
    $abaixo = @($pentes | Where-Object { $_.Atual -and $_.Nominal -and $_.Atual -lt $_.Nominal })
    $txtRam = "$($Info.RamGB) GB em $($pentes.Count) pente(s)"
    if ($pentes.Count -eq 1) { New-Checagem 'Memória RAM' "$($txtRam): rodando em single channel. Um segundo pente igual aumenta o desempenho." 'medio' }
    elseif ($abaixo.Count) { New-Checagem 'Memória RAM' "$($txtRam), mas a $($abaixo[0].Atual) MT/s, abaixo dos $($abaixo[0].Nominal) do pente. Ative o XMP/EXPO na BIOS." 'medio' }
    elseif ($Info.RamGB -lt 8) { New-Checagem 'Memória RAM' "$($txtRam): pouco para o uso atual. 16 GB é o recomendado." 'alto' }
    else { New-Checagem 'Memória RAM' "$($txtRam), na velocidade correta." }
}

function Get-SaudeVideo {
    $g = Get-InfoGpu
    $p = $g.Principal
    if ($p -and $null -ne $p.DriverDias) {
        $data = $p.DriverData.ToString('dd/MM/yyyy')
        if ($p.DriverDias -gt 180) { New-Checagem 'Driver de vídeo' "$($p.Nome): driver $($p.Driver) de $data (há $([math]::Round($p.DriverDias / 30)) meses). Atualize pelo site do fabricante." 'medio' 'video' }
        else { New-Checagem 'Driver de vídeo' "$($p.Nome): driver $($p.Driver) de $data." }
    }
    foreach ($m in $g.Monitores) {
        $nome = if ($m.Principal) { 'Monitor principal' } else { "Monitor $($m.Dispositivo -replace '\\\\\.\\DISPLAY', '')" }
        if ($m.Hz -lt $m.HzMaximo) { New-Checagem $nome "$($m.Largura)x$($m.Altura) em $($m.Hz) Hz, mas aceita $($m.HzMaximo) Hz." 'medio' 'gpu.hz-maximo' }
        else { New-Checagem $nome "$($m.Largura)x$($m.Altura) na taxa máxima ($($m.Hz) Hz)." }
    }
    return $g
}

function Get-SaudeManutencao($Info) {
    if ($Info.Inicializacao -gt 10) { New-Checagem 'Inicialização' "$($Info.Inicializacao) programas abrem com o Windows. Desligue os desnecessários." 'medio' 'inicializacao' }
    else { New-Checagem 'Inicialização' "$($Info.Inicializacao) programa(s) abrem com o Windows." }
    $temp = Get-TamanhoPastas @($env:TEMP, "$env:SystemRoot\Temp")
    if ($temp -gt 1GB) { New-Checagem 'Arquivos temporários' "$(Format-Tamanho $temp) em temporários podem ser apagados." 'medio' 'limpeza' }
    else { New-Checagem 'Arquivos temporários' "Só $(Format-Tamanho $temp) em temporários." }
    if ($Info.Uptime.TotalDays -gt 7) { New-Checagem 'Tempo ligado' "Ligado há $([math]::Floor($Info.Uptime.TotalDays)) dias sem reiniciar. Reinicie para liberar memória." 'medio' 'reiniciar' }
    else { New-Checagem 'Tempo ligado' "Ligado há $($Info.UptimeTexto)." }
}

# Pior nível de uma lista de checagens (para o ícone da etapa)
function Get-PiorNivel($Checagens) {
    $n = @($Checagens | ForEach-Object Nivel)
    if ($n -contains 'alto') { return 'alto' }
    if ($n -contains 'medio') { return 'medio' }
    return 'ok'
}
# ===============================================================
#  Nota do PC sem janela + histórico de verificações (evolução)
#  Mesma conta da página Verificar: 60% ajustes recomendados aplicados
#  + 40% checagens de saúde sem problema.
# ===============================================================
function Measure-NotaPc {
    $winReal = if ($Script:Otz.IsWin11) { '11' } else { '10' }
    $base = 0; $aplicados = 0
    foreach ($i in Get-Catalogo) {
        if ($i.Tipo -eq 'acao' -or @($i.Perfis).Count -eq 0) { continue }
        if (-not (Test-Compativel $i $winReal).Ok) { continue }
        $e = (Get-EstadoAjuste $i).Estado
        if ($e -eq 'na') { continue }
        $base++
        if ($e -eq 'aplicado') { $aplicados++ }
    }
    $info = Get-InfoPC
    $checks = @(@(Get-SaudeSeguranca) + @(Get-SaudeAtualizacoes) + @(Get-SaudeHardware $info) + @(Get-SaudeVideo | Where-Object { $_.Titulo }) + @(Get-SaudeManutencao $info))
    $validos = @($checks | Where-Object { $_.Nivel -ne 'info' })
    $fracA = if ($base) { $aplicados / $base } else { 1 }
    $fracS = if ($validos.Count) { @($validos | Where-Object Nivel -eq 'ok').Count / $validos.Count } else { 1 }
    $r = [ordered]@{}
    $r.Nota = [int][math]::Round(60 * $fracA + 40 * $fracS)
    $r.Ajustes = "$aplicados/$base"
    $r.Problemas = @($validos | Where-Object { $_.Nivel -in 'medio', 'alto' }).Count
    return [pscustomobject]$r
}

function Save-Verificacao([int]$Nota, [string]$Ajustes, [int]$Problemas, [string]$Origem = 'manual') {
    $arq = Join-Path $Script:Otz.Dados 'verificacoes.jsonl'
    $linha = (ConvertTo-Json -Compress -InputObject ([ordered]@{ Data = (Get-Date).ToString('s'); Nota = $Nota; Ajustes = $Ajustes; Problemas = $Problemas; Origem = $Origem })) + [Environment]::NewLine
    [IO.File]::AppendAllText($arq, $linha, (New-Object Text.UTF8Encoding $false))
}

function Get-Verificacoes([int]$Max = 30) {
    $arq = Join-Path $Script:Otz.Dados 'verificacoes.jsonl'
    if (-not (Test-Path $arq)) { return @() }
    $linhas = @([IO.File]::ReadAllLines($arq, [Text.Encoding]::UTF8) | Where-Object { $_.Trim() })
    $ini = [math]::Max(0, $linhas.Count - $Max)
    $res = New-Object System.Collections.Generic.List[object]
    for ($i = $ini; $i -lt $linhas.Count; $i++) { try { $res.Add(($linhas[$i] | ConvertFrom-Json)) } catch { } }
    return $res.ToArray()
}
# ===============================================================
#  Monitor de conexão: 1 ping por segundo em cada alvo
#  $Controle é um hashtable sincronizado compartilhado com a janela:
#  quando a janela põe Parar = $true, o laço termina.
# ===============================================================
function Get-GatewayPadrao {
    return [string](Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
}

function Watch-Conexao($Alvos, $Controle) {
    $ping = [Net.NetworkInformation.Ping]::new()
    try {
        while (-not $Controle.Parar) {
            $ini = Get-Date
            foreach ($a in $Alvos) {
                $ms = $null
                try { $r = $ping.Send([string]$a.Endereco, 1000); if ($r.Status -eq 'Success') { $ms = [int]$r.RoundtripTime } } catch { }
                Send-Evento @{ Tipo = 'ping'; Chave = $a.Chave; Ms = $ms }
            }
            $resto = 1000 - ((Get-Date) - $ini).TotalMilliseconds
            if ($resto -gt 0) { Start-Sleep -Milliseconds ([int]$resto) }
        }
    } finally { $ping.Dispose() }
}