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
# ===============================================================
#  Suporte técnico
# ===============================================================
# Texto pronto para colar num chamado / WhatsApp do suporte
function Get-ResumoChamado {
    $genericos = 'Default string|To be filled|System Product Name|System manufacturer|O\.E\.M\.|^None$|^\s*$'
    $info = Get-InfoPC
    $cs = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $l = New-Object System.Collections.Generic.List[string]
    $l.Add("=== Resumo do PC para suporte ===")
    $l.Add("Gerado em: $(Get-Date -Format 'dd/MM/yyyy HH:mm')")
    $l.Add("Computador: $env:COMPUTERNAME  |  Usuário: $env:USERDOMAIN\$env:USERNAME")
    $modelo = (@($cs.Manufacturer, $cs.Model) | Where-Object { $_ -and $_ -notmatch $genericos }) -join ' '
    if ($modelo) { $l.Add("Modelo: $modelo") }
    if ($info.PlacaMae -and $info.PlacaMae -ne $modelo) { $l.Add("Placa-mãe: $($info.PlacaMae)") }
    if ($bios.SerialNumber -and $bios.SerialNumber -notmatch $genericos) { $l.Add("Número de série: $($bios.SerialNumber)") }
    $l.Add("Windows: $($info.Sistema) $($info.VersaoWin) (build $($Script:Otz.Build).$($Script:Otz.Ubr))")
    $l.Add("Processador: $($info.Cpu) ($($info.Threads) threads)")
    $l.Add("Memória: $($info.RamGB) GB ($($info.RamUso)% em uso agora)")
    $l.Add("Disco do sistema: $($info.DiscoTipo), $($info.DiscoLivreGB) GB livres ($($info.DiscoLivre)%)")
    if ($info.GpuNome) { $l.Add("Placa de vídeo: $($info.GpuNome)") }
    $l.Add("Ligado há: $($info.UptimeTexto)")
    foreach ($a in Get-AdaptadoresRede) {
        $mac = (Get-NetAdapter -InterfaceIndex $a.Index -ErrorAction SilentlyContinue).MacAddress
        $l.Add("Rede ($($a.Tipo)) $($a.Nome): IP $($a.Ip)  |  DNS $($a.Dns)  |  MAC $mac  |  $($a.Velocidade)")
    }
    $gw = Get-GatewayPadrao
    if ($gw) { $l.Add("Gateway (roteador): $gw") }
    $any = Get-IdAnyDesk
    if ($any) { $l.Add("AnyDesk ID: $any") }
    return ($l -join "`r`n")
}

function Get-IdAnyDesk {
    foreach ($arq in "$env:ProgramData\AnyDesk\system.conf", "$env:APPDATA\AnyDesk\system.conf") {
        if (-not (Test-Path $arq)) { continue }
        try {
            $linha = Get-Content $arq -ErrorAction Stop | Where-Object { $_ -match '^ad\.anynet\.id=' } | Select-Object -First 1
            if ($linha) { return ($linha -split '=', 2)[1].Trim() }
        } catch { }
    }
    return $null
}

# Redes Wi-Fi salvas e senhas (o mesmo que o Windows mostra nas propriedades da rede)
function Get-SenhasWifi {
    $saida = (netsh wlan show profiles 2>&1) -join "`n"
    if ($saida -match 'interface sem fio|wireless interface|WLAN AutoConfig|Servi.o Configura..o Autom.tica de WLAN') {
        return [pscustomobject]@{ SemWifi = $true; Redes = @(); Mensagem = 'Este PC não tem placa Wi-Fi (ou o serviço de Wi-Fi está desligado).' }
    }
    $redes = New-Object System.Collections.Generic.List[object]
    $secao = $false
    foreach ($linha in ($saida -split "`n")) {
        if ($linha -match 'Perfis de usu|User profiles') { $secao = $true; continue }
        if (-not $secao) { continue }
        if ($linha -match '^\s+.+?\s:\s(.+)$') {
            $nome = $Matches[1].Trim()
            $det = (netsh wlan show profile name="$nome" key=clear 2>&1) -join "`n"
            $senha = ''
            if ($det -match '(Key Content|Conte.do da [Cc]have)\s*:\s*(.+)') { $senha = $Matches[2].Trim() }
            $redes.Add([pscustomobject]@{ Nome = $nome; Senha = $senha })
        }
    }
    return [pscustomobject]@{ SemWifi = $false; Redes = $redes.ToArray(); Mensagem = '' }
}

# Assistência Rápida: abre se instalada; senão informa (a instalação é pelo winget/Store)
function Get-AppIdAssistenciaRapida {
    $app = Get-StartApps -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Quick Assist|Assist.ncia R.pida' } | Select-Object -First 1
    if ($app) { return [string]$app.AppID }
    return $null
}

# ===============================================================
#  Temperaturas (sem programas extras)
#  - Placa de vídeo NVIDIA: nvidia-smi (vem com o driver)
#  - Discos: contador de confiabilidade do Windows
#  - Processador: sensor ACPI, se a placa-mãe expuser (muitos desktops não expõem)
# ===============================================================
function Get-Temperaturas {
    $res = New-Object System.Collections.Generic.List[object]
    $smi = "$env:SystemRoot\System32\nvidia-smi.exe"
    if (Test-Path $smi) {
        $linhas = & $smi --query-gpu=name,temperature.gpu,utilization.gpu,power.draw,fan.speed --format=csv,noheader,nounits 2>$null
        foreach ($l in @($linhas)) {
            $p = $l -split ',\s*'
            if ($p.Count -ge 5 -and $p[1] -match '^\d+') {
                $t = [int]$p[1]
                $nivel = if ($t -ge 85) { 'alto' } elseif ($t -ge 76) { 'medio' } else { 'ok' }
                $fan = if ($p[4] -match '^\d+') { "ventoinha $($p[4])%" } else { 'ventoinha -' }
                $pw = if ($p[3] -match '^[\d.]+') { "$([math]::Round([double]::Parse($p[3], [Globalization.CultureInfo]::InvariantCulture))) W" } else { '' }
                $res.Add([pscustomobject]@{ Nome = $p[0].Trim(); Tipo = 'Placa de vídeo'; Celsius = $t; Nivel = $nivel; Detalhe = "uso $($p[2])%  ·  $pw  ·  $fan"; Limite = 'Normal até ~75 °C em jogo; acima de 85 °C, limpe a poeira e confira o fluxo de ar.' })
            }
        }
    }
    foreach ($d in @(Get-PhysicalDisk -ErrorAction SilentlyContinue)) {
        $r = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        if (-not $r -or -not $r.Temperature) { continue }
        $t = [int]$r.Temperature
        $ehNvme = [string]$d.BusType -eq 'NVMe'
        $lim = if ($ehNvme) { 70 } elseif ([string]$d.MediaType -eq 'HDD') { 50 } else { 60 }
        $nivel = if ($t -ge $lim) { 'alto' } elseif ($t -ge $lim - 10) { 'medio' } else { 'ok' }
        $tipo = if ($ehNvme) { 'SSD NVMe' } else { "$($d.MediaType)" }
        $res.Add([pscustomobject]@{ Nome = $d.FriendlyName; Tipo = "Disco ($tipo)"; Celsius = $t; Nivel = $nivel; Detalhe = "limite confortável: ~$lim °C"; Limite = "Acima de $lim °C o disco pode reduzir a velocidade para se proteger." })
    }
    $cpu = @(Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue)
    foreach ($z in $cpu) {
        $t = [math]::Round($z.CurrentTemperature / 10 - 273.15)
        if ($t -le 0 -or $t -ge 120) { continue }
        $nivel = if ($t -ge 90) { 'alto' } elseif ($t -ge 80) { 'medio' } else { 'ok' }
        $res.Add([pscustomobject]@{ Nome = 'Sensor da placa-mãe (ACPI)'; Tipo = 'Processador (aproximado)'; Celsius = [int]$t; Nivel = $nivel; Detalhe = 'zona térmica informada pela BIOS'; Limite = 'É uma leitura aproximada. Para a temperatura exata do processador, use o HWMonitor.' })
    }
    return [pscustomobject]@{ Sensores = $res.ToArray(); SemCpu = ($cpu.Count -eq 0) }
}

function Watch-Temperaturas($Controle) {
    while (-not $Controle.Parar) {
        $t = Get-Temperaturas
        Send-Evento @{ Tipo = 'temp'; Dados = $t }
        for ($i = 0; $i -lt 20 -and -not $Controle.Parar; $i++) { Start-Sleep -Milliseconds 100 }
    }
}