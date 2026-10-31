#Requires -Version 5.1
<#
    Office e Proteção (antivírus) do Otimizador Vinicius v2.0
    Depende do nucleo.ps1 (Write-Log, Send-Evento, Read-RegValor...).

    IMPORTANTE sobre antivírus:
    No Windows atual, a "Proteção contra Adulteração" (Tamper Protection)
    impede desligar o Microsoft Defender por script - de propósito, por
    segurança. Então aqui a gente LÊ o estado real e, quando não dá para
    agir por script, abre a tela certa do Windows com o passo a passo.
    Antivírus de terceiros (Avast, Kaspersky...) não têm um jeito único
    de desligar por fora; a gente detecta e abre o programa deles.
#>

# ===============================================================
#  Office: detectar e desinstalar
#  Usa a string de desinstalação OFICIAL que o próprio Office registra
#  (QuietUninstallString). Não montamos comando na mão.
# ===============================================================
function Get-OfficeInstalado {
    $itens = New-Object System.Collections.Generic.List[object]
    $chaves = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $padrao = 'Microsoft 365|Microsoft Office|Office 16|Office 15|Office Professional|Office Home|Office Standard|Project|Visio'
    # Componentes auxiliares são removidos junto com o produto principal: não listar
    $auxiliar = 'Extensibility|Licensing|MUI|Proofing|Shared|Components|Resources|WebExperience'
    foreach ($base in $chaves) {
        foreach ($k in Get-ChildItem $base -ErrorAction SilentlyContinue) {
            $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
            if (-not $p.DisplayName) { continue }
            if ($p.DisplayName -notmatch $padrao -or $p.DisplayName -match $auxiliar) { continue }
            if ([string]$p.Publisher -and [string]$p.Publisher -notmatch 'Microsoft') { continue }
            $cmd = if ($p.QuietUninstallString) { [string]$p.QuietUninstallString } else { [string]$p.UninstallString }
            if (-not $cmd) { continue }
            $itens.Add([pscustomobject]@{
                Nome      = [string]$p.DisplayName
                Versao    = [string]$p.DisplayVersion
                Comando   = $cmd
                Silencioso = [bool]$p.QuietUninstallString
                Tipo      = if ($cmd -match 'OfficeClickToRun') { 'ClickToRun' } elseif ($cmd -match 'msiexec') { 'MSI' } else { 'Outro' }
                Appx      = $false
            })
        }
    }
    # Office da Microsoft Store (ponte C2R)
    foreach ($a in Get-AppxPackage -Name 'Microsoft.Office.Desktop*' -ErrorAction SilentlyContinue) {
        $itens.Add([pscustomobject]@{ Nome = "$($a.Name) (Microsoft Store)"; Versao = [string]$a.Version; Comando = $a.PackageFullName; Silencioso = $true; Tipo = 'Store'; Appx = $true })
    }
    return $itens.ToArray()
}

# Desinstala um item do Office, mostrando a saída ao vivo. Retorna o código.
function Uninstall-OfficeItem($Item) {
    Write-Log "Desinstalando Office: $($Item.Nome) [$($Item.Tipo)]"
    if ($Item.Appx) {
        try { Remove-AppxPackage -Package $Item.Comando -ErrorAction Stop; return 0 }
        catch { Send-Evento @{ Tipo = 'log'; Texto = $_.Exception.Message }; return 1 }
    }
    $cmd = $Item.Comando
    if ($Item.Tipo -eq 'ClickToRun') {
        # Garante modo silencioso e sem reinício automático
        if ($cmd -notmatch 'DisplayLevel=') { $cmd += ' DisplayLevel=False' }
        if ($cmd -notmatch 'forceappshutdown') { $cmd += ' forceappshutdown=True' }
    } elseif ($Item.Tipo -eq 'MSI' -and $cmd -match 'msiexec') {
        $cmd = ($cmd -replace '/I', '/X') -replace '/i', '/X'
        if ($cmd -notmatch '/qn|/quiet|/passive') { $cmd += ' /passive /norestart' }
    }
    # Separa executável e argumentos (o executável pode vir entre aspas)
    if ($cmd -match '^"([^"]+)"\s*(.*)$') { $exe = $Matches[1]; $resto = $Matches[2] }
    elseif ($cmd -match '^(\S+)\s*(.*)$') { $exe = $Matches[1]; $resto = $Matches[2] }
    else { $exe = $cmd; $resto = '' }
    return (Invoke-ProcessoAoVivo -Arquivo $exe -Argumentos $resto -Codificacao oem)
}

# ===============================================================
#  Antivírus / Proteção
# ===============================================================
# Lê o estado de todos os antivírus registrados na Central de Segurança.
function Get-InfoAntivirus {
    $lista = New-Object System.Collections.Generic.List[object]
    foreach ($av in Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue) {
        $estado = [int]$av.productState
        # productState: o 3º byte (0x..10..) indica ligado; 0x..00.. desligado
        $ligado = ($estado -band 0x1000) -ne 0
        $atualizado = ($estado -band 0x10) -eq 0
        $ehDefender = $av.displayName -match 'Defender'
        $lista.Add([pscustomobject]@{ Nome = [string]$av.displayName; Ligado = $ligado; Atualizado = $atualizado; Defender = $ehDefender; Caminho = [string]$av.pathToSignedProductExe })
    }
    $def = $null
    try {
        $s = Get-MpComputerStatus -ErrorAction Stop
        $def = [pscustomobject]@{
            Presente        = $true
            RealTime        = [bool]$s.RealTimeProtectionEnabled
            Antivirus       = [bool]$s.AntivirusEnabled
            TamperProtegido = [bool]$s.IsTamperProtected
            Modo            = [string]$s.AMRunningMode   # Normal | 'Passive Mode' | EDR Block | SxS Passive
        }
    } catch { }
    $terceiros = @($lista | Where-Object { -not $_.Defender -and $_.Ligado })
    return [pscustomobject]@{ Lista = $lista.ToArray(); Defender = $def; Terceiros = $terceiros; TemTerceiro = ($terceiros.Count -gt 0) }
}

$Script:FlagProtecao = { Join-Path $Script:Otz.Dados 'protecao-pausada.flag' }

function Test-ProtecaoPausada { return (Test-Path (& $Script:FlagProtecao)) }

# Tenta pausar a proteção em tempo real do Defender.
# Retorna @{ Status = ok|bloqueado|na; Mensagem }
function Suspend-Defender {
    $info = Get-InfoAntivirus
    if ($info.TemTerceiro) {
        return @{ Status = 'na'; Mensagem = "Quem protege o PC agora é o $($info.Terceiros[0].Nome), não o Defender. Pause pela janela do próprio $($info.Terceiros[0].Nome) (ícone ao lado do relógio)." }
    }
    if (-not $info.Defender -or -not $info.Defender.Presente) {
        return @{ Status = 'na'; Mensagem = 'Não foi possível falar com o Microsoft Defender neste PC.' }
    }
    if ($info.Defender.TamperProtegido) {
        return @{ Status = 'bloqueado'; Mensagem = 'A Proteção contra Adulteração está ligada, e o Windows NÃO deixa desligar a proteção por programa (é de propósito). Desligue-a primeiro na Segurança do Windows e tente de novo.' }
    }
    try {
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction Stop
        [IO.File]::WriteAllText((& $Script:FlagProtecao), (Get-Date).ToString('s'), (New-Object Text.UTF8Encoding $false))
        Write-Log 'Proteção em tempo real do Defender PAUSADA pelo usuário.'
        $depois = Get-InfoAntivirus
        if ($depois.Defender.RealTime) {
            return @{ Status = 'bloqueado'; Mensagem = 'O Windows recusou o pedido (provável Proteção contra Adulteração ou política). Desligue na Segurança do Windows.' }
        }
        return @{ Status = 'ok'; Mensagem = 'Proteção em tempo real PAUSADA. Reative assim que terminar.' }
    } catch {
        return @{ Status = 'bloqueado'; Mensagem = "O Windows bloqueou: $($_.Exception.Message). Desligue na Segurança do Windows." }
    }
}

function Resume-Defender {
    $erros = @()
    try { Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop }
    catch { $erros += $_.Exception.Message }
    Remove-Item (& $Script:FlagProtecao) -ErrorAction SilentlyContinue
    Write-Log 'Proteção em tempo real do Defender REATIVADA.'
    $info = Get-InfoAntivirus
    if ($info.Defender -and $info.Defender.RealTime) { return @{ Status = 'ok'; Mensagem = 'Proteção em tempo real reativada.' } }
    if ($info.TemTerceiro) { return @{ Status = 'ok'; Mensagem = 'O antivírus de terceiros continua protegendo o PC.' } }
    $msg = 'Pedido de reativação enviado. Confira na Segurança do Windows se a proteção voltou.'
    if ($erros) { $msg = "$($erros -join ' ') - $msg" }
    return @{ Status = 'aviso'; Mensagem = $msg }
}

# Exclusão de pasta/arquivo: resolve falso positivo sem baixar a guarda do PC.
function Add-DefenderExclusao([string]$Caminho) {
    Add-MpPreference -ExclusionPath $Caminho -ErrorAction Stop
    Write-Log "Exclusão do Defender adicionada: $Caminho"
}
function Remove-DefenderExclusao([string]$Caminho) {
    Remove-MpPreference -ExclusionPath $Caminho -ErrorAction Stop
    Write-Log "Exclusão do Defender removida: $Caminho"
}
function Get-DefenderExclusoes {
    try {
        $e = @((Get-MpPreference -ErrorAction Stop).ExclusionPath)
        # Sem admin, o Windows devolve um texto de erro no lugar da lista: descarta
        return @($e | Where-Object { $_ -and $_ -notmatch 'Must be an administrator|^N/A' })
    } catch { return @() }
}
