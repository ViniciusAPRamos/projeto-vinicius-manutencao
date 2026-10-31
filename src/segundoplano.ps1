#Requires -Version 5.1
<#
    "Limpar o segundo plano" (Otimizador Vinicius v2.0)
    Programas e serviços de TERCEIROS que ligam sozinhos com o Windows.
    Aplica uma vez e fica valendo: serviço vai para Manual (o programa ainda
    o liga quando precisa) e o item de inicialização é desligado (mesmo
    mecanismo do Gerenciador de Tarefas). Tudo com desfazer.

    Classificação (src\conhecidos.ps1):
      seguro       vem marcado; entra nos perfis e no Aplicar-Perfil.bat
      depende      aparece desmarcado, com a explicação
      desconhecido não está na base: nunca vem marcado nem entra em modo silencioso
      manter       nunca aparece (anti-cheat, drivers, ventoinhas)
    Fora da lista sempre: Microsoft, arquivos dentro do Windows (inclui drivers
    do DriverStore) e serviços de que outros dependem.

    Estado em Documentos\OtimizadorVinicius\segundo-plano.json:
      Itens      o que o otimizador desligou e como estava antes
      Escolhidos a última escolha do usuário (ausente = usar os "seguro")
    Depende do nucleo.ps1 e do ferramentas.ps1 (Get-ItensInicializacao).
#>

function Get-BaseConhecidos {
    if (-not $Script:BaseConhecidos) {
        $Script:BaseConhecidos = @(. (Join-Path $Script:Otz.SrcDir 'conhecidos.ps1'))
    }
    return $Script:BaseConhecidos
}

function Find-Conhecido([string]$Tipo, [string[]]$Textos) {
    $campo = if ($Tipo -eq 'servico') { 'Servicos' } else { 'Inicio' }
    foreach ($k in Get-BaseConhecidos) {
        foreach ($re in @($k[$campo])) {
            if (-not $re) { continue }
            foreach ($t in $Textos) { if ($t -and $t -match $re) { return $k } }
        }
    }
    return $null
}

# Quem assinou o .exe (assinatura embutida; não consulta a internet)
$Script:CacheAssinante = @{}
function Get-AssinanteArquivo([string]$Caminho) {
    if (-not $Caminho) { return '' }
    if ($Script:CacheAssinante.ContainsKey($Caminho)) { return $Script:CacheAssinante[$Caminho] }
    $nome = ''
    if (Test-Path -LiteralPath $Caminho -PathType Leaf) {
        try {
            $c = [Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($Caminho)
            $nome = ([Security.Cryptography.X509Certificates.X509Certificate2]$c).GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
        } catch { }
    }
    $Script:CacheAssinante[$Caminho] = $nome
    return $nome
}

function Get-ExeDeComando([string]$Linha) {
    if (-not $Linha) { return '' }
    $l = [Environment]::ExpandEnvironmentVariables($Linha.Trim())
    if ($l -match '^"([^"]+)"') { return $Matches[1] }
    if ($l -match '^(.+?\.exe)\b') { return $Matches[1] }
    return $l
}

# Arquivo do próprio Windows ou de driver (DriverStore): nunca entra na lista
function Test-ArquivoDoWindows([string]$Exe) {
    if (-not $Exe) { return $false }
    $win = $env:SystemRoot.TrimEnd('\') + '\'
    return $Exe.StartsWith($win, [StringComparison]::OrdinalIgnoreCase) -or $Exe -match '\\WindowsApps\\Microsoft\.'
}

# Memória privada (o que o Gerenciador de Tarefas mostra) de cada processo
function Get-MapaProcessos {
    $mem = @{}
    foreach ($p in @(Get-CimInstance Win32_PerfRawData_PerfProc_Process -Property IDProcess, WorkingSetPrivate -OperationTimeoutSec 15 -ErrorAction SilentlyContinue)) {
        if ($p.IDProcess) { $mem[[int]$p.IDProcess] = [double]$p.WorkingSetPrivate }
    }
    $lista = New-Object System.Collections.Generic.List[object]
    foreach ($p in [Diagnostics.Process]::GetProcesses()) {
        $bytes = $mem[[int]$p.Id]
        if ($null -eq $bytes) { try { $bytes = [double]$p.WorkingSet64 } catch { $bytes = 0.0 } }
        $caminho = ''
        try { $caminho = $p.MainModule.FileName } catch { }
        $lista.Add([pscustomobject]@{ Id = [int]$p.Id; Nome = $p.ProcessName; Caminho = $caminho; Bytes = [double]$bytes })
    }
    return $lista.ToArray()
}

function Get-PidsDoItem($Mapa, [string]$Exe, [int]$PidServico, $Conhecido) {
    $ids = New-Object System.Collections.Generic.HashSet[int]
    if ($PidServico -gt 0) { [void]$ids.Add($PidServico) }
    foreach ($p in $Mapa) {
        if ($Exe -and $p.Caminho -and $p.Caminho -ieq $Exe) { [void]$ids.Add($p.Id); continue }
        if ($Conhecido) { foreach ($re in @($Conhecido.Processos)) { if ($re -and $p.Nome -match $re) { [void]$ids.Add($p.Id); break } } }
    }
    return [int[]]@($ids)
}

function Get-BytesPids($Mapa, [int[]]$Pids) {
    $t = 0.0
    foreach ($p in $Mapa) { if ($Pids -contains $p.Id) { $t += $p.Bytes } }
    return $t
}

# ---------------- Estado salvo ----------------
function Get-ArqSegundoPlano { return (Join-Path $Script:Otz.Dados 'segundo-plano.json') }

function Get-EstadoSegundoPlano {
    $r = @{ Itens = @{}; Escolhidos = $null }
    $arq = Get-ArqSegundoPlano
    if (-not (Test-Path $arq)) { return $r }
    try {
        $o = [IO.File]::ReadAllText($arq, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($o.Itens) { foreach ($p in $o.Itens.PSObject.Properties) { $r.Itens[$p.Name] = $p.Value } }
        if ($null -ne $o.Escolhidos) { $r.Escolhidos = [string[]]@($o.Escolhidos) }
    } catch { Write-Log "Aviso: segundo-plano.json ilegível ($($_.Exception.Message))." }
    return $r
}

function Save-EstadoSegundoPlano($Estado) {
    $o = [ordered]@{ Itens = $Estado.Itens; Escolhidos = $Estado.Escolhidos }
    [IO.File]::WriteAllText((Get-ArqSegundoPlano), (ConvertTo-Json -InputObject $o -Depth 5), (New-Object Text.UTF8Encoding $false))
}

# A escolha feita na tela (lida pelo ajuste serv.segundo-plano na hora de aplicar)
function Save-EscolhidosSegundoPlano([string[]]$Ids) {
    $e = Get-EstadoSegundoPlano
    $e.Escolhidos = [string[]]@($Ids)
    Save-EstadoSegundoPlano $e
}

# ---------------- Levantamento ----------------
function Get-ItensSegundoPlano {
    $mapa = Get-MapaProcessos
    $estado = Get-EstadoSegundoPlano
    $cache = @{}
    foreach ($c in Get-ServicosCache) { $cache[$c.Name] = $c }
    $itens = New-Object System.Collections.Generic.List[object]


    # Serviços de terceiros em Automático (ou que o otimizador já passou para Manual)
    foreach ($s in @(Get-Service -ErrorAction SilentlyContinue)) {
        $id = "svc:$($s.Name)"
        $nosso = $estado.Itens.ContainsKey($id)
        $reg = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.Name)" -ErrorAction SilentlyContinue
        if (-not $reg) { continue }
        if ([int]$reg.Start -ne 2 -and -not $nosso) { continue }
        $imagem = [string]$reg.ImagePath
        if ($imagem -match 'svchost\.exe') { continue }
        $exe = Get-ExeDeComando $imagem
        $k = Find-Conhecido 'servico' @($s.Name)
        if ($k -and $k.Nivel -eq 'manter') { continue }
        $assinante = ''
        if (-not $k) {
            if (Test-ArquivoDoWindows $exe) { continue }
            if (@($s.DependentServices).Count) { continue }
            $assinante = Get-AssinanteArquivo $exe
            if ($assinante -match 'Microsoft') { continue }
        }
        $pidSvc = 0; if ($cache.ContainsKey($s.Name)) { $pidSvc = [int]$cache[$s.Name].ProcessId }
        $pids = Get-PidsDoItem $mapa $exe $pidSvc $k
        $r = [ordered]@{}
        $r.Id = $id; $r.Tipo = 'servico'
        $r.Nome = if ($k) { $k.Nome } else { $s.DisplayName }
        $r.Grupo = if ($k) { $k.Grupo } else { 'Não reconhecido' }
        $r.Nivel = if ($k) { $k.Nivel } else { 'desconhecido' }
        $r.Texto = if ($k) { $k.Texto } else { "Serviço '$($s.DisplayName)'$(if ($assinante) { " de $assinante" }) que liga com o Windows. O otimizador não o conhece: desligue só se souber o que é." }
        $r.Efeito = if ($k) { [string]$k.Efeito } else { 'Se algum programa parar de funcionar, desfaça este item.' }
        $r.Bandeja = if ($k) { [string]$k.Bandeja } else { '' }
        $r.Servico = $s.Name; $r.Aprovado = ''; $r.NomeIni = ''
        $r.Exe = $exe; $r.Pids = $pids; $r.Bytes = Get-BytesPids $mapa $pids
        $r.Aplicado = $nosso
        $r.Tecnico = "Serviço '$($s.DisplayName)' ($($s.Name)): Automático → Manual"
        $itens.Add([pscustomobject]$r)
    }

    # Itens de inicialização ativos (ou desligados pelo otimizador)
    foreach ($e in @(Get-ItensInicializacao)) {
        $id = "ini:$($e.Aprovado)|$($e.Nome)"
        $nosso = $estado.Itens.ContainsKey($id)
        if (-not $e.Ativo -and -not $nosso) { continue }
        $exe = Get-ExeDeComando ([string]$e.Comando)
        $k = Find-Conhecido 'inicio' @([string]$e.Nome, $exe)
        if ($k -and $k.Nivel -eq 'manter') { continue }
        $assinante = ''
        if (-not $k) {
            if (Test-ArquivoDoWindows $exe) { continue }
            $assinante = Get-AssinanteArquivo $exe
            if ($assinante -match 'Microsoft') { continue }
        }
        $pids = Get-PidsDoItem $mapa $exe 0 $k
        $r = [ordered]@{}
        $r.Id = $id; $r.Tipo = 'inicio'
        $r.Nome = if ($k) { $k.Nome } else { [string]$e.Nome }
        $r.Grupo = if ($k) { $k.Grupo } else { 'Não reconhecido' }
        $r.Nivel = if ($k) { $k.Nivel } else { 'desconhecido' }
        $r.Texto = if ($k) { $k.Texto } else { "Abre junto com o Windows: $exe$(if ($assinante) { " (de $assinante)" }). O otimizador não o conhece: desligue só se souber o que é." }
        $r.Efeito = if ($k) { [string]$k.Efeito } else { 'O programa continua instalado e abre quando você clicar.' }
        $r.Bandeja = if ($k) { [string]$k.Bandeja } else { '' }
        $r.Servico = ''; $r.Aprovado = [string]$e.Aprovado; $r.NomeIni = [string]$e.Nome
        $r.Exe = $exe; $r.Pids = $pids; $r.Bytes = Get-BytesPids $mapa $pids
        $r.Aplicado = $nosso
        $r.Tecnico = "Inicialização '$($e.Nome)' ($($e.Escopo)): desligada"
        $itens.Add([pscustomobject]$r)
    }

    $ordemNivel = @{ seguro = 0; depende = 1; desconhecido = 2 }
    return @($itens | Sort-Object @{ Expression = { $ordemNivel[$_.Nivel] } }, @{ Expression = { $_.Bytes }; Descending = $true })
}

# Programas que só se desligam por dentro (overlay da NVIDIA etc.), com a RAM de agora
function Get-GuiasBandejaAtivas {
    [void](Get-BaseConhecidos)
    $mapa = Get-MapaProcessos
    $res = New-Object System.Collections.Generic.List[object]
    foreach ($g in @($Script:GuiasBandeja)) {
        $bytes = 0.0
        foreach ($p in $mapa) { foreach ($re in @($g.Processos)) { if ($p.Nome -match $re) { $bytes += $p.Bytes; break } } }
        if ($bytes -gt 0) { $res.Add([pscustomobject]@{ Nome = $g.Nome; Texto = $g.Texto; Bytes = $bytes }) }
    }
    return $res.ToArray()
}

# Ids que valem para aplicar: a escolha salva ou, sem escolha, os "seguro"
function Get-IdsAlvoSegundoPlano($Itens) {
    $e = Get-EstadoSegundoPlano
    if ($null -ne $e.Escolhidos) { return [string[]]@($e.Escolhidos) }
    return [string[]]@($Itens | Where-Object Nivel -eq 'seguro' | ForEach-Object Id)
}

# ---------------- Aplicar / desfazer ----------------
function Invoke-AplicarItemSp($Item, $Estado) {
    if ($Item.Tipo -eq 'servico') {
        $st = Get-ServicoEstado $Item.Servico
        if (-not $Estado.Itens.ContainsKey($Item.Id)) {
            $Estado.Itens[$Item.Id] = [pscustomobject]@{ Tipo = 'servico'; Nome = $Item.Nome; Servico = $Item.Servico; Modo = $st.Modo; Rodava = [bool]$st.Rodando; Data = (Get-Date).ToString('s') }
        }
        Set-ServicoModo $Item.Servico 'demand'
        if ($st.Rodando) { Stop-Service -Name $Item.Servico -Force -ErrorAction SilentlyContinue }
        Write-Log "Segundo plano: serviço $($Item.Servico) → Manual"
    } else {
        if (-not $Estado.Itens.ContainsKey($Item.Id)) {
            $Estado.Itens[$Item.Id] = [pscustomobject]@{ Tipo = 'inicio'; Nome = $Item.Nome; Aprovado = $Item.Aprovado; NomeIni = $Item.NomeIni; Data = (Get-Date).ToString('s') }
        }
        Set-ItemInicializacao $Item.Aprovado $Item.NomeIni $false
    }
}

function Invoke-DesfazerItemSp([string]$Id, $Orig) {
    if ($Orig.Tipo -eq 'servico') {
        $modo = [string]$Orig.Modo; if (-not $modo) { $modo = 'auto' }
        Set-ServicoModo $Orig.Servico $modo
        if ($Orig.Rodava) { Start-Service -Name $Orig.Servico -ErrorAction SilentlyContinue }
        Write-Log "Segundo plano: serviço $($Orig.Servico) voltou para $modo"
    } else {
        Set-ItemInicializacao $Orig.Aprovado $Orig.NomeIni $true
    }
}

# Deixa o PC igual à escolha: aplica os escolhidos e desfaz os que saíram da escolha
function Sync-SegundoPlano([string[]]$Ids) {
    $itens = @(Get-ItensSegundoPlano)
    $estado = Get-EstadoSegundoPlano
    $ok = New-Object System.Collections.Generic.List[string]
    $erros = New-Object System.Collections.Generic.List[string]
    $voltaram = 0
    # Memória que os escolhidos usam agora (antes de desligar), sem contar o mesmo processo duas vezes
    $bytes = 0.0
    $mapa = Get-MapaProcessos
    $pids = New-Object System.Collections.Generic.HashSet[int]
    foreach ($it in $itens) { if ($Ids -contains $it.Id -and -not $it.Aplicado) { foreach ($p in $it.Pids) { [void]$pids.Add($p) } } }
    foreach ($p in $mapa) { if ($pids.Contains($p.Id)) { $bytes += $p.Bytes } }
    foreach ($it in $itens) {
        if ($Ids -contains $it.Id) {
            if ($it.Aplicado) { continue }
            try { Invoke-AplicarItemSp $it $estado; $ok.Add($it.Nome) } catch { $erros.Add("$($it.Nome): $($_.Exception.Message)") }
        }
    }
    foreach ($id in @($estado.Itens.Keys)) {
        if ($Ids -contains $id) { continue }
        try { Invoke-DesfazerItemSp $id $estado.Itens[$id]; $estado.Itens.Remove($id); $voltaram++ } catch { $erros.Add("$($estado.Itens[$id].Nome): $($_.Exception.Message)") }
    }
    $estado.Escolhidos = [string[]]@($Ids)
    Save-EstadoSegundoPlano $estado
    return [pscustomobject]@{ Aplicados = $ok.ToArray(); Voltaram = $voltaram; Erros = $erros.ToArray(); Bytes = $bytes }
}

function Undo-SegundoPlano {
    $estado = Get-EstadoSegundoPlano
    $erros = New-Object System.Collections.Generic.List[string]
    $n = 0
    foreach ($id in @($estado.Itens.Keys)) {
        try { Invoke-DesfazerItemSp $id $estado.Itens[$id]; $estado.Itens.Remove($id); $n++ } catch { $erros.Add("$($estado.Itens[$id].Nome): $($_.Exception.Message)") }
    }
    $estado.Escolhidos = $null
    Save-EstadoSegundoPlano $estado
    return [pscustomobject]@{ Desfeitos = $n; Erros = $erros.ToArray() }
}

# Guardião (manutenção semanal): atualizações às vezes religam o que foi desligado
function Invoke-GuardiaoSegundoPlano {
    $estado = Get-EstadoSegundoPlano
    $refeitos = New-Object System.Collections.Generic.List[string]
    $inicio = @{}
    foreach ($e in @(Get-ItensInicializacao)) { $inicio["$($e.Aprovado)|$($e.Nome)"] = $e }
    foreach ($id in @($estado.Itens.Keys)) {
        $o = $estado.Itens[$id]
        try {
            if ($o.Tipo -eq 'servico') {
                $st = Get-ServicoEstado $o.Servico
                if ($st.Existe -and $st.Modo -in 'auto', 'delayed-auto') { Set-ServicoModo $o.Servico 'demand'; $refeitos.Add($o.Nome) }
            } else {
                $e = $inicio["$($o.Aprovado)|$($o.NomeIni)"]
                if ($e -and $e.Ativo) { Set-ItemInicializacao $o.Aprovado $o.NomeIni $false; $refeitos.Add($o.Nome) }
            }
        } catch { Write-Log "Guardião: $($o.Nome): $($_.Exception.Message)" }
    }
    if ($refeitos.Count) { Write-Log "Guardião do segundo plano: desligou de novo $($refeitos -join ', ')" }
    return $refeitos.ToArray()
}

# Garante a tarefa semanal com o Guardião ligado (cria uma, se ainda não existir)
function Enable-GuardiaoSegundoPlano {
    if (-not (Get-Command Register-Manutencao -ErrorAction SilentlyContinue)) { return $false }
    $cfg = Get-ConfigManutencao
    $existe = [bool](Get-ScheduledTask -TaskName $Script:NomeTarefaManut -ErrorAction SilentlyContinue)
    if ($existe -and $cfg.Guardiao) { return $true }
    $novo = [ordered]@{}
    $novo.Frequencia = if ($existe) { $cfg.Frequencia } else { 'semanal' }
    $novo.Dia = if ($existe) { $cfg.Dia } else { 'Sunday' }
    $novo.Hora = if ($existe) { $cfg.Hora } else { '12:00' }
    $novo.Tarefas = if ($existe) { @($cfg.Tarefas) } else { @() }
    $novo.Verificar = if ($existe) { [bool]$cfg.Verificar } else { $false }
    $novo.Guardiao = $true
    if ($existe) { [void](Save-ConfigManutencao ([pscustomobject]$novo)) } else { Register-Manutencao ([pscustomobject]$novo) }
    return $true
}
