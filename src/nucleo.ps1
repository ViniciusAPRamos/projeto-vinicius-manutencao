#Requires -Version 5.1
<#
    Núcleo do Otimizador Vinicius v2.0
    ---------------------------------------------------------------
    Motor que lê o catálogo (src\catalogo\*.ps1) e executa cada ajuste:
      - Get-EstadoAjuste   → já está aplicado?
      - Get-SimulacaoAjuste → o que mudaria (sem alterar nada)
      - Invoke-AplicarAjuste / Invoke-DesfazerAjuste

    Desfazer por item: antes da PRIMEIRA alteração de um ajuste, o valor
    original exato (inclusive "não existia") é salvo em originais.json.
    Assim o desfazer apaga o que foi criado, coisa que o .reg não fazia.

    Usado tanto pela janela (thread da interface) quanto pelas tarefas
    em segundo plano (runspace). Não use Write-Host aqui.
#>

$Script:Otz = @{}

# ---------------------------------------------------------------
#  Inicialização
# ---------------------------------------------------------------
function Initialize-Otz {
    param(
        [Parameter(Mandatory)][string]$SrcDir,
        $Fila = $null,
        [string]$SidAlvo = $null
    )
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $dados = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'OtimizadorVinicius'
    $Script:Otz = @{
        Versao     = '2.0'
        SrcDir     = $SrcDir
        Fila       = $Fila
        SidAlvo    = $SidAlvo   # preenchido quando o admin é outra conta: HKCU vira HKU\<sid>
        Dados      = $dados
        Build      = [int]$cv.CurrentBuildNumber
        Ubr        = [int]$cv.UBR
        VersaoWin  = [string]$cv.DisplayVersion
        Edicao     = [string]$cv.EditionID
        NomePlano  = 'Vinicius - Desempenho Maximo'
    }
    $Script:Otz.IsWin11 = $Script:Otz.Build -ge 22000
    $Script:Otz.ArqOriginais = Join-Path $dados 'originais.json'
    $Script:Otz.ArqHistorico = Join-Path $dados 'historico.jsonl'
    $Script:Otz.ArqLog       = Join-Path $dados ("log_" + (Get-Date -Format 'yyyy-MM-dd') + ".txt")
    New-Item -ItemType Directory -Path $dados -Force | Out-Null

    if (-not ('OtzWin32' -as [type])) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class OtzWin32 {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni);
    [DllImport("user32.dll", SetLastError = true, EntryPoint = "SystemParametersInfo")]
    public static extern bool SystemParametersInfoPtr(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
}
"@
    }
    if (-not ('Otz.Tela' -as [type])) {
        Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $SrcDir 'ui\Tela.cs'), [Text.Encoding]::UTF8))
    }
}

# Envia um evento para a interface (no-op quando não há fila)
function Send-Evento([hashtable]$Dados) {
    if ($Script:Otz.Fila) { $Script:Otz.Fila.Enqueue([pscustomobject]$Dados) }
}

function Write-Log([string]$Texto) {
    $linha = (Get-Date -Format 'HH:mm:ss') + '  ' + $Texto + [Environment]::NewLine
    for ($i = 0; $i -lt 3; $i++) {
        try { [IO.File]::AppendAllText($Script:Otz.ArqLog, $linha, (New-Object Text.UTF8Encoding $true)); break }
        catch { Start-Sleep -Milliseconds 50 }
    }
    Send-Evento @{ Tipo = 'log'; Texto = $Texto }
}

# ---------------------------------------------------------------
#  Usuário alvo
#  Se o administrador que elevou for outra conta, os ajustes de HKCU
#  precisam ir para o usuário logado (dono do explorer.exe da sessão).
# ---------------------------------------------------------------
function Get-SidUsuarioSessao {
    $atual  = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $sessao = [Diagnostics.Process]::GetCurrentProcess().SessionId
    try {
        $exp = Get-CimInstance Win32_Process -Filter "Name='explorer.exe' AND SessionId=$sessao" -ErrorAction Stop | Select-Object -First 1
        if ($exp) {
            $sid = (Invoke-CimMethod -InputObject $exp -MethodName GetOwnerSid -ErrorAction Stop).Sid
            if ($sid -and $sid -ne $atual) { return $sid }
        }
    } catch { }
    return $null
}

function Get-NomeConta([string]$Sid) {
    try { return (New-Object Security.Principal.SecurityIdentifier $Sid).Translate([Security.Principal.NTAccount]).Value }
    catch { return $Sid }
}

# ---------------------------------------------------------------
#  Registro (via .NET: trata valor padrão, HKU e tipos exatos)
#  Caminhos no formato do reg.exe: 'HKCU\Control Panel\Mouse'
# ---------------------------------------------------------------
function Get-RegRaiz([string]$Caminho) {
    $hive, $sub = $Caminho -split '\\', 2
    switch ($hive) {
        'HKCU' {
            if ($Script:Otz.SidAlvo) {
                return @{ Base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('Users', 'Registry64'); Sub = "$($Script:Otz.SidAlvo)\$sub" }
            }
            return @{ Base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('CurrentUser', 'Registry64'); Sub = $sub }
        }
        'HKLM' { return @{ Base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64'); Sub = $sub } }
        'HKU'  { return @{ Base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('Users', 'Registry64'); Sub = $sub } }
        default { throw "Raiz de registro não suportada: $hive" }
    }
}

function Test-RegChave([string]$Caminho) {
    $r = Get-RegRaiz $Caminho
    $k = $r.Base.OpenSubKey($r.Sub)
    if ($k) { $k.Close(); return $true }
    return $false
}

# Devolve @{ Existe; Tipo; Valor }
function Read-RegValor([string]$Caminho, [string]$Nome) {
    $r = Get-RegRaiz $Caminho
    $k = $r.Base.OpenSubKey($r.Sub)
    if (-not $k) { return @{ Existe = $false; Tipo = $null; Valor = $null } }
    try {
        if (@($k.GetValueNames()) -notcontains $Nome) { return @{ Existe = $false; Tipo = $null; Valor = $null } }
        $v = $k.GetValue($Nome, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        return @{ Existe = $true; Tipo = [string]$k.GetValueKind($Nome); Valor = $v }
    } finally { $k.Close() }
}

function ConvertTo-RegValor($Valor, [string]$Tipo) {
    switch ($Tipo) {
        'DWord'        { return [int]$Valor }
        'QWord'        { return [long]$Valor }
        # A vírgula impede o PowerShell de "desmontar" o array no retorno
        'Binary'       { return , ([byte[]]@($Valor)) }
        'MultiString'  { return , ([string[]]@($Valor)) }
        default        { return [string]$Valor }
    }
}

function Write-RegValor([string]$Caminho, [string]$Nome, $Valor, [string]$Tipo = 'DWord') {
    $r = Get-RegRaiz $Caminho
    $k = $r.Base.CreateSubKey($r.Sub)
    if (-not $k) { throw "Não foi possível abrir/criar $Caminho" }
    try { $k.SetValue($Nome, (ConvertTo-RegValor $Valor $Tipo), [Microsoft.Win32.RegistryValueKind]$Tipo) }
    finally { $k.Close() }
}

function Remove-RegValor([string]$Caminho, [string]$Nome) {
    $r = Get-RegRaiz $Caminho
    $k = $r.Base.OpenSubKey($r.Sub, $true)
    if (-not $k) { return }
    try { $k.DeleteValue($Nome, $false) } finally { $k.Close() }
}

# Primeiro nível que ainda não existe (para apagar no desfazer só o que foi criado)
function Get-PrimeiraChaveAusente([string]$Caminho) {
    $partes = $Caminho -split '\\'
    for ($i = 2; $i -le $partes.Count; $i++) {
        $p = ($partes[0..($i - 1)] -join '\')
        if (-not (Test-RegChave $p)) { return $p }
    }
    return $null
}

# Apaga chaves vazias do caminho até o nível que o otimizador criou
function Remove-RegChavesVazias([string]$Caminho, [string]$Ate) {
    $atual = $Caminho
    while ($atual -and $atual.Length -ge $Ate.Length) {
        $r = Get-RegRaiz $atual
        $k = $r.Base.OpenSubKey($r.Sub)
        if (-not $k) { $atual = Split-Path $atual -Parent; continue }
        $vazia = ($k.ValueCount -eq 0 -and $k.SubKeyCount -eq 0)
        $k.Close()
        if (-not $vazia) { return }
        $pai = Split-Path $atual -Parent
        $rp = Get-RegRaiz $pai
        $kp = $rp.Base.OpenSubKey($rp.Sub, $true)
        if ($kp) { $kp.DeleteSubKey((Split-Path $atual -Leaf), $false); $kp.Close() }
        if ($atual -eq $Ate) { return }
        $atual = $pai
    }
}

function Format-RegValor($Valor, [string]$Tipo) {
    if ($null -eq $Valor) { return '(não existe)' }
    if ($Tipo -eq 'Binary') { return (@($Valor) | ForEach-Object { '{0:X2}' -f [int]$_ }) -join ' ' }
    if ($Tipo -eq 'String' -or $Tipo -eq 'ExpandString') { return '"' + $Valor + '"' }
    return [string]$Valor
}

function Test-RegIgual($Atual, $Desejado, [string]$Tipo) {
    if (-not $Atual.Existe) { return $false }
    if ($Tipo -eq 'Binary') { return ((@($Atual.Valor) -join ',') -eq (@($Desejado) -join ',')) }
    if ($Tipo -eq 'DWord' -or $Tipo -eq 'QWord') {
        try { return ([long]$Atual.Valor -eq [long]$Desejado) } catch { return $false }
    }
    return ([string]$Atual.Valor -eq [string]$Desejado)
}

# ---------------------------------------------------------------
#  Energia (powercfg)
# ---------------------------------------------------------------
$Script:RegexGuid = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

function Get-PlanoAtivo {
    $o = (powercfg /getactivescheme 2>$null) -join ' '
    if ($o -match "($Script:RegexGuid)\s*\((.+)\)") { return @{ Guid = $Matches[1]; Nome = $Matches[2].Trim() } }
    if ($o -match "($Script:RegexGuid)") { return @{ Guid = $Matches[1]; Nome = '' } }
    return $null
}

# Índice AC atual: na saída de "powercfg /q" os dois últimos hexadecimais são AC e DC
# (vale para qualquer idioma do Windows)
# -Dc lê o índice da bateria (último hexadecimal) em vez da tomada (penúltimo)
function Get-EnergiaIndice([string]$Plano, [string]$Sub, [string]$Config, [switch]$Dc) {
    $o = (powercfg /q $Plano $Sub $Config 2>$null) -join "`n"
    $hex = [regex]::Matches($o, '0x([0-9a-fA-F]{8})')
    if ($hex.Count -lt 2) { return $null }
    $pos = if ($Dc) { $hex.Count - 1 } else { $hex.Count - 2 }
    return [Convert]::ToInt32($hex[$pos].Groups[1].Value, 16)
}

function Set-EnergiaIndice([string]$Plano, [string]$Sub, [string]$Config, [int]$Valor, [switch]$Dc) {
    $acao = if ($Dc) { '/setdcvalueindex' } else { '/setacvalueindex' }
    $saida = powercfg $acao $Plano $Sub $Config $Valor 2>&1
    if ($LASTEXITCODE -ne 0) { throw "powercfg recusou $Sub/$Config : $($saida -join ' ')" }
    $ativo = Get-PlanoAtivo
    if ($ativo -and $ativo.Guid -eq $Plano) { powercfg /setactive $Plano 2>&1 | Out-Null }
}

# ---------------------------------------------------------------
#  Serviços do Windows
#  Modo no formato do sc.exe: auto | delayed-auto | demand | disabled
# ---------------------------------------------------------------
$Script:NomesModoServico = @{ 'auto' = 'Automático'; 'delayed-auto' = 'Automático (atrasado)'; 'demand' = 'Manual'; 'disabled' = 'Desativado'; 'boot' = 'Boot'; 'system' = 'Sistema' }

# Estado e PID de todos os serviços SEM WMI: o Win32_Service trava em alguns PCs
# (visto num Dell G15 com utilitários de terceiros). Get-Service dá o estado e
# "tasklist /svc" dá o PID de cada serviço (CSV: imagem, PID, serviços).
function Get-ServicosCache {
    if (-not $Script:CacheSvc -or ((Get-Date) - $Script:CacheSvcData).TotalSeconds -gt 15) {
        $pids = @{}
        foreach ($l in @(tasklist.exe /svc /fo csv /nh 2>$null | ConvertFrom-Csv -Header Imagem, Pid, Servicos)) {
            foreach ($n in ([string]$l.Servicos -split ',')) { $n = $n.Trim(); if ($n) { $pids[$n] = [int]$l.Pid } }
        }
        $lista = New-Object System.Collections.Generic.List[object]
        foreach ($s in @(Get-Service -ErrorAction SilentlyContinue)) {
            $lista.Add([pscustomobject]@{ Name = $s.Name; State = [string]$s.Status; ProcessId = [int]$pids[$s.Name] })
        }
        $Script:CacheSvc = $lista.ToArray()
        $Script:CacheSvcData = Get-Date
    }
    return $Script:CacheSvc
}

# Devolve @{ Existe; Modo; Rodando; MemBytes } (MemBytes só quando o serviço tem processo próprio)
function Get-ServicoEstado([string]$Nome) {
    $chave = "HKLM\SYSTEM\CurrentControlSet\Services\$Nome"
    if (-not (Test-RegChave $chave)) { return @{ Existe = $false } }
    $start = (Read-RegValor $chave 'Start').Valor
    $modo = switch ([int]$start) { 0 { 'boot' } 1 { 'system' } 2 { 'auto' } 3 { 'demand' } 4 { 'disabled' } default { "$start" } }
    $atraso = Read-RegValor $chave 'DelayedAutostart'
    if ($modo -eq 'auto' -and $atraso.Existe -and [int]$atraso.Valor -eq 1) { $modo = 'delayed-auto' }
    $todos = Get-ServicosCache
    $svc = $todos | Where-Object { $_.Name -eq $Nome } | Select-Object -First 1
    $rodando = [bool]($svc -and $svc.State -eq 'Running')
    $mem = $null
    if ($rodando -and $svc.ProcessId -gt 0) {
        # No Windows 10/11 com mais de 3,5 GB de RAM, cada serviço costuma ter o próprio svchost
        $vizinhos = @($todos | Where-Object { $_.ProcessId -eq $svc.ProcessId }).Count
        if ($vizinhos -eq 1) { try { $mem = (Get-Process -Id $svc.ProcessId -ErrorAction Stop).WorkingSet64 } catch { } }
    }
    return @{ Existe = $true; Modo = $modo; Rodando = $rodando; MemBytes = $mem }
}

function Set-ServicoModo([string]$Nome, [string]$Modo) {
    $saida = sc.exe config $Nome start= $Modo 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sc config $Nome : $(($saida | Where-Object { $_ }) -join ' ')" }
    $Script:CacheSvc = $null
}

# ---------------------------------------------------------------
#  DirectX: opções globais de jogos (Configurações > Tela > Gráficos)
#  Ficam numa única string "Chave=valor;Chave=valor;"
# ---------------------------------------------------------------
$Script:ChaveDx = 'HKCU\Software\Microsoft\DirectX\UserGpuPreferences'

function Get-DxGlobal {
    $d = [ordered]@{}
    $v = Read-RegValor $Script:ChaveDx 'DirectXUserGlobalSettings'
    if ($v.Existe) {
        foreach ($par in ([string]$v.Valor -split ';')) {
            if ($par -match '^\s*([^=]+)=(.*)$') { $d[$Matches[1].Trim()] = $Matches[2].Trim() }
        }
    }
    return $d
}

function Set-DxGlobal($Dados) {
    if ($Dados.Count -eq 0) { Remove-RegValor $Script:ChaveDx 'DirectXUserGlobalSettings'; return }
    $txt = (@($Dados.Keys) | ForEach-Object { "$_=$($Dados[$_]);" }) -join ''
    Write-RegValor $Script:ChaveDx 'DirectXUserGlobalSettings' $txt 'String'
}

# ---------------------------------------------------------------
#  Requisitos usados pelo catálogo (com cache: rodam na thread da janela)
# ---------------------------------------------------------------
function Test-Notebook {
    if ($null -eq $Script:EhNotebook) { $Script:EhNotebook = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) }
    return $Script:EhNotebook
}

function Test-ImpressoraFisica {
    if ($null -eq $Script:TemImpressora) {
        $virtuais = 'PDF|XPS|OneNote|Fax|Send To|Enviar para'
        $Script:TemImpressora = [bool](Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch $virtuais })
    }
    return $Script:TemImpressora
}

# ---------------------------------------------------------------
#  Originais (desfazer por item)
# ---------------------------------------------------------------
function Get-Originais {
    $h = @{}
    if (-not (Test-Path $Script:Otz.ArqOriginais)) { return $h }
    try {
        $json = [IO.File]::ReadAllText($Script:Otz.ArqOriginais, [Text.Encoding]::UTF8)
        $obj = $json | ConvertFrom-Json
        foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = $p.Value }
    } catch { Write-Log "Aviso: originais.json ilegível ($($_.Exception.Message))." }
    return $h
}

function Save-Originais([hashtable]$Tabela) {
    $json = ConvertTo-Json -InputObject $Tabela -Depth 8
    [IO.File]::WriteAllText($Script:Otz.ArqOriginais, $json, (New-Object Text.UTF8Encoding $false))
}

function Get-Original([string]$Id) { return (Get-Originais)[$Id] }

function Set-Original([string]$Id, $Dados) {
    $t = Get-Originais
    $t[$Id] = $Dados
    Save-Originais $t
}

function Remove-Original([string]$Id) {
    $t = Get-Originais
    if ($t.ContainsKey($Id)) { $t.Remove($Id); Save-Originais $t }
}

# ---------------------------------------------------------------
#  Catálogo
# ---------------------------------------------------------------
function Get-Catalogo {
    $pasta = Join-Path $Script:Otz.SrcDir 'catalogo'
    $ordem = 0
    foreach ($arq in Get-ChildItem $pasta -Filter '*.ps1' | Sort-Object Name) {
        foreach ($item in @(. $arq.FullName)) {
            if ($item -isnot [hashtable]) { continue }
            $ordem++
            $item.Ordem = $ordem
            foreach ($padrao in @{ Windows = @('10', '11'); BuildMinima = 0; Perfis = @(); Reinicio = 'nenhum'; Risco = 'seguro'; Tipo = 'ajuste' }.GetEnumerator()) {
                if (-not $item.ContainsKey($padrao.Key)) { $item[$padrao.Key] = $padrao.Value }
            }
            $item
        }
    }
}

# Compatibilidade com o Windows escolhido ('10' ou '11')
function Test-Compativel([hashtable]$Item, [string]$WinAlvo) {
    if ($Item.Windows -notcontains $WinAlvo) {
        $outro = if ($WinAlvo -eq '11') { 'Windows 10' } else { 'Windows 11' }
        return @{ Ok = $false; Motivo = "Só existe no $outro." }
    }
    $winReal = if ($Script:Otz.IsWin11) { '11' } else { '10' }
    if ($WinAlvo -eq $winReal -and $Item.BuildMinima -gt 0 -and $Script:Otz.Build -lt $Item.BuildMinima) {
        return @{ Ok = $false; Motivo = "Precisa do Windows build $($Item.BuildMinima) ou mais novo (este é $($Script:Otz.Build)). Atualize o Windows." }
    }
    if ($Item.ContainsKey('Requisito')) {
        $falha = & $Item.Requisito
        if ($falha) { return @{ Ok = $false; Motivo = [string]$falha } }
    }
    return @{ Ok = $true; Motivo = '' }
}

# Texto técnico "o que muda" gerado a partir dos dados do item
function Get-TecnicoAjuste([hashtable]$Item) {
    $linhas = New-Object System.Collections.Generic.List[string]
    foreach ($r in @($Item.Registro)) {
        if (-not $r) { continue }
        $nome = if ($r.Nome -eq '') { '(Padrão)' } else { $r.Nome }
        $linhas.Add("$($r.Chave)`n    $nome = $(Format-RegValor $r.Valor $r.Tipo)  [$($r.Tipo)]")
    }
    foreach ($e in @($Item.Energia)) {
        if (-not $e) { continue }
        $cmd = if ($e.Corrente -eq 'dc') { '/setdcvalueindex' } else { '/setacvalueindex' }
        $linhas.Add("powercfg $cmd <plano ativo> $($e.Sub) $($e.Config) $($e.Valor)")
    }
    foreach ($s in @($Item.Servicos)) {
        if (-not $s) { continue }
        $linhas.Add("sc config $($s.Nome) start= $($s.Modo)   ($($Script:NomesModoServico[$s.Modo]))")
    }
    if ($Item.DirectX) {
        $linhas.Add("$($Script:ChaveDx)`n    DirectXUserGlobalSettings: " + ((@($Item.DirectX) | ForEach-Object { "$($_.Chave)=$($_.Valor);" }) -join ''))
    }
    if ($Item.Tecnico) { $linhas.Add($Item.Tecnico) }
    return ($linhas -join "`n")
}

# ---------------------------------------------------------------
#  Detectar
#  Estado: aplicado | parcial | nao | acao | na | erro
# ---------------------------------------------------------------
function Get-EstadoAjuste([hashtable]$Item) {
    try {
        if ($Item.Detectar) {
            $r = & $Item.Detectar
            if ($r -is [string]) { return @{ Estado = $r; Texto = '' } }
            return $r
        }
        $total = 0; $iguais = 0
        foreach ($r in @($Item.Registro)) {
            if (-not $r) { continue }
            $total++
            if (Test-RegIgual (Read-RegValor $r.Chave $r.Nome) $r.Valor $r.Tipo) { $iguais++ }
        }
        if ($Item.Energia) {
            $plano = (Get-PlanoAtivo).Guid
            foreach ($e in $Item.Energia) {
                $total++
                if ((Get-EnergiaIndice $plano $e.Sub $e.Config -Dc:($e.Corrente -eq 'dc')) -eq $e.Valor) { $iguais++ }
            }
        }
        $texto = ''
        if ($Item.Servicos) {
            $rodando = 0; $mem = 0.0; $existem = 0
            foreach ($s in $Item.Servicos) {
                $st = Get-ServicoEstado $s.Nome
                if (-not $st.Existe) { continue }
                $existem++; $total++
                if ($st.Modo -eq $s.Modo) { $iguais++ }
                if ($st.Rodando) { $rodando++; if ($st.MemBytes) { $mem += $st.MemBytes } }
            }
            if ($existem -eq 0) { return @{ Estado = 'na'; Texto = 'Este serviço não existe nesta instalação do Windows.' } }
            $texto = if ($rodando -eq 0) { 'Parado agora' }
                     elseif ($mem -gt 0) { "Rodando agora · usa $(Format-Tamanho $mem) de RAM" }
                     else { 'Rodando agora (divide processo com outros serviços)' }
        }
        if ($Item.DirectX) {
            $dx = Get-DxGlobal
            foreach ($d in $Item.DirectX) { $total++; if ([string]$dx[$d.Chave] -eq [string]$d.Valor) { $iguais++ } }
        }
        if ($total -eq 0) { return @{ Estado = 'acao'; Texto = $texto } }
        if ($iguais -eq $total) { return @{ Estado = 'aplicado'; Texto = $texto } }
        if ($iguais -eq 0) { return @{ Estado = 'nao'; Texto = $texto } }
        $parcial = "$iguais de $total configurações já estão assim."
        if ($texto) { $parcial = "$texto · $parcial" }
        return @{ Estado = 'parcial'; Texto = $parcial }
    } catch {
        return @{ Estado = 'erro'; Texto = $_.Exception.Message }
    }
}

# ---------------------------------------------------------------
#  Simular (não altera nada)
# ---------------------------------------------------------------
function Get-SimulacaoAjuste([hashtable]$Item) {
    $linhas = New-Object System.Collections.Generic.List[string]
    foreach ($r in @($Item.Registro)) {
        if (-not $r) { continue }
        $atual = Read-RegValor $r.Chave $r.Nome
        $nome = if ($r.Nome -eq '') { '(Padrão)' } else { $r.Nome }
        $de   = if ($atual.Existe) { Format-RegValor $atual.Valor $atual.Tipo } else { '(não existe)' }
        $para = Format-RegValor $r.Valor $r.Tipo
        if (Test-RegIgual $atual $r.Valor $r.Tipo) { $linhas.Add("= $nome já é $para") }
        else { $linhas.Add("→ $nome`: $de  →  $para") }
    }
    if ($Item.Energia) {
        $plano = Get-PlanoAtivo
        foreach ($e in $Item.Energia) {
            $dc = $e.Corrente -eq 'dc'
            $onde = if ($dc) { 'na bateria' } else { 'na tomada' }
            $atual = Get-EnergiaIndice $plano.Guid $e.Sub $e.Config -Dc:$dc
            if ($null -eq $atual) { $linhas.Add("⚠ $($e.Config): configuração não existe neste PC") }
            elseif ($atual -eq $e.Valor) { $linhas.Add("= $($e.Config) já é $($e.Valor) $onde") }
            else { $linhas.Add("→ $($e.Config): $atual  →  $($e.Valor) (plano '$($plano.Nome)', $onde)") }
        }
    }
    foreach ($s in @($Item.Servicos)) {
        if (-not $s) { continue }
        $st = Get-ServicoEstado $s.Nome
        $para = $Script:NomesModoServico[$s.Modo]
        if (-not $st.Existe) { $linhas.Add("= $($s.Nome): não existe neste Windows"); continue }
        $de = $Script:NomesModoServico[$st.Modo]
        $extra = if ($st.Rodando) { if ($st.MemBytes) { " (rodando, $(Format-Tamanho $st.MemBytes); seria parado)" } else { ' (rodando; seria parado)' } } else { '' }
        if ($st.Modo -eq $s.Modo) { $linhas.Add("= $($s.Nome) já é $para") }
        else { $linhas.Add("→ $($s.Nome): $de  →  $para$extra") }
    }
    if ($Item.DirectX) {
        $dx = Get-DxGlobal
        foreach ($d in $Item.DirectX) {
            $de = if ($dx.Contains($d.Chave)) { $dx[$d.Chave] } else { '(não definido)' }
            if ([string]$dx[$d.Chave] -eq [string]$d.Valor) { $linhas.Add("= $($d.Chave) já é $($d.Valor)") }
            else { $linhas.Add("→ $($d.Chave): $de  →  $($d.Valor)") }
        }
    }
    if ($Item.Simular) { foreach ($l in @(& $Item.Simular)) { $linhas.Add([string]$l) } }
    if ($linhas.Count -eq 0) { $linhas.Add('Executaria a ação descrita nos detalhes.') }
    return @($linhas)
}

# ---------------------------------------------------------------
#  Aplicar
#  Retorno: @{ Status = ok|erro|aviso|ignorado; Mensagem }
# ---------------------------------------------------------------
function Invoke-AplicarAjuste([hashtable]$Item) {
    $erros = New-Object System.Collections.Generic.List[string]
    $temReg = [bool]$Item.Registro
    $temEne = [bool]$Item.Energia
    $temSvc = [bool]$Item.Servicos
    $temDx  = [bool]$Item.DirectX

    # 1) Guarda o estado original (só na primeira vez)
    if (($temReg -or $temEne -or $temSvc -or $temDx) -and -not (Get-Original $Item.Id)) {
        $orig = @{ Data = (Get-Date).ToString('s'); Registro = @(); Energia = @(); Servicos = @(); DirectX = @() }
        if ($temSvc) {
            $orig.Servicos = @(foreach ($s in $Item.Servicos) {
                $st = Get-ServicoEstado $s.Nome
                if ($st.Existe) { @{ Nome = $s.Nome; Modo = $st.Modo; Rodando = $st.Rodando } }
            })
        }
        if ($temDx) {
            $dx = Get-DxGlobal
            $orig.DirectX = @(foreach ($d in $Item.DirectX) { @{ Chave = $d.Chave; Existia = $dx.Contains($d.Chave); Valor = [string]$dx[$d.Chave] } })
        }
        if ($temReg) {
            $orig.Registro = @(foreach ($r in $Item.Registro) {
                $a = Read-RegValor $r.Chave $r.Nome
                $val = $a.Valor
                if ($a.Tipo -eq 'Binary' -and $val) { $val = @($val | ForEach-Object { [int]$_ }) }
                @{ Chave = $r.Chave; Nome = $r.Nome; Existia = $a.Existe; Tipo = $a.Tipo; Valor = $val; ChaveCriada = (Get-PrimeiraChaveAusente $r.Chave) }
            })
        }
        if ($temEne) {
            $plano = (Get-PlanoAtivo).Guid
            $orig.Energia = @(foreach ($e in $Item.Energia) {
                @{ Plano = $plano; Sub = $e.Sub; Config = $e.Config; Corrente = [string]$e.Corrente; Valor = (Get-EnergiaIndice $plano $e.Sub $e.Config -Dc:($e.Corrente -eq 'dc')) }
            })
        }
        Set-Original $Item.Id $orig
    }

    # 2) Registro
    if ($temReg) {
        foreach ($r in $Item.Registro) {
            try {
                Write-RegValor $r.Chave $r.Nome $r.Valor $r.Tipo
                Write-Log "  $($r.Chave)\$($r.Nome) = $(Format-RegValor $r.Valor $r.Tipo)"
            } catch {
                $erros.Add("$($r.Nome): $($_.Exception.Message)")
            }
        }
    }

    # 3) Energia
    if ($temEne) {
        $plano = (Get-PlanoAtivo).Guid
        foreach ($e in $Item.Energia) {
            try {
                Set-EnergiaIndice $plano $e.Sub $e.Config $e.Valor -Dc:($e.Corrente -eq 'dc')
                Write-Log "  powercfg $($e.Sub) $($e.Config) = $($e.Valor) ($(if ($e.Corrente -eq 'dc') { 'bateria' } else { 'tomada' }))"
            } catch { $erros.Add($_.Exception.Message) }
        }
    }

    # 4) Serviços: muda o tipo de inicialização e para o serviço (libera a memória na hora)
    $msg = ''
    if ($temSvc) {
        $liberado = 0.0
        foreach ($s in $Item.Servicos) {
            $st = Get-ServicoEstado $s.Nome
            if (-not $st.Existe) { continue }
            try {
                Set-ServicoModo $s.Nome $s.Modo
                Write-Log "  serviço $($s.Nome): $($st.Modo) -> $($s.Modo)"
                if ($st.Rodando -and $s.Modo -in 'disabled', 'demand') {
                    Stop-Service -Name $s.Nome -Force -ErrorAction Stop
                    if ($st.MemBytes) { $liberado += $st.MemBytes }
                    Write-Log "  serviço $($s.Nome) parado"
                }
            } catch { $erros.Add("$($s.Nome): $($_.Exception.Message)") }
        }
        if ($liberado -gt 0) { $msg = "Parado agora. Liberou cerca de $(Format-Tamanho $liberado) de RAM." }
    }

    # 5) DirectX (opções globais de jogos)
    if ($temDx) {
        try {
            $dx = Get-DxGlobal
            foreach ($d in $Item.DirectX) { $dx[$d.Chave] = [string]$d.Valor }
            Set-DxGlobal $dx
            Write-Log "  DirectX: $((@($Item.DirectX) | ForEach-Object { "$($_.Chave)=$($_.Valor)" }) -join ', ')"
        } catch { $erros.Add("DirectX: $($_.Exception.Message)") }
    }

    # 6) Código próprio do item
    if ($Item.Aplicar) {
        $r = & $Item.Aplicar
        if ($r -is [hashtable]) {
            if ($r.Status -and $r.Status -ne 'ok') { return $r }
            $msg = [string]$r.Mensagem
        }
    }

    if ($erros.Count -gt 0) {
        return @{ Status = 'erro'; Mensagem = ($erros -join ' | ') }
    }
    if ($Item.AposAplicar) { try { & $Item.AposAplicar } catch { Write-Log "  Aviso: $($_.Exception.Message)" } }
    if (-not $msg) { $msg = 'Aplicado.' }
    return @{ Status = 'ok'; Mensagem = $msg }
}

# ---------------------------------------------------------------
#  Desfazer
# ---------------------------------------------------------------
function Invoke-DesfazerAjuste([hashtable]$Item) {
    $orig = Get-Original $Item.Id
    $erros = New-Object System.Collections.Generic.List[string]
    $fez = $false

    if ($orig) {
        foreach ($r in @($orig.Registro)) {
            if (-not $r) { continue }
            try {
                if ($r.Existia) {
                    $val = $r.Valor
                    if ($r.Tipo -eq 'Binary') { $val = [byte[]]@($val) }
                    Write-RegValor $r.Chave $r.Nome $val $r.Tipo
                    Write-Log "  $($r.Chave)\$($r.Nome) voltou para $(Format-RegValor $r.Valor $r.Tipo)"
                } else {
                    Remove-RegValor $r.Chave $r.Nome
                    Write-Log "  $($r.Chave)\$($r.Nome) removido (não existia antes)"
                    if ($r.ChaveCriada) { Remove-RegChavesVazias $r.Chave $r.ChaveCriada }
                }
                $fez = $true
            } catch { $erros.Add("$($r.Nome): $($_.Exception.Message)") }
        }
        foreach ($e in @($orig.Energia)) {
            if (-not $e -or $null -eq $e.Valor) { continue }
            try { Set-EnergiaIndice $e.Plano $e.Sub $e.Config ([int]$e.Valor) -Dc:($e.Corrente -eq 'dc'); $fez = $true }
            catch { $erros.Add($_.Exception.Message) }
        }
        foreach ($s in @($orig.Servicos)) {
            if (-not $s) { continue }
            try {
                Set-ServicoModo $s.Nome $s.Modo
                if ($s.Rodando) { Start-Service -Name $s.Nome -ErrorAction SilentlyContinue }
                Write-Log "  serviço $($s.Nome) voltou para $($s.Modo)"
                $fez = $true
            } catch { $erros.Add("$($s.Nome): $($_.Exception.Message)") }
        }
        if (@($orig.DirectX).Count -gt 0 -and $orig.DirectX[0]) {
            try {
                $dx = Get-DxGlobal
                foreach ($d in $orig.DirectX) { if ($d.Existia) { $dx[$d.Chave] = $d.Valor } else { $dx.Remove($d.Chave) } }
                Set-DxGlobal $dx
                $fez = $true
            } catch { $erros.Add("DirectX: $($_.Exception.Message)") }
        }
    }

    if ($Item.Desfazer) {
        $r = & $Item.Desfazer $orig
        if ($r -is [hashtable] -and $r.Status -and $r.Status -ne 'ok') { return $r }
        $fez = $true
    }

    if (-not $fez) {
        return @{ Status = 'aviso'; Mensagem = 'Nada para desfazer: este ajuste não foi feito pelo otimizador (ou já foi desfeito).' }
    }
    if ($erros.Count -gt 0) { return @{ Status = 'erro'; Mensagem = ($erros -join ' | ') } }
    Remove-Original $Item.Id
    if ($Item.AposDesfazer) { try { & $Item.AposDesfazer } catch { Write-Log "  Aviso: $($_.Exception.Message)" } }
    return @{ Status = 'ok'; Mensagem = 'Voltou ao valor original.' }
}

# ---------------------------------------------------------------
#  Ponto de restauração
# ---------------------------------------------------------------
function New-PontoRestauracao {
    $chave = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    # Guarda o valor do usuário (se houver) para não apagar uma configuração dele
    $anterior = (Get-ItemProperty -Path $chave -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        # O Windows só permite 1 ponto a cada 24 h; libera temporariamente
        New-ItemProperty -Path $chave -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force | Out-Null
        $avisos = $null
        Checkpoint-Computer -Description ("Otimizador Vinicius " + (Get-Date -Format 'dd/MM HH:mm')) -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningVariable avisos -WarningAction SilentlyContinue
        if ($avisos) { return @{ Status = 'aviso'; Mensagem = [string]$avisos[0] } }
        return @{ Status = 'ok'; Mensagem = 'Ponto de restauração criado.' }
    } catch {
        return @{ Status = 'aviso'; Mensagem = "Não foi possível criar o ponto: $($_.Exception.Message)" }
    } finally {
        if ($null -ne $anterior) {
            New-ItemProperty -Path $chave -Name 'SystemRestorePointCreationFrequency' -Value $anterior -PropertyType DWord -Force | Out-Null
        } else {
            Remove-ItemProperty -Path $chave -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------
#  Tamanhos (limpeza)
# ---------------------------------------------------------------
function Format-Tamanho([double]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return ('{0:N0} bytes' -f $Bytes)
}

function Get-TamanhoPastas([string[]]$Pastas) {
    $total = 0.0
    foreach ($p in $Pastas) {
        if (-not $p -or -not (Test-Path $p)) { continue }
        $s = (Get-ChildItem $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        if ($s) { $total += $s }
    }
    return $total
}

function Get-TamanhoLixeira {
    try {
        $sh = New-Object -ComObject Shell.Application
        $total = 0.0
        foreach ($i in @($sh.NameSpace(10).Items())) { $total += [double]$i.Size }
        return $total
    } catch { return $null }
}

# ---------------------------------------------------------------
#  Ações aplicadas ao vivo
# ---------------------------------------------------------------
function Update-MouseAoVivo {
    if ($Script:Otz.SidAlvo) { return }   # outra conta: vale no próximo logon
    $m = 'HKCU\Control Panel\Mouse'
    $t1 = [int](Read-RegValor $m 'MouseThreshold1').Valor
    $t2 = [int](Read-RegValor $m 'MouseThreshold2').Valor
    $ac = [int](Read-RegValor $m 'MouseSpeed').Valor
    $sens = (Read-RegValor $m 'MouseSensitivity').Valor
    $flags = 0x01 -bor 0x02   # SPIF_UPDATEINIFILE | SPIF_SENDCHANGE
    [void][OtzWin32]::SystemParametersInfo(0x0004, 0, [int[]]($t1, $t2, $ac), $flags)          # SPI_SETMOUSE
    if ($sens) { [void][OtzWin32]::SystemParametersInfoPtr(0x0071, 0, [IntPtr][int]$sens, $flags) }  # SPI_SETMOUSESPEED
}

# Avisa os programas que o tema/configuração mudou (WM_SETTINGCHANGE)
function Send-MudancaConfiguracao([string]$Area = 'ImmersiveColorSet') {
    $r = [UIntPtr]::Zero
    [void][OtzWin32]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, $Area, 0x0002, 3000, [ref]$r)
}

function Restart-Explorer {
    Get-Process explorer -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq [Diagnostics.Process]::GetCurrentProcess().SessionId } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    # Normalmente o Windows reabre sozinho; se não reabrir em 3 s, abre manualmente
    for ($i = 0; $i -lt 6; $i++) {
        Start-Sleep -Milliseconds 500
        if (Get-Process explorer -ErrorAction SilentlyContinue) { return }
    }
    Start-Process explorer.exe
}

# ---------------------------------------------------------------
#  Execução de um plano (lista de ids) com eventos para a interface
#  Modo: aplicar | desfazer | simular
# ---------------------------------------------------------------
function Invoke-Plano {
    param(
        [Parameter(Mandatory)][string[]]$Ids,
        [Parameter(Mandatory)][ValidateSet('aplicar', 'desfazer', 'simular')][string]$Modo,
        [bool]$CriarPonto = $true
    )
    $catalogo = @{}
    foreach ($i in Get-Catalogo) { $catalogo[$i.Id] = $i }
    $itens = @($Ids | Where-Object { $catalogo.ContainsKey($_) } | ForEach-Object { $catalogo[$_] } | Sort-Object { $_.Ordem })
    if ($Modo -eq 'desfazer') { [array]::Reverse($itens) }

    Write-Log "===== $($Modo.ToUpper()): $($itens.Count) item(ns) ====="
    Send-Evento @{ Tipo = 'inicio'; Total = $itens.Count; Modo = $Modo }

    if ($Modo -ne 'simular' -and $CriarPonto -and @($itens | Where-Object { $_.Tipo -ne 'acao' }).Count -gt 0) {
        Send-Evento @{ Tipo = 'ponto'; Status = 'executando'; Mensagem = 'Criando ponto de restauração (pode levar até 1 minuto)...' }
        $p = New-PontoRestauracao
        Write-Log "Ponto de restauração: $($p.Mensagem)"
        Send-Evento @{ Tipo = 'ponto'; Status = $p.Status; Mensagem = $p.Mensagem }
    }

    $resultados = New-Object System.Collections.Generic.List[object]
    $reinicioExplorer = $false
    $n = 0
    foreach ($item in $itens) {
        $n++
        Send-Evento @{ Tipo = 'item'; Id = $item.Id; Status = 'executando'; Mensagem = ''; Indice = $n }
        Write-Log "[$($item.Id)] $($item.Nome)"
        try {
            switch ($Modo) {
                'aplicar'  { $r = Invoke-AplicarAjuste $item }
                'desfazer' { $r = Invoke-DesfazerAjuste $item }
                'simular'  { $r = @{ Status = 'simulado'; Mensagem = ((Get-SimulacaoAjuste $item) -join "`n") } }
            }
        } catch {
            $r = @{ Status = 'erro'; Mensagem = $_.Exception.Message }
        }
        if ($r.Status -eq 'ok' -and $item.Reinicio -eq 'explorer') { $reinicioExplorer = $true }
        Write-Log "  → $($r.Status): $($r.Mensagem)"
        $resultados.Add([pscustomobject]@{ Id = $item.Id; Nome = $item.Nome; Status = $r.Status; Mensagem = $r.Mensagem; Reinicio = $item.Reinicio })
        Send-Evento @{ Tipo = 'item'; Id = $item.Id; Status = $r.Status; Mensagem = $r.Mensagem; Indice = $n }
    }

    if ($reinicioExplorer -and $Modo -ne 'simular') {
        Send-Evento @{ Tipo = 'log'; Texto = 'Reiniciando o Explorer para aplicar a aparência...' }
        Restart-Explorer
    }

    if ($Modo -ne 'simular' -and $resultados.Count -gt 0) {
        $registro = [pscustomobject]@{
            Data  = (Get-Date).ToString('s')
            Acao  = $Modo
            Itens = @($resultados | Select-Object Id, Nome, Status, Mensagem)
        }
        $linha = (ConvertTo-Json -InputObject $registro -Depth 5 -Compress) + [Environment]::NewLine
        [IO.File]::AppendAllText($Script:Otz.ArqHistorico, $linha, (New-Object Text.UTF8Encoding $false))
    }

    Send-Evento @{ Tipo = 'fim'; Modo = $Modo }
    return $resultados
}

# ---------------------------------------------------------------
#  Perfis exportáveis (padronizar vários PCs)
#  Arquivo JSON: { Formato, Versao, Nome, Criado, Computador, Ids[] }
# ---------------------------------------------------------------
$Script:PerfisProntos = @('basico', 'trabalho', 'gamer', 'leve')

function Export-Perfil([string[]]$Ids, [string]$Nome, [string]$Arquivo) {
    $dados = [ordered]@{
        Formato    = 'otimizador-vinicius-perfil'
        Versao     = 1
        Nome       = $Nome
        Criado     = (Get-Date).ToString('s')
        Computador = $env:COMPUTERNAME
        Ids        = @($Ids)
    }
    [IO.File]::WriteAllText($Arquivo, (ConvertTo-Json -InputObject $dados -Depth 4), (New-Object Text.UTF8Encoding $false))
    Write-Log "Perfil '$Nome' exportado ($($Ids.Count) ajustes): $Arquivo"
}

function Import-Perfil([string]$Arquivo) {
    if (-not (Test-Path $Arquivo)) { throw "Arquivo não encontrado: $Arquivo" }
    $p = $null
    try { $p = [IO.File]::ReadAllText($Arquivo, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { }
    if (-not $p -or $p.Formato -ne 'otimizador-vinicius-perfil') { throw 'Este arquivo não é um perfil do Otimizador Vinicius (exporte pelo botão Exportar, em Otimizar).' }
    return $p
}

# Ids de um perfil pronto (basico/trabalho/gamer/leve) ou de um arquivo .json
function Resolve-IdsPerfil([string]$Origem) {
    if ($Script:PerfisProntos -contains $Origem.ToLowerInvariant()) {
        $nome = $Origem.ToLowerInvariant()
        $ids = @(Get-Catalogo | Where-Object { $_.Perfis -contains $nome -and $_.Risco -ne 'avancado' } | ForEach-Object Id)
        return @{ Nome = $nome; Ids = $ids }
    }
    $p = Import-Perfil $Origem
    return @{ Nome = [string]$p.Nome; Ids = @($p.Ids) }
}

# Aplica um perfil sem janela (linha de comando / tarefa agendada).
# Pula o que não existe neste Windows. Devolve os resultados.
function Invoke-PerfilSilencioso([string]$Origem, [bool]$CriarPonto = $true) {
    $perfil = Resolve-IdsPerfil $Origem
    $winReal = if ($Script:Otz.IsWin11) { '11' } else { '10' }
    $catalogo = @{}
    foreach ($i in Get-Catalogo) { $catalogo[$i.Id] = $i }
    $validos = New-Object System.Collections.Generic.List[string]
    $pulados = New-Object System.Collections.Generic.List[string]
    foreach ($id in $perfil.Ids) {
        if (-not $catalogo.ContainsKey($id)) { $pulados.Add("$id (não existe nesta versão do otimizador)"); continue }
        $c = Test-Compativel $catalogo[$id] $winReal
        if ($c.Ok) { $validos.Add($id) } else { $pulados.Add("$($catalogo[$id].Nome): $($c.Motivo)") }
    }
    Write-Log "Perfil silencioso '$($perfil.Nome)': $($validos.Count) para aplicar, $($pulados.Count) pulados."
    $res = @()
    if ($validos.Count) { $res = @(Invoke-Plano -Ids $validos.ToArray() -Modo aplicar -CriarPonto $CriarPonto) }
    return @{ Nome = $perfil.Nome; Resultados = $res; Pulados = $pulados.ToArray() }
}

# Estado de todos os itens (usado na abertura e após aplicar)
function Get-EstadoTodos {
    $originais = Get-Originais
    foreach ($item in Get-Catalogo) {
        $e = Get-EstadoAjuste $item
        Send-Evento @{ Tipo = 'estado'; Id = $item.Id; Estado = $e.Estado; Texto = [string]$e.Texto; PodeDesfazer = ($originais.ContainsKey($item.Id) -or [bool]$item.DesfazerSemOriginal) }
    }
}

function Get-Historico([int]$Max = 50) {
    if (-not (Test-Path $Script:Otz.ArqHistorico)) { return @() }
    $linhas = [IO.File]::ReadAllLines($Script:Otz.ArqHistorico, [Text.Encoding]::UTF8)
    $res = for ($i = $linhas.Count - 1; $i -ge 0 -and ($linhas.Count - $i) -le $Max; $i--) {
        if ($linhas[$i].Trim()) { try { $linhas[$i] | ConvertFrom-Json } catch { } }
    }
    return @($res)
}
