# Catálogo: Rede
# DNS fica em Ferramentas > Rede, porque é uma escolha (Cloudflare, Google...) e não liga/desliga.
$cat = 'Rede'

@(
    @{
        Id        = 'rede.energia-placa'
        Categoria = $cat
        Nome      = 'Placa de rede sem economia de energia'
        Resumo    = 'Evita quedas de conexão quando o PC fica parado (comum no Wi-Fi e no acesso remoto).'
        Detalhe   = 'Em cada placa de rede física: desmarca "Permitir que o computador desligue este dispositivo", desliga a suspensão seletiva e o Ethernet com Eficiência Energética (EEE), quando o driver permite.'
        Indicado  = 'PCs acessados remotamente, Wi-Fi que "cai do nada" e quem usa equipamentos em rede local.'
        Atencao   = 'Em notebooks, a bateria dura um pouco menos com o Wi-Fi sempre ativo. Pode piscar a conexão por 1 segundo ao aplicar.'
        Risco     = 'seguro'
        Reinicio  = 'reiniciar'
        Perfis    = @('trabalho', 'gamer')
        Tecnico   = "Set-NetAdapterPowerManagement -AllowComputerToTurnOffDevice Disabled -SelectiveSuspend Disabled`nSet-NetAdapterAdvancedProperty -RegistryKeyword *EEE -RegistryValue 0"
        Detectar  = {
            $ads = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)
            if ($ads.Count -eq 0) { return @{ Estado = 'na'; Texto = 'Nenhuma placa de rede física encontrada.' } }
            $ligadas = 0; $suportam = 0
            foreach ($a in $ads) {
                $pm = Get-NetAdapterPowerManagement -Name $a.Name -ErrorAction SilentlyContinue
                if ($pm -and [string]$pm.AllowComputerToTurnOffDevice -ne 'Unsupported') {
                    $suportam++
                    if ([string]$pm.AllowComputerToTurnOffDevice -eq 'Enabled') { $ligadas++ }
                }
            }
            if ($suportam -eq 0) { return @{ Estado = 'na'; Texto = 'Os drivers das placas não permitem esse ajuste.' } }
            if ($ligadas -eq 0) { return @{ Estado = 'aplicado'; Texto = '' } }
            return @{ Estado = 'nao'; Texto = "$ligadas de $suportam placa(s) com economia ligada." }
        }
        Simular   = {
            foreach ($a in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)) {
                $pm = Get-NetAdapterPowerManagement -Name $a.Name -ErrorAction SilentlyContinue
                "→ $($a.Name): desligar dispositivo = $($pm.AllowComputerToTurnOffDevice)  →  Disabled"
            }
        }
        Aplicar   = {
            $ads = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)
            if ($ads.Count -eq 0) { return @{ Status = 'ignorado'; Mensagem = 'Nenhuma placa de rede física.' } }
            if (-not (Get-Original 'rede.energia-placa')) {
                $orig = @(foreach ($a in $ads) {
                    $pm  = Get-NetAdapterPowerManagement -Name $a.Name -ErrorAction SilentlyContinue
                    $eee = Get-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword '*EEE' -ErrorAction SilentlyContinue
                    $valorEee = $null
                    if ($eee) { $valorEee = [string]@($eee.RegistryValue)[0] }
                    @{ Nome = $a.Name; Desligar = [string]$pm.AllowComputerToTurnOffDevice; Seletiva = [string]$pm.SelectiveSuspend; Eee = $valorEee }
                })
                Set-Original 'rede.energia-placa' @{ Data = (Get-Date).ToString('s'); Placas = $orig }
            }
            $feitos = New-Object System.Collections.Generic.List[string]
            foreach ($a in $ads) {
                try {
                    Set-NetAdapterPowerManagement -Name $a.Name -AllowComputerToTurnOffDevice Disabled -NoRestart -ErrorAction Stop
                    $feitos.Add($a.Name)
                } catch { Write-Log "  $($a.Name): driver não permite alterar o desligamento." }
                try { Set-NetAdapterPowerManagement -Name $a.Name -SelectiveSuspend Disabled -NoRestart -ErrorAction Stop } catch { }
                if (Get-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword '*EEE' -ErrorAction SilentlyContinue) {
                    try { Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword '*EEE' -RegistryValue 0 -NoRestart -ErrorAction Stop } catch { }
                }
            }
            if ($feitos.Count -eq 0) { return @{ Status = 'aviso'; Mensagem = 'Nenhum driver de placa permitiu a alteração.' } }
            return @{ Status = 'ok'; Mensagem = "Ajustado em: $($feitos -join ', ')." }
        }
        Desfazer  = {
            param($orig)
            if (-not $orig) { return @{ Status = 'aviso'; Mensagem = 'Não há configuração anterior guardada.' } }
            foreach ($p in @($orig.Placas)) {
                if ($p.Desligar -in 'Enabled', 'Disabled') {
                    try { Set-NetAdapterPowerManagement -Name $p.Nome -AllowComputerToTurnOffDevice $p.Desligar -NoRestart -ErrorAction Stop } catch { }
                }
                if ($p.Seletiva -in 'Enabled', 'Disabled') {
                    try { Set-NetAdapterPowerManagement -Name $p.Nome -SelectiveSuspend $p.Seletiva -NoRestart -ErrorAction Stop } catch { }
                }
                if ($null -ne $p.Eee) {
                    try { Set-NetAdapterAdvancedProperty -Name $p.Nome -RegistryKeyword '*EEE' -RegistryValue $p.Eee -NoRestart -ErrorAction Stop } catch { }
                }
            }
            return @{ Status = 'ok'; Mensagem = 'Configuração das placas restaurada.' }
        }
    }
)
