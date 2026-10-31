#Requires -Version 5.1
<#
    Ferramentas do Otimizador Vinicius v2.0
    Funções sem interface: devolvem dados. Quem desenha é a janela.
    Dependem do nucleo.ps1 (Write-Log, Send-Evento, Read-RegValor...).
#>

# ===============================================================
#  Informações do PC (Início + Relatório)
# ===============================================================
function Get-InfoPC {
    $os   = Get-CimInstance Win32_OperatingSystem
    $cs   = Get-CimInstance Win32_ComputerSystem
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
    $mem  = @(Get-CimInstance Win32_PhysicalMemory)
    $gpus = @(Get-CimInstance Win32_VideoController)
    $mb   = Get-CimInstance Win32_BaseBoard
    $bios = Get-CimInstance Win32_BIOS
    $discos = @(Get-PhysicalDisk -ErrorAction SilentlyContinue | Sort-Object DeviceId)
    $vols   = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveLetter | Sort-Object DriveLetter)
    $plano  = Get-PlanoAtivo
    $inic   = @(Get-ItensInicializacao | Where-Object Ativo).Count
    $uptime = (Get-Date) - $os.LastBootUpTime
    $notebook = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)

    $ramGB   = [math]::Round($cs.TotalPhysicalMemory / 1GB)
    $ramUso  = [math]::Round((1 - ($os.FreePhysicalMemory / $os.TotalVisibleMemorySize)) * 100)
    $threads = [int]$cpu.NumberOfLogicalProcessors

    # Disco do sistema
    $letra    = $env:SystemDrive.Substring(0, 1)
    $sysNum   = (Get-Partition -DriveLetter $letra -ErrorAction SilentlyContinue).DiskNumber
    $sysDisk  = $discos | Where-Object { [string]$_.DeviceId -eq [string]$sysNum } | Select-Object -First 1
    $tipoSys  = 'Desconhecido'
    if ($sysDisk) {
        if ([string]$sysDisk.BusType -eq 'NVMe')      { $tipoSys = 'NVMe' }
        elseif ([string]$sysDisk.MediaType -eq 'SSD') { $tipoSys = 'SSD SATA' }
        elseif ([string]$sysDisk.MediaType -eq 'HDD') { $tipoSys = 'HDD' }
    }
    $volSys = $vols | Where-Object { $_.DriveLetter -eq $letra } | Select-Object -First 1
    $livrePct = if ($volSys -and $volSys.Size) { [math]::Round(($volSys.SizeRemaining / $volSys.Size) * 100) } else { $null }

    # Classificação (não avalia a placa de vídeo)
    if ($ramGB -le 8 -or $tipoSys -eq 'HDD' -or $threads -le 4) { $tier = 'Low-end' }
    elseif ($ramGB -ge 32 -and $threads -ge 12 -and $tipoSys -eq 'NVMe') { $tier = 'High-end' }
    else { $tier = 'Mid-end' }

    $gpuDedicada = [bool]($gpus | Where-Object { $_.Name -match 'NVIDIA|Radeon RX|Radeon Pro|Arc A|Arc B' })
    $gpuNome = ($gpus | Where-Object { $_.Name -match 'NVIDIA|Radeon|Arc' } | Select-Object -First 1).Name
    if (-not $gpuNome -and $gpus.Count) { $gpuNome = $gpus[0].Name }
    $perfil = switch ($tier) {
        'Low-end'  { 'leve' }
        'High-end' { if ($gpuDedicada) { 'gamer' } else { 'trabalho' } }
        default    { 'trabalho' }
    }

    # Alertas: Nivel = alto | medio | info ; Acao = página/ferramenta sugerida
    $alertas = New-Object System.Collections.Generic.List[object]
    function Add-Alerta($nivel, $texto, $acao = '') { $alertas.Add([pscustomobject]@{ Nivel = $nivel; Texto = $texto; Acao = $acao }) }

    if ($tipoSys -eq 'HDD') { Add-Alerta 'alto' 'O Windows está em HD mecânico. Trocar por SSD é a melhoria de maior impacto possível (3 a 10 vezes mais rápido para abrir tudo).' }
    if ($ramGB -lt 16)      { Add-Alerta 'medio' "Apenas $ramGB GB de RAM. Para navegador com várias abas e sistemas web, o recomendado hoje é 16 GB." }
    if ($mem.Count -eq 1)   { Add-Alerta 'medio' 'Só 1 pente de memória (single channel). Um segundo pente igual pode aumentar bastante o desempenho, principalmente com vídeo integrado.' }
    foreach ($m in $mem) {
        if ($m.ConfiguredClockSpeed -and $m.Speed -and $m.ConfiguredClockSpeed -lt $m.Speed) {
            Add-Alerta 'medio' "Memória rodando a $($m.ConfiguredClockSpeed) MT/s, abaixo dos $($m.Speed) MT/s do pente. Ative o XMP/EXPO na BIOS."; break
        }
    }
    if ($null -ne $livrePct -and $livrePct -lt 15) { Add-Alerta 'alto' "Disco $letra`: com só $livrePct% livre. Isso deixa o Windows e as atualizações lentos." 'limpeza' }
    if ($inic -gt 10)              { Add-Alerta 'medio' "$inic programas abrem junto com o Windows. Desligue os que não precisa." 'inicializacao' }
    if ($uptime.TotalDays -gt 7)   { Add-Alerta 'info' "PC ligado há $([math]::Floor($uptime.TotalDays)) dias sem reiniciar. Reiniciar libera memória e conclui atualizações." }
    if ($plano -and $plano.Nome -match 'Equilibrado|Balanced|Economia|Power saver') { Add-Alerta 'info' "Plano de energia '$($plano.Nome)'. Para mais desempenho, aplique 'Plano de energia Desempenho Máximo'." 'energia.plano' }
    foreach ($g in $gpus) {
        if ($g.CurrentRefreshRate -and $g.MaxRefreshRate -and $g.CurrentRefreshRate -lt $g.MaxRefreshRate -and $g.MaxRefreshRate -le 400) {
            Add-Alerta 'medio' "Tela em $($g.CurrentRefreshRate) Hz, mas a placa $($g.Name) suporta até $($g.MaxRefreshRate) Hz. Confira em Configurações > Tela > Tela avançada."
        }
    }

    # Discos com saúde/desgaste
    $listaDiscos = foreach ($d in $discos) {
        $r = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        $saude = [string]$d.HealthStatus
        if ($saude -and $saude -ne 'Healthy') { Add-Alerta 'alto' "Disco $($d.FriendlyName) com saúde '$saude'. Faça backup e verifique com o CrystalDiskInfo." }
        if ($r -and $r.Wear -ge 80) { Add-Alerta 'alto' "SSD $($d.FriendlyName) com $($r.Wear)% de desgaste. Planeje a troca." }
        [pscustomobject]@{
            Nome   = $d.FriendlyName
            Tipo   = if ([string]$d.BusType -eq 'NVMe') { 'NVMe' } else { "$($d.MediaType) $($d.BusType)" }
            GB     = [math]::Round($d.Size / 1GB)
            Saude  = $saude
            Temp   = if ($r -and $r.Temperature) { "$($r.Temperature) °C" } else { '-' }
            Desg   = if ($r -and $null -ne $r.Wear) { "$($r.Wear)%" } else { '-' }
            Horas  = if ($r -and $r.PowerOnHours) { "$($r.PowerOnHours) h" } else { '-' }
        }
    }

    # Valores condicionais calculados ANTES do objeto: no PowerShell 5.1, "if" dentro de
    # @{...} com ramos de tipos diferentes (número / $null) gera "Os tipos de argumento não correspondem"
    $winNome = if ($Script:Otz.IsWin11) { 'Windows 11' } else { 'Windows 10' }
    $uptimeTexto = if ($uptime.TotalDays -ge 1) { "{0} d {1} h" -f $uptime.Days, $uptime.Hours } else { "{0} h {1} min" -f $uptime.Hours, $uptime.Minutes }
    $livreGB = $null
    if ($volSys) { $livreGB = [math]::Round($volSys.SizeRemaining / 1GB) }
    $nomePlano = '?'
    if ($plano) { $nomePlano = $plano.Nome }
    $biosTexto = [string]$bios.SMBIOSBIOSVersion
    if ($bios.ReleaseDate) { $biosTexto += " ($($bios.ReleaseDate.ToString('dd/MM/yyyy')))" }
    $listaPentes = New-Object System.Collections.Generic.List[object]
    foreach ($m in $mem) {
        $listaPentes.Add([pscustomobject]@{ Slot = $m.DeviceLocator; GB = [math]::Round($m.Capacity / 1GB); Atual = $m.ConfiguredClockSpeed; Nominal = $m.Speed; Modelo = ("$($m.Manufacturer) $(([string]$m.PartNumber).Trim())").Trim() })
    }
    $listaGpus = New-Object System.Collections.Generic.List[object]
    foreach ($g in $gpus) {
        $tela = '-'
        if ($g.CurrentHorizontalResolution) { $tela = "$($g.CurrentHorizontalResolution)x$($g.CurrentVerticalResolution) @ $($g.CurrentRefreshRate) Hz" }
        $listaGpus.Add([pscustomobject]@{ Nome = $g.Name; Driver = $g.DriverVersion; Tela = $tela })
    }
    $listaVolumes = New-Object System.Collections.Generic.List[object]
    foreach ($v in $vols) {
        if (-not $v.Size) { continue }
        $tam = [double]$v.Size; $livre = [double]$v.SizeRemaining
        $listaVolumes.Add([pscustomobject]@{ Letra = [string]$v.DriveLetter; Nome = $v.FileSystemLabel; GB = [math]::Round($tam / 1GB); LivreGB = [math]::Round($livre / 1GB); LivrePct = [math]::Round(($livre / $tam) * 100) })
    }
    $cpuNome = ([string]$cpu.Name -replace '\s+', ' ').Trim()
    $placaMae = "$($mb.Manufacturer) $($mb.Product)".Trim()
    $r = [ordered]@{}
    $r.Computador = $env:COMPUTERNAME
    $r.Sistema = $os.Caption
    $r.WinNome = $winNome
    $r.Build = $Script:Otz.Build
    $r.VersaoWin = $Script:Otz.VersaoWin
    $r.Instalado = $os.InstallDate
    $r.Uptime = $uptime
    $r.UptimeTexto = $uptimeTexto
    $r.Cpu = $cpuNome
    $r.Nucleos = $cpu.NumberOfCores
    $r.Threads = $threads
    $r.ClockMHz = $cpu.MaxClockSpeed
    $r.RamGB = $ramGB
    $r.RamUso = $ramUso
    $r.Pentes = $listaPentes.ToArray()
    $r.Gpus = $listaGpus.ToArray()
    $r.GpuNome = $gpuNome
    $r.GpuDedicada = $gpuDedicada
    $r.PlacaMae = $placaMae
    $r.Bios = $biosTexto
    $r.DiscoTipo = $tipoSys
    $r.DiscoLivre = $livrePct
    $r.DiscoLivreGB = $livreGB
    $r.Discos = [object[]]@($listaDiscos)
    $r.Volumes = $listaVolumes.ToArray()
    $r.Plano = $nomePlano
    $r.Inicializacao = $inic
    $r.Notebook = $notebook
    $r.Tier = $tier
    $r.PerfilSugerido = $perfil
    $r.Alertas = $alertas.ToArray()
    [pscustomobject]$r
}

# ===============================================================
#  Relatório HTML
# ===============================================================
function ConvertTo-Html5([string]$s) { return [System.Net.WebUtility]::HtmlEncode($s) }

function New-RelatorioPC($Info) {
    if (-not $Info) { $Info = Get-InfoPC }
    $e = { param($s) ConvertTo-Html5 ([string]$s) }
    $linha = { param($k, $v) "<tr><th>$(& $e $k)</th><td>$(& $e $v)</td></tr>" }

    $tSis = (& $linha 'Computador' $Info.Computador) + (& $linha 'Sistema' "$($Info.Sistema) $($Info.VersaoWin) (build $($Info.Build))") +
            (& $linha 'Instalado em' $Info.Instalado.ToString('dd/MM/yyyy')) + (& $linha 'Ligado há' $Info.UptimeTexto) +
            (& $linha 'Placa-mãe' $Info.PlacaMae) + (& $linha 'BIOS' $Info.Bios) +
            (& $linha 'Plano de energia' $Info.Plano) + (& $linha 'Programas na inicialização' $Info.Inicializacao)
    $tCpu = (& $linha 'Processador' $Info.Cpu) + (& $linha 'Núcleos / Threads' "$($Info.Nucleos) / $($Info.Threads)") +
            (& $linha 'Clock máximo' "$($Info.ClockMHz) MHz") + (& $linha 'RAM total' "$($Info.RamGB) GB ($($Info.RamUso)% em uso agora)")
    $tMem = ($Info.Pentes | ForEach-Object { "<tr><td>$(& $e $_.Slot)</td><td>$($_.GB) GB</td><td>$(& $e $_.Atual) / $(& $e $_.Nominal) MT/s</td><td>$(& $e $_.Modelo)</td></tr>" }) -join ''
    $tGpu = ($Info.Gpus | ForEach-Object { "<tr><td>$(& $e $_.Nome)</td><td>$(& $e $_.Driver)</td><td>$(& $e $_.Tela)</td></tr>" }) -join ''
    $tDisco = ($Info.Discos | ForEach-Object {
        $cls = if ($_.Saude -eq 'Healthy') { 'ok' } else { 'bad' }
        "<tr><td>$(& $e $_.Nome)</td><td>$(& $e $_.Tipo)</td><td>$($_.GB) GB</td><td class='$cls'>$(& $e $_.Saude)</td><td>$(& $e $_.Temp)</td><td>$(& $e $_.Desg)</td><td>$(& $e $_.Horas)</td></tr>"
    }) -join ''
    $tVol = ($Info.Volumes | ForEach-Object {
        $cls = if ($_.LivrePct -lt 15) { 'bad' } elseif ($_.LivrePct -lt 25) { 'warn' } else { 'ok' }
        "<tr><td>$($_.Letra):</td><td>$(& $e $_.Nome)</td><td>$($_.GB) GB</td><td>$($_.LivreGB) GB</td><td class='$cls'>$($_.LivrePct)%</td></tr>"
    }) -join ''

    $recs = @{
        'Low-end'  = @('SSD no lugar do HD (de 3 a 10 vezes mais rápido para abrir programas)', 'Subir para 16 GB em dual channel (dois pentes iguais)', 'Perfil "PC simples" do otimizador e revisão dos programas de inicialização', 'Navegador com economia de memória (abas em suspensão)', 'Remover programas do fabricante e antivírus extras, mantendo só o Defender')
        'Mid-end'  = @('Ativar XMP/EXPO na BIOS e confirmar dual channel', 'Atualizar BIOS, chipset e driver de vídeo pelo site do fabricante', 'Ativar Resizable BAR (se a placa-mãe e a GPU suportarem)', 'Windows no SSD NVMe, com o HD só para arquivos', 'Limpeza interna e troca de pasta térmica se a CPU passar de 85 °C')
        'High-end' = @('XMP/EXPO, Resizable BAR e BIOS atualizada', 'Monitor na taxa máxima, com G-Sync/FreeSync e cabo na placa de vídeo', 'Desligar overlays (Discord, Steam, GeForce/Adrenalin) em jogos competitivos', 'NVIDIA Reflex / AMD Anti-Lag nos jogos que suportam', 'Opcional: desligar Integridade de Memória (VBS) ganha FPS, mas reduz a segurança')
    }
    $cores = @{ alto = 'bad'; medio = 'warn'; info = 'info' }
    $liRecs  = ($recs[$Info.Tier] | ForEach-Object { "<li>$(& $e $_)</li>" }) -join ''
    $liAlert = if ($Info.Alertas.Count) { ($Info.Alertas | ForEach-Object { "<li class='$($cores[$_.Nivel])'>$(& $e $_.Texto)</li>" }) -join '' } else { '<li class="ok">Nenhum problema detectado.</li>' }
    $data = Get-Date -Format 'dd/MM/yyyy HH:mm'

    $html = @"
<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Relatório do PC - $(& $e $Info.Computador)</title>
<style>
:root{--bg:#f4f6fa;--card:#fff;--tx:#111827;--mut:#5b6474;--ln:#dde3ec;--ac:#0d9488;--ok:#059669;--warn:#b45309;--bad:#dc2626;--info:#2563eb}
@media (prefers-color-scheme:dark){:root{--bg:#0f1218;--card:#171b23;--tx:#e8ecf3;--mut:#9aa4b5;--ln:#2a3140;--ac:#2dd4bf;--ok:#34d399;--warn:#fbbf24;--bad:#f87171;--info:#60a5fa}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--tx);font:15px/1.55 "Segoe UI Variable Text","Segoe UI",system-ui,sans-serif}
.wrap{max-width:1040px;margin:0 auto;padding:28px 16px}
h1{margin:0;font-size:26px;display:flex;flex-wrap:wrap;align-items:center;gap:10px}.sub{color:var(--mut);margin:6px 0 22px}
.tier{padding:3px 12px;border-radius:99px;background:linear-gradient(90deg,#14b8a6,#3b82f6);color:#fff;font-weight:600;font-size:14px}
.card{background:var(--card);border:1px solid var(--ln);border-radius:14px;padding:16px 18px;margin-bottom:16px;overflow-x:auto}
h2{font-size:16px;margin:0 0 10px}table{width:100%;border-collapse:collapse}
th,td{text-align:left;padding:7px 8px;border-bottom:1px solid var(--ln);vertical-align:top}
th{color:var(--mut);font-weight:500;width:34%}thead th{width:auto}
.ok{color:var(--ok)}.warn{color:var(--warn)}.bad{color:var(--bad)}.info{color:var(--info)}
td.ok,td.warn,td.bad{font-weight:600}
ul{margin:0;padding-left:20px}li{margin:5px 0}.alert li{color:var(--tx)}.alert li::marker{font-size:1.2em}
.alert li.bad::marker{color:var(--bad)}.alert li.warn::marker{color:var(--warn)}.alert li.info::marker{color:var(--info)}.alert li.ok::marker{color:var(--ok)}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:16px}@media (max-width:760px){.grid{grid-template-columns:1fr}}
.foot{color:var(--mut);font-size:13px;text-align:center;margin-top:8px}
</style></head><body><div class="wrap">
<h1>$(& $e $Info.Computador) <span class="tier">$($Info.Tier)</span></h1>
<p class="sub">Gerado em $data pelo Otimizador Vinicius v$($Script:Otz.Versao). A classificação considera CPU, RAM e disco (não avalia a placa de vídeo).</p>
<div class="card alert"><h2>Pontos de atenção</h2><ul>$liAlert</ul></div>
<div class="card"><h2>Recomendações para $($Info.Tier)</h2><ul>$liRecs</ul></div>
<div class="grid">
<div class="card"><h2>Sistema</h2><table>$tSis</table></div>
<div class="card"><h2>Processador e memória</h2><table>$tCpu</table></div>
</div>
<div class="card"><h2>Pentes de memória</h2><table><thead><tr><th>Slot</th><th>Tamanho</th><th>Atual / Nominal</th><th>Fabricante / Modelo</th></tr></thead>$tMem</table></div>
<div class="card"><h2>Vídeo</h2><table><thead><tr><th>Placa</th><th>Driver</th><th>Tela</th></tr></thead>$tGpu</table></div>
<div class="card"><h2>Discos físicos</h2><table><thead><tr><th>Modelo</th><th>Tipo</th><th>Tamanho</th><th>Saúde</th><th>Temp.</th><th>Desgaste</th><th>Horas ligado</th></tr></thead>$tDisco</table></div>
<div class="card"><h2>Partições</h2><table><thead><tr><th>Unidade</th><th>Nome</th><th>Total</th><th>Livre</th><th>% livre</th></tr></thead>$tVol</table></div>
<p class="foot">Temperatura e desgaste dependem do suporte do disco/driver; "-" significa que o dado não foi informado.</p>
</div></body></html>
"@
    $arq = Join-Path $Script:Otz.Dados ("Relatorio_PC_" + (Get-Date -Format 'yyyy-MM-dd_HH-mm') + ".html")
    [IO.File]::WriteAllText($arq, $html, (New-Object Text.UTF8Encoding $true))
    return $arq
}

# ===============================================================
#  Programas de inicialização (mesmo mecanismo do Gerenciador de Tarefas)
# ===============================================================
function Get-ItensInicializacao {
    $apr = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    $fontes = @(
        @{ Origem = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';             Apr = "HKCU\$apr\Run";           Escopo = 'Só você';        Tipo = 'Reg' }
        @{ Origem = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';             Apr = "HKLM\$apr\Run";           Escopo = 'Todos';          Tipo = 'Reg' }
        @{ Origem = 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Apr = "HKLM\$apr\Run32";         Escopo = 'Todos (32 bits)'; Tipo = 'Reg' }
        @{ Origem = [Environment]::GetFolderPath('Startup');                          Apr = "HKCU\$apr\StartupFolder"; Escopo = 'Pasta (você)';   Tipo = 'Pasta' }
        @{ Origem = [Environment]::GetFolderPath('CommonStartup');                    Apr = "HKLM\$apr\StartupFolder"; Escopo = 'Pasta (todos)';  Tipo = 'Pasta' }
    )
    foreach ($f in $fontes) {
        if (-not $f.Origem) { continue }
        $entradas = @()
        if ($f.Tipo -eq 'Reg') {
            $r = Get-RegRaiz $f.Origem
            $k = $r.Base.OpenSubKey($r.Sub)
            if (-not $k) { continue }
            try {
                # Correção da v1.1: chave Run vazia gerava um item fantasma sem nome
                $entradas = @(foreach ($n in $k.GetValueNames()) {
                    if ($n -eq '') { continue }
                    @{ Nome = $n; Comando = [string]$k.GetValue($n) }
                })
            } finally { $k.Close() }
        } else {
            if (-not (Test-Path $f.Origem)) { continue }
            $entradas = @(Get-ChildItem $f.Origem -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' } |
                ForEach-Object { @{ Nome = $_.Name; Comando = $_.FullName } })
        }
        foreach ($e in $entradas) {
            $v = Read-RegValor $f.Apr $e.Nome
            # Primeiro byte par = ativo (02/06), ímpar = desativado (03/07)
            $ativo = -not ($v.Existe -and $v.Valor -is [byte[]] -and $v.Valor.Length -gt 0 -and ($v.Valor[0] % 2) -eq 1)
            $exe = ($e.Comando -replace '^"([^"]+)".*$', '$1') -replace '^(\S+\.exe).*$', '$1'
            [pscustomobject]@{ Nome = $e.Nome; Comando = $e.Comando; Exe = $exe; Escopo = $f.Escopo; Aprovado = $f.Apr; Ativo = $ativo }
        }
    }
}

function Set-ItemInicializacao([string]$Aprovado, [string]$Nome, [bool]$Ativo) {
    $byte = if ($Ativo) { 2 } else { 3 }
    # 12 bytes: estado + data (zerada), como o Gerenciador de Tarefas
    Write-RegValor $Aprovado $Nome ([byte[]]($byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) 'Binary'
    Write-Log "Inicialização: '$Nome' $(if ($Ativo) { 'ativado' } else { 'desativado' })"
}

# ===============================================================
#  Drivers USB-serial e portas COM
# ===============================================================
$Script:ChipsSerial = @(
    [pscustomobject]@{ Nome = 'Silicon Labs CP210x'; Infs = 'silabser\.inf';             Vid = '10C4'; Url = 'https://www.silabs.com/developer-tools/usb-to-uart-bridge-vcp-drivers' }
    [pscustomobject]@{ Nome = 'WCH CH340 / CH341';   Infs = 'ch341ser\.inf';             Vid = '1A86'; Url = 'https://www.wch-ic.com/downloads/CH341SER_EXE.html' }
    [pscustomobject]@{ Nome = 'FTDI';                Infs = 'ftdiport\.inf|ftdibus\.inf'; Vid = '0403'; Url = 'https://ftdichip.com/drivers/vcp-drivers/' }
    [pscustomobject]@{ Nome = 'Prolific PL2303';     Infs = 'ser2pl\.inf';               Vid = '067B'; Url = 'https://www.prolific.com.tw/' }
)

function Get-StatusSerial {
    $lista = (pnputil /enum-drivers 2>$null) -join "`n"
    $chips = foreach ($c in $Script:ChipsSerial) {
        [pscustomobject]@{ Nome = $c.Nome; Instalado = ($lista -match $c.Infs); Url = $c.Url; Vid = $c.Vid }
    }
    $portas = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\(COM\d+\)' } |
        ForEach-Object {
            $vid = if ($_.PNPDeviceID -match 'VID_([0-9A-F]{4})') { $Matches[1] } else { '' }
            $chip = ($Script:ChipsSerial | Where-Object Vid -eq $vid | Select-Object -First 1).Nome
            [pscustomobject]@{ Nome = $_.Name; Status = $_.Status; Ok = ($_.Status -eq 'OK'); Chip = $chip }
        })
    $erros = @(Get-PnpDevice -PresentOnly -Status ERROR, UNKNOWN -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -like 'USB*' -or $_.InstanceId -like 'FTDIBUS*' } |
        ForEach-Object {
            $d = $_
            $sug = ($Script:ChipsSerial | Where-Object { $d.InstanceId -match "VID_$($_.Vid)" } | Select-Object -First 1).Nome
            [pscustomobject]@{ Nome = $d.FriendlyName; Id = $d.InstanceId; Sugestao = if ($sug) { "Provável chip $($sug). Instale o driver dele." } else { 'Chip não identificado. Veja o modelo no Gerenciador de Dispositivos.' } }
        })
    [pscustomobject]@{ Chips = @($chips); Portas = $portas; Erros = $erros }
}

function Install-DriverPasta([string]$Pasta) {
    if (-not (Test-Path $Pasta)) { throw 'Pasta não encontrada.' }
    $infs = @(Get-ChildItem $Pasta -Recurse -Filter *.inf -ErrorAction SilentlyContinue)
    if ($infs.Count -eq 0) { throw 'Nenhum arquivo .inf nessa pasta. Extraia o driver (.zip) antes.' }
    $saida = pnputil /add-driver (Join-Path $Pasta '*.inf') /subdirs /install 2>&1
    Write-Log ("pnputil: " + ($saida -join ' '))
    return @{ Codigo = $LASTEXITCODE; Saida = ($saida -join "`n") }
}

# ===============================================================
#  Rede: DNS
# ===============================================================
$Script:ServidoresDns = [ordered]@{
    cloudflare = @{ Nome = 'Cloudflare'; Ips = @('1.1.1.1', '1.0.0.1');         Desc = 'Geralmente o mais rápido. Foco em privacidade.' }
    google     = @{ Nome = 'Google';     Ips = @('8.8.8.8', '8.8.4.4');         Desc = 'Muito estável e conhecido.' }
    quad9      = @{ Nome = 'Quad9';      Ips = @('9.9.9.9', '149.112.112.112'); Desc = 'Bloqueia sites de golpe e vírus conhecidos.' }
    auto       = @{ Nome = 'Automático'; Ips = @();                             Desc = 'O do roteador/provedor. Use em redes de empresa com DNS interno.' }
}

function Get-AdaptadoresRede {
    @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | ForEach-Object {
        $dns = (Get-DnsClientServerAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
        $ip  = (Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
        $chave = "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($_.InterfaceGuid)"
        $estatico = [string](Read-RegValor $chave 'NameServer').Valor
        [pscustomobject]@{
            Nome = $_.Name; Descricao = $_.InterfaceDescription; Index = $_.ifIndex; Velocidade = $_.LinkSpeed
            Ip = $ip; Dns = (@($dns) -join ', '); DnsEstatico = $estatico
            Tipo = if ($_.PhysicalMediaType -match '802\.11|Wireless') { 'Wi-Fi' } else { 'Cabo' }
        }
    })
}

# Guarda o DNS original UMA vez (antes da primeira troca pelo otimizador)
function Save-DnsOriginal {
    if (Get-Original 'rede.dns') { return }
    $dados = @(Get-AdaptadoresRede | ForEach-Object { @{ Nome = $_.Nome; Index = $_.Index; Estatico = $_.DnsEstatico } })
    Set-Original 'rede.dns' @{ Data = (Get-Date).ToString('s'); Adaptadores = $dados }
}

function Set-DnsServidores([string]$Chave) {
    $srv = $Script:ServidoresDns[$Chave]
    $ads = @(Get-AdaptadoresRede)
    if ($ads.Count -eq 0) { throw 'Nenhuma placa de rede conectada.' }
    Save-DnsOriginal
    $res = foreach ($a in $ads) {
        try {
            if ($srv.Ips.Count) { Set-DnsClientServerAddress -InterfaceIndex $a.Index -ServerAddresses $srv.Ips -ErrorAction Stop }
            else { Set-DnsClientServerAddress -InterfaceIndex $a.Index -ResetServerAddresses -ErrorAction Stop }
            Write-Log "DNS $($srv.Nome) aplicado em $($a.Nome)"
            "$($a.Nome): ok"
        } catch { "$($a.Nome): $($_.Exception.Message)" }
    }
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    return ($res -join "`n")
}

function Restore-DnsOriginal {
    $orig = Get-Original 'rede.dns'
    if (-not $orig) { throw 'O otimizador ainda não alterou o DNS, então não há o que restaurar.' }
    foreach ($d in @($orig.Adaptadores)) {
        if ([string]::IsNullOrWhiteSpace($d.Estatico)) {
            Set-DnsClientServerAddress -InterfaceIndex $d.Index -ResetServerAddresses -ErrorAction SilentlyContinue
        } else {
            Set-DnsClientServerAddress -InterfaceIndex $d.Index -ServerAddresses ($d.Estatico -split '[,\s]+' | Where-Object { $_ }) -ErrorAction SilentlyContinue
        }
    }
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    Remove-Original 'rede.dns'
    Write-Log 'DNS original restaurado.'
}

function Test-VelocidadeDns {
    $atual = $null
    foreach ($a in Get-AdaptadoresRede) { if ($a.Dns) { $atual = ($a.Dns -split ',\s*')[0]; break } }
    $alvos = [ordered]@{}
    if ($atual) { $alvos["Atual ($atual)"] = $atual }
    foreach ($k in 'cloudflare', 'google', 'quad9') { $alvos[$Script:ServidoresDns[$k].Nome] = $Script:ServidoresDns[$k].Ips[0] }
    $dominios = 'google.com', 'microsoft.com', 'youtube.com', 'cloudflare.com', 'mercadolivre.com.br', 'globo.com', 'gov.br', 'whatsapp.com'
    foreach ($nome in $alvos.Keys) {
        $tempos = @(foreach ($d in $dominios) {
            try { (Measure-Command { Resolve-DnsName -Name $d -Server $alvos[$nome] -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop | Out-Null }).TotalMilliseconds } catch { }
        })
        $res = [pscustomobject]@{
            Nome = $nome; Ip = $alvos[$nome]
            Ms = if ($tempos.Count) { [math]::Round(($tempos | Measure-Object -Average).Average) } else { $null }
            Respostas = "$($tempos.Count)/$($dominios.Count)"
        }
        Send-Evento @{ Tipo = 'dns'; Resultado = $res }
        $res
    }
}

function Reset-PilhaRede {
    $s1 = netsh winsock reset 2>&1
    $s2 = netsh int ip reset 2>&1
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    Write-Log "Reset de rede: $($s1 -join ' ') | $($s2 -join ' ')"
}

# ===============================================================
#  Teste de servidor (TCP)
# ===============================================================
function Test-PortaTcp([string]$Servidor, [int]$Porta, [int]$TimeoutMs = 3000) {
    $res = [ordered]@{ Servidor = $Servidor; Porta = $Porta; Ok = $false; Ip = ''; DnsMs = $null; Ms = $null; Ping = ''; Mensagem = '' }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $ips = [Net.Dns]::GetHostAddresses($Servidor) | Where-Object { $_.AddressFamily -eq 'InterNetwork' }
        if (-not $ips) { $ips = [Net.Dns]::GetHostAddresses($Servidor) }
        $res.DnsMs = [int]$sw.ElapsedMilliseconds
        $ip = @($ips)[0]
        $res.Ip = $ip.ToString()
    } catch {
        $res.Mensagem = 'Nome não encontrado. Confira o endereço ou o DNS.'
        return [pscustomobject]$res
    }
    $cli = New-Object Net.Sockets.TcpClient
    try {
        $sw.Restart()
        $ar = $cli.BeginConnect($ip, $Porta, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            $res.Mensagem = "Sem resposta em $([math]::Round($TimeoutMs / 1000)) s. Firewall bloqueando ou servidor fora do ar."
        } else {
            $cli.EndConnect($ar)
            $res.Ms = [int]$sw.ElapsedMilliseconds
            $res.Ok = $true
            $res.Mensagem = "Porta aberta: conectou em $($res.Ms) ms."
        }
    } catch {
        $se = $_.Exception.InnerException
        if ($se -is [Net.Sockets.SocketException] -and $se.SocketErrorCode -eq 'ConnectionRefused') {
            $res.Mensagem = 'Conexão recusada: o servidor está no ar, mas nada escuta nessa porta.'
        } else { $res.Mensagem = "Falhou: $($_.Exception.InnerException.Message)" }
    } finally { $cli.Close() }
    try {
        $p = Test-Connection -ComputerName $res.Ip -Count 2 -ErrorAction Stop
        $res.Ping = "$([math]::Round(($p | Measure-Object ResponseTime -Average).Average)) ms"
    } catch { $res.Ping = 'sem resposta (normal em muitos servidores)' }
    return [pscustomobject]$res
}

# ===============================================================
#  Processo com saída ao vivo (SFC, DISM, winget)
#  Envia eventos 'log' (linhas) e 'progresso' (%) para a interface.
# ===============================================================
function Invoke-ProcessoAoVivo {
    param(
        [Parameter(Mandatory)][string]$Arquivo,
        [string]$Argumentos = '',
        [ValidateSet('oem', 'unicode', 'utf8')][string]$Codificacao = 'oem'
    )
    $enc = switch ($Codificacao) {
        'unicode' { [Text.Encoding]::Unicode }
        'utf8'    { New-Object Text.UTF8Encoding $false }
        default   { [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage) }
    }
    $psi = New-Object Diagnostics.ProcessStartInfo $Arquivo, $Argumentos
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = $enc
    $psi.StandardErrorEncoding = $enc
    Write-Log "Executando: $Arquivo $Argumentos"
    $p = [Diagnostics.Process]::Start($psi)
    $tarefaErro = $p.StandardError.ReadToEndAsync()
    $sb = New-Object Text.StringBuilder
    $ultima = ''
    $enviar = {
        $l = ($sb.ToString() -replace "`0", '').Trim()
        [void]$sb.Clear()
        # Ignora linhas vazias, giratórios (- \ | /) e barras de bloco do winget
        if (-not $l -or $l -match '^[\-\\|/\s]+$' -or $l -match '^[▀-▟\s]+$') { return }
        if ($l -match '(\d{1,3}(?:[.,]\d+)?)\s?%') {
            $pct = [double]($Matches[1] -replace ',', '.')
            if ($pct -le 100) { Send-Evento @{ Tipo = 'progresso'; Valor = $pct } }
        }
        if ($l -ne $ultima) { Send-Evento @{ Tipo = 'log'; Texto = $l }; $ultima = $l }
    }
    while (($c = $p.StandardOutput.Read()) -ge 0) {
        $ch = [char]$c
        if ($ch -eq "`r" -or $ch -eq "`n") { if ($sb.Length) { . $enviar } }
        else { [void]$sb.Append($ch) }
    }
    if ($sb.Length) { . $enviar }
    $p.WaitForExit()
    $err = $tarefaErro.Result
    if ($err) { foreach ($l in ($err -split "`r?`n")) { if ($l.Trim()) { Send-Evento @{ Tipo = 'log'; Texto = $l.Trim() } } } }
    Write-Log "Código de saída: $($p.ExitCode)"
    return $p.ExitCode
}

# ===============================================================
#  Winget
# ===============================================================
# IDs conferidos com "winget search" em 2026. Formato: Id = @{ Nome; Grupo }
# (RustDesk saiu do winget da comunidade; removido para não dar erro.)
$Script:ListaWingetPadrao = [ordered]@{
    'Google.Chrome'                   = @{ Nome = 'Google Chrome';                 Grupo = 'Navegadores e internet' }
    'Mozilla.Firefox'                 = @{ Nome = 'Firefox';                       Grupo = 'Navegadores e internet' }
    'Telegram.TelegramDesktop'        = @{ Nome = 'Telegram';                      Grupo = 'Navegadores e internet' }
    'Discord.Discord'                 = @{ Nome = 'Discord';                       Grupo = 'Navegadores e internet' }
    '7zip.7zip'                       = @{ Nome = '7-Zip';                         Grupo = 'Utilitários' }
    'RARLab.WinRAR'                   = @{ Nome = 'WinRAR';                         Grupo = 'Utilitários' }
    'Notepad++.Notepad++'             = @{ Nome = 'Notepad++';                      Grupo = 'Utilitários' }
    'voidtools.Everything'            = @{ Nome = 'Everything (busca instantânea)'; Grupo = 'Utilitários' }
    'Flameshot.Flameshot'             = @{ Nome = 'Flameshot (captura de tela)';   Grupo = 'Utilitários' }
    'VideoLAN.VLC'                    = @{ Nome = 'VLC';                           Grupo = 'Utilitários' }
    'Spotify.Spotify'                 = @{ Nome = 'Spotify';                        Grupo = 'Utilitários' }
    'AnyDesk.AnyDesk'                 = @{ Nome = 'AnyDesk';                        Grupo = 'Acesso remoto e rede' }
    'Famatech.RadminVPN'              = @{ Nome = 'Radmin VPN';                     Grupo = 'Acesso remoto e rede' }
    'Famatech.AdvancedIPScanner'      = @{ Nome = 'Advanced IP Scanner';           Grupo = 'Acesso remoto e rede' }
    'PuTTY.PuTTY'                     = @{ Nome = 'PuTTY';                          Grupo = 'Acesso remoto e rede' }
    'WinSCP.WinSCP'                   = @{ Nome = 'WinSCP';                         Grupo = 'Acesso remoto e rede' }
    'WiresharkFoundation.Wireshark'   = @{ Nome = 'Wireshark';                      Grupo = 'Acesso remoto e rede' }
    'Valve.Steam'                     = @{ Nome = 'Steam';                          Grupo = 'Jogos' }
    'ArtCraft.PdfCraft'               = @{ Nome = 'PdfCraft (editor de PDF)';       Grupo = 'ArtCraft (criação)' }
    'ArtCraft.VectorCraft'            = @{ Nome = 'VectorCraft (vetores)';          Grupo = 'ArtCraft (criação)' }
    'ArtCraft.CadCraft'               = @{ Nome = 'CadCraft (desenho técnico)';     Grupo = 'ArtCraft (criação)' }
    'ArtCraft.EffectCraft'            = @{ Nome = 'EffectCraft (efeitos)';          Grupo = 'ArtCraft (criação)' }
    'ArtCraft.FilmCraft'              = @{ Nome = 'FilmCraft (vídeo)';              Grupo = 'ArtCraft (criação)' }
    'ArtCraft.GridCraft'              = @{ Nome = 'GridCraft (planilhas/grid)';     Grupo = 'ArtCraft (criação)' }
    'ArtCraft.SoundCraft'             = @{ Nome = 'SoundCraft (áudio)';             Grupo = 'ArtCraft (criação)' }
    'Git.Git'                         = @{ Nome = 'Git';                            Grupo = 'Desenvolvimento' }
    'Microsoft.VisualStudioCode'      = @{ Nome = 'VS Code';                        Grupo = 'Desenvolvimento' }
    'Microsoft.PowerToys'             = @{ Nome = 'PowerToys';                      Grupo = 'Desenvolvimento' }
    'Microsoft.WindowsTerminal'       = @{ Nome = 'Windows Terminal';               Grupo = 'Desenvolvimento' }
    'Python.Python.3.12'              = @{ Nome = 'Python 3.12';                     Grupo = 'Desenvolvimento' }
    'CPUID.CPU-Z'                     = @{ Nome = 'CPU-Z';                           Grupo = 'Diagnóstico' }
    'CPUID.HWMonitor'                 = @{ Nome = 'HWMonitor (temperaturas)';        Grupo = 'Diagnóstico' }
    'TechPowerUp.GPU-Z'               = @{ Nome = 'GPU-Z';                           Grupo = 'Diagnóstico' }
    'CrystalDewWorld.CrystalDiskInfo' = @{ Nome = 'CrystalDiskInfo (saúde do disco)'; Grupo = 'Diagnóstico' }
}

# Devolve lista de objetos { Id; Nome; Grupo }, mantendo a ordem.
# A lista pessoal (winget-lista.txt) aceita "Id;Nome" ou "Id;Nome;Grupo".
function Get-ListaWinget {
    $arq = Join-Path $Script:Otz.SrcDir 'winget-lista.txt'
    if (Test-Path $arq) {
        $itens = New-Object System.Collections.Generic.List[object]
        foreach ($l in [IO.File]::ReadAllLines($arq, [Text.Encoding]::UTF8)) {
            $l = $l.Trim()
            if (-not $l -or $l.StartsWith('#')) { continue }
            $p = $l -split ';'
            $id = $p[0].Trim()
            $nome = if ($p.Count -gt 1 -and $p[1].Trim()) { $p[1].Trim() } else { $id }
            $grupo = if ($p.Count -gt 2 -and $p[2].Trim()) { $p[2].Trim() } else { 'Minha lista' }
            $itens.Add([pscustomobject]@{ Id = $id; Nome = $nome; Grupo = $grupo })
        }
        return $itens.ToArray()
    }
    $itens = New-Object System.Collections.Generic.List[object]
    foreach ($id in $Script:ListaWingetPadrao.Keys) {
        $v = $Script:ListaWingetPadrao[$id]
        $itens.Add([pscustomobject]@{ Id = $id; Nome = $v.Nome; Grupo = $v.Grupo })
    }
    return $itens.ToArray()
}

# ===============================================================
#  Espaço em disco: onde está o espaço e limpezas seguras
# ===============================================================
function Get-PastasCacheNavegador {
    $la = $env:LOCALAPPDATA
    $padroes = @(
        "$la\Google\Chrome\User Data\*\Cache", "$la\Google\Chrome\User Data\*\Code Cache"
        "$la\Microsoft\Edge\User Data\*\Cache", "$la\Microsoft\Edge\User Data\*\Code Cache"
        "$la\Mozilla\Firefox\Profiles\*\cache2"
    )
    $pastas = New-Object System.Collections.Generic.List[string]
    foreach ($p in $padroes) {
        foreach ($r in @(Resolve-Path $p -ErrorAction SilentlyContinue)) { $pastas.Add($r.ProviderPath) }
    }
    return $pastas.ToArray()
}

function Get-NavegadoresAbertos {
    $nomes = @{ chrome = 'Chrome'; msedge = 'Edge'; firefox = 'Firefox' }
    return @($nomes.Keys | Where-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue } | ForEach-Object { $nomes[$_] })
}

function Clear-CacheNavegadores {
    $pastas = Get-PastasCacheNavegador
    $antes = Get-TamanhoPastas $pastas
    foreach ($p in $pastas) { Get-ChildItem $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
    $liberado = [math]::Max(0, $antes - (Get-TamanhoPastas $pastas))
    $abertos = Get-NavegadoresAbertos
    $msg = "Liberados $(Format-Tamanho $liberado)."
    if ($abertos) { return @{ Status = 'aviso'; Mensagem = "$msg Com $($abertos -join ', ') aberto(s), parte do cache ficou em uso. Feche e rode de novo para limpar tudo." } }
    return @{ Status = 'ok'; Mensagem = $msg }
}

function Clear-CacheWindowsUpdate {
    $pasta = "$env:SystemRoot\SoftwareDistribution\Download"
    $antes = Get-TamanhoPastas @($pasta)
    foreach ($s in 'wuauserv', 'bits') { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue }
    try {
        Get-ChildItem $pasta -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    } finally {
        foreach ($s in 'bits', 'wuauserv') { Start-Service -Name $s -ErrorAction SilentlyContinue }
    }
    $liberado = [math]::Max(0, $antes - (Get-TamanhoPastas @($pasta)))
    return @{ Status = 'ok'; Mensagem = "Liberados $(Format-Tamanho $liberado). O Windows Update já voltou a funcionar." }
}

# Lugares que costumam ocupar espaço. Acao: abrir:<pasta> | item:<id do catálogo> | cleanmgr | info
function Get-LocaisEspaco {
    $u = $env:USERPROFILE
    $l = New-Object System.Collections.Generic.List[object]
    function Add-Local($nome, $pastas, $acao, $dica) { $l.Add([pscustomobject]@{ Nome = $nome; Pastas = @($pastas); Acao = $acao; Dica = $dica }) }
    $pastaUsuario = { param($id, $padrao) $p = [Environment]::GetFolderPath($id); if (-not $p) { $p = Join-Path $u $padrao }; $p }
    $down = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
    if (-not $down) { $down = Join-Path $u 'Downloads' }
    Add-Local 'Downloads'               @($down) "abrir:$down" 'Instaladores e arquivos antigos costumam se acumular aqui.'
    Add-Local 'Área de Trabalho'        @((& $pastaUsuario 'Desktop' 'Desktop')) "abrir:$((& $pastaUsuario 'Desktop' 'Desktop'))" 'Arquivos salvos direto na área de trabalho.'
    Add-Local 'Documentos'              @((& $pastaUsuario 'MyDocuments' 'Documents')) "abrir:$((& $pastaUsuario 'MyDocuments' 'Documents'))" 'Seus documentos e, às vezes, saves de jogos.'
    Add-Local 'Vídeos'                  @((& $pastaUsuario 'MyVideos' 'Videos')) "abrir:$((& $pastaUsuario 'MyVideos' 'Videos'))" 'Gravações de tela e de jogos ficam aqui.'
    Add-Local 'Imagens'                 @((& $pastaUsuario 'MyPictures' 'Pictures')) "abrir:$((& $pastaUsuario 'MyPictures' 'Pictures'))" 'Fotos e capturas de tela.'
    Add-Local 'Arquivos temporários'    @($env:TEMP, "$env:SystemRoot\Temp") 'item:limpeza.temp' 'Sobras de instalações. Pode limpar sem medo.'
    Add-Local 'Cache dos navegadores'   (Get-PastasCacheNavegador) 'item:limpeza.navegadores' 'Cópias de sites visitados. Pode limpar; senhas e favoritos ficam.'
    Add-Local 'Atualizações já baixadas' @("$env:SystemRoot\SoftwareDistribution\Download") 'item:limpeza.windows-update' 'Instaladores de atualizações do Windows.'
    $old = Join-Path $env:SystemDrive 'Windows.old'
    if (Test-Path $old) { Add-Local 'Windows antigo (Windows.old)' @($old) 'cleanmgr' 'Cópia do Windows anterior a uma atualização grande. Remova pela Limpeza de Disco > Limpar arquivos do sistema.' }
    return $l.ToArray()
}

# Mede cada local e envia 'espaco' ao vivo; arquivos do sistema (hiberfil/pagefile) só informativo
function Get-UsoEspaco {
    $res = New-Object System.Collections.Generic.List[object]
    foreach ($loc in Get-LocaisEspaco) {
        $tam = Get-TamanhoPastas $loc.Pastas
        $r = [pscustomobject]@{ Nome = $loc.Nome; Bytes = $tam; Acao = $loc.Acao; Dica = $loc.Dica }
        Send-Evento @{ Tipo = 'espaco'; Local = $r }
        $res.Add($r)
    }
    foreach ($sis in @(@{ N = 'Arquivo de hibernação (hiberfil.sys)'; A = 'hiberfil.sys'; D = 'Dá para remover desligando a hibernação (Otimizar > Sistema).' }, @{ N = 'Memória virtual (pagefile.sys)'; A = 'pagefile.sys'; D = 'Usado pelo Windows quando a RAM enche. Não apague.' })) {
        $tam = 0
        try { $tam = (Get-Item (Join-Path $env:SystemDrive $sis.A) -Force -ErrorAction Stop).Length } catch { }
        if ($tam -gt 0) {
            $acao = if ($sis.A -eq 'hiberfil.sys') { 'item:sistema.hibernacao' } else { 'info' }
            $r = [pscustomobject]@{ Nome = $sis.N; Bytes = [double]$tam; Acao = $acao; Dica = $sis.D }
            Send-Evento @{ Tipo = 'espaco'; Local = $r }
            $res.Add($r)
        }
    }
    return $res.ToArray()
}

# Maiores arquivos da pasta do usuário (só lê)
function Get-ArquivosGrandes([int]$Quantidade = 15, [long]$MinBytes = 300MB) {
    Send-Evento @{ Tipo = 'log'; Texto = "Procurando arquivos maiores que $(Format-Tamanho $MinBytes) em $env:USERPROFILE..." }
    $achados = Get-ChildItem $env:USERPROFILE -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -ge $MinBytes } | Sort-Object Length -Descending | Select-Object -First $Quantidade
    # Explica os tipos que mais aparecem e não são "seus arquivos"
    $dicas = @(
        @{ Re = '\\NVIDIA\\(DXCache|GLCache)|\.nvph$';       Txt = 'Cache de shaders da NVIDIA: o driver recria sozinho. Não apague à mão; use a Limpeza de Disco (Cache de sombreador DirectX).' }
        @{ Re = 'D3DSCache|ushaderprecache|shadercache';      Txt = 'Cache de shaders de jogos/DirectX: acelera o carregamento. Pode ser recriado pelo jogo.' }
        @{ Re = '\.(iso|img)$';                               Txt = 'Imagem de disco (instalador). Se já instalou, pode apagar.' }
        @{ Re = '\.(exe|msi|zip|rar|7z)$';                    Txt = 'Instalador ou arquivo compactado. Se já usou, pode apagar.' }
        @{ Re = '\.(mp4|mkv|mov|avi)$';                       Txt = 'Vídeo. Considere mover para um HD externo ou nuvem.' }
        @{ Re = '\.(vhdx?|vmdk)$';                            Txt = 'Disco virtual (máquina virtual ou WSL). Não apague se usa a VM.' }
        @{ Re = '\.(pst|ost)$';                               Txt = 'Arquivo de e-mails do Outlook. NÃO apague.' }
    )
    return @($achados | ForEach-Object {
        $dica = ''
        foreach ($d in $dicas) { if ($_.FullName -match $d.Re) { $dica = $d.Txt; break } }
        [pscustomobject]@{ Nome = $_.Name; Pasta = $_.DirectoryName; Caminho = $_.FullName; Bytes = [double]$_.Length; Data = $_.LastWriteTime; Dica = $dica }
    })
}
# Arquivos repetidos nas pastas do usuário (mesmo tamanho e mesmo conteúdo).
# Arquivos só na nuvem (OneDrive "sob demanda") são pulados para não baixá-los.
function Get-ArquivosDuplicados([long]$MinBytes = 1MB, [int]$MaxGrupos = 30) {
    $u = $env:USERPROFILE
    $down = Join-Path $u 'Downloads'
    try { $d = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path; if ($d) { $down = $d } } catch { }
    $pastas = @($down, [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('MyPictures'), [Environment]::GetFolderPath('MyVideos'), [Environment]::GetFolderPath('MyMusic')) |
        Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
    Send-Evento @{ Tipo = 'log'; Texto = "Procurando arquivos repetidos em $($pastas.Count) pasta(s)..." }
    $nuvem = 0x00400000 -bor 0x00001000 -bor 0x00040000   # RECALL_ON_DATA_ACCESS | OFFLINE | RECALL_ON_OPEN
    $porTamanho = @{}
    foreach ($p in $pastas) {
        foreach ($f in @(Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue)) {
            if ($f.Length -lt $MinBytes -or ([int]$f.Attributes -band $nuvem)) { continue }
            if (-not $porTamanho.ContainsKey($f.Length)) { $porTamanho[$f.Length] = New-Object System.Collections.Generic.List[object] }
            $porTamanho[$f.Length].Add($f)
        }
    }
    $grupos = New-Object System.Collections.Generic.List[object]
    foreach ($tam in $porTamanho.Keys) {
        $cands = $porTamanho[$tam]
        if ($cands.Count -lt 2) { continue }
        $porHash = @{}
        foreach ($f in $cands) {
            try { $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash } catch { continue }
            if (-not $porHash.ContainsKey($h)) { $porHash[$h] = New-Object System.Collections.Generic.List[object] }
            $porHash[$h].Add($f)
        }
        foreach ($h in $porHash.Keys) {
            $iguais = $porHash[$h]
            if ($iguais.Count -lt 2) { continue }
            # Mantém a cópia fora de Downloads, se houver; senão a mais antiga
            $ordenados = @($iguais | Sort-Object @{ Expression = { $_.FullName -like "$down\*" } }, CreationTime)
            $r = [ordered]@{}
            $r.Nome = $ordenados[0].Name
            $r.Bytes = [double]$tam
            $r.Manter = $ordenados[0].FullName
            $r.Copias = [string[]]@($ordenados | Select-Object -Skip 1 | ForEach-Object FullName)
            $r.Desperdicio = [double]$tam * ($iguais.Count - 1)
            $grupos.Add([pscustomobject]$r)
        }
    }
    return @($grupos | Sort-Object Desperdicio -Descending | Select-Object -First $MaxGrupos)
}

# Envia para a Lixeira (dá para recuperar), nunca apaga direto
function Move-ParaLixeira([string[]]$Caminhos) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $ok = 0; $erros = New-Object System.Collections.Generic.List[string]
    foreach ($c in $Caminhos) {
        try {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($c, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
            $ok++
            Write-Log "Enviado para a Lixeira: $c"
        } catch { $erros.Add("$(Split-Path $c -Leaf): $($_.Exception.Message)") }
    }
    return @{ Ok = $ok; Erros = $erros.ToArray() }
}
