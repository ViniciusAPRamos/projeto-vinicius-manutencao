#Requires -Version 5.1
<#
    Análises que explicam o PC (Otimizador Vinicius v2.0)
      - Get-DiagnosticoLentidao   "Por que está lento agora?"
      - Get-HistoricoBoot         tempo real de inicialização e o que atrasou
      - Get-Medicao / *Referencia antes × depois da otimização
      - Get-Estabilidade          desligamentos inesperados, telas azuis, travamentos
      - Get-QualidadeConexao      velocidade do cabo e sinal do Wi-Fi
      - Get-ChecklistBios         UEFI, Secure Boot, TPM, XMP, Resizable BAR
    Só LEITURA: nada aqui altera o sistema. Depende do nucleo.ps1.
#>

function New-Achado([string]$Titulo, [string]$Texto, [string]$Nivel = 'ok', [string]$Acao = '', [string]$Rotulo = '') {
    $r = [ordered]@{}
    $r.Titulo = $Titulo; $r.Texto = $Texto; $r.Nivel = $Nivel; $r.Acao = $Acao; $r.Rotulo = $Rotulo
    return [pscustomobject]$r
}

# ===============================================================
#  1. Por que está lento agora?
#  Duas leituras dos contadores "brutos" de processo (rápidas e iguais em
#  qualquer idioma, ao contrário do Get-Counter) com 1,5 s entre elas.
# ===============================================================
$Script:ExplicaProcesso = @{
    'MsMpEng'            = 'Antivírus (Microsoft Defender) verificando arquivos. Costuma passar em alguns minutos.'
    'MpDefenderCoreService' = 'Antivírus (Microsoft Defender). Costuma passar em alguns minutos.'
    'TiWorker'           = 'Windows Update instalando atualizações. Deixe terminar; reinicie quando pedir.'
    'TrustedInstaller'   = 'Windows Update instalando atualizações. Deixe terminar; reinicie quando pedir.'
    'MoUsoCoreWorker'    = 'Windows Update procurando ou baixando atualizações.'
    'SearchIndexer'      = 'Indexação da pesquisa do Windows (normal depois de copiar muitos arquivos). Pode ser ajustada na página Serviços.'
    'SearchProtocolHost' = 'Indexação da pesquisa do Windows.'
    'CompatTelRunner'    = 'Telemetria de compatibilidade da Microsoft. Pode ser desligada na página Serviços.'
    'OneDrive'           = 'OneDrive sincronizando arquivos.'
    'dwm'                = 'Gerenciador de janelas (desenha a tela). Uso alto costuma ser driver de vídeo ou muitos monitores/efeitos.'
    'System'             = 'Núcleo do Windows e drivers. Uso alto e constante costuma ser driver com problema.'
    'Memory Compression' = 'Memória comprimida pelo Windows: sinal de que a RAM está apertada.'
    'explorer'           = 'Explorador de arquivos e barra de tarefas.'
    'chrome'             = 'Google Chrome (cada aba é um processo).'
    'msedge'             = 'Microsoft Edge (cada aba é um processo).'
    'firefox'            = 'Mozilla Firefox.'
    'WmiPrvSE'           = 'Serviço de informações do sistema (inclui a própria medição deste otimizador).'
    'svchost'            = 'Serviços do Windows agrupados.'
}
# Processos que o botão "Finalizar" nunca oferece
$Script:ProcessosProtegidos = @('System', 'Idle', 'Registry', 'smss', 'csrss', 'wininit', 'winlogon', 'services', 'lsass', 'svchost', 'dwm', 'fontdrvhost',
    'Memory Compression', 'sihost', 'ctfmon', 'MsMpEng', 'MpDefenderCoreService', 'NisSrv', 'SecurityHealthService', 'TiWorker', 'TrustedInstaller',
    'audiodg', 'spoolsv', 'WmiPrvSE', 'conhost', 'RuntimeBroker', 'SearchIndexer', 'StartMenuExperienceHost', 'ShellExperienceHost', 'TextInputHost', 'LsaIso', 'Secure System', 'vmmem', 'powershell')

function Get-AmostraDesempenho {
    $r = @{}
    $r.Proc = @(Get-CimInstance Win32_PerfRawData_PerfProc_Process -Property Name, IDProcess, PercentProcessorTime, WorkingSetPrivate, IODataBytesPersec, Timestamp_Sys100NS -ErrorAction SilentlyContinue)
    $r.Disco = @(Get-CimInstance Win32_PerfRawData_PerfDisk_PhysicalDisk -Property Name, PercentIdleTime, Timestamp_Sys100NS -ErrorAction SilentlyContinue)
    return $r
}

function Get-DiagnosticoLentidao([int]$JanelaMs = 1500) {
    $nucleos = [Environment]::ProcessorCount
    $a1 = Get-AmostraDesempenho
    Start-Sleep -Milliseconds $JanelaMs
    $a2 = Get-AmostraDesempenho

    # CPU e E/S por processo (diferença entre as duas leituras)
    $antes = @{}
    foreach ($p in $a1.Proc) { $antes["$($p.IDProcess)|$($p.Name)"] = $p }
    $grupos = @{}
    $cpuTotal = 0.0
    foreach ($p in $a2.Proc) {
        if ($p.Name -eq '_Total' -or $p.Name -eq 'Idle' -or $p.IDProcess -eq [uint32]$PID) { continue }
        $p0 = $antes["$($p.IDProcess)|$($p.Name)"]
        $cpu = 0.0; $io = 0.0
        if ($p0) {
            $dt = [double]($p.Timestamp_Sys100NS - $p0.Timestamp_Sys100NS)
            if ($dt -gt 0) {
                $cpu = [math]::Max(0, [double]($p.PercentProcessorTime - $p0.PercentProcessorTime) / $dt / $nucleos * 100)
                $io = [math]::Max(0, [double]($p.IODataBytesPersec - $p0.IODataBytesPersec) / ($dt / 1e7))
            }
        }
        $cpuTotal += $cpu
        $nome = $p.Name -replace '#\d+$', ''
        if (-not $grupos.ContainsKey($nome)) {
            $g = [ordered]@{}
            $g.Nome = $nome; $g.Descricao = ''; $g.Cpu = 0.0; $g.Ram = [double]0; $g.Io = 0.0; $g.Qtd = 0; $g.Id = [int]$p.IDProcess
            $grupos[$nome] = [pscustomobject]$g
        }
        $x = $grupos[$nome]
        $x.Cpu += $cpu; $x.Ram += [double]$p.WorkingSetPrivate; $x.Io += $io; $x.Qtd++
    }
    $lista = @($grupos.Values)
    # Nome amigável (descrição do .exe) só para os que vão aparecer
    $topCpu = @($lista | Sort-Object Cpu -Descending | Select-Object -First 6)
    $topRam = @($lista | Sort-Object Ram -Descending | Select-Object -First 6)
    $topIo  = @($lista | Where-Object { $_.Io -ge 1MB } | Sort-Object Io -Descending | Select-Object -First 4)
    foreach ($x in @($topCpu + $topRam + $topIo)) {
        if ($x.Descricao) { continue }
        $d = ''
        try { $d = [string](Get-Process -Id $x.Id -ErrorAction Stop).MainModule.FileVersionInfo.FileDescription } catch { }
        $x.Descricao = if ($d.Trim()) { $d.Trim() } else { $x.Nome }
    }

    # Memória
    $os = Get-CimInstance Win32_OperatingSystem -Property FreePhysicalMemory, TotalVisibleMemorySize, LastBootUpTime
    $totalRam = [double]$os.TotalVisibleMemorySize * 1KB
    $ramPct = [math]::Round(100 * (1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize))
    $mem = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -Property PercentCommittedBytesInUse -ErrorAction SilentlyContinue
    $commit = if ($mem) { [int]$mem.PercentCommittedBytesInUse } else { 0 }

    # Disco: tempo ocupado = 1 - tempo ocioso
    $discos = New-Object System.Collections.Generic.List[object]
    $d0 = @{}; foreach ($d in $a1.Disco) { $d0[$d.Name] = $d }
    foreach ($d in $a2.Disco) {
        if ($d.Name -eq '_Total' -or -not $d0.ContainsKey($d.Name)) { continue }
        $dt = [double]($d.Timestamp_Sys100NS - $d0[$d.Name].Timestamp_Sys100NS)
        if ($dt -le 0) { continue }
        $ocioso = [double]($d.PercentIdleTime - $d0[$d.Name].PercentIdleTime) / $dt
        $discos.Add([pscustomobject]@{ Nome = ($d.Name -replace '^\d+\s*', '').Trim(); Ocupado = [int][math]::Round([math]::Min(100, [math]::Max(0, 100 * (1 - $ocioso)))) })
    }
    $discoMax = 0; foreach ($d in $discos) { if ($d.Ocupado -gt $discoMax) { $discoMax = $d.Ocupado } }
    $cpuPct = [int][math]::Round([math]::Min(100, $cpuTotal))

    # Conclusões em linguagem simples
    $achados = New-Object System.Collections.Generic.List[object]
    $explica = { param($n) if ($Script:ExplicaProcesso.ContainsKey($n)) { ' ' + $Script:ExplicaProcesso[$n] } else { '' } }
    $c1 = $topCpu | Select-Object -First 1
    if ($cpuPct -ge 85) {
        $achados.Add((New-Achado 'Processador no limite' "Uso de $cpuPct%. Quem mais usa: $($c1.Descricao) ($([math]::Round($c1.Cpu))%).$(& $explica $c1.Nome)" 'alto'))
    } elseif ($c1 -and $c1.Cpu -ge 25 -and $c1.Nome -ne 'WmiPrvSE') {
        $achados.Add((New-Achado 'Um programa está pesando no processador' "$($c1.Descricao) está usando $([math]::Round($c1.Cpu))% do processador.$(& $explica $c1.Nome)" 'medio'))
    }
    $r1 = $topRam | Select-Object -First 1
    $navegadores = @($lista | Where-Object { $_.Nome -in 'chrome', 'msedge', 'firefox', 'opera', 'brave' })
    $ramNav = 0.0; foreach ($n in $navegadores) { $ramNav += $n.Ram }
    if ($ramPct -ge 90) {
        $achados.Add((New-Achado 'Memória RAM quase cheia' "$ramPct% em uso. O Windows passa a usar o disco no lugar da RAM e tudo fica lento. Quem mais usa: $($r1.Descricao) ($(Format-Tamanho $r1.Ram))." 'alto'))
    } elseif ($ramPct -ge 80) {
        $achados.Add((New-Achado 'Memória RAM apertada' "$ramPct% em uso. Feche o que não estiver usando. Quem mais usa: $($r1.Descricao) ($(Format-Tamanho $r1.Ram))." 'medio'))
    }
    if ($totalRam -gt 0 -and $ramNav / $totalRam -ge 0.25) {
        $achados.Add((New-Achado 'Navegador ocupando muita memória' "Os navegadores somam $(Format-Tamanho $ramNav) ($([math]::Round(100 * $ramNav / $totalRam))% da RAM). Abas que dormem ajudam: veja a categoria Navegadores em Otimizar." 'medio' 'nav.edge-abas-dormir' 'Ver ajuste'))
    }
    if ($commit -ge 90) {
        $achados.Add((New-Achado 'Memória virtual quase esgotada' "$commit% da memória virtual em uso. Programas podem travar ou fechar. Confira o ajuste 'Arquivo de paginação gerenciado pelo Windows'." 'alto' 'sistema.paginacao' 'Ver ajuste'))
    }
    if ($discoMax -ge 90) {
        $io1 = $topIo | Select-Object -First 1
        $quem = if ($io1) { " Quem mais lê/grava: $($io1.Descricao) ($(Format-Tamanho $io1.Io)/s).$(& $explica $io1.Nome)" } else { '' }
        $achados.Add((New-Achado 'Disco em 100%' "O disco está ocupado $discoMax% do tempo: tudo espera por ele.$quem" 'alto'))
    } elseif ($discoMax -ge 60) {
        $achados.Add((New-Achado 'Disco bastante ocupado' "O disco está ocupado $discoMax% do tempo." 'medio'))
    }
    if (@($lista | Where-Object { $_.Nome -in 'TiWorker', 'TrustedInstaller', 'MoUsoCoreWorker' -and $_.Cpu -ge 5 }).Count) {
        $achados.Add((New-Achado 'Windows Update trabalhando' 'O Windows está baixando ou instalando atualizações agora. É temporário: deixe terminar e reinicie quando pedir.' 'medio' 'windowsupdate' 'Abrir'))
    }
    $plano = Get-PlanoAtivo
    if ($plano -and $plano.Nome -match 'Economia|Power saver') {
        $achados.Add((New-Achado 'Plano de energia em economia' "O plano '$($plano.Nome)' limita o processador. Use um plano equilibrado ou de desempenho." 'medio' 'energia.plano' 'Ver ajuste'))
    }
    $smi = "$env:SystemRoot\System32\nvidia-smi.exe"
    if (Test-Path $smi) {
        foreach ($l in @(& $smi --query-gpu=name,temperature.gpu --format=csv,noheader,nounits 2>$null)) {
            $p = $l -split ',\s*'
            if ($p.Count -ge 2 -and $p[1] -match '^\d+' -and [int]$p[1] -ge 85) {
                $achados.Add((New-Achado 'Placa de vídeo muito quente' "$($p[0].Trim()) a $($p[1]) °C: ela reduz a velocidade para se proteger. Limpe a poeira e confira as ventoinhas." 'alto' 'temperaturas' 'Ver'))
            }
        }
    }
    $uptime = (Get-Date) - $os.LastBootUpTime
    if ($uptime.TotalDays -gt 7) {
        $achados.Add((New-Achado 'Muito tempo sem reiniciar' "Ligado há $([math]::Floor($uptime.TotalDays)) dias. Reiniciar libera memória e conclui atualizações." 'medio' 'reiniciar' 'Reiniciar'))
    }
    if ($achados.Count -eq 0) {
        $achados.Add((New-Achado 'Nada anormal agora' 'Processador, memória e disco estão folgados. Se a lentidão acontece em um momento específico (abrir um programa, jogar), clique em "Analisar agora" enquanto ela acontece.' 'ok'))
    }

    $r = [ordered]@{}
    $r.Cpu = $cpuPct
    $r.Ram = $ramPct
    $r.RamTotal = $totalRam
    $r.Commit = $commit
    $r.Disco = $discoMax
    $r.Discos = $discos.ToArray()
    $r.TopCpu = $topCpu
    $r.TopRam = $topRam
    $r.TopIo = $topIo
    $r.Achados = $achados.ToArray()
    return [pscustomobject]$r
}

# ===============================================================
#  2. Tempo real de inicialização (log de diagnóstico de desempenho)
#  Evento 100 = boot completo. 101/102/103/109 = o que atrasou.
#  O log só é legível com administrador.
# ===============================================================
function Get-DadosEvento($Evento) {
    $d = @{}
    try { foreach ($n in ([xml]$Evento.ToXml()).Event.EventData.Data) { $d[[string]$n.Name] = [string]$n.'#text' } } catch { }
    return $d
}

function Get-HistoricoBoot([int]$Max = 20) {
    $r = [ordered]@{}
    $r.Disponivel = $false; $r.Motivo = ''; $r.Boots = @(); $r.Atrasos = @()
    $log = 'Microsoft-Windows-Diagnostics-Performance/Operational'
    # Com -FilterHashtable, "acesso negado" vira "nenhum evento"; por isso testa a leitura antes
    try { [void](Get-WinEvent -LogName $log -MaxEvents 1 -ErrorAction Stop) }
    catch [UnauthorizedAccessException] { $r.Motivo = 'O registro de inicialização do Windows só pode ser lido como administrador.'; return [pscustomobject]$r }
    catch { }
    try {
        $evs = @(Get-WinEvent -FilterHashtable @{ LogName = $log; Id = 100 } -MaxEvents $Max -ErrorAction Stop)
    } catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { $r.Motivo = 'O Windows ainda não registrou nenhuma inicialização completa. Reinicie o PC (Reiniciar, não Desligar) e volte aqui.' }
        elseif ($_.Exception -is [UnauthorizedAccessException] -or $_.Exception.Message -match 'autoriza|unauthorized|denied|negado') { $r.Motivo = 'O registro de inicialização do Windows só pode ser lido como administrador.' }
        else { $r.Motivo = "Não foi possível ler o registro de inicialização: $($_.Exception.Message)" }
        return [pscustomobject]$r
    }
    $boots = New-Object System.Collections.Generic.List[object]
    foreach ($e in $evs) {
        $d = Get-DadosEvento $e
        $total = 0; $principal = 0
        if ($d['BootTime'] -match '^\d+$') { $total = [int]$d['BootTime'] }
        if ($d['MainPathBootTime'] -match '^\d+$') { $principal = [int]$d['MainPathBootTime'] }
        if ($total -le 0) { continue }
        $b = [ordered]@{}
        $b.Data = $e.TimeCreated
        $b.Total = [math]::Round($total / 1000.0, 1)
        $b.AteAreaDeTrabalho = [math]::Round($principal / 1000.0, 1)
        $boots.Add([pscustomobject]$b)
    }
    $r.Boots = $boots.ToArray()
    $r.Disponivel = $boots.Count -gt 0
    if (-not $r.Disponivel) { $r.Motivo = 'Os eventos de inicialização não trazem o tempo. Reinicie o PC e volte aqui.' }

    # O que atrasou (últimos 60 dias), agrupado por nome
    $tipos = @{ 101 = 'Programa'; 102 = 'Driver'; 103 = 'Serviço'; 109 = 'Dispositivo' }
    $atrasos = @{}
    try {
        $evs2 = @(Get-WinEvent -FilterHashtable @{ LogName = $log; Id = 101, 102, 103, 109; StartTime = (Get-Date).AddDays(-60) } -MaxEvents 300 -ErrorAction Stop)
        foreach ($e in $evs2) {
            $d = Get-DadosEvento $e
            $nome = @($d['FriendlyName'], $d['Name'], $d['FileName']) | Where-Object { $_ } | Select-Object -First 1
            if (-not $nome) { continue }
            $ms = 0
            foreach ($campo in 'DegradationTime', 'TotalTime') { if ($d[$campo] -match '^\d+$') { $ms = [int]$d[$campo]; break } }
            $chave = "$($e.Id)|$nome"
            if (-not $atrasos.ContainsKey($chave)) { $atrasos[$chave] = [pscustomobject]@{ Nome = $nome; Tipo = $tipos[[int]$e.Id]; Vezes = 0; Ms = 0 } }
            $atrasos[$chave].Vezes++
            $atrasos[$chave].Ms += $ms
        }
    } catch { }
    $r.Atrasos = @($atrasos.Values | Sort-Object Ms -Descending | Select-Object -First 10)
    return [pscustomobject]$r
}

# ===============================================================
#  3. Antes × depois
#  A referência é gravada uma vez, antes da primeira otimização.
#  O tempo de boot vem do log: boots antes e depois da data da referência.
# ===============================================================
function Get-ArqReferencia { return (Join-Path $Script:Otz.Dados 'medicao-referencia.json') }

function Get-Medicao {
    $os = Get-CimInstance Win32_OperatingSystem -Property FreePhysicalMemory, TotalVisibleMemorySize, LastBootUpTime
    $r = [ordered]@{}
    $r.Data = (Get-Date).ToString('s')
    $r.RamUsoMB = [int](($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1KB)
    $r.Processos = @([Diagnostics.Process]::GetProcesses()).Count
    $r.Servicos = @(Get-Service -ErrorAction SilentlyContinue | Where-Object Status -eq 'Running').Count
    $r.Inicializacao = @(Get-ItensInicializacao | Where-Object Ativo).Count
    $r.MinutosLigado = [int]((Get-Date) - $os.LastBootUpTime).TotalMinutes
    return [pscustomobject]$r
}

function Get-MedicaoReferencia {
    $arq = Get-ArqReferencia
    if (-not (Test-Path $arq)) { return $null }
    try { return ([IO.File]::ReadAllText($arq, [Text.Encoding]::UTF8) | ConvertFrom-Json) } catch { return $null }
}

function Save-MedicaoReferencia {
    $m = Get-Medicao
    [IO.File]::WriteAllText((Get-ArqReferencia), (ConvertTo-Json -InputObject $m), (New-Object Text.UTF8Encoding $false))
    Write-Log "Medição de referência (antes): RAM $($m.RamUsoMB) MB, $($m.Processos) processos, $($m.Servicos) serviços, $($m.Inicializacao) na inicialização."
    return $m
}

function Remove-MedicaoReferencia { Remove-Item (Get-ArqReferencia) -Force -ErrorAction SilentlyContinue }

# Data da primeira aplicação registrada no histórico (ou $null)
function Get-PrimeiraAplicacao {
    $primeira = $null
    foreach ($h in @(Get-Historico 100000)) {
        if ($h.Acao -ne 'aplicar') { continue }
        try { $d = [datetime]::Parse($h.Data, [Globalization.CultureInfo]::InvariantCulture) } catch { continue }
        if (-not $primeira -or $d -lt $primeira) { $primeira = $d }
    }
    return $primeira
}

function Get-Comparacao {
    $ref = Get-MedicaoReferencia
    $dataRef = $null
    if ($ref) { $dataRef = [datetime]::Parse($ref.Data, [Globalization.CultureInfo]::InvariantCulture) }
    # O tempo de boot vem do log do Windows: dá para comparar desde a primeira otimização,
    # mesmo que ela seja anterior à referência (ajustes aplicados antes desta função existir)
    $corte = Get-PrimeiraAplicacao
    if ($dataRef -and (-not $corte -or $dataRef -lt $corte)) { $corte = $dataRef }
    if (-not $ref -and -not $corte) { return $null }
    $boot = Get-HistoricoBoot 60
    $antes = @(); $depois = @()
    if ($corte) {
        $antes = @($boot.Boots | Where-Object { $_.Data -lt $corte } | Select-Object -First 5)
        $depois = @($boot.Boots | Where-Object { $_.Data -ge $corte } | Select-Object -First 5)
    }
    $r = [ordered]@{}
    $r.TemReferencia = [bool]$ref
    $r.DataReferencia = $dataRef
    $r.DataCorte = $corte
    $r.Antes = $ref
    $r.Agora = Get-Medicao
    $r.BootAntes = $null; $r.BootDepois = $null; $r.BootsDepois = $depois.Count
    if ($antes.Count) { $r.BootAntes = [math]::Round((($antes | Measure-Object AteAreaDeTrabalho -Average).Average), 1) }
    if ($depois.Count) { $r.BootDepois = [math]::Round((($depois | Measure-Object AteAreaDeTrabalho -Average).Average), 1) }
    $r.BootDisponivel = $boot.Disponivel
    return [pscustomobject]$r
}

# ===============================================================
#  4. Estabilidade: desligamentos, telas azuis, erros de hardware, travamentos
#  Logs System/Application são legíveis sem administrador.
# ===============================================================
function Get-ContagemEventos([hashtable]$Filtro) {
    try { return @(Get-WinEvent -FilterHashtable $Filtro -ErrorAction Stop) } catch { return @() }
}

function Get-Estabilidade([int]$Dias = 30) {
    $desde = (Get-Date).AddDays(-$Dias)
    $achados = New-Object System.Collections.Generic.List[object]

    $indice = $null
    try {
        $m = Get-CimInstance Win32_ReliabilityStabilityMetrics -ErrorAction Stop | Sort-Object TimeGenerated -Descending | Select-Object -First 1
        if ($m) { $indice = [math]::Round([double]$m.SystemStabilityIndex, 1) }
    } catch { }

    $deslig = Get-ContagemEventos @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $desde }
    $azuis  = Get-ContagemEventos @{ LogName = 'System'; Id = 1001; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; StartTime = $desde }
    $whea   = Get-ContagemEventos @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; Level = 1, 2, 3; StartTime = $desde }
    $crash  = Get-ContagemEventos @{ LogName = 'Application'; Id = 1000; StartTime = $desde }
    $hang   = Get-ContagemEventos @{ LogName = 'Application'; Id = 1002; StartTime = $desde }

    if ($null -ne $indice) {
        $nivel = if ($indice -ge 8) { 'ok' } elseif ($indice -ge 5) { 'medio' } else { 'alto' }
        $achados.Add((New-Achado 'Índice de confiabilidade do Windows' "$($indice.ToString('0.0')) de 10. Ele cai a cada travamento, erro de programa ou desligamento inesperado e sobe sozinho quando o PC fica dias sem problemas." $nivel 'perfmon' 'Abrir monitor'))
    }
    if ($deslig.Count) {
        $ult = $deslig[0].TimeCreated.ToString('dd/MM HH:mm')
        $nivel = if ($deslig.Count -ge 3) { 'alto' } else { 'medio' }
        $achados.Add((New-Achado "Desligou sozinho $($deslig.Count) vez(es)" "O Windows não foi fechado direito (último: $ult). Causas comuns: queda de energia, travamento total, botão de ligar segurado, fonte fraca, superaquecimento ou overclock/XMP instável." $nivel))
    } else { $achados.Add((New-Achado 'Desligamentos inesperados' "Nenhum nos últimos $Dias dias." 'ok')) }
    if ($azuis.Count) {
        $achados.Add((New-Achado "Tela azul $($azuis.Count) vez(es)" "Último: $($azuis[0].TimeCreated.ToString('dd/MM HH:mm')). Quase sempre é driver (vídeo, rede, chipset), memória instável ou disco com defeito. Atualize os drivers e, se continuar, teste a memória." 'alto'))
    } else { $achados.Add((New-Achado 'Telas azuis' "Nenhuma nos últimos $Dias dias." 'ok')) }
    if ($whea.Count) {
        $achados.Add((New-Achado "Erros de hardware relatados: $($whea.Count)" 'O processador, a memória ou o barramento PCIe relataram erros (o Windows corrigiu, mas não é normal). Se você ativou XMP/EXPO ou overclock, ele pode estar instável; teste com as configurações padrão da BIOS.' 'medio' 'bios' 'Ver BIOS'))
    }
    $porApp = @{}
    foreach ($e in @($crash + $hang)) {
        $app = [string]$e.Properties[0].Value
        if (-not $app) { continue }
        $sistema = $app -match '\\Windows\\(System32|SysWOW64)\\' -or $app -match '^(explorer|userinit|dwm|svchost|sihost|ShellExperienceHost|StartMenuExperienceHost|SearchHost|RuntimeBroker)\.exe$'
        $app = Split-Path $app -Leaf
        if (-not $porApp.ContainsKey($app)) { $porApp[$app] = [pscustomobject]@{ App = $app; Erros = 0; Travou = 0; Ultimo = $e.TimeCreated; Sistema = $sistema } }
        if ($e.Id -eq 1000) { $porApp[$app].Erros++ } else { $porApp[$app].Travou++ }
        if ($e.TimeCreated -gt $porApp[$app].Ultimo) { $porApp[$app].Ultimo = $e.TimeCreated }
    }
    $apps = @($porApp.Values | Sort-Object { $_.Erros + $_.Travou } -Descending | Select-Object -First 8)
    if ($apps.Count -eq 0) { $achados.Add((New-Achado 'Programas fechando com erro' "Nenhum nos últimos $Dias dias." 'ok')) }

    $r = [ordered]@{}
    $r.Dias = $Dias
    $r.Indice = $indice
    $r.Desligamentos = $deslig.Count
    $r.TelasAzuis = $azuis.Count
    $r.ErrosHardware = $whea.Count
    $r.Apps = $apps
    $r.Achados = $achados.ToArray()
    return [pscustomobject]$r
}

# Checagem resumida para a página Verificar
function Get-SaudeEstabilidade {
    $e = Get-Estabilidade 30
    $problemas = $e.Desligamentos + $e.TelasAzuis
    if ($e.TelasAzuis) { New-Checagem 'Estabilidade' "$($e.TelasAzuis) tela(s) azul(is) e $($e.Desligamentos) desligamento(s) inesperado(s) em 30 dias." 'alto' 'estabilidade' }
    elseif ($e.Desligamentos -ge 3) { New-Checagem 'Estabilidade' "O PC desligou sozinho $($e.Desligamentos) vezes em 30 dias." 'alto' 'estabilidade' }
    elseif ($problemas) { New-Checagem 'Estabilidade' "$($e.Desligamentos) desligamento(s) inesperado(s) em 30 dias." 'medio' 'estabilidade' }
    else { New-Checagem 'Estabilidade' 'Nenhuma tela azul ou desligamento inesperado em 30 dias.' }
}

# ===============================================================
#  5. Qualidade da conexão física (cabo e Wi-Fi)
# ===============================================================
function Get-InfoWifi {
    $saida = @(netsh wlan show interfaces 2>$null)
    $lista = New-Object System.Collections.Generic.List[object]
    $atual = $null
    foreach ($l in $saida) {
        if ($l -notmatch '^\s*([^:]+?)\s*:\s*(.*)$') { continue }
        $k = $Matches[1].Trim(); $v = $Matches[2].Trim()
        if ($k -match '^(Name|Nome)$') { $atual = @{ Nome = $v }; $lista.Add($atual); continue }
        if (-not $atual) { continue }
        if ($k -eq 'SSID') { $atual.Ssid = $v }
        elseif ($k -match '^(Signal|Sinal)$' -and $v -match '(\d+)') { $atual.Sinal = [int]$Matches[1] }
        elseif ($k -match '^(Channel|Canal)$' -and $v -match '(\d+)') { $atual.Canal = [int]$Matches[1] }
        elseif ($k -match '^(Band|Banda)$') { $atual.Banda = $v }
        elseif ($k -match '^(Radio type|Tipo de r)') { $atual.Radio = $v }
        elseif ($k -match '^(Receive rate|Taxa de rece)' -and $v -match '([\d.,]+)') { $atual.Taxa = $Matches[1] }
        elseif ($k -match '^(State|Estado)$') { $atual.Estado = $v }
    }
    return $lista.ToArray()
}

function Get-QualidadeConexao {
    $achados = New-Object System.Collections.Generic.List[object]
    $ativos = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')
    $wifis = @(Get-InfoWifi)
    foreach ($a in $ativos) {
        $semFio = ([string]$a.PhysicalMediaType -match '802\.11|Wireless') -or ($a.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN|802\.11')
        if (-not $semFio) {
            $mbps = [math]::Round([double]$a.Speed / 1e6)
            $giga = $a.InterfaceDescription -match 'Gigabit|GbE|2\.5G|5G|10G|1000'
            if ($mbps -lt 1000 -and $giga) {
                $achados.Add((New-Achado "Cabo: $($a.Name) a $mbps Mbps" "A placa ($($a.InterfaceDescription)) aceita 1 Gbps ou mais, mas está ligada a só $mbps Mbps. Se sua internet passa de 100 Mega, você está perdendo velocidade. Causas: cabo velho ou com fio rompido (precisa ser Cat5e ou superior), conector mal crimpado ou porta do roteador de 100 Mbps. Troque o cabo e teste outra porta." 'alto'))
            } elseif ($mbps -lt 1000) {
                $achados.Add((New-Achado "Cabo: $($a.Name) a $mbps Mbps" "Esta placa de rede é de $mbps Mbps. Para internet acima de 100 Mega, uma placa gigabit (USB ou PCIe) resolve." 'medio'))
            } else {
                $txt = if ($mbps -ge 1000) { "$([math]::Round($mbps / 1000, 1)) Gbps" } else { "$mbps Mbps" }
                $achados.Add((New-Achado "Cabo: $($a.Name) a $txt" "Ligação na velocidade máxima ($($a.InterfaceDescription))." 'ok'))
            }
            if ($a.FullDuplex -eq $false) {
                $achados.Add((New-Achado "Cabo: $($a.Name) em half duplex" 'A placa só consegue enviar OU receber de cada vez. Quase sempre é cabo ou porta com defeito.' 'alto'))
            }
        } else {
            $w = $wifis | Where-Object { $_.Nome -eq $a.Name } | Select-Object -First 1
            if (-not $w) { $w = $wifis | Select-Object -First 1 }
            if (-not $w -or $null -eq $w.Sinal) { $achados.Add((New-Achado "Wi-Fi: $($a.Name)" 'Conectado, mas o Windows não informou o sinal.' 'info')); continue }
            $banda = if ($w.Banda) { $w.Banda } elseif ($w.Canal -gt 14) { '5 GHz' } elseif ($w.Canal) { '2,4 GHz' } else { '' }
            $nivel = if ($w.Sinal -ge 70) { 'ok' } elseif ($w.Sinal -ge 50) { 'medio' } else { 'alto' }
            $txt = "Sinal $($w.Sinal)%"
            if ($banda) { $txt += " na faixa de $banda" }
            if ($w.Taxa) { $txt += ", conexão a $($w.Taxa) Mbps" }
            $txt += '. '
            $txt += switch ($nivel) {
                'ok'    { 'Sinal bom.' }
                'medio' { 'Sinal regular: a velocidade cai e o ping oscila. Aproxime-se do roteador ou tire obstáculos (paredes, espelhos, micro-ondas).' }
                default { 'Sinal fraco: espere quedas e lentidão. Aproxime o PC do roteador, use um repetidor/mesh ou cabo.' }
            }
            if ($banda -match '2[,.]4') { $txt += ' Se o roteador tiver uma rede de 5 GHz, conecte nela: é bem mais rápida em distâncias curtas.' }
            $achados.Add((New-Achado "Wi-Fi: $($w.Ssid)" $txt $nivel))
        }
    }
    if ($achados.Count -eq 0) { $achados.Add((New-Achado 'Nenhuma conexão ativa' 'Não há placa de rede física conectada.' 'medio')) }
    return $achados.ToArray()
}

# ===============================================================
#  9. Checklist de BIOS e hardware (só orienta, não altera nada)
# ===============================================================
function Get-ChecklistBios {
    $achados = New-Object System.Collections.Generic.List[object]
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    # Modo UEFI
    if ($env:firmware_type -eq 'UEFI') { $achados.Add((New-Achado 'Modo de inicialização: UEFI' 'Correto. É o modo moderno, exigido pelo Windows 11 e pelo Secure Boot.' 'ok')) }
    elseif ($env:firmware_type) { $achados.Add((New-Achado "Modo de inicialização: $($env:firmware_type)" 'O PC usa o modo antigo (Legacy/CSM). O Windows 11, o Secure Boot e o Resizable BAR exigem UEFI. Converter exige cuidado (ferramenta MBR2GPT da Microsoft): faça backup antes.' 'medio')) }

    # Secure Boot (lido do registro: funciona sem administrador)
    $sb = Read-RegValor 'HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\State' 'UEFISecureBootEnabled'
    if ($sb.Existe -and [int]$sb.Valor -eq 1) { $achados.Add((New-Achado 'Secure Boot: ligado' 'Protege a inicialização contra programas maliciosos. Alguns jogos com anti-cheat exigem.' 'ok')) }
    elseif ($sb.Existe) { $achados.Add((New-Achado 'Secure Boot: desligado' 'Alguns jogos com anti-cheat (ex.: VALORANT e Battlefield no Windows 11) exigem Secure Boot. Na BIOS, procure "Secure Boot" (aba Boot ou Security) e ative. Requer modo UEFI.' 'medio')) }

    # TPM
    if ($admin) {
        try {
            $t = Get-CimInstance -Namespace root\cimv2\security\microsofttpm -ClassName Win32_Tpm -ErrorAction Stop
            if ($t) {
                $ver = ([string]$t.SpecVersion -split ',')[0].Trim()
                $ok = $t.IsEnabled_InitialValue -and $ver -like '2*'
                if ($ok) { $achados.Add((New-Achado "TPM $($ver): ativo" 'Exigido pelo Windows 11 e por alguns anti-cheats.' 'ok')) }
                else { $achados.Add((New-Achado "TPM $($ver)" 'O TPM existe mas não está pronto. Na BIOS, procure "fTPM" (AMD) ou "PTT" (Intel) e ative.' 'medio')) }
            } else { throw 'sem TPM' }
        } catch { $achados.Add((New-Achado 'TPM: não encontrado' 'Na BIOS, procure "fTPM" (AMD) ou "PTT"/"Intel Platform Trust" (Intel) e ative. O Windows 11 exige TPM 2.0.' 'medio')) }
    } else { $achados.Add((New-Achado 'TPM' 'Para ler o TPM, abra o otimizador como administrador.' 'info')) }

    # Memória: XMP/EXPO e canais
    $mem = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    if ($mem.Count) {
        $m = $mem[0]
        $tipo = switch ([int]$m.SMBIOSMemoryType) { 26 { 'DDR4' } 34 { 'DDR5' } 24 { 'DDR3' } default { '' } }
        $atual = [int]$m.ConfiguredClockSpeed; $nominal = [int]$m.Speed
        $comoXmp = 'Na BIOS, ative o perfil de memória: XMP (Intel), EXPO ou DOCP (AMD/ASUS), às vezes chamado "A-XMP" (MSI). Se o PC ficar instável depois, volte ao padrão.'
        if ($atual -and $nominal -and $atual -lt $nominal) {
            $achados.Add((New-Achado "Memória a $atual MT/s (pente suporta $nominal)" "A memória está mais lenta do que pode. $comoXmp" 'medio'))
        } elseif (($tipo -eq 'DDR4' -and $atual -le 2400) -or ($tipo -eq 'DDR5' -and $atual -le 4800)) {
            $achados.Add((New-Achado "Memória $tipo a $atual MT/s" "É a velocidade padrão de fábrica. Se o pente for vendido como mais rápido (ex.: DDR4-3200, DDR5-6000, veja a etiqueta), o perfil está desligado. $comoXmp" 'info'))
        } else {
            $achados.Add((New-Achado "Memória $tipo a $atual MT/s" 'Rodando acima do padrão de fábrica: o perfil XMP/EXPO já está ativo.' 'ok'))
        }
        if ($mem.Count -eq 1) { $achados.Add((New-Achado 'Memória em um canal só' 'Só há 1 pente. Com 2 pentes iguais (dual channel) a memória fica até 2x mais rápida, o que ajuda muito em vídeo integrado e jogos.' 'medio')) }
        else { $achados.Add((New-Achado "Memória: $($mem.Count) pentes" 'Com 2 ou 4 pentes iguais nos slots indicados no manual (geralmente A2 e B2), a memória trabalha em dual channel.' 'ok')) }
    }

    # Resizable BAR (só NVIDIA dá para ler com segurança: BAR1 ≈ VRAM quando ligado)
    $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object Name)
    $smi = "$env:SystemRoot\System32\nvidia-smi.exe"
    $nv = $gpus | Where-Object { $_ -match 'NVIDIA' } | Select-Object -First 1
    if ($nv -and (Test-Path $smi)) {
        $q = (& $smi -q -d MEMORY 2>$null) -join "`n"
        $fb = $null; $bar = $null
        if ($q -match 'FB Memory Usage\s*\n\s*Total\s*:\s*(\d+)') { $fb = [int]$Matches[1] }
        if ($q -match 'BAR1 Memory Usage\s*\n\s*Total\s*:\s*(\d+)') { $bar = [int]$Matches[1] }
        $comoRebar = 'Na BIOS, ative "Above 4G Decoding" e depois "Re-Size BAR Support" (a BIOS precisa estar em UEFI, com CSM desligado). Confirme depois no Painel de Controle NVIDIA > Informações do sistema > "Resizable BAR".'
        if ($nv -notmatch 'RTX\s*(30|40|50)') {
            $achados.Add((New-Achado 'Resizable BAR' "$nv não usa Resizable BAR (recurso das RTX 30 em diante)." 'info'))
        } elseif ($fb -and $bar -and $bar -ge 0.9 * $fb) {
            $achados.Add((New-Achado 'Resizable BAR: ligado' "O processador acessa toda a memória da $nv de uma vez. Dá alguns % a mais de FPS em vários jogos." 'ok'))
        } elseif ($bar) {
            $achados.Add((New-Achado 'Resizable BAR: provavelmente desligado' "A $nv expõe só $bar MiB de $fb MiB ao processador. Ligar costuma dar alguns % de FPS a mais. $comoRebar" 'medio'))
        }
    } elseif ($gpus | Where-Object { $_ -match 'Radeon RX' }) {
        $achados.Add((New-Achado 'Smart Access Memory (Resizable BAR)' 'Em placas AMD, o recurso se chama Smart Access Memory. Confira no AMD Software se está ativo; para ligar, ative "Above 4G Decoding" e "Re-Size BAR Support" na BIOS.' 'info'))
    }

    # Virtualização (WSL, emuladores Android, máquinas virtuais)
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $hv = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).HypervisorPresent
    if ($hv) { $achados.Add((New-Achado 'Virtualização: em uso' 'O Windows já usa a virtualização (Hyper-V, WSL ou Integridade de Memória).' 'ok')) }
    elseif ($cpu -and $cpu.VirtualizationFirmwareEnabled) { $achados.Add((New-Achado 'Virtualização: ligada na BIOS' 'Pronta para WSL, emuladores Android e máquinas virtuais.' 'ok')) }
    elseif ($cpu) { $achados.Add((New-Achado 'Virtualização: desligada na BIOS' 'Só precisa se você usa WSL, emuladores de Android ou máquinas virtuais. Na BIOS: "SVM Mode" (AMD) ou "Intel VT-x"/"Virtualization Technology".' 'info')) }

    # Versão da BIOS
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $mb = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
    if ($bios -and $bios.ReleaseDate) {
        $anos = ((Get-Date) - $bios.ReleaseDate).TotalDays / 365
        $placa = "$($mb.Manufacturer) $($mb.Product)".Trim()
        $txt = "Versão $($bios.SMBIOSBIOSVersion) de $($bios.ReleaseDate.ToString('dd/MM/yyyy')) ($placa)."
        if ($anos -ge 2) { $achados.Add((New-Achado 'BIOS com mais de 2 anos' "$txt Versões novas corrigem estabilidade, compatibilidade de memória e segurança. Baixe só do site do fabricante da placa-mãe e não desligue o PC durante a atualização." 'info')) }
        else { $achados.Add((New-Achado 'BIOS' $txt 'ok')) }
    }
    return $achados.ToArray()
}
