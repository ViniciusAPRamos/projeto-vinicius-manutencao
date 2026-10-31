#Requires -Version 5.1
<#
    ===============================================================
     OTIMIZADOR VINICIUS  v1.1
     Desenvolvimento próprio - Windows 10 / 11
    ---------------------------------------------------------------
     - Cria ponto de restauração antes da primeira alteração
     - Exporta (.reg) cada chave do registro antes de alterar
     - Opção [R] restaura qualquer backup feito pelo script
     - Log completo em Documentos\OtimizadorVinicius
    ---------------------------------------------------------------
     v1.1: Rede/DNS, Inicialização, Drivers USB-serial,
           Relatório do PC (HTML) e Programas (winget)
    ===============================================================
#>

# ---------------------------------------------------------------
#  Elevação automática (precisa de administrador para HKLM/powercfg)
# ---------------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

# ---------------------------------------------------------------
#  Variáveis globais
# ---------------------------------------------------------------
$Script:Versao        = '1.1'
$Script:ScriptDir     = Split-Path -Parent $PSCommandPath
$Script:BaseDir       = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'OtimizadorVinicius'
$Script:BackupRoot    = Join-Path $Script:BaseDir 'Backups'
$Script:BackupDir     = Join-Path $Script:BackupRoot (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')
$Script:Build         = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
$Script:IsWin11       = $Script:Build -ge 22000
$Script:PontoCriado   = $false
$Script:PrecisaLogoff = $false
$Script:PrecisaReboot = $false
$Script:NomePlano     = 'Vinicius - Desempenho Maximo'

# Lista padrão de programas (winget). Para personalizar sem editar o script,
# crie "winget-lista.txt" ao lado do script com uma linha por programa: Id;Nome
$Script:ListaWinget = [ordered]@{
    'Google.Chrome'                  = 'Google Chrome'
    'Mozilla.Firefox'                = 'Firefox'
    '7zip.7zip'                      = '7-Zip'
    'Notepad++.Notepad++'            = 'Notepad++'
    'Microsoft.VisualStudioCode'     = 'VS Code'
    'Microsoft.PowerToys'            = 'PowerToys'
    'Microsoft.WindowsTerminal'      = 'Windows Terminal'
    'voidtools.Everything'           = 'Everything (busca instantânea)'
    'AnyDesk.AnyDesk'                = 'AnyDesk'
    'RustDesk.RustDesk'              = 'RustDesk'
    'PuTTY.PuTTY'                    = 'PuTTY'
    'WinSCP.WinSCP'                  = 'WinSCP'
    'WiresharkFoundation.Wireshark'  = 'Wireshark'
    'Famatech.AdvancedIPScanner'     = 'Advanced IP Scanner'
    'Git.Git'                        = 'Git'
    'Python.Python.3.12'             = 'Python 3.12'
    'CPUID.CPU-Z'                    = 'CPU-Z'
    'CPUID.HWMonitor'                = 'HWMonitor'
    'TechPowerUp.GPU-Z'              = 'GPU-Z'
    'CrystalDewWorld.CrystalDiskInfo'= 'CrystalDiskInfo'
    'VideoLAN.VLC'                   = 'VLC'
    'Telegram.TelegramDesktop'       = 'Telegram'
    'Discord.Discord'                = 'Discord'
    'Valve.Steam'                    = 'Steam'
    'Spotify.Spotify'                = 'Spotify'
}

New-Item -ItemType Directory -Path $Script:BackupRoot -Force | Out-Null
Start-Transcript -Path (Join-Path $Script:BaseDir ("log_" + (Get-Date -Format 'yyyy-MM-dd') + ".txt")) -Append | Out-Null

# ---------------------------------------------------------------
#  Funções auxiliares
# ---------------------------------------------------------------
function Write-Titulo([string]$t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }
function Write-Ok([string]$t)     { Write-Host "  [OK] $t" -ForegroundColor Green }
function Write-Aviso([string]$t)  { Write-Host "  [!]  $t" -ForegroundColor Yellow }
function Write-Erro([string]$t)   { Write-Host "  [X]  $t" -ForegroundColor Red }

function Confirmar([string]$pergunta) {
    $r = Read-Host "  $pergunta (S/N)"
    return ($r -match '^[sS]')
}

function Cortar([string]$s, [int]$n) {
    if ($null -eq $s) { return '' }
    if ($s.Length -gt $n) { return $s.Substring(0, $n - 3) + '...' }
    return $s
}

# Reinicia o Explorer; se o Windows não reabrir sozinho em 3 s, abre manualmente
function Restart-Explorer {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 6; $i++) {
        Start-Sleep -Milliseconds 500
        if (Get-Process explorer -ErrorAction SilentlyContinue) { return }
    }
    Start-Process explorer.exe
}

# Lê "1,3,5-8" ou "T" (todos) e devolve índices de 1..$max
function Read-Indices([string]$texto, [int]$max) {
    $texto = $texto.Trim().ToUpper()
    if ($texto -eq 'T') { return 1..$max }
    $res = New-Object System.Collections.Generic.List[int]
    foreach ($parte in ($texto -split '[,; ]+')) {
        if ($parte -match '^(\d+)-(\d+)$') {
            foreach ($i in [int]$Matches[1]..[int]$Matches[2]) { if ($i -ge 1 -and $i -le $max) { $res.Add($i) } }
        } elseif ($parte -match '^\d+$') {
            $i = [int]$parte
            if ($i -ge 1 -and $i -le $max) { $res.Add($i) }
        }
    }
    return ($res | Select-Object -Unique)
}

function ConvertTo-RegExePath([string]$p) {
    return ($p -replace '^HKCU:\\', 'HKCU\' -replace '^HKLM:\\', 'HKLM\')
}

function Initialize-BackupDir {
    if (-not (Test-Path $Script:BackupDir)) { New-Item -ItemType Directory -Path $Script:BackupDir -Force | Out-Null }
}

# Exporta a chave para .reg uma única vez por sessão
function Backup-Chave([string]$Path) {
    if (-not (Test-Path $Path)) { return }
    Initialize-BackupDir
    $reg  = ConvertTo-RegExePath $Path
    $nome = ($reg -replace '[\\/:*?"<>| {}]', '_') + '.reg'
    $dest = Join-Path $Script:BackupDir $nome
    if (Test-Path $dest) { return }
    reg.exe export $reg $dest /y 2>&1 | Out-Null
}

function Set-Reg {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('DWord', 'String', 'QWord', 'Binary')][string]$Type = 'DWord'
    )
    try {
        Backup-Chave $Path
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Erro "Falha em $Path\$Name : $($_.Exception.Message)"
    }
}

function New-PontoRestauracao {
    if ($Script:PontoCriado) { return }
    $Script:PontoCriado = $true
    Write-Titulo 'Ponto de restauração'
    $chaveSR = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    # Guarda o valor do usuário (se houver) para não apagar uma configuração dele
    $anterior = (Get-ItemProperty -Path $chaveSR -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        # O Windows só permite 1 ponto a cada 24h; libera temporariamente
        New-ItemProperty -Path $chaveSR -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force | Out-Null
        $avisos = $null
        Checkpoint-Computer -Description ("Otimizador Vinicius " + (Get-Date -Format 'dd/MM HH:mm')) -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningVariable avisos -WarningAction SilentlyContinue
        # Checkpoint-Computer avisa (não dá erro) quando não consegue criar o ponto
        if ($avisos) { Write-Aviso "Ponto não criado: $($avisos[0])" } else { Write-Ok 'Ponto de restauração criado.' }
    } catch {
        Write-Aviso "Não foi possível criar o ponto: $($_.Exception.Message)"
        Write-Aviso 'O backup .reg continuará sendo feito normalmente.'
    } finally {
        if ($null -ne $anterior) {
            New-ItemProperty -Path $chaveSR -Name 'SystemRestorePointCreationFrequency' -Value $anterior -PropertyType DWord -Force | Out-Null
        } else {
            Remove-ItemProperty -Path $chaveSR -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue
        }
    }
}

# API do Windows para aplicar configurações de mouse sem precisar de logoff
Add-Type -ErrorAction SilentlyContinue @"
using System;
using System.Runtime.InteropServices;
public static class OtzWin32 {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni);
    [DllImport("user32.dll", SetLastError = true, EntryPoint = "SystemParametersInfo")]
    public static extern bool SystemParametersInfoPtr(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);
}
"@

# ===============================================================
#  1 - MOUSE
# ===============================================================
function Optimize-Mouse {
    Write-Titulo '1 - Mouse (precisão 1:1)'
    $k = 'HKCU:\Control Panel\Mouse'
    # Desativa "Aumentar precisão do ponteiro" (aceleração)
    Set-Reg $k 'MouseSpeed'      '0'  String
    Set-Reg $k 'MouseThreshold1' '0'  String
    Set-Reg $k 'MouseThreshold2' '0'  String
    # 10 = 6º entalhe (padrão) = movimento 1:1, sem pular pixels
    Set-Reg $k 'MouseSensitivity' '10' String

    # Aplica na hora (SPI_SETMOUSE = 0x0004 / SPI_SETMOUSESPEED = 0x0071)
    $flags = 0x01 -bor 0x02   # SPIF_UPDATEINIFILE | SPIF_SENDCHANGE
    [void][OtzWin32]::SystemParametersInfo(0x0004, 0, [int[]](0, 0, 0), $flags)
    [void][OtzWin32]::SystemParametersInfoPtr(0x0071, 0, [IntPtr]10, $flags)

    Write-Ok 'Aceleração desativada (Aumentar precisão do ponteiro = OFF).'
    Write-Ok 'Sensibilidade do Windows em 6/11 (1:1). Ajuste o DPI no software do mouse.'
}

# ===============================================================
#  2 - TECLADO: aderência, filtro, alternância e Alt+Shift
# ===============================================================
function Disable-AtalhosTeclado {
    Write-Titulo '2 - Teclado (atalhos de acessibilidade e idioma)'
    Set-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys'        'Flags' '506' String   # Shift 5x
    Set-Reg 'HKCU:\Control Panel\Accessibility\ToggleKeys'        'Flags' '58'  String   # NumLock 5s
    Set-Reg 'HKCU:\Control Panel\Accessibility\Keyboard Response' 'Flags' '122' String   # Shift direito 8s

    $t = 'HKCU:\Keyboard Layout\Toggle'
    Set-Reg $t 'Hotkey'          '3' String
    Set-Reg $t 'Language Hotkey' '3' String
    Set-Reg $t 'Layout Hotkey'   '3' String

    $Script:PrecisaLogoff = $true
    Write-Ok 'Teclas de aderência, filtro e alternância: atalhos desativados.'
    Write-Ok 'Alt+Shift e Ctrl+Shift não trocam mais o idioma (Win+Espaço continua).'
}

# ===============================================================
#  3 - ENERGIA
# ===============================================================
function Set-EnergiaMaxima {
    Write-Titulo '3 - Energia (desempenho máximo)'

    if (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) {
        Write-Aviso 'Notebook detectado: as alterações valem só na tomada (AC). Bateria não é afetada.'
    }

    $existente = powercfg /list | Select-String -SimpleMatch $Script:NomePlano
    if ($existente -and ($existente.ToString() -match '([0-9a-fA-F-]{36})')) {
        $guid = $Matches[1]
        Write-Ok 'Plano já existia, reutilizando.'
    } else {
        $out = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-String
        if ($out -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
            $guid = $Matches[1]
            powercfg -changename $guid $Script:NomePlano 'Plano criado pelo Otimizador Vinicius' | Out-Null
            Write-Ok 'Plano "Desempenho Máximo" (Ultimate) criado.'
        } else {
            Write-Aviso 'Este PC não aceita o plano Ultimate (comum em notebooks com Modern Standby).'
            Write-Aviso 'Usando "Alto desempenho".'
            $guid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        }
    }

    powercfg -setactive $guid | Out-Null

    # Ajustes finos do plano ativo (somente AC)
    powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 2>&1 | Out-Null              # CPU mínimo 100%
    powercfg -setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null  # USB seletivo OFF
    powercfg -setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0 2>&1 | Out-Null  # PCIe ASPM OFF
    powercfg -change -disk-timeout-ac 0    | Out-Null
    powercfg -change -standby-timeout-ac 0 | Out-Null
    powercfg -setactive SCHEME_CURRENT     | Out-Null

    Write-Ok 'Plano ativo. CPU sem redução de clock, USB e PCIe sem economia de energia.'
    Write-Ok 'Disco e suspensão nunca desligam na tomada (monitor mantém sua configuração).'
}

# ===============================================================
#  4 - MODO GAME
# ===============================================================
function Set-ModoGame {
    Write-Titulo '4 - Modo Game'
    Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
    Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode'   1
    Write-Ok 'Modo de Jogo do Windows ativado.'

    # Gravação em segundo plano (Game DVR) consome GPU/disco
    Set-Reg 'HKCU:\System\GameConfigStore'                            'GameDVR_Enabled'   0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
    Write-Ok 'Gravação em segundo plano (Game DVR) desativada.'

    # Agendamento de GPU acelerado por hardware (HAGS)
    if ($Script:Build -ge 19041) {
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2
        $Script:PrecisaReboot = $true
        Write-Ok 'Agendamento de GPU por hardware ativado (requer GPU/driver compatível).'
    }

    # Prioridade multimídia para jogos
    $mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    Set-Reg $mm 'SystemResponsiveness' 10
    Set-Reg "$mm\Tasks\Games" 'GPU Priority'        8
    Set-Reg "$mm\Tasks\Games" 'Priority'            6
    Set-Reg "$mm\Tasks\Games" 'Scheduling Category' 'High' String
    Set-Reg "$mm\Tasks\Games" 'SFIO Priority'       'High' String
    Write-Ok 'Prioridade de CPU/GPU para jogos elevada (MMCSS).'
}

# ===============================================================
#  5 - INTERFACE MAIS RÁPIDA
# ===============================================================
function Optimize-Interface {
    Write-Titulo '5 - Interface mais rápida'
    Set-Reg 'HKCU:\Control Panel\Desktop'               'MenuShowDelay' '50' String
    Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate'    '0'  String
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'  'TaskbarAnimations'  0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'  'HideFileExt'        0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0

    Write-Ok 'Menus abrem mais rápido, animações e transparência desligadas.'
    Write-Ok 'Extensões de arquivo visíveis (.exe, .bat, .cfg...).'
    Write-Ok 'Programas de inicialização sem atraso artificial.'

    Restart-Explorer
    $Script:PrecisaLogoff = $true
}

# ===============================================================
#  6 - PRIVACIDADE E ANÚNCIOS
# ===============================================================
function Disable-Anuncios {
    Write-Titulo '6 - Privacidade e anúncios'
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0

    $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach ($n in 'SilentInstalledAppsEnabled', 'SystemPaneSuggestionsEnabled', 'SoftLandingEnabled',
                   'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
                   'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled') {
        Set-Reg $cdm $n 0
    }

    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'      'DisableSearchBoxSuggestions' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'             0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'         'PublishUserActivities'      0

    Write-Ok 'ID de anúncios, apps sugeridos e dicas do Windows desativados.'
    Write-Ok 'Pesquisa do Iniciar sem resultados do Bing.'
    Write-Ok 'Telemetria no mínimo permitido pela edição do Windows.'
    $Script:PrecisaLogoff = $true
}

# ===============================================================
#  7 - LIMPEZA
# ===============================================================
function Invoke-Limpeza {
    Write-Titulo '7 - Limpeza de temporários'
    $liberado = 0
    foreach ($pasta in @($env:TEMP, "$env:SystemRoot\Temp")) {
        if (-not (Test-Path $pasta)) { continue }
        $antes = [double](Get-ChildItem $pasta -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        Get-ChildItem $pasta -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $depois = [double](Get-ChildItem $pasta -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        $liberado += [math]::Max(0, $antes - $depois)
    }
    Write-Ok ("Temporários: {0:N0} MB liberados (arquivos em uso foram mantidos)." -f ($liberado / 1MB))

    ipconfig /flushdns | Out-Null
    Write-Ok 'Cache DNS limpo.'

    if (Confirmar 'Esvaziar a Lixeira? (exclusão permanente)') {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-Ok 'Lixeira esvaziada.'
    }
}

# ===============================================================
#  8 - INICIALIZAÇÃO RÁPIDA / HIBERNAÇÃO
# ===============================================================
function Disable-InicializacaoRapida {
    Write-Titulo '8 - Inicialização rápida e hibernação'
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0
    Write-Ok 'Inicialização rápida desativada (desligar passa a ser desligamento real).'
    Write-Ok 'Ajuda com drivers USB/serial que travam após "desligar".'

    if (Confirmar 'Desativar também a hibernação e liberar o arquivo hiberfil.sys?') {
        powercfg -h off | Out-Null
        Write-Ok 'Hibernação desativada.'
    }
}

# ===============================================================
#  9 - MENU DE CONTEXTO CLÁSSICO (Windows 11)
# ===============================================================
function Set-MenuClassico {
    Write-Titulo '9 - Menu de contexto clássico (Windows 11)'
    if (-not $Script:IsWin11) { Write-Aviso 'Disponível apenas no Windows 11.'; return }
    $p = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
    New-Item -Path $p -Force | Out-Null
    Set-Item -Path $p -Value ''
    Restart-Explorer
    Write-Ok 'Clique direito volta ao menu completo, sem "Mostrar mais opções".'
    Write-Aviso 'Para desfazer use a opção D (a restauração R não remove esta chave).'
}

function Undo-MenuClassico {
    Remove-Item 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' -Recurse -Force -ErrorAction SilentlyContinue
    Restart-Explorer
    Write-Ok 'Menu de contexto do Windows 11 restaurado.'
}

# ===============================================================
#  N - REDE: DNS e economia de energia da placa
# ===============================================================
function Get-AdaptadoresAtivos {
    return @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')
}

# Salva o DNS atual (estático ou automático) no backup da sessão
function Save-DnsAtual {
    Initialize-BackupDir
    $arq = Join-Path $Script:BackupDir 'dns.json'
    if (Test-Path $arq) { return }
    $dados = foreach ($a in Get-AdaptadoresAtivos) {
        $chave    = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($a.InterfaceGuid)"
        $estatico = [string](Get-ItemProperty -Path $chave -Name NameServer -ErrorAction SilentlyContinue).NameServer
        [pscustomobject]@{ Nome = $a.Name; Index = $a.ifIndex; Estatico = $estatico }
    }
    @($dados) | ConvertTo-Json | Set-Content -Path $arq -Encoding UTF8
}

function Restore-Dns([string]$arquivo) {
    if (-not (Test-Path $arquivo)) { return }
    foreach ($d in @(Get-Content $arquivo -Raw | ConvertFrom-Json)) {
        try {
            if ([string]::IsNullOrWhiteSpace($d.Estatico)) {
                Set-DnsClientServerAddress -InterfaceIndex $d.Index -ResetServerAddresses -ErrorAction Stop
                Write-Ok "$($d.Nome): DNS automático restaurado."
            } else {
                Set-DnsClientServerAddress -InterfaceIndex $d.Index -ServerAddresses ($d.Estatico -split '[,\s]+' | Where-Object { $_ }) -ErrorAction Stop
                Write-Ok "$($d.Nome): DNS $($d.Estatico) restaurado."
            }
        } catch { Write-Erro "$($d.Nome): $($_.Exception.Message)" }
    }
    Clear-DnsClientCache
}

function Set-Dns([string[]]$servidores, [string]$nome) {
    $ads = Get-AdaptadoresAtivos
    if ($ads.Count -eq 0) { Write-Aviso 'Nenhum adaptador de rede conectado.'; return }
    Save-DnsAtual
    foreach ($a in $ads) {
        try {
            if ($servidores) {
                Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $servidores -ErrorAction Stop
            } else {
                Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses -ErrorAction Stop
            }
            Write-Ok "$($a.Name): $nome"
        } catch { Write-Erro "$($a.Name): $($_.Exception.Message)" }
    }
    Clear-DnsClientCache
    Write-Ok 'Cache DNS limpo.'
}

function Test-Dns {
    Write-Titulo 'Teste de velocidade de DNS'
    $atual = $null
    foreach ($a in Get-AdaptadoresAtivos) {
        $s = (Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
        if ($s) { $atual = $s[0]; break }
    }
    $servs = [ordered]@{}
    if ($atual) { $servs["Atual ($atual)"] = $atual }
    $servs['Cloudflare (1.1.1.1)'] = '1.1.1.1'
    $servs['Google (8.8.8.8)']     = '8.8.8.8'
    $servs['Quad9 (9.9.9.9)']      = '9.9.9.9'

    $dominios = 'google.com', 'microsoft.com', 'youtube.com', 'cloudflare.com', 'mercadolivre.com.br', 'globo.com'
    foreach ($k in $servs.Keys) {
        $tempos = foreach ($d in $dominios) {
            try {
                (Measure-Command {
                    Resolve-DnsName -Name $d -Server $servs[$k] -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop | Out-Null
                }).TotalMilliseconds
            } catch { }
        }
        if ($tempos) {
            $media = ($tempos | Measure-Object -Average).Average
            Write-Host ("  {0,-28} {1,6:N0} ms  ({2}/{3} respostas)" -f $k, $media, @($tempos).Count, $dominios.Count)
        } else {
            Write-Host ("  {0,-28} sem resposta" -f $k) -ForegroundColor Red
        }
    }
    Write-Aviso 'Rode 2 vezes: o primeiro teste pode pegar cache vazio no servidor.'
}

function Set-EnergiaRede([bool]$desativar) {
    $acao = if ($desativar) { 'Disabled' } else { 'Enabled' }
    $eee  = if ($desativar) { 0 } else { 1 }
    foreach ($a in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)) {
        try {
            Set-NetAdapterPowerManagement -Name $a.Name -AllowComputerToTurnOffDevice $acao -NoRestart -ErrorAction Stop
            Write-Ok "$($a.Name): 'Permitir que o computador desligue o dispositivo' = $acao"
        } catch { Write-Aviso "$($a.Name): driver não permite alterar o desligamento automático." }

        try {
            Set-NetAdapterPowerManagement -Name $a.Name -SelectiveSuspend $acao -NoRestart -ErrorAction Stop
            Write-Ok "$($a.Name): Suspensão seletiva = $acao"
        } catch { }

        # *EEE = Ethernet com Eficiência Energética (palavra-chave padrão NDIS)
        if (Get-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword '*EEE' -ErrorAction SilentlyContinue) {
            try {
                Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword '*EEE' -RegistryValue $eee -NoRestart -ErrorAction Stop
                Write-Ok "$($a.Name): Energy Efficient Ethernet = $acao"
            } catch { Write-Aviso "$($a.Name): não foi possível alterar o EEE." }
        }
    }
    Write-Aviso 'As alterações nas placas valem após reiniciar o PC (ou desativar/ativar a placa).'
    $Script:PrecisaReboot = $true
}

function Show-Rede {
    do {
        Write-Titulo 'N - Rede'
        foreach ($a in Get-AdaptadoresAtivos) {
            $s = (Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses -join ', '
            Write-Host ("  {0,-22} {1,-12} DNS: {2}" -f (Cortar $a.Name 22), $a.LinkSpeed, $s) -ForegroundColor DarkGray
        }
        Write-Host ''
        Write-Host '  [1] DNS Cloudflare (1.1.1.1 / 1.0.0.1) - geralmente o mais rápido'
        Write-Host '  [2] DNS Google     (8.8.8.8 / 8.8.4.4)'
        Write-Host '  [3] DNS Quad9      (9.9.9.9 / 149.112.112.112) - bloqueia sites maliciosos'
        Write-Host '  [4] DNS automático (do roteador/provedor)'
        Write-Host '  [5] Testar qual DNS é mais rápido aqui'
        Write-Host '  [6] Desativar economia de energia das placas de rede'
        Write-Host '  [7] Reativar economia de energia das placas de rede'
        Write-Host '  [Enter] Voltar'
        Write-Aviso 'Em rede de empresa com DNS interno (servidor local/AD), mantenha o automático.'
        $o = (Read-Host '  Escolha').Trim()
        switch ($o) {
            '1' { Set-Dns @('1.1.1.1', '1.0.0.1') 'Cloudflare' }
            '2' { Set-Dns @('8.8.8.8', '8.8.4.4') 'Google' }
            '3' { Set-Dns @('9.9.9.9', '149.112.112.112') 'Quad9' }
            '4' { Set-Dns $null 'automático (DHCP)' }
            '5' { Test-Dns }
            '6' { Set-EnergiaRede $true }
            '7' { Set-EnergiaRede $false }
        }
    } while ($o -ne '')
}

# ===============================================================
#  S - PROGRAMAS DE INICIALIZAÇÃO
#  Usa o mesmo mecanismo do Gerenciador de Tarefas (StartupApproved),
#  então tudo aparece lá e pode ser revertido por lá também.
# ===============================================================
function Get-ItensInicializacao {
    $apr = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    $fontes = @(
        @{ Origem = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';             Apr = "HKCU:\$apr\Run";           Escopo = 'Usuário';    Tipo = 'Reg' }
        @{ Origem = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';             Apr = "HKLM:\$apr\Run";           Escopo = 'Todos';      Tipo = 'Reg' }
        @{ Origem = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Apr = "HKLM:\$apr\Run32";         Escopo = 'Todos 32b';  Tipo = 'Reg' }
        @{ Origem = [Environment]::GetFolderPath('Startup');                           Apr = "HKCU:\$apr\StartupFolder"; Escopo = 'Pasta usr';  Tipo = 'Pasta' }
        @{ Origem = [Environment]::GetFolderPath('CommonStartup');                     Apr = "HKLM:\$apr\StartupFolder"; Escopo = 'Pasta all';  Tipo = 'Pasta' }
    )
    $ignorar = 'PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider'

    foreach ($f in $fontes) {
        if (-not $f.Origem -or -not (Test-Path $f.Origem)) { continue }
        $entradas = @()
        if ($f.Tipo -eq 'Reg') {
            $props = Get-ItemProperty $f.Origem
            if (-not $props) { continue }   # chave Run vazia gerava item fantasma sem nome
            $entradas = $props.PSObject.Properties | Where-Object { $_.Name -notin $ignorar } |
                        ForEach-Object { @{ Nome = $_.Name; Comando = [string]$_.Value } }
        } else {
            $entradas = Get-ChildItem $f.Origem -File -Force -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -ne 'desktop.ini' } |
                        ForEach-Object { @{ Nome = $_.Name; Comando = $_.FullName } }
        }
        foreach ($e in $entradas) {
            $v = $null
            $p = Get-ItemProperty -Path $f.Apr -Name $e.Nome -ErrorAction SilentlyContinue
            if ($p) { $v = $p.($e.Nome) }
            # Primeiro byte par = ativo (02/06), ímpar = desativado (03/07)
            $ativo = -not ($v -is [byte[]] -and $v.Length -gt 0 -and ($v[0] % 2) -eq 1)
            [pscustomobject]@{ Nome = $e.Nome; Comando = $e.Comando; Escopo = $f.Escopo; Aprovado = $f.Apr; Ativo = $ativo }
        }
    }
}

function Show-Inicializacao {
    do {
        Write-Titulo 'S - Programas que abrem com o Windows'
        $itens = @(Get-ItensInicializacao | Sort-Object @{ e = { -not $_.Ativo } }, Nome)
        if ($itens.Count -eq 0) { Write-Aviso 'Nenhum item encontrado.'; return }
        for ($i = 0; $i -lt $itens.Count; $i++) {
            $it  = $itens[$i]
            $st  = if ($it.Ativo) { 'ATIVO' } else { 'off  ' }
            $cor = if ($it.Ativo) { 'Green' } else { 'DarkGray' }
            Write-Host ("  [{0,2}] " -f ($i + 1)) -NoNewline
            Write-Host $st -ForegroundColor $cor -NoNewline
            Write-Host ("  {0,-28} {1,-9} {2}" -f (Cortar $it.Nome 28), $it.Escopo, (Cortar $it.Comando 50)) -ForegroundColor Gray
        }
        $ativos = @($itens | Where-Object Ativo).Count
        Write-Host ''
        Write-Host "  $ativos de $($itens.Count) ativos. Dica: mantenha drivers (áudio, touchpad, GPU) e antivírus." -ForegroundColor DarkGray
        $r = Read-Host '  Números para ATIVAR/DESATIVAR (ex: 2,5,7-9) ou Enter para voltar'
        if ([string]::IsNullOrWhiteSpace($r)) { return }

        foreach ($n in (Read-Indices $r $itens.Count)) {
            $it = $itens[$n - 1]
            if ($it.Ativo) {
                Set-Reg $it.Aprovado $it.Nome ([byte[]](3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) Binary
                Write-Ok "$($it.Nome) desativado."
            } else {
                Set-Reg $it.Aprovado $it.Nome ([byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) Binary
                Write-Ok "$($it.Nome) ativado."
            }
        }
    } while ($true)
}

# ===============================================================
#  U - DRIVERS USB-SERIAL (configuração de equipamentos)
# ===============================================================
function Show-DriversSerial {
    $chips = @(
        [pscustomobject]@{ Nome = 'Silicon Labs CP210x'; Infs = 'silabser.inf';               Vid = '10C4'; Url = 'https://www.silabs.com/developer-tools/usb-to-uart-bridge-vcp-drivers' }
        [pscustomobject]@{ Nome = 'WCH CH340/CH341';     Infs = 'ch341ser.inf';               Vid = '1A86'; Url = 'https://www.wch-ic.com/downloads/CH341SER_EXE.html' }
        [pscustomobject]@{ Nome = 'FTDI';                Infs = 'ftdiport.inf|ftdibus.inf';   Vid = '0403'; Url = 'https://ftdichip.com/drivers/vcp-drivers/' }
        [pscustomobject]@{ Nome = 'Prolific PL2303';     Infs = 'ser2pl.inf';                 Vid = '067B'; Url = $null }
    )

    do {
        Write-Titulo 'U - Drivers USB-serial'
        $lista = pnputil /enum-drivers 2>$null | Out-String

        Write-Host '  Drivers instalados no Windows:'
        for ($i = 0; $i -lt $chips.Count; $i++) {
            $c  = $chips[$i]
            $ok = $lista -match $c.Infs
            $st = if ($ok) { 'instalado    ' } else { 'NÃO instalado' }
            $cor = if ($ok) { 'Green' } else { 'Yellow' }
            Write-Host ("  [{0}] {1,-22}" -f ($i + 1), $c.Nome) -NoNewline
            Write-Host $st -ForegroundColor $cor
        }
        Write-Host '      Dispositivos USB CDC (porta serial padrão) usam o driver nativo do Windows.' -ForegroundColor DarkGray

        Write-Host ''
        Write-Host '  Portas COM conectadas agora:'
        $portas = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\(COM\d+\)' })
        if ($portas.Count -eq 0) { Write-Host '      nenhuma' -ForegroundColor DarkGray }
        foreach ($p in $portas) {
            $cor = if ($p.Status -eq 'OK') { 'Gray' } else { 'Red' }
            Write-Host ("      {0}  [{1}]" -f $p.Name, $p.Status) -ForegroundColor $cor
        }

        Write-Host ''
        Write-Host '  Dispositivos USB com erro/sem driver:'
        $erro = @(Get-PnpDevice -PresentOnly -Status ERROR, UNKNOWN -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'USB*' -or $_.InstanceId -like 'FTDIBUS*' })
        if ($erro.Count -eq 0) { Write-Host '      nenhum' -ForegroundColor DarkGray }
        foreach ($d in $erro) {
            $sug = ''
            foreach ($c in $chips) { if ($d.InstanceId -match "VID_$($c.Vid)") { $sug = " -> provável chip $($c.Nome)" } }
            Write-Host ("      {0}  ({1}){2}" -f $d.FriendlyName, (Cortar $d.InstanceId 40), $sug) -ForegroundColor Red
        }

        Write-Host ''
        Write-Host '  [1-3] Abrir site oficial do driver   [I] Instalar driver de uma pasta (.inf)'
        Write-Host '  [G] Gerenciador de Dispositivos       [Enter] Voltar'
        $o = (Read-Host '  Escolha').Trim().ToUpper()
        switch -Regex ($o) {
            '^[1-3]$' { Start-Process $chips[[int]$o - 1].Url }
            '^I$' {
                $pasta = (Read-Host '  Caminho da pasta extraída do driver').Trim('" ')
                if (Test-Path $pasta) {
                    pnputil /add-driver (Join-Path $pasta '*.inf') /subdirs /install
                    Write-Ok 'Comando executado. Reconecte o cabo do equipamento.'
                } else { Write-Erro 'Pasta não encontrada.' }
                Read-Host '  Enter para continuar' | Out-Null
            }
            '^G$' { Start-Process devmgmt.msc }
        }
    } while ($o -ne '')
}

# ===============================================================
#  H - RELATÓRIO DO PC (HTML)
# ===============================================================
function HtmlE($s) { return [System.Net.WebUtility]::HtmlEncode([string]$s) }
function HtmlLinha($k, $v) { return "<tr><th>$(HtmlE $k)</th><td>$(HtmlE $v)</td></tr>" }

function New-RelatorioPC {
    Write-Titulo 'H - Relatório do PC'
    Write-Host '  Coletando informações...' -ForegroundColor DarkGray

    $os   = Get-CimInstance Win32_OperatingSystem
    $cs   = Get-CimInstance Win32_ComputerSystem
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
    $mem  = @(Get-CimInstance Win32_PhysicalMemory)
    $gpus = @(Get-CimInstance Win32_VideoController)
    $mb   = Get-CimInstance Win32_BaseBoard
    $bios = Get-CimInstance Win32_BIOS
    $discos = @(Get-PhysicalDisk -ErrorAction SilentlyContinue | Sort-Object DeviceId)
    $vols   = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveLetter | Sort-Object DriveLetter)
    $plano  = (powercfg /getactivescheme | Out-String).Trim() -replace '^.*?\(', '('
    $inic   = @(Get-ItensInicializacao | Where-Object Ativo).Count
    $uptime = (Get-Date) - $os.LastBootUpTime

    $ramGB   = [math]::Round($cs.TotalPhysicalMemory / 1GB)
    $ramUso  = [math]::Round((1 - ($os.FreePhysicalMemory / $os.TotalVisibleMemorySize)) * 100)
    $threads = [int]$cpu.NumberOfLogicalProcessors

    # Disco do sistema
    $sysNum   = (Get-Partition -DriveLetter $env:SystemDrive.Substring(0, 1) -ErrorAction SilentlyContinue).DiskNumber
    $sysDisk  = $discos | Where-Object { [string]$_.DeviceId -eq [string]$sysNum } | Select-Object -First 1
    $tipoSys  = 'Desconhecido'
    if ($sysDisk) {
        if ([string]$sysDisk.BusType -eq 'NVMe')      { $tipoSys = 'NVMe' }
        elseif ([string]$sysDisk.MediaType -eq 'SSD') { $tipoSys = 'SSD SATA' }
        elseif ([string]$sysDisk.MediaType -eq 'HDD') { $tipoSys = 'HDD' }
    }

    # Classificação
    if ($ramGB -le 8 -or $tipoSys -eq 'HDD' -or $threads -le 4) { $tier = 'Low-end' }
    elseif ($ramGB -ge 32 -and $threads -ge 12 -and $tipoSys -eq 'NVMe') { $tier = 'High-end' }
    else { $tier = 'Mid-end' }

    # Alertas automáticos
    $alertas = New-Object System.Collections.Generic.List[string]
    if ($tipoSys -eq 'HDD') { $alertas.Add('O Windows está em HD mecânico. Trocar por SSD é a melhoria de maior impacto possível.') }
    if ($ramGB -lt 16)      { $alertas.Add("Apenas $ramGB GB de RAM. Para uso atual (navegador + sistemas web), 16 GB é o recomendado.") }
    if ($mem.Count -eq 1)   { $alertas.Add('Só 1 pente de memória: rodando em single channel. Um segundo pente igual pode aumentar bastante o desempenho, principalmente com vídeo integrado.') }
    foreach ($m in $mem) {
        if ($m.ConfiguredClockSpeed -and $m.Speed -and $m.ConfiguredClockSpeed -lt $m.Speed) {
            $alertas.Add("Memória rodando a $($m.ConfiguredClockSpeed) MT/s, abaixo dos $($m.Speed) MT/s do pente. Verifique XMP/EXPO na BIOS."); break
        }
    }
    $volSys = $vols | Where-Object { $_.DriveLetter -eq $env:SystemDrive.Substring(0, 1) }
    if ($volSys -and $volSys.Size -gt 0 -and ($volSys.SizeRemaining / $volSys.Size) -lt 0.15) {
        $alertas.Add('Disco do sistema com menos de 15% livre. Isso deixa o Windows e as atualizações lentos.')
    }
    if ($inic -gt 10)          { $alertas.Add("$inic programas abrem com o Windows. Use a opção [S] do otimizador para enxugar.") }
    if ($uptime.TotalDays -gt 7) { $alertas.Add("PC ligado há $([math]::Floor($uptime.TotalDays)) dias sem reiniciar. Reinicie para liberar memória e aplicar atualizações.") }
    if ($plano -match 'Equilibrado|Balanced|Economia|Power saver') { $alertas.Add('Plano de energia não está em desempenho. Use a opção [3].') }
    foreach ($g in $gpus) {
        if ($g.CurrentRefreshRate -and $g.MaxRefreshRate -and $g.CurrentRefreshRate -lt $g.MaxRefreshRate -and $g.MaxRefreshRate -le 400) {
            $alertas.Add("Vídeo $($g.Name) em $($g.CurrentRefreshRate) Hz, mas suporta até $($g.MaxRefreshRate) Hz. Confira em Configurações > Tela > Tela avançada.")
        }
    }

    # ---- Tabelas ----
    $tSis = (HtmlLinha 'Computador' $env:COMPUTERNAME) +
            (HtmlLinha 'Sistema' "$($os.Caption) (build $($Script:Build))") +
            (HtmlLinha 'Instalado em' $os.InstallDate.ToString('dd/MM/yyyy')) +
            (HtmlLinha 'Ligado há' ("{0} d {1} h {2} min" -f $uptime.Days, $uptime.Hours, $uptime.Minutes)) +
            (HtmlLinha 'Placa-mãe' "$($mb.Manufacturer) $($mb.Product)") +
            (HtmlLinha 'BIOS' "$($bios.SMBIOSBIOSVersion) ($(if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString('dd/MM/yyyy') }))") +
            (HtmlLinha 'Plano de energia' $plano) +
            (HtmlLinha 'Programas na inicialização' $inic)

    $tCpu = (HtmlLinha 'Processador' $cpu.Name.Trim()) +
            (HtmlLinha 'Núcleos / Threads' "$($cpu.NumberOfCores) / $threads") +
            (HtmlLinha 'Clock máximo' "$($cpu.MaxClockSpeed) MHz") +
            (HtmlLinha 'RAM total' "$ramGB GB ($ramUso% em uso agora)")

    $tMem = ''
    foreach ($m in $mem) {
        $tMem += "<tr><td>$(HtmlE $m.DeviceLocator)</td><td>$([math]::Round($m.Capacity / 1GB)) GB</td><td>$(HtmlE $m.ConfiguredClockSpeed) / $(HtmlE $m.Speed) MT/s</td><td>$(HtmlE $m.Manufacturer) $(HtmlE ([string]$m.PartNumber).Trim())</td></tr>"
    }

    $tGpu = ''
    foreach ($g in $gpus) {
        $res = if ($g.CurrentHorizontalResolution) { "$($g.CurrentHorizontalResolution)x$($g.CurrentVerticalResolution) @ $($g.CurrentRefreshRate) Hz" } else { '-' }
        $tGpu += "<tr><td>$(HtmlE $g.Name)</td><td>$(HtmlE $g.DriverVersion)</td><td>$(HtmlE $res)</td></tr>"
    }

    $tDisco = ''
    foreach ($d in $discos) {
        $r = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        $tipo = if ([string]$d.BusType -eq 'NVMe') { 'NVMe' } else { "$($d.MediaType) $($d.BusType)" }
        $temp = if ($r -and $r.Temperature) { "$($r.Temperature) °C" } else { '-' }
        $desg = if ($r -and $null -ne $r.Wear) { "$($r.Wear)%" } else { '-' }
        $horas = if ($r -and $r.PowerOnHours) { "$($r.PowerOnHours) h" } else { '-' }
        $saude = [string]$d.HealthStatus
        $cls = if ($saude -eq 'Healthy') { 'ok' } else { 'bad' }
        if ($saude -ne 'Healthy') { $alertas.Add("Disco $($d.FriendlyName) com status de saúde '$saude'. Faça backup e verifique com o CrystalDiskInfo.") }
        if ($r -and $r.Wear -ge 80) { $alertas.Add("SSD $($d.FriendlyName) com $($r.Wear)% de desgaste. Planeje a troca.") }
        $tDisco += "<tr><td>$(HtmlE $d.FriendlyName)</td><td>$(HtmlE $tipo)</td><td>$([math]::Round($d.Size / 1GB)) GB</td><td class='$cls'>$(HtmlE $saude)</td><td>$(HtmlE $temp)</td><td>$(HtmlE $desg)</td><td>$(HtmlE $horas)</td></tr>"
    }

    $tVol = ''
    foreach ($v in $vols) {
        if (-not $v.Size) { continue }
        $livre = [math]::Round(($v.SizeRemaining / $v.Size) * 100)
        $cls = if ($livre -lt 15) { 'bad' } elseif ($livre -lt 25) { 'warn' } else { 'ok' }
        $tVol += "<tr><td>$($v.DriveLetter):</td><td>$(HtmlE $v.FileSystemLabel)</td><td>$([math]::Round($v.Size / 1GB)) GB</td><td>$([math]::Round($v.SizeRemaining / 1GB)) GB</td><td class='$cls'>$livre%</td></tr>"
    }

    $recs = @{
        'Low-end'  = @(
            'SSD no lugar do HD (ganho de 3 a 10x no tempo de abertura)',
            'Subir para 16 GB em dual channel (dois pentes iguais)',
            'Efeitos visuais em "Melhor desempenho" e opções [5] e [S] do otimizador',
            'Navegador com economia de memória/abas em suspensão ativa',
            'Remover programas do fabricante (bloatware) e antivírus extras: manter só o Defender'
        )
        'Mid-end'  = @(
            'Ativar XMP/EXPO na BIOS e confirmar dual channel',
            'Atualizar BIOS, driver de chipset e driver de vídeo pelo site do fabricante',
            'Ativar Resizable BAR (se placa e GPU suportarem)',
            'Windows em SSD NVMe, deixando HD só para arquivos',
            'Limpeza interna e troca de pasta térmica se a CPU passar de 85 °C'
        )
        'High-end' = @(
            'XMP/EXPO, Resizable BAR e BIOS atualizada',
            'Monitor na taxa máxima, com G-Sync/FreeSync ativo e cabo na placa de vídeo',
            'Desativar overlays (Discord, Steam, GeForce/Adrenalin) em jogos competitivos',
            'Modo de baixa latência no painel da GPU (NVIDIA Reflex/AMD Anti-Lag nos jogos que suportam)',
            'Opcional: desligar Integridade de Memória (VBS) ganha FPS, mas reduz segurança'
        )
    }
    $liRecs = ($recs[$tier] | ForEach-Object { "<li>$(HtmlE $_)</li>" }) -join ''
    $liAlert = if ($alertas.Count) { ($alertas | ForEach-Object { "<li>$(HtmlE $_)</li>" }) -join '' } else { '<li>Nenhum problema detectado.</li>' }
    $data = Get-Date -Format 'dd/MM/yyyy HH:mm'

    $html = @"
<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Relatório do PC - $(HtmlE $env:COMPUTERNAME)</title>
<style>
:root{--bg:#f6f7f9;--card:#fff;--tx:#1d2330;--mut:#667085;--ln:#e4e7ec;--ac:#0f6fde;--ok:#12825a;--warn:#b26b00;--bad:#c4321c}
@media (prefers-color-scheme:dark){:root{--bg:#0f1115;--card:#181b21;--tx:#e6e8ec;--mut:#98a2b3;--ln:#2a2f38;--ac:#5aa2ff;--ok:#3ccf8e;--warn:#f0b13d;--bad:#ff6b57}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--tx);font:15px/1.5 "Segoe UI",system-ui,sans-serif}
.wrap{max-width:1000px;margin:0 auto;padding:24px 16px}
h1{margin:0;font-size:24px}.sub{color:var(--mut);margin:4px 0 20px}
.tier{display:inline-block;padding:4px 12px;border-radius:99px;background:var(--ac);color:#fff;font-weight:600;margin-left:8px;font-size:14px}
.card{background:var(--card);border:1px solid var(--ln);border-radius:12px;padding:16px 18px;margin-bottom:16px;overflow-x:auto}
h2{font-size:16px;margin:0 0 10px}table{width:100%;border-collapse:collapse}
th,td{text-align:left;padding:7px 8px;border-bottom:1px solid var(--ln);vertical-align:top}
th{color:var(--mut);font-weight:500;width:32%}thead th{width:auto}
.ok{color:var(--ok);font-weight:600}.warn{color:var(--warn);font-weight:600}.bad{color:var(--bad);font-weight:600}
ul{margin:0;padding-left:20px}li{margin:4px 0}.alert li::marker{color:var(--warn)}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:16px}@media (max-width:760px){.grid{grid-template-columns:1fr}}
.foot{color:var(--mut);font-size:13px;text-align:center;margin-top:8px}
</style></head><body><div class="wrap">
<h1>$(HtmlE $env:COMPUTERNAME) <span class="tier">$tier</span></h1>
<p class="sub">Gerado em $data pelo Otimizador Vinicius v$($Script:Versao). A classificação considera CPU, RAM e disco (não avalia a placa de vídeo).</p>
<div class="card alert"><h2>Pontos de atenção</h2><ul>$liAlert</ul></div>
<div class="card"><h2>Recomendações para $tier</h2><ul>$liRecs</ul></div>
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

    $arq = Join-Path $Script:BaseDir ("Relatorio_PC_" + (Get-Date -Format 'yyyy-MM-dd_HH-mm') + ".html")
    Set-Content -Path $arq -Value $html -Encoding UTF8
    Write-Ok "Relatório salvo em: $arq"
    Write-Ok "Classificação: $tier  |  $($alertas.Count) ponto(s) de atenção."
    Start-Process $arq
}

# ===============================================================
#  W - PROGRAMAS (winget)
# ===============================================================
function Get-ListaWinget {
    $arq = Join-Path $Script:ScriptDir 'winget-lista.txt'
    if (-not (Test-Path $arq)) { return $Script:ListaWinget }
    $lista = [ordered]@{}
    foreach ($l in Get-Content $arq -Encoding UTF8) {
        $l = $l.Trim()
        if (-not $l -or $l.StartsWith('#')) { continue }
        $p = $l -split ';', 2
        $lista[$p[0].Trim()] = if ($p.Count -gt 1) { $p[1].Trim() } else { $p[0].Trim() }
    }
    Write-Host '  (usando winget-lista.txt)' -ForegroundColor DarkGray
    return $lista
}

function Show-Winget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Erro 'winget não encontrado. Instale/atualize o "Instalador de Aplicativo" pela Microsoft Store.'
        return
    }
    $acordos = @('--accept-source-agreements', '--accept-package-agreements')
    $arqExp  = Join-Path $Script:BaseDir 'winget-programas.json'

    do {
        Write-Titulo 'W - Programas (winget)'
        Write-Host '  [1] Instalar programas da lista'
        Write-Host '  [2] Atualizar TODOS os programas instalados'
        Write-Host '  [3] Exportar lista dos programas deste PC (para usar após formatar)'
        Write-Host '  [4] Importar lista exportada (reinstala tudo)'
        Write-Host '  [Enter] Voltar'
        $o = (Read-Host '  Escolha').Trim()
        switch ($o) {
            '1' {
                $lista = Get-ListaWinget
                $ids = @($lista.Keys)
                for ($i = 0; $i -lt $ids.Count; $i++) {
                    Write-Host ("  [{0,2}] {1,-30} {2}" -f ($i + 1), $lista[$ids[$i]], $ids[$i])
                }
                $r = Read-Host '  Números (ex: 1,3,7-10), T para todos, Enter cancela'
                if ([string]::IsNullOrWhiteSpace($r)) { break }
                foreach ($n in (Read-Indices $r $ids.Count)) {
                    $id = $ids[$n - 1]
                    Write-Host "  Instalando $($lista[$id])..." -ForegroundColor Cyan
                    winget install --id $id -e --silent @acordos
                    if ($LASTEXITCODE -eq 0) { Write-Ok $lista[$id] }
                    else { Write-Aviso "$($lista[$id]): código $LASTEXITCODE (pode já estar instalado ou o ID mudou)" }
                }
            }
            '2' { winget upgrade --all --silent @acordos }
            '3' {
                winget export -o $arqExp @('--accept-source-agreements')
                if (Test-Path $arqExp) { Write-Ok "Lista salva em: $arqExp" }
            }
            '4' {
                $caminho = (Read-Host "  Arquivo JSON (Enter = $arqExp)").Trim('" ')
                if (-not $caminho) { $caminho = $arqExp }
                if (Test-Path $caminho) { winget import -i $caminho --ignore-unavailable @acordos }
                else { Write-Erro 'Arquivo não encontrado.' }
            }
        }
    } while ($o -ne '')
}

# ===============================================================
#  R - RESTAURAR BACKUP
# ===============================================================
function Restore-Backup {
    Write-Titulo 'Restaurar backup'
    $pastas = @(Get-ChildItem $Script:BackupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    if ($pastas.Count -eq 0) { Write-Aviso 'Nenhum backup encontrado.'; return }

    for ($i = 0; $i -lt $pastas.Count; $i++) {
        $qtd = @(Get-ChildItem $pastas[$i].FullName -Filter *.reg).Count
        $dns = if (Test-Path (Join-Path $pastas[$i].FullName 'dns.json')) { ' + DNS' } else { '' }
        Write-Host ("  [{0}] {1}  ({2} chaves{3})" -f ($i + 1), $pastas[$i].Name, $qtd, $dns)
    }
    $esc = Read-Host '  Número do backup (Enter cancela)'
    if (-not ($esc -match '^\d+$') -or [int]$esc -lt 1 -or [int]$esc -gt $pastas.Count) { return }

    $alvo = $pastas[[int]$esc - 1].FullName
    foreach ($f in Get-ChildItem $alvo -Filter *.reg) {
        reg.exe import $f.FullName 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Ok $f.Name } else { Write-Erro $f.Name }
    }
    Restore-Dns (Join-Path $alvo 'dns.json')

    if (Confirmar 'Voltar também para o plano de energia "Equilibrado"?') {
        powercfg -setactive SCHEME_BALANCED | Out-Null
        Write-Ok 'Plano Equilibrado ativo.'
    }
    Write-Aviso 'Valores que não existiam antes não são apagados pelo .reg.'
    Write-Aviso 'Para reverter 100%, use o ponto de restauração (Win+R > rstrui).'
    $Script:PrecisaLogoff = $true
    $Script:PrecisaReboot = $true
}

# ===============================================================
#  MENU
# ===============================================================
function Show-Menu {
    Clear-Host
    $so = if ($Script:IsWin11) { 'Windows 11' } else { 'Windows 10' }
    Write-Host '=================================================' -ForegroundColor DarkCyan
    Write-Host "   OTIMIZADOR VINICIUS v$($Script:Versao)   |   $so (build $($Script:Build))" -ForegroundColor White
    Write-Host '=================================================' -ForegroundColor DarkCyan
    Write-Host '  OTIMIZAÇÕES' -ForegroundColor DarkCyan
    Write-Host '  [1] Mouse - precisão 1:1, sem aceleração'
    Write-Host '  [2] Teclado - aderência, filtro e Alt+Shift'
    Write-Host '  [3] Energia - desempenho máximo'
    Write-Host '  [4] Modo Game - Game Mode, DVR off, HAGS, prioridade'
    Write-Host '  [5] Interface - menus rápidos, sem animações'
    Write-Host '  [6] Privacidade - anúncios, Bing, sugestões'
    Write-Host '  [7] Limpeza - temporários, DNS, lixeira'
    Write-Host '  [8] Inicialização rápida / hibernação OFF'
    Write-Host '  [9] Menu de contexto clássico (Win 11)'
    Write-Host '  FERRAMENTAS' -ForegroundColor DarkCyan
    Write-Host '  [N] Rede - DNS e energia da placa de rede'
    Write-Host '  [S] Programas que abrem com o Windows'
    Write-Host '  [U] Drivers USB-serial (CP210x, CH340, FTDI...)'
    Write-Host '  [H] Relatório do PC (HTML) + classificação'
    Write-Host '  [W] Instalar/atualizar programas (winget)'
    Write-Host '  -----------------------------------------------'
    Write-Host '  [A] Aplicar recomendados (1 a 7)' -ForegroundColor Green
    Write-Host '  [R] Restaurar backup'              -ForegroundColor Yellow
    Write-Host '  [D] Desfazer menu clássico (Win 11)'
    Write-Host '  [0] Sair'
    Write-Host ''
    Write-Host "  Backups, relatórios e log: $($Script:BaseDir)" -ForegroundColor DarkGray
    Write-Host ''
}

do {
    Show-Menu
    $op = (Read-Host '  Escolha').Trim().ToUpper()
    $pausa = $true
    switch ($op) {
        '1' { New-PontoRestauracao; Optimize-Mouse }
        '2' { New-PontoRestauracao; Disable-AtalhosTeclado }
        '3' { New-PontoRestauracao; Set-EnergiaMaxima }
        '4' { New-PontoRestauracao; Set-ModoGame }
        '5' { New-PontoRestauracao; Optimize-Interface }
        '6' { New-PontoRestauracao; Disable-Anuncios }
        '7' { Invoke-Limpeza }
        '8' { New-PontoRestauracao; Disable-InicializacaoRapida }
        '9' { New-PontoRestauracao; Set-MenuClassico }
        'N' { Show-Rede; $pausa = $false }
        'S' { Show-Inicializacao; $pausa = $false }
        'U' { Show-DriversSerial; $pausa = $false }
        'H' { New-RelatorioPC }
        'W' { Show-Winget; $pausa = $false }
        'A' {
            if (Confirmar 'Aplicar as opções 1 a 7?') {
                New-PontoRestauracao
                Optimize-Mouse; Disable-AtalhosTeclado; Set-EnergiaMaxima; Set-ModoGame
                Optimize-Interface; Disable-Anuncios; Invoke-Limpeza
            }
        }
        'R' { Restore-Backup }
        'D' { Undo-MenuClassico }
        '0' { $pausa = $false }
        default { Write-Aviso 'Opção inválida.' }
    }
    if ($pausa) { Write-Host ''; Read-Host '  Enter para voltar ao menu' | Out-Null }
} while ($op -ne '0')

# ---------------------------------------------------------------
#  Encerramento
# ---------------------------------------------------------------
Write-Host ''
if ($Script:PrecisaReboot) {
    Write-Aviso 'Reinicie o computador para aplicar todas as alterações.'
} elseif ($Script:PrecisaLogoff) {
    Write-Aviso 'Faça logoff (ou reinicie) para aplicar todas as alterações.'
}
Stop-Transcript | Out-Null
Start-Sleep -Seconds 2
