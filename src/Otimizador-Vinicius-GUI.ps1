#Requires -Version 5.1
<#
    ===============================================================
     OTIMIZADOR VINICIUS  v2.0  -  interface gráfica (WPF)
    ---------------------------------------------------------------
     Arquivos:
       nucleo.ps1        motor: detectar / aplicar / desfazer / simular
       ferramentas.ps1   relatório, rede, inicialização, drivers, reparo
       catalogo\*.ps1    um arquivo por categoria de ajustes
       ui\Janela.xaml    layout da janela
       ui\Modelos.cs     modelos de tela (avisam a interface das mudanças)

     Operações demoradas rodam em segundo plano (runspace) e mandam
     eventos por uma fila; um timer na interface lê a fila. Assim a
     janela nunca trava.

     Modo silencioso (sem janela, para padronizar vários PCs):
       -Perfil <basico|trabalho|gamer|leve|arquivo.json>
                         aplica o perfil e mostra o resumo no console
       -SemPausa         não espera Enter no final (scripts e tarefas)
       -Manutencao <config.json>
                         manutenção agendada (usado pela tarefa do Windows)
       -Inventario <pasta>
                         grava <NOME-DO-PC>.json na pasta (não pede administrador)

     Parâmetros de desenvolvimento:
       -SemElevar        abre sem administrador (só visualização)
       -Captura <pasta>  salva imagens das telas e fecha (teste visual)
    ===============================================================
#>
param(
    [switch]$SemElevar,
    [string]$Captura,
    [string]$Perfil,
    [switch]$SemPausa,
    [string]$Manutencao,
    [string]$Inventario
)

$ErrorActionPreference = 'Stop'
$Script:SrcDir = $PSScriptRoot
$Script:Silencioso = [bool]($Perfil -or $Manutencao -or $Inventario)

# ---------------------------------------------------------------
#  Elevação (repassa os parâmetros do modo silencioso)
# ---------------------------------------------------------------
$ehAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $ehAdmin -and -not $SemElevar -and -not $Captura -and -not $Inventario) {
    $argsElev = "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`""
    $estilo = 'Hidden'
    if ($Perfil) { $argsElev += " -Perfil `"$Perfil`""; $estilo = 'Normal' }
    if ($SemPausa) { $argsElev += ' -SemPausa' }
    if ($Manutencao) { $argsElev += " -Manutencao `"$Manutencao`"" }
    if (-not $Script:Silencioso) { $argsElev = "-WindowStyle Hidden $argsElev" }
    try {
        Start-Process powershell.exe -Verb RunAs -WindowStyle $estilo -ArgumentList $argsElev
    } catch {
        if ($Script:Silencioso) { Write-Host 'É preciso permissão de administrador.' -ForegroundColor Red; exit 1 }
        Add-Type -AssemblyName PresentationFramework
        [void][Windows.MessageBox]::Show('O otimizador precisa de permissão de administrador para alterar o sistema. Abra de novo e clique em "Sim".', 'Otimizador Vinicius', 'OK', 'Warning')
    }
    exit
}

# ---------------------------------------------------------------
#  Modo silencioso: sem janela
# ---------------------------------------------------------------
if ($Script:Silencioso) {
    $codigo = 0
    try {
        . (Join-Path $Script:SrcDir 'nucleo.ps1')
        . (Join-Path $Script:SrcDir 'ferramentas.ps1')
        . (Join-Path $Script:SrcDir 'diagnostico.ps1')
        . (Join-Path $Script:SrcDir 'seguranca.ps1')
        . (Join-Path $Script:SrcDir 'manutencao.ps1')
        . (Join-Path $Script:SrcDir 'analise.ps1')
        . (Join-Path $Script:SrcDir 'inventario.ps1')
        . (Join-Path $Script:SrcDir 'segundoplano.ps1')
        $sidAlvo = if ($ehAdmin) { Get-SidUsuarioSessao } else { $null }
        Initialize-Otz -SrcDir $Script:SrcDir -SidAlvo $sidAlvo
        if ($Inventario) {
            Write-Host "Otimizador Vinicius - inventário de $env:COMPUTERNAME" -ForegroundColor Cyan
            $arq = Save-InventarioPC $Inventario
            Write-Host "Salvo em $arq" -ForegroundColor Green
        } elseif ($Manutencao) {
            $r = Invoke-ManutencaoAgendada $Manutencao
            if ($r.Erros) { $codigo = 1 }
        } else {
            $host.UI.RawUI.WindowTitle = "Otimizador Vinicius - aplicando perfil $Perfil"
            Write-Host "Otimizador Vinicius v$($Otz.Versao) - modo silencioso" -ForegroundColor Cyan
            Write-Host "Perfil: $Perfil" -ForegroundColor Cyan
            Write-Host ''
            $r = Invoke-PerfilSilencioso $Perfil
            foreach ($x in $r.Resultados) {
                $cor = switch ($x.Status) { 'ok' { 'Green' } 'erro' { 'Red' } default { 'Yellow' } }
                $marca = switch ($x.Status) { 'ok' { '[OK]  ' } 'erro' { '[ERRO]' } default { '[AVISO]' } }
                Write-Host ("  {0} {1}" -f $marca, $x.Nome) -ForegroundColor $cor
                if ($x.Status -ne 'ok' -and $x.Mensagem) { Write-Host "         $($x.Mensagem)" -ForegroundColor DarkGray }
            }
            foreach ($p in $r.Pulados) { Write-Host "  [PULADO] $p" -ForegroundColor DarkGray }
            $ok = @($r.Resultados | Where-Object Status -eq 'ok').Count
            $er = @($r.Resultados | Where-Object Status -eq 'erro').Count
            Write-Host ''
            Write-Host "Resumo: $ok aplicado(s), $er erro(s), $($r.Pulados.Count) pulado(s). Log: $($Otz.ArqLog)" -ForegroundColor Cyan
            if (@($r.Resultados | Where-Object { $_.Status -eq 'ok' -and $_.Reinicio -eq 'reiniciar' }).Count) { Write-Host 'Reinicie o PC para concluir.' -ForegroundColor Yellow }
            if ($er) { $codigo = 1 }
        }
    } catch {
        Write-Host "Falhou: $($_.Exception.Message)" -ForegroundColor Red
        try { Write-Log "Modo silencioso falhou: $($_.Exception.Message)" } catch { }
        $codigo = 2
    }
    if ($Perfil -and -not $SemPausa) { Write-Host ''; [void](Read-Host 'Pressione Enter para fechar') }
    exit $codigo
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# Esconde o console que ficou atrás da janela
if (-not $Captura) {
    if (-not ('OtzNativo.Console' -as [type])) {
        Add-Type -Namespace 'OtzNativo' -Name 'Console' -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
    }
    $c = [OtzNativo.Console]::GetConsoleWindow()
    if ($c -ne [IntPtr]::Zero) { [void][OtzNativo.Console]::ShowWindow($c, 0) }
}

try {
    . (Join-Path $Script:SrcDir 'nucleo.ps1')
    . (Join-Path $Script:SrcDir 'ferramentas.ps1')
    . (Join-Path $Script:SrcDir 'diagnostico.ps1')
    . (Join-Path $Script:SrcDir 'seguranca.ps1')
    . (Join-Path $Script:SrcDir 'manutencao.ps1')
    . (Join-Path $Script:SrcDir 'analise.ps1')
    . (Join-Path $Script:SrcDir 'programas.ps1')
    . (Join-Path $Script:SrcDir 'inventario.ps1')
    . (Join-Path $Script:SrcDir 'segundoplano.ps1')
    . (Join-Path $Script:SrcDir 'desinstalar.ps1')
    . (Join-Path $Script:SrcDir 'glossario.ps1')
    $sidAlvo = if ($ehAdmin) { Get-SidUsuarioSessao } else { $null }
    Initialize-Otz -SrcDir $Script:SrcDir -SidAlvo $sidAlvo
    Write-Log "===== Otimizador v$($Otz.Versao) aberto (admin: $ehAdmin) ====="

    if (-not ('Otz.Ajuste' -as [type])) {
        Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $Script:SrcDir 'ui\Modelos.cs'), [Text.Encoding]::UTF8))
    }
    $xaml = [IO.File]::ReadAllText((Join-Path $Script:SrcDir 'ui\Janela.xaml'), [Text.Encoding]::UTF8)
    $Script:Win = [Windows.Markup.XamlReader]::Parse($xaml)
} catch {
    $msg = "Falha ao abrir o otimizador:`n`n$($_.Exception.Message)"
    try { Write-Log $msg } catch { }
    [void][Windows.MessageBox]::Show($msg, 'Otimizador Vinicius', 'OK', 'Error')
    exit 1
}
$ErrorActionPreference = 'Continue'

# Todos os elementos com x:Name ficam em $UI
$Script:UI = @{}
foreach ($m in [regex]::Matches($xaml, 'x:Name="(\w+)"')) {
    $el = $Win.FindName($m.Groups[1].Value)
    if ($el) { $UI[$m.Groups[1].Value] = $el }
}

# Estado da janela
$Script:S = @{
    Ajustes     = New-Object 'System.Collections.ObjectModel.ObservableCollection[Otz.Ajuste]'
    PorId       = @{}
    Catalogo    = @()
    Perfil      = 'personalizado'
    Tarefas     = New-Object System.Collections.ArrayList
    Executando  = $false
    PontoCriado = $false
    Info        = $null
    AnelAtual   = 0.0
    FerCarregado = @{}
    Tema        = 'escuro'
    ArqPrefs    = Join-Path $Otz.Dados 'preferencias.json'
}

function G([int]$Codigo) { return [string][char]$Codigo }

# ===============================================================
#  Tema
# ===============================================================
$Script:Paletas = @{
    escuro = @{
        Fundo = '#0E1117'; Palco = '#131720'; Superficie = '#1A1F29'; Superficie2 = '#232A36'; SuperficieHover = '#2B3341'; Borda = '#2A3140'
        Texto = '#E8ECF3'; TextoSec = '#9AA4B5'; TextoFraco = '#5D6778'; Acento = '#2DD4BF'; AcentoSuave = '#262DD4BF'; SobreAcento = '#04211D'
        Ok = '#34D399'; OkSuave = '#2634D399'; Aviso = '#FBBF24'; AvisoSuave = '#26FBBF24'; Erro = '#F87171'; ErroSuave = '#26F87171'
        Info = '#60A5FA'; InfoSuave = '#2660A5FA'; Scrim = '#A6000000'; Serie1 = '#3987E5'; Serie2 = '#D95926'; Grade = '#2A3140'
    }
    claro = @{
        Fundo = '#E9EDF3'; Palco = '#F5F7FA'; Superficie = '#FFFFFF'; Superficie2 = '#EEF1F6'; SuperficieHover = '#E3E8EF'; Borda = '#DCE2EA'
        Texto = '#111827'; TextoSec = '#5B6474'; TextoFraco = '#9AA3B2'; Acento = '#0D9488'; AcentoSuave = '#1F0D9488'; SobreAcento = '#FFFFFF'
        Ok = '#059669'; OkSuave = '#1F059669'; Aviso = '#B45309'; AvisoSuave = '#1FB45309'; Erro = '#DC2626'; ErroSuave = '#1FDC2626'
        Info = '#2563EB'; InfoSuave = '#1F2563EB'; Scrim = '#66000000'; Serie1 = '#2A78D6'; Serie2 = '#EB6834'; Grade = '#E3E8EF'
    }
}

function Set-Tema([string]$Nome) {
    foreach ($par in $Paletas[$Nome].GetEnumerator()) {
        $b = [Windows.Media.SolidColorBrush]::new([Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($par.Value))
        $b.Freeze()
        $Win.Resources[$par.Key] = $b
    }
    $S.Tema = $Nome
}

function Save-Preferencias {
    try { [IO.File]::WriteAllText($S.ArqPrefs, (@{ Tema = $S.Tema; Avancado = [bool]$S.ModoAvancado; PastaFrota = [string]$S.PastaFrota } | ConvertTo-Json), (New-Object Text.UTF8Encoding $false)) } catch { }
}

function Get-TemaInicial {
    try {
        if (Test-Path $S.ArqPrefs) {
            $p = [IO.File]::ReadAllText($S.ArqPrefs) | ConvertFrom-Json
            if ($p.Tema -in 'claro', 'escuro') { return $p.Tema }
        }
    } catch { }
    $v = Read-RegValor 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme'
    if ($v.Existe -and [int]$v.Valor -eq 1) { return 'claro' }
    return 'escuro'
}

# ===============================================================
#  Animações
# ===============================================================
function Start-Animacao($Alvo, $Propriedade, $De, $Para, [int]$Ms = 250, [scriptblock]$AoConcluir) {
    $a = New-Object Windows.Media.Animation.DoubleAnimation
    if ($null -ne $De) { $a.From = [double]$De }
    $a.To = [double]$Para
    $a.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds($Ms))
    $e = New-Object Windows.Media.Animation.CubicEase
    $e.EasingMode = 'EaseOut'
    $a.EasingFunction = $e
    if ($AoConcluir) { $a.Add_Completed($AoConcluir) }
    $Alvo.BeginAnimation($Propriedade, $a)
}

function Start-Giro($Transformacao) {
    $a = New-Object Windows.Media.Animation.DoubleAnimation 0, 360, (New-Object Windows.Duration ([TimeSpan]::FromSeconds(1)))
    $a.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
    $Transformacao.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $a)
}

function Stop-Giro($Transformacao) {
    $Transformacao.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $null)
    $Transformacao.Angle = 0
}

function Show-Entrada($Elemento) {
    $Elemento.Visibility = 'Visible'
    Start-Animacao $Elemento ([Windows.UIElement]::OpacityProperty) 0 1 260
    if ($Elemento.RenderTransform -is [Windows.Media.TranslateTransform]) {
        Start-Animacao $Elemento.RenderTransform ([Windows.Media.TranslateTransform]::YProperty) 14 0 320
    }
}

function Set-Referencia($Elemento, $Propriedade, [string]$Chave) {
    $Elemento.SetResourceReference($Propriedade, $Chave)
}

# ===============================================================
#  Notificação (toast) e diálogo
# ===============================================================
$S.TimerToast = New-Object Windows.Threading.DispatcherTimer
$S.TimerToast.Add_Tick({
    $S.TimerToast.Stop()
    Start-Animacao $UI.Toast ([Windows.UIElement]::OpacityProperty) $null 0 220
    Start-Animacao $UI.ToastT ([Windows.Media.TranslateTransform]::YProperty) $null 20 220
})

function Show-Toast([string]$Texto, [string]$Tipo = 'ok') {
    $mapa = @{ ok = @(0xE73E, 'Ok'); erro = @(0xE783, 'Erro'); aviso = @(0xE7BA, 'Aviso'); info = @(0xE946, 'Info') }
    $m = $mapa[$Tipo]
    $UI.ToastIcone.Text = G $m[0]
    Set-Referencia $UI.ToastIcone ([Windows.Controls.TextBlock]::ForegroundProperty) $m[1]
    $UI.ToastTexto.Text = $Texto
    Start-Animacao $UI.Toast ([Windows.UIElement]::OpacityProperty) $null 1 220
    Start-Animacao $UI.ToastT ([Windows.Media.TranslateTransform]::YProperty) 30 0 300
    $S.TimerToast.Stop()
    $S.TimerToast.Interval = [TimeSpan]::FromMilliseconds([math]::Min(8000, 2800 + $Texto.Length * 35))
    $S.TimerToast.Start()
}

# Converte qualquer coleção em Otz.Linha[] sem passar por @($lista): no PS 5.1,
# "[T[]]@($lista)" com List[object] dá "Os tipos de argumento não correspondem"
function ConvertTo-Linhas($Itens) {
    $l = New-Object 'System.Collections.Generic.List[Otz.Linha]'
    foreach ($i in $Itens) { if ($i) { $l.Add($i) } }
    return , $l.ToArray()
}

function New-Linha {
    param([string]$Titulo, [string]$Texto = '', [string]$Nivel = 'info', [string]$Extra = '', [string]$Tag = '', [string]$Icone = '', [double]$Valor = 0)
    $l = [Otz.Linha]::new()
    $l.Titulo = $Titulo; $l.Texto = $Texto; $l.Nivel = $Nivel; $l.Extra = $Extra; $l.Tag = $Tag; $l.Icone = $Icone; $l.Valor = $Valor
    return $l
}

function Show-Dialogo {
    param(
        [string]$Titulo, [string]$Texto, $Linhas = @(), [string]$TextoOk = 'Confirmar',
        [ValidateSet('normal', 'perigo', 'info')][string]$Tipo = 'normal',
        [scriptblock]$Acao, $Dados = $null, [switch]$SoOk
    )
    $UI.TxtDlgTitulo.Text = $Titulo
    $UI.TxtDlgTexto.Text = $Texto
    $UI.TxtDlgTexto.Visibility = if ($Texto) { 'Visible' } else { 'Collapsed' }
    $UI.ListaDlg.ItemsSource = ConvertTo-Linhas $Linhas
    $UI.TxtDlgOk.Text = $TextoOk
    $UI.BtnDlgCancelar.Visibility = if ($SoOk) { 'Collapsed' } else { 'Visible' }
    switch ($Tipo) {
        'perigo' { $UI.BtnDlgOk.Style = $Win.FindResource('BtnPerigo'); $UI.DlgIcone.Text = G 0xE7BA; $cor = 'Aviso'; $fundo = 'AvisoSuave' }
        'info'   { $UI.BtnDlgOk.Style = $Win.FindResource('BtnPrimario'); $UI.DlgIcone.Text = G 0xE946; $cor = 'Info'; $fundo = 'InfoSuave' }
        default  { $UI.BtnDlgOk.Style = $Win.FindResource('BtnPrimario'); $UI.DlgIcone.Text = G 0xE768; $cor = 'Acento'; $fundo = 'AcentoSuave' }
    }
    Set-Referencia $UI.DlgIcone ([Windows.Controls.TextBlock]::ForegroundProperty) $cor
    Set-Referencia $UI.DlgCirculo ([Windows.Controls.Border]::BackgroundProperty) $fundo
    $S.DlgAcao = $Acao
    $S.DlgDados = $Dados
    Show-Entrada $UI.Dialogo
    [void]$UI.BtnDlgOk.Focus()
}

function Hide-Dialogo {
    Start-Animacao $UI.Dialogo ([Windows.UIElement]::OpacityProperty) $null 0 150 { $UI.Dialogo.Visibility = 'Collapsed' }
}

$UI.BtnDlgCancelar.Add_Click({ Hide-Dialogo })
$UI.BtnDlgOk.Add_Click({
    $acao = $S.DlgAcao; $dados = $S.DlgDados
    Hide-Dialogo
    if ($acao) { & $acao $dados }
})

# ===============================================================
#  Tarefas em segundo plano
# ===============================================================
$S.Timer = New-Object Windows.Threading.DispatcherTimer
$S.Timer.Interval = [TimeSpan]::FromMilliseconds(90)
$S.Timer.Add_Tick({ Update-Tarefas })

function Start-Tarefa {
    param(
        [Parameter(Mandatory)][string]$Nome,
        [Parameter(Mandatory)][string]$Script,
        [hashtable]$Parametros = @{},
        [scriptblock]$AoEvento,
        [scriptblock]$AoTerminar
    )
    $fila = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('Fila', $fila)
    $rs.SessionStateProxy.SetVariable('SrcDir', $Script:SrcDir)
    $rs.SessionStateProxy.SetVariable('SidAlvo', [string]$Otz.SidAlvo)
    $rs.SessionStateProxy.SetVariable('Parametros', $Parametros)
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $codigo = @"
`$ErrorActionPreference = 'Continue'
. (Join-Path `$SrcDir 'nucleo.ps1')
. (Join-Path `$SrcDir 'ferramentas.ps1')
. (Join-Path `$SrcDir 'diagnostico.ps1')
. (Join-Path `$SrcDir 'seguranca.ps1')
. (Join-Path `$SrcDir 'analise.ps1')
. (Join-Path `$SrcDir 'programas.ps1')
. (Join-Path `$SrcDir 'inventario.ps1')
. (Join-Path `$SrcDir 'manutencao.ps1')
. (Join-Path `$SrcDir 'segundoplano.ps1')
. (Join-Path `$SrcDir 'desinstalar.ps1')
Initialize-Otz -SrcDir `$SrcDir -Fila `$Fila -SidAlvo `$SidAlvo
$Script
"@
    [void]$ps.AddScript($codigo)
    $t = @{ Nome = $Nome; PS = $ps; RS = $rs; Handle = $ps.BeginInvoke(); Fila = $fila; AoEvento = $AoEvento; AoTerminar = $AoTerminar }
    [void]$S.Tarefas.Add($t)
    if (-not $S.Timer.IsEnabled) { $S.Timer.Start() }
}

function Receive-Fila($Tarefa) {
    $ev = $null
    while ($Tarefa.Fila.TryDequeue([ref]$ev)) {
        if ($Tarefa.AoEvento) {
            try { & $Tarefa.AoEvento $ev } catch { Write-Log "UI [$($Tarefa.Nome)]: $($_.Exception.Message)" }
        }
    }
}

function Update-Tarefas {
    foreach ($t in @($S.Tarefas)) {
        Receive-Fila $t
        if (-not $t.Handle.IsCompleted) { continue }
        Receive-Fila $t
        $saida = $null; $erro = $null
        try { $saida = @($t.PS.EndInvoke($t.Handle)) } catch { $erro = $_.Exception.InnerException.Message; if (-not $erro) { $erro = $_.Exception.Message } }
        foreach ($e in $t.PS.Streams.Error) { Write-Log "[$($t.Nome)] $e" }
        $t.PS.Dispose(); $t.RS.Close(); $t.RS.Dispose()
        $S.Tarefas.Remove($t)
        if ($t.AoTerminar) {
            try { & $t.AoTerminar $saida $erro } catch { Write-Log "UI [$($t.Nome)] fim: $($_.Exception.Message) | $($_.ScriptStackTrace -replace "`r?`n", ' <- ')"; Show-Toast "Erro: $($_.Exception.Message)" 'erro' }
        }
    }
    if ($S.Tarefas.Count -eq 0) { $S.Timer.Stop() }
}

function Test-TarefaAtiva([string]$Nome) { return [bool](@($S.Tarefas) | Where-Object { $_.Nome -eq $Nome }) }

# ===============================================================
#  Navegação
# ===============================================================
$Script:Paginas = [ordered]@{
    NavInicio = 'PagInicio'; NavVerificar = 'PagVerificar'; NavDiagnostico = 'PagDiagnostico'; NavOtimizar = 'PagOtimizar'; NavVideo = 'PagVideo'; NavNotebook = 'PagNotebook'
    NavServicos = 'PagServicos'; NavFerramentas = 'PagFerramentas'; NavHistorico = 'PagHistorico'; NavAjuda = 'PagAjuda'
}

function Show-Pagina([string]$Pagina) {
    foreach ($p in $Paginas.Values) { if ($p -ne $Pagina) { $UI[$p].Visibility = 'Collapsed' } }
    if ($Pagina -ne 'PagFerramentas') { Stop-Temperaturas } elseif ($UI.FerTemp.Visibility -eq 'Visible') { Start-Temperaturas }
    Show-Entrada $UI[$Pagina]
    switch ($Pagina) {
        'PagHistorico'   { Update-Historico; Update-Comparacao }
        'PagDiagnostico' { if (-not $S.DiagCarregado.Count) { Show-Diagnostico 'RbDiagLento' } }
        'PagVideo'       { if (-not $S.GpuCarregada) { Update-Gpu } }
        'PagNotebook'    { if (-not $S.BateriaCarregada) { Update-Bateria } }
        'PagServicos'    { Update-Ram; if (-not $S.SegCarregado) { Update-SegundoPlano } }
        'PagVerificar'   { Show-Evolucao }
        'PagFerramentas' { if (-not $S.FerCarregado.Count) { Show-Ferramenta 'RbFerRede' } }
    }
}

function Open-Pagina([string]$Nav) {
    if ($UI[$Nav].IsChecked) { Show-Pagina $Paginas[$Nav] } else { $UI[$Nav].IsChecked = $true }
}

foreach ($nav in $Paginas.Keys) {
    $UI[$nav].Add_Checked({ Show-Pagina $Paginas[$this.Name] })
}

# ===============================================================
#  Catálogo → lista de ajustes
# ===============================================================
$S.Catalogo = @(Get-Catalogo)
foreach ($i in $S.Catalogo) {
    $a = [Otz.Ajuste]::new()
    $a.Id = $i.Id; $a.Nome = $i.Nome; $a.Resumo = $i.Resumo; $a.Detalhe = $i.Detalhe
    $a.Indicado = [string]$i.Indicado; $a.Atencao = [string]$i.Atencao; $a.Categoria = $i.Categoria
    $a.Tecnico = Get-TecnicoAjuste $i
    $a.Confirmar = [string]$i.Confirmar
    $a.Tipo = $i.Tipo; $a.Risco = $i.Risco; $a.Reinicio = $i.Reinicio
    $a.Perfis = [string[]]@($i.Perfis); $a.Ordem = $i.Ordem
    $a.Glossario = Get-GlossarioTexto "$($i.Nome) $($i.Resumo) $($i.Detalhe) $($i.Atencao)"
    $a.ComoDesfazer = if ($i.ComoDesfazer) { $i.ComoDesfazer }
                      elseif ($i.Tipo -eq 'acao') { 'Ação única, não tem desfazer.' }
                      else { 'Clique em "Desfazer este ajuste" (aqui ou em Histórico > Desfazer todos). O valor original foi guardado antes da mudança.' }
    $S.Ajustes.Add($a)
    $S.PorId[$i.Id] = $a
}
$S.CatPorId = @{}
foreach ($i in $S.Catalogo) { $S.CatPorId[$i.Id] = $i }

$S.View = [Windows.Data.CollectionViewSource]::GetDefaultView($S.Ajustes)
$S.View.GroupDescriptions.Add((New-Object Windows.Data.PropertyGroupDescription 'Categoria'))
$UI.ListaAjustes.ItemsSource = $S.Ajustes

function Remove-Acentos([string]$Texto) {
    $n = $Texto.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $n.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne 'NonSpacingMark') { [void]$sb.Append($ch) }
    }
    return $sb.ToString().ToLowerInvariant()
}

foreach ($a in $S.Ajustes) { $S["Busca_$($a.Id)"] = Remove-Acentos "$($a.Nome) $($a.Resumo) $($a.Categoria) $($a.Id) $($a.Detalhe)" }

$S.View.Filter = [Predicate[object]]{
    param($o)
    if (-not $S.ModoAvancado -and $o.Risco -eq 'avancado') { return $false }
    if ($UI.ChkSoPendentes.IsChecked -and ($o.Estado -eq 'aplicado' -or $o.Estado -eq 'na' -or -not $o.Habilitado)) { return $false }
    $q = $S.Busca
    if (-not $q) { return $true }
    foreach ($termo in ($q -split '\s+')) { if ($termo -and $S["Busca_$($o.Id)"] -notlike "*$termo*") { return $false } }
    return $true
}

$UI.TxtBusca.Add_TextChanged({ $S.Busca = Remove-Acentos $UI.TxtBusca.Text.Trim(); $S.View.Refresh() })
$UI.ChkSoPendentes.Add_Click({ $S.View.Refresh() })

# ---------------------------------------------------------------
#  Windows alvo e compatibilidade
# ---------------------------------------------------------------
$S.WinReal = if ($Otz.IsWin11) { '11' } else { '10' }

function Get-WinAlvo {
    if ($UI.RbWin10.IsChecked) { return '10' }
    if ($UI.RbWin11.IsChecked) { return '11' }
    return $S.WinReal
}

function Update-Compatibilidade {
    $alvo = Get-WinAlvo
    foreach ($i in $S.Catalogo) {
        $a = $S.PorId[$i.Id]
        $c = Test-Compativel $i $alvo
        if ($c.Ok -and $a.Estado -eq 'na') { $c = @{ Ok = $false; Motivo = $a.EstadoDetalhe } }
        $a.Habilitado = $c.Ok
        $a.Motivo = $c.Motivo
        if (-not $c.Ok) { $a.Selecionado = $false }
    }
    if ($alvo -ne $S.WinReal) {
        $UI.TxtBannerWin.Text = "Você escolheu Windows $alvo, mas este PC é Windows $($S.WinReal). Itens exclusivos do outro sistema podem não ter efeito aqui."
        $UI.BannerWin.Visibility = 'Visible'
    } else { $UI.BannerWin.Visibility = 'Collapsed' }
    $S.View.Refresh()
    Update-Rodape
}

$UI.RbWinAuto.Content = "Automático ($($S.WinReal))"
foreach ($rb in 'RbWinAuto', 'RbWin10', 'RbWin11') { $UI[$rb].Add_Checked({ Update-Compatibilidade; if ($S.Perfil -ne 'personalizado') { Set-Perfil $S.Perfil } }) }

# ---------------------------------------------------------------
#  Perfis
# ---------------------------------------------------------------
$S.DescPerfis = @{
    basico        = 'Básico: ajustes seguros para qualquer PC. Mouse, teclado, menus rápidos, menos propaganda e limpeza.'
    trabalho      = 'Trabalho: Básico + energia no máximo, USB estável, Windows Update sem reinício surpresa e Explorador mais prático.'
    gamer         = 'Gamer: Trabalho + Modo de Jogo, sem gravação em segundo plano, HAGS, prioridade para jogos e sem economia no PCIe.'
    leve          = 'PC simples: Básico + menos efeitos visuais, sem Widgets, limpeza automática e menos tarefas em segundo plano.'
    personalizado = 'Personalizado: você escolhe item por item. Clique em um perfil acima para começar com uma sugestão.'
}
$S.NomePerfis = @{ basico = 'Básico'; trabalho = 'Trabalho'; gamer = 'Gamer'; leve = 'PC simples'; personalizado = 'Personalizado' }

function Set-Perfil([string]$Perfil) {
    $S.Perfil = $Perfil
    if ($Perfil -ne 'personalizado') {
        $total = 0; $jaFeitos = 0
        foreach ($a in $S.Ajustes) {
            $no = ($a.Perfis -contains $Perfil) -and $a.Habilitado -and $a.Risco -ne 'avancado'
            if ($no) { $total++ }
            if ($no -and $a.Estado -eq 'aplicado') { $jaFeitos++ }
            $a.Selecionado = $no -and $a.Estado -ne 'aplicado'
        }
        $desc = $S.DescPerfis[$Perfil]
        if ($jaFeitos -gt 0) { $desc += "  ($jaFeitos de $total já estão aplicados e ficaram desmarcados.)" }
        $UI.TxtPerfilDescricao.Text = $desc
    } else {
        $UI.TxtPerfilDescricao.Text = $S.DescPerfis[$Perfil]
    }
    Update-Rodape
}

foreach ($rb in 'RbPerfilBasico', 'RbPerfilTrabalho', 'RbPerfilGamer', 'RbPerfilLeve', 'RbPerfilNenhum') {
    $UI[$rb].Add_Checked({ Set-Perfil ([string]$this.Tag) })
}

function Select-Perfil([string]$Perfil) {
    $rb = @{ basico = 'RbPerfilBasico'; trabalho = 'RbPerfilTrabalho'; gamer = 'RbPerfilGamer'; leve = 'RbPerfilLeve'; personalizado = 'RbPerfilNenhum' }[$Perfil]
    if ($UI[$rb].IsChecked) { Set-Perfil $Perfil } else { $UI[$rb].IsChecked = $true }
}

# ---------------------------------------------------------------
#  Rodapé (contagem da seleção)
# ---------------------------------------------------------------
function Update-Rodape {
    $sel = @($S.Ajustes | Where-Object Selecionado)
    $n = $sel.Count
    $UI.TxtSelecaoNumero.Text = [string]$n
    $UI.TxtSelecao.Text = switch ($n) { 0 { 'Nenhum ajuste selecionado' } 1 { '1 ajuste selecionado' } default { "$n ajustes selecionados" } }
    $partes = New-Object System.Collections.Generic.List[string]
    $r = @($sel | Where-Object Reinicio -eq 'reiniciar').Count
    $l = @($sel | Where-Object Reinicio -eq 'logoff').Count
    $m = @($sel | Where-Object { $_.Risco -ne 'seguro' }).Count
    if ($r) { $partes.Add("$r só vale(m) após reiniciar") }
    if ($l) { $partes.Add("$l após sair da conta") }
    if ($m) { $partes.Add("$m moderado(s) ou avançado(s): leia a Atenção") }
    $UI.TxtSelecaoSub.Text = if ($n -eq 0) { 'Escolha um perfil acima ou marque os itens da lista.' }
                             elseif ($partes.Count) { $partes -join '  ·  ' }
                             else { 'Todos valem na hora e são seguros.' }
    $UI.BtnAplicar.IsEnabled = ($n -gt 0)
    $UI.BtnSimular.IsEnabled = ($n -gt 0)
    if ($S.PaginasAjustes) { foreach ($k in @($S.PaginasAjustes.Keys)) { Update-RodapePagina $k } }
}

# Clique dentro da lista: caixa de seleção ou "Marcar todos" de uma categoria
$UI.ListaAjustes.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
    param($origem, $e)
    $src = $e.OriginalSource
    if ($src -is [Windows.Controls.CheckBox]) {
        if ($S.Perfil -ne 'personalizado') { $UI.RbPerfilNenhum.IsChecked = $true }
        Update-Rodape
    } elseif ($src -is [Windows.Controls.Button] -and $src.Tag) {
        $cat = [string]$src.Tag
        $itens = @($S.Ajustes | Where-Object { $_.Categoria -eq $cat -and $_.Habilitado -and $_.Risco -ne 'avancado' })
        $marcar = @($itens | Where-Object { -not $_.Selecionado }).Count -gt 0
        foreach ($a in $itens) { $a.Selecionado = $marcar }
        if ($S.Perfil -ne 'personalizado') { $UI.RbPerfilNenhum.IsChecked = $true }
        Update-Rodape
    }
})

$UI.BtnLimparSelecao.Add_Click({
    foreach ($a in $S.Ajustes) { $a.Selecionado = $false }
    $UI.RbPerfilNenhum.IsChecked = $true
    Update-Rodape
})

# ---------------------------------------------------------------
#  Prévia "agora → depois" do item aberto (calculada em segundo plano)
# ---------------------------------------------------------------
function Update-Previa($Ajuste) {
    if (-not $Ajuste -or $Ajuste.Previa) { return }
    $Ajuste.Previa = 'Lendo o valor atual neste PC...'
    Start-Tarefa -Nome "previa-$($Ajuste.Id)" -Parametros @{ Id = $Ajuste.Id } `
        -Script '$Parametros.Id; ((Get-SimulacaoAjuste (Get-Catalogo | Where-Object { $_.Id -eq $Parametros.Id } | Select-Object -First 1)) -join "`n")' `
        -AoTerminar {
            param($saida, $erro)
            $saida = @($saida)
            if ($saida.Count -lt 1) { return }
            $x = $S.PorId[[string]$saida[0]]
            if (-not $x) { return }
            $x.Previa = if ($erro) { "Não foi possível ler: $erro" } elseif ($saida.Count -gt 1 -and $saida[1]) { [string]$saida[1] } else { 'Sem dados para mostrar.' }
        }
}
$UI.ListaAjustes.Add_SelectionChanged({ Update-Previa $UI.ListaAjustes.SelectedItem })

# ---------------------------------------------------------------
#  Modo simples / avançado
#  Simples: esconde detalhes técnicos, a escolha manual do Windows e os
#  ajustes avançados. Avançado: mostra tudo.
# ---------------------------------------------------------------
function Set-ModoAvancado([bool]$Avancado) {
    $S.ModoAvancado = $Avancado
    $vis = if ($Avancado) { 'Visible' } else { 'Collapsed' }
    $UI.PainelWindows.Visibility = $vis
    $UI.PainelTecnico.Visibility = $vis
    if (-not $Avancado) {
        foreach ($a in $S.Ajustes) { if ($a.Risco -eq 'avancado') { $a.Selecionado = $false } }
    }
    $S.View.Refresh()
    Update-Rodape
}
$UI.ChkAvancado.Add_Click({
    Set-ModoAvancado ([bool]$UI.ChkAvancado.IsChecked)
    Save-Preferencias
    Show-Toast $(if ($S.ModoAvancado) { 'Modo avançado: detalhes técnicos e ajustes avançados visíveis.' } else { 'Modo simples: só o essencial, sem detalhes técnicos.' }) 'info'
})

# ---------------------------------------------------------------
#  Perfis exportáveis (aplicar igual em vários PCs)
# ---------------------------------------------------------------
$UI.BtnExportarPerfil.Add_Click({
    $ids = @($S.Ajustes | Where-Object Selecionado | ForEach-Object Id)
    if ($ids.Count -eq 0) { Show-Toast 'Marque os ajustes que vão no perfil (ou escolha um perfil pronto) e clique em Exportar.' 'aviso'; return }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $base = if ($S.Perfil -ne 'personalizado') { $S.Perfil } else { 'meu-perfil' }
    $dlg.FileName = "perfil-$base.json"
    $dlg.InitialDirectory = $Otz.Dados
    $dlg.Filter = 'Perfil do Otimizador (*.json)|*.json'
    if (-not $dlg.ShowDialog()) { return }
    try {
        $nome = [IO.Path]::GetFileNameWithoutExtension($dlg.FileName) -replace '^perfil-', ''
        Export-Perfil $ids $nome $dlg.FileName
        Show-Dialogo -Titulo "Perfil '$nome' salvo" -Tipo 'info' -SoOk -TextoOk 'Entendi' `
            -Texto "$($ids.Count) ajuste(s) no arquivo:`n$($dlg.FileName)`n`nPara aplicar em outro PC: copie a pasta do otimizador e o arquivo, e rode:`nAplicar-Perfil.bat `"$([IO.Path]::GetFileName($dlg.FileName))`"`n`nOu abra o otimizador lá e use Otimizar > Importar."
    } catch { Show-Toast "Não foi possível salvar: $($_.Exception.Message)" 'erro' }
})

$UI.BtnImportarPerfil.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.InitialDirectory = $Otz.Dados
    $dlg.Filter = 'Perfil do Otimizador (*.json)|*.json'
    if (-not $dlg.ShowDialog()) { return }
    try {
        $p = Import-Perfil $dlg.FileName
        $UI.RbPerfilNenhum.IsChecked = $true
        $marcados = 0; $fora = 0; $jaFeitos = 0
        foreach ($a in $S.Ajustes) { $a.Selecionado = $false }
        foreach ($id in @($p.Ids)) {
            $a = $S.PorId[[string]$id]
            if (-not $a -or -not $a.Habilitado) { $fora++; continue }
            if ($a.Estado -eq 'aplicado') { $jaFeitos++; continue }
            if ($a.Risco -eq 'avancado' -and -not $S.ModoAvancado) { $UI.ChkAvancado.IsChecked = $true; Set-ModoAvancado $true }
            $a.Selecionado = $true; $marcados++
        }
        Update-Rodape
        $txt = "Perfil '$($p.Nome)' (criado em $($p.Computador)): $marcados ajuste(s) marcados."
        if ($jaFeitos) { $txt += " $jaFeitos já estavam aplicados." }
        if ($fora) { $txt += " $fora não se aplicam a este PC." }
        Show-Toast "$txt Revise e clique em Aplicar." 'info'
    } catch { Show-Toast $_.Exception.Message 'erro' }
})

# ---------------------------------------------------------------
#  Estado (detecção em segundo plano)
# ---------------------------------------------------------------
function Start-Deteccao {
    if (Test-TarefaAtiva 'estado') { return }
    Start-Tarefa -Nome 'estado' -Script 'Get-EstadoTodos' -AoEvento {
        param($ev)
        if ($ev.Tipo -ne 'estado') { return }
        $a = $S.PorId[$ev.Id]
        if (-not $a) { return }
        $a.Estado = $ev.Estado
        $a.EstadoDetalhe = [string]$ev.Texto
        $a.PodeDesfazer = [bool]$ev.PodeDesfazer
        if ($ev.Id -eq 'limpeza.temp' -and $ev.Texto) { $UI.TxtAcaoLimparSub.Text = ($ev.Texto.Substring(0, 1).ToUpper() + $ev.Texto.Substring(1)) + '. Libere com um clique.' }
    } -AoTerminar {
        Update-Compatibilidade
        if ($S.Perfil -ne 'personalizado') { Set-Perfil $S.Perfil }
        Update-Anel
        $n = @($S.Ajustes | Where-Object PodeDesfazer).Count
        $UI.TxtDesfazerTudo.Text = if ($n) { "Desfazer todos ($n)" } else { 'Desfazer todos' }
        $UI.BtnDesfazerTudo.IsEnabled = ($n -gt 0)
        foreach ($x in $S.Ajustes) { $x.Previa = '' }
        if ($UI.ListaAjustes.SelectedItem) { Update-Previa $UI.ListaAjustes.SelectedItem }
    }
}

# ===============================================================
#  Início: resumo do PC
# ===============================================================
$S.TimerAnel = New-Object Windows.Threading.DispatcherTimer
$S.TimerAnel.Interval = [TimeSpan]::FromMilliseconds(16)
$S.TimerAnel.Add_Tick({
    $t = [math]::Min(1.0, ((Get-Date) - $S.AnelInicio).TotalMilliseconds / 900)
    $e = 1 - [math]::Pow(1 - $t, 3)
    $v = $S.AnelDe + ($S.AnelPara - $S.AnelDe) * $e
    Set-Arco $v
    $UI.TxtAnelNumero.Text = [string][math]::Round($v * $S.AnelTotal)
    if ($t -ge 1) { $S.TimerAnel.Stop(); $S.AnelAtual = $S.AnelPara; $UI.TxtAnelNumero.Text = [string]$S.AnelFeitos }
})

function Set-Arco([double]$Fracao, $Caminho = $UI.ArcoProgresso) {
    $r = 69.0; $c = 75.0
    if ($Fracao -le 0.001) { $Caminho.Data = $null; return }
    if ($Fracao -gt 0.9999) { $Fracao = 0.9999 }
    $ang = $Fracao * 2 * [math]::PI
    $x = $c + $r * [math]::Sin($ang)
    $y = $c - $r * [math]::Cos($ang)
    $grande = if ($Fracao -gt 0.5) { 1 } else { 0 }
    $d = [string]::Format([Globalization.CultureInfo]::InvariantCulture, 'M {0},{1} A {2},{2} 0 {3} 1 {4:0.##},{5:0.##}', $c, ($c - $r), $r, $grande, $x, $y)
    $Caminho.Data = [Windows.Media.Geometry]::Parse($d)
}

function Update-Anel {
    $base = @($S.Ajustes | Where-Object { $_.Tipo -ne 'acao' -and $_.Habilitado -and $_.Estado -ne 'na' -and $_.Perfis.Count -gt 0 })
    $feitos = @($base | Where-Object { $_.Estado -eq 'aplicado' }).Count
    $S.AnelDe = $S.AnelAtual
    $S.AnelPara = if ($base.Count) { $feitos / $base.Count } else { 0 }
    $S.AnelTotal = $base.Count
    $S.AnelFeitos = $feitos
    $S.AnelInicio = Get-Date
    $UI.TxtAnelLegenda.Text = "de $($base.Count)"
    $S.TimerAnel.Start()
}

function New-Chip([int]$Glifo, [string]$Texto, [string]$Dica = '') {
    $b = [Windows.Controls.Border]::new()
    $b.Style = $Win.FindResource('Chip')
    $b.Padding = '12,6'
    $sp = [Windows.Controls.StackPanel]::new()
    $sp.Orientation = 'Horizontal'
    $i = [Windows.Controls.TextBlock]::new()
    $i.Text = G $Glifo
    $i.Style = $Win.FindResource('Icone')
    $i.FontSize = 13
    $i.Margin = '0,0,8,0'
    Set-Referencia $i ([Windows.Controls.TextBlock]::ForegroundProperty) 'Acento'
    $t = [Windows.Controls.TextBlock]::new()
    $t.Text = $Texto
    $t.FontSize = 13
    [void]$sp.Children.Add($i); [void]$sp.Children.Add($t)
    $b.Child = $sp
    if ($Dica) { $b.ToolTip = $Dica }
    return $b
}

function Set-Saudacao {
    $h = (Get-Date).Hour
    $oi = if ($h -lt 5) { 'Boa noite' } elseif ($h -lt 12) { 'Bom dia' } elseif ($h -lt 18) { 'Boa tarde' } else { 'Boa noite' }
    $nome = ''
    try {
        if (-not $Otz.SidAlvo) { $nome = ((Get-LocalUser -Name $env:USERNAME -ErrorAction Stop).FullName -split '\s+')[0] }
    } catch { }
    $UI.TxtSaudacao.Text = if ($nome) { "$oi, $nome!" } else { "$oi!" }
}

function Show-InfoPC($Info) {
    $S.Info = $Info
    $UI.TxtPcNome.Text = $Info.Computador
    $UI.TxtNavPc.Text = $Info.Computador
    $UI.TxtPcWin.Text = "$($Info.WinNome) $($Info.VersaoWin)  ·  build $($Info.Build)  ·  $(if ($Info.Notebook) { 'Notebook' } else { 'Desktop' })"
    $UI.TxtNavWin.Text = "$($Info.WinNome) $($Info.VersaoWin)`n$($Info.Tier)  ·  $($Info.RamGB) GB  ·  $($Info.DiscoTipo)"
    if ($Info.Notebook) { $UI.IcoPc.Text = G 0xE7F8 }
    $UI.TxtTier.Text = $Info.Tier
    Start-Animacao $UI.BadgeTier ([Windows.UIElement]::OpacityProperty) 0 1 500

    $UI.PainelChips.Children.Clear()
    $cpu = $Info.Cpu -replace '\(R\)|\(TM\)|CPU|Processor|\d+-Core', '' -replace '\s+', ' '
    [void]$UI.PainelChips.Children.Add((New-Chip 0xE950 "$($cpu.Trim())  ·  $($Info.Threads) threads" "$($Info.Nucleos) núcleos, $($Info.Threads) threads, até $($Info.ClockMHz) MHz"))
    [void]$UI.PainelChips.Children.Add((New-Chip 0xE964 "$($Info.RamGB) GB de RAM  ·  $($Info.RamUso)% em uso" "$(@($Info.Pentes).Count) pente(s) de memória"))
    $livre = if ($null -ne $Info.DiscoLivre) { "  ·  $($Info.DiscoLivreGB) GB livres ($($Info.DiscoLivre)%)" } else { '' }
    [void]$UI.PainelChips.Children.Add((New-Chip 0xEDA2 "$($Info.DiscoTipo)$livre" 'Disco onde o Windows está instalado'))
    if ($Info.GpuNome) { [void]$UI.PainelChips.Children.Add((New-Chip 0xE7F4 $Info.GpuNome 'Placa de vídeo')) }
    [void]$UI.PainelChips.Children.Add((New-Chip 0xE81C "Ligado há $($Info.UptimeTexto)" 'Tempo desde o último reinício de verdade'))
    [void]$UI.PainelChips.Children.Add((New-Chip 0xE945 $Info.Plano 'Plano de energia ativo'))

    $nomePerfil = $S.NomePerfis[$Info.PerfilSugerido]
    $UI.TxtTierExplica.Text = switch ($Info.Tier) {
        'Low-end'  { "PC de entrada. O perfil sugerido é '$nomePerfil': deixa o Windows mais leve sem mexer em nada arriscado." }
        'High-end' { "PC potente. O perfil sugerido é '$nomePerfil': tira os freios de energia e prioriza o que você está usando." }
        default    { "PC intermediário. O perfil sugerido é '$nomePerfil': equilibra desempenho e estabilidade no dia a dia." }
    }
    $UI.TxtAcaoOtimizarSub.Text = "Perfil sugerido para este PC: $nomePerfil"
    $n = @($Info.Alertas).Count
    $UI.TxtSaudacaoSub.Text = if ($n -eq 0) { 'Seu computador está em boa forma. Veja abaixo o que dá para melhorar.' }
                              elseif ($n -eq 1) { 'Encontrei 1 ponto de atenção. Veja abaixo.' }
                              else { "Encontrei $n pontos de atenção. Veja abaixo." }

    $linhas = foreach ($al in $Info.Alertas) {
        $extra = switch ($al.Acao) { 'inicializacao' { 'Ver programas' } 'limpeza' { 'Limpar agora' } 'energia.plano' { 'Ver ajuste' } default { '' } }
        New-Linha -Titulo '' -Texto $al.Texto -Nivel $al.Nivel -Extra $extra -Tag $al.Acao
    }
    if ($n -eq 0) { $linhas = @(New-Linha -Texto 'Nenhum problema de hardware encontrado. Memória, discos e sistema estão ok.' -Nivel 'ok') }
    $UI.ListaAlertas.ItemsSource = ConvertTo-Linhas $linhas
    $UI.TxtAlertasCarregando.Visibility = 'Collapsed'
}

function Start-InfoPC {
    Start-Tarefa -Nome 'info' -Script 'Get-InfoPC' -AoTerminar {
        param($saida, $erro)
        if ($erro -or -not $saida) { $UI.TxtAlertasCarregando.Text = "Não foi possível analisar o hardware: $erro"; return }
        Show-InfoPC $saida[0]
    }
}

$UI.ListaAlertas.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
    param($origem, $e)
    switch ([string]$e.OriginalSource.Tag) {
        'inicializacao' { Open-Pagina 'NavFerramentas'; Show-Ferramenta 'RbFerInicio' }
        'limpeza'       { Start-Execucao 'aplicar' @('limpeza.temp') }
        'energia.plano' { Open-Pagina 'NavOtimizar'; $UI.ListaAjustes.SelectedItem = $S.PorId['energia.plano']; $UI.ListaAjustes.ScrollIntoView($S.PorId['energia.plano']) }
    }
})

$UI.BtnVerAjustes.Add_Click({ Open-Pagina 'NavOtimizar' })
$UI.BtnAcaoOtimizar.Add_Click({
    $p = if ($S.Info) { $S.Info.PerfilSugerido } else { 'basico' }
    Open-Pagina 'NavOtimizar'
    Select-Perfil $p
    $n = @($S.Ajustes | Where-Object Selecionado).Count
    if ($n) { Show-Toast "Perfil '$($S.NomePerfis[$p])' selecionado: $n ajuste(s). Revise e clique em Aplicar." 'info' }
    else { Show-Toast "Tudo do perfil '$($S.NomePerfis[$p])' já está aplicado neste PC." 'ok' }
})
$UI.BtnAcaoLimpar.Add_Click({ Start-Execucao 'aplicar' @('limpeza.temp', 'limpeza.dns') })
$UI.BtnAcaoRelatorio.Add_Click({ Start-Relatorio })
$UI.BtnAcaoServidor.Add_Click({ Open-Pagina 'NavFerramentas'; Show-Ferramenta 'RbFerServidor'; [void]$UI.TxtServidorHost.Focus() })

# ===============================================================
#  Execução (aplicar / simular / desfazer)
# ===============================================================
function Show-Overlay {
    $UI.Overlay.Visibility = 'Visible'
    Start-Animacao $UI.Overlay ([Windows.UIElement]::OpacityProperty) 0 1 200
    Start-Animacao $UI.OverlayEscala ([Windows.Media.ScaleTransform]::ScaleXProperty) 0.96 1 260
    Start-Animacao $UI.OverlayEscala ([Windows.Media.ScaleTransform]::ScaleYProperty) 0.96 1 260
}

function Hide-Overlay {
    Start-Animacao $UI.Overlay ([Windows.UIElement]::OpacityProperty) $null 0 180 { $UI.Overlay.Visibility = 'Collapsed' }
}

function Start-Execucao([string]$Modo, [string[]]$Ids) {
    if ($S.Executando) { Show-Toast 'Aguarde a execução atual terminar.' 'aviso'; return }
    $itens = @($Ids | ForEach-Object { $S.PorId[$_] } | Where-Object { $_ } | Sort-Object Ordem)
    if ($Modo -eq 'desfazer') { [array]::Reverse($itens) }
    if ($itens.Count -eq 0) { return }
    $S.Executando = $true
    $S.ExecModo = $Modo
    $S.ExecTotal = $itens.Count
    $S.ExecFeitos = 0

    $col = New-Object 'System.Collections.ObjectModel.ObservableCollection[Otz.Ajuste]'
    foreach ($a in $itens) { $a.Execucao = 'fila'; $a.ExecucaoTexto = ''; $col.Add($a) }
    $UI.ListaExec.ItemsSource = $col

    $n = $itens.Count
    $UI.TxtExecTitulo.Text = switch ($Modo) {
        'simular'  { "Simulando $n ajuste(s)" }
        'desfazer' { "Desfazendo $n ajuste(s)" }
        default    { "Aplicando $n ajuste(s)" }
    }
    $UI.TxtExecSub.Text = if ($Modo -eq 'simular') { 'Nada será alterado. Veja o valor atual e o que seria gravado em cada item.' }
                          else { 'Acompanhe cada item abaixo. Não feche a janela.' }
    $UI.TxtExecContagem.Text = "0 de $n"
    $UI.BarraExec.BeginAnimation([Windows.Controls.Primitives.RangeBase]::ValueProperty, $null)
    $UI.BarraExec.Value = 0
    $UI.LinhaPonto.Visibility = 'Collapsed'
    $UI.PainelResumo.Visibility = 'Collapsed'
    $UI.BtnExecReiniciar.Visibility = 'Collapsed'
    $UI.BtnExecLogoff.Visibility = 'Collapsed'
    $UI.BtnExecFechar.IsEnabled = $false
    $UI.TxtExecFechar.Text = 'Aguarde...'
    $UI.LogExec.Text = ''
    $UI.BtnExecLog.IsChecked = $false
    $UI.ExecIcone.Text = G 0xE895
    Set-Referencia $UI.ExecCirculo ([Windows.Controls.Border]::BackgroundProperty) 'AcentoGrad'
    Start-Giro $UI.ExecGiro
    Show-Overlay

    $criarPonto = -not $S.PontoCriado
    # Antes da primeira otimização, grava a "foto" do PC para o Antes × depois do Histórico
    $script = @'
if ($Parametros.Modo -eq 'aplicar' -and -not (Get-MedicaoReferencia)) { try { [void](Save-MedicaoReferencia) } catch { Write-Log "Medição de referência falhou: $($_.Exception.Message)" } }
Invoke-Plano -Ids $Parametros.Ids -Modo $Parametros.Modo -CriarPonto $Parametros.CriarPonto
'@
    Start-Tarefa -Nome 'execucao' -Script $script `
        -Parametros @{ Ids = [string[]]@($itens | ForEach-Object Id); Modo = $Modo; CriarPonto = [bool]$criarPonto } `
        -AoEvento { param($ev) Receive-EventoExecucao $ev } `
        -AoTerminar { param($saida, $erro) Complete-Execucao $saida $erro }
}

function Receive-EventoExecucao($ev) {
    switch ($ev.Tipo) {
        'ponto' {
            $UI.LinhaPonto.Visibility = 'Visible'
            $UI.TxtPonto.Text = $ev.Mensagem
            if ($ev.Status -eq 'executando') {
                $UI.IcoPonto.Text = G 0xE895; Set-Referencia $UI.IcoPonto ([Windows.Controls.TextBlock]::ForegroundProperty) 'Acento'; Start-Giro $UI.PontoGiro
            } else {
                Stop-Giro $UI.PontoGiro
                if ($ev.Status -eq 'ok') { $S.PontoCriado = $true; $UI.IcoPonto.Text = G 0xE73E; Set-Referencia $UI.IcoPonto ([Windows.Controls.TextBlock]::ForegroundProperty) 'Ok' }
                else { $UI.IcoPonto.Text = G 0xE7BA; Set-Referencia $UI.IcoPonto ([Windows.Controls.TextBlock]::ForegroundProperty) 'Aviso' }
            }
        }
        'item' {
            $a = $S.PorId[$ev.Id]
            if (-not $a) { return }
            $a.Execucao = $ev.Status
            if ($ev.Status -eq 'executando') {
                $cont = $UI.ListaExec.ItemContainerGenerator.ContainerFromItem($a)
                if ($cont) { $cont.BringIntoView() }
            } else {
                $a.ExecucaoTexto = if ($ev.Status -eq 'ok' -and $S.ExecModo -eq 'aplicar' -and [string]$ev.Mensagem -eq 'Aplicado.') { "O que mudou: $($a.Resumo)" } else { [string]$ev.Mensagem }
                $S.ExecFeitos++
                $UI.TxtExecContagem.Text = "$($S.ExecFeitos) de $($S.ExecTotal)"
                Start-Animacao $UI.BarraExec ([Windows.Controls.Primitives.RangeBase]::ValueProperty) $null (100 * $S.ExecFeitos / $S.ExecTotal) 350
            }
        }
        'log' { $UI.LogExec.AppendText($ev.Texto + "`r`n"); $UI.LogExec.ScrollToEnd() }
    }
}

function Complete-Execucao($Saida, $Erro) {
    Stop-Giro $UI.ExecGiro
    $S.Executando = $false
    $res = @($Saida | Where-Object { $_ -and $_.Status })
    $ok = @($res | Where-Object { $_.Status -eq 'ok' -or $_.Status -eq 'simulado' }).Count
    $er = @($res | Where-Object Status -eq 'erro').Count
    $av = @($res | Where-Object { $_.Status -eq 'aviso' -or $_.Status -eq 'ignorado' }).Count
    if ($Erro) { $er++; $UI.LogExec.AppendText("ERRO GERAL: $Erro`r`n"); Write-Log "Execução falhou: $Erro" }

    # Itens que não chegaram a rodar (falha geral)
    foreach ($a in $UI.ListaExec.ItemsSource) { if ($a.Execucao -in 'fila', 'executando') { $a.Execucao = 'erro'; $a.ExecucaoTexto = 'Não executado.' } }

    $modo = $S.ExecModo
    if ($er -eq 0) {
        $UI.ExecIcone.Text = G 0xE73E
        $UI.TxtExecTitulo.Text = switch ($modo) { 'simular' { 'Simulação concluída' } 'desfazer' { 'Ajustes desfeitos' } default { 'Tudo certo!' } }
    } else {
        $UI.ExecIcone.Text = G 0xE7BA
        Set-Referencia $UI.ExecCirculo ([Windows.Controls.Border]::BackgroundProperty) 'Aviso'
        $UI.TxtExecTitulo.Text = "Concluído com $er erro(s)"
    }

    $okItens = @($res | Where-Object Status -eq 'ok')
    $reiniciar = @($okItens | Where-Object Reinicio -eq 'reiniciar').Count
    $logoff    = @($okItens | Where-Object Reinicio -eq 'logoff').Count
    $explorer  = @($okItens | Where-Object Reinicio -eq 'explorer').Count
    if ($modo -eq 'simular') {
        $UI.TxtExecSub.Text = 'Nada foi alterado. Se estiver tudo certo, feche e clique em Aplicar.'
    } elseif ($reiniciar) {
        $UI.TxtExecSub.Text = "Reinicie o PC para concluir $reiniciar ajuste(s). Os demais já estão valendo."
        $UI.BtnExecReiniciar.Visibility = 'Visible'
    } elseif ($logoff) {
        $UI.TxtExecSub.Text = "Saia da conta e entre de novo para concluir $logoff ajuste(s). Os demais já estão valendo."
        $UI.BtnExecLogoff.Visibility = 'Visible'
    } elseif ($explorer) {
        $UI.TxtExecSub.Text = 'A barra de tarefas foi recarregada. Tudo já está valendo.'
    } elseif ($er) {
        $UI.TxtExecSub.Text = 'Os itens em vermelho mostram o motivo do erro. O restante foi aplicado.'
    } else {
        $UI.TxtExecSub.Text = 'Tudo já está valendo.'
    }

    $rotuloOk = if ($modo -eq 'simular') { 'simulado(s)' } else { 'ok' }
    $UI.TxtChipOk.Text = "$ok $rotuloOk"; $UI.ChipOk.Visibility = if ($ok) { 'Visible' } else { 'Collapsed' }
    $UI.TxtChipErro.Text = "$er erro(s)"; $UI.ChipErro.Visibility = if ($er) { 'Visible' } else { 'Collapsed' }
    $UI.TxtChipAviso.Text = "$av aviso(s)"; $UI.ChipAviso.Visibility = if ($av) { 'Visible' } else { 'Collapsed' }
    $UI.PainelResumo.Visibility = 'Visible'
    $UI.BtnExecFechar.IsEnabled = $true
    $UI.TxtExecFechar.Text = 'Fechar'
    Start-Animacao $UI.BarraExec ([Windows.Controls.Primitives.RangeBase]::ValueProperty) $null 100 300

    if ($modo -ne 'simular') {
        foreach ($r in $okItens) { $S.PorId[$r.Id].Selecionado = $false }
        Update-Rodape
        Start-Deteccao
        if (@($okItens | Where-Object { $_.Id -like 'serv.*' }).Count) { Update-Ram -Comparar }
        if ($S.SegCarregado -and @($res | Where-Object Id -eq 'serv.segundo-plano').Count) { Update-SegundoPlano }
        if (@($okItens | Where-Object { $_.Id -like 'gpu.*' }).Count) { $S.GpuCarregada = $false }
        if ($S.FerCarregado['FerEspaco'] -and @($okItens | Where-Object { $_.Id -like 'limpeza.*' -or $_.Id -eq 'sistema.hibernacao' }).Count) { Update-Espaco }
    }
}

$UI.BtnExecFechar.Add_Click({ Hide-Overlay })
$UI.BtnExecLog.Add_Click({
    $log = [bool]$UI.BtnExecLog.IsChecked
    $UI.LogExec.Visibility = if ($log) { 'Visible' } else { 'Collapsed' }
    $UI.RolagemExec.Visibility = if ($log) { 'Collapsed' } else { 'Visible' }
})
$UI.BtnExecReiniciar.Add_Click({
    Show-Dialogo -Titulo 'Reiniciar o computador agora?' -Texto 'Salve o que estiver aberto. O PC reinicia em 5 segundos.' -TextoOk 'Reiniciar' -Tipo 'perigo' -Acao {
        Write-Log 'Usuário pediu reinício.'
        shutdown.exe /r /t 5 /c "Otimizador Vinicius: reiniciando para concluir os ajustes."
    }
})
$UI.BtnExecLogoff.Add_Click({
    Show-Dialogo -Titulo 'Sair da conta agora?' -Texto 'Salve o que estiver aberto. Os programas serão fechados e você volta para a tela de entrada.' -TextoOk 'Sair da conta' -Tipo 'perigo' -Acao {
        Write-Log 'Usuário pediu logoff.'
        shutdown.exe /l
    }
})

# Botões principais
$UI.BtnSimular.Add_Click({
    $ids = @($S.Ajustes | Where-Object Selecionado | ForEach-Object Id)
    Start-Execucao 'simular' $ids
})

$UI.BtnAplicar.Add_Click({ Request-Aplicar @($S.Ajustes | Where-Object Selecionado) })

# Confirmação antes de aplicar (usada por Otimizar, Placa de vídeo, Notebook e Serviços)
function Request-Aplicar($Itens) {
    $sel = @($Itens | Sort-Object Ordem)
    if ($sel.Count -eq 0) { return }
    $linhas = New-Object System.Collections.Generic.List[object]
    if (@($sel | Where-Object Tipo -ne 'acao').Count -and -not $S.PontoCriado) {
        $linhas.Add((New-Linha -Titulo 'Um ponto de restauração será criado antes' -Texto 'Se algo der errado, dá para voltar o Windows inteiro.' -Nivel 'ok'))
    }
    foreach ($a in $sel | Where-Object { $_.Confirmar }) { $linhas.Add((New-Linha -Titulo $a.Nome -Texto $a.Confirmar -Nivel 'alto')) }
    foreach ($a in $sel | Where-Object { $_.Risco -eq 'avancado' }) { $linhas.Add((New-Linha -Titulo "$($a.Nome) (avançado)" -Texto $a.Atencao -Nivel 'alto')) }
    $r = @($sel | Where-Object Reinicio -eq 'reiniciar').Count
    $l = @($sel | Where-Object Reinicio -eq 'logoff').Count
    $x = @($sel | Where-Object Reinicio -eq 'explorer').Count
    if ($r) { $linhas.Add((New-Linha -Titulo "$r ajuste(s) só valem depois de reiniciar" -Nivel 'info')) }
    if ($l) { $linhas.Add((New-Linha -Titulo "$l ajuste(s) só valem depois de sair e entrar na conta" -Nivel 'info')) }
    if ($x) { $linhas.Add((New-Linha -Titulo 'A barra de tarefas vai piscar enquanto recarrega' -Texto 'Suas janelas abertas não são fechadas.' -Nivel 'info')) }
    $perigo = @($sel | Where-Object { $_.Confirmar -or $_.Risco -eq 'avancado' }).Count -gt 0
    Show-Dialogo -Titulo "Aplicar $($sel.Count) ajuste(s)?" `
        -Texto 'Cada ajuste pode ser desfeito depois, no painel de detalhes ou em Histórico.' `
        -Linhas $linhas -TextoOk 'Aplicar agora' -Tipo $(if ($perigo) { 'perigo' } else { 'normal' }) `
        -Dados ([string[]]@($sel | ForEach-Object Id)) -Acao { param($ids) Start-Execucao 'aplicar' $ids }
}

$UI.BtnDesfazerItem.Add_Click({
    $id = [string]$UI.BtnDesfazerItem.Tag
    $a = $S.PorId[$id]
    if (-not $a) { return }
    Show-Dialogo -Titulo "Desfazer '$($a.Nome)'?" -Texto 'O valor que existia antes do otimizador será restaurado.' -TextoOk 'Desfazer' -Dados @($id) -Acao { param($ids) Start-Execucao 'desfazer' $ids }
})

# ===============================================================
#  Ferramentas
# ===============================================================
$Script:FerPaineis = [ordered]@{
    RbFerRede = 'FerRede'; RbFerInicio = 'FerInicio'; RbFerServidor = 'FerServidor'; RbFerSerial = 'FerSerial'
    RbFerReparo = 'FerReparo'; RbFerProgramas = 'FerProgramas'; RbFerRelatorio = 'FerRelatorio'
    RbFerSuporte = 'FerSuporte'; RbFerTemp = 'FerTemp'; RbFerMonitor = 'FerMonitor'; RbFerManut = 'FerManut'; RbFerEspaco = 'FerEspaco'; RbFerProtecao = 'FerProtecao'; RbFerOffice = 'FerOffice'; RbFerAtalhos = 'FerAtalhos'
    RbFerJogo = 'FerJogo'; RbFerApps = 'FerApps'; RbFerFrota = 'FerFrota'; RbFerDesinstalar = 'FerDesinstalar'
}

function Show-Ferramenta([string]$Rb) {
    if (-not $UI[$Rb].IsChecked) { $UI[$Rb].IsChecked = $true; return }   # o evento Checked chama de novo
    $painel = $FerPaineis[$Rb]
    if ($painel -eq 'FerTemp') { Start-Temperaturas } else { Stop-Temperaturas }
    foreach ($p in $FerPaineis.Values) { if ($p -ne $painel) { $UI[$p].Visibility = 'Collapsed' } }
    $UI[$painel].Visibility = 'Visible'
    Start-Animacao $UI[$painel] ([Windows.UIElement]::OpacityProperty) 0 1 220
    if (-not $S.FerCarregado[$painel]) {
        $S.FerCarregado[$painel] = $true
        switch ($painel) {
            'FerRede'      { Update-Rede }
            'FerInicio'    { Update-Inicio }
            'FerSerial'    { Update-Serial }
            'FerProgramas' { Initialize-Winget }
            'FerEspaco'    { Update-Espaco; Update-ProgTam }
            'FerJogo'      { Update-Jogo }
            'FerApps'      { Update-Apps }
            'FerDesinstalar' { Update-Desinstalar }
            'FerFrota'     { if ($S.PastaFrota) { $UI.TxtFrotaPasta.Text = $S.PastaFrota; Update-Frota } }
            'FerManut'     { Initialize-Manut }
            'FerSuporte'   { Initialize-Suporte }
            'FerProtecao'  { Update-Protecao }
            'FerOffice'    { Update-Office }
            'FerAtalhos'   { Initialize-Atalhos }
        }
    }
}
foreach ($rb in $FerPaineis.Keys) { $UI[$rb].Add_Checked({ Show-Ferramenta $this.Name }) }

# ---------------- Rede e DNS ----------------
$S.DnsIps = @{ '1.1.1.1' = 'cloudflare'; '1.0.0.1' = 'cloudflare'; '8.8.8.8' = 'google'; '8.8.4.4' = 'google'; '9.9.9.9' = 'quad9'; '149.112.112.112' = 'quad9' }
$S.DnsRadios = @{ cloudflare = 'RbDnsCloudflare'; google = 'RbDnsGoogle'; quad9 = 'RbDnsQuad9'; auto = 'RbDnsAuto' }

function Update-Rede {
    $UI.BtnRedeAtualizar.IsEnabled = $false
    Start-Tarefa -Nome 'rede' -Script 'Get-AdaptadoresRede' -AoTerminar {
        param($saida, $erro)
        $UI.BtnRedeAtualizar.IsEnabled = $true
        $ads = @($saida | Where-Object { $_ -and $_.Nome })
        $UI.ListaAdaptadores.ItemsSource = [Otz.Linha[]]@(foreach ($a in $ads) {
            $ic = if ($a.Tipo -eq 'Wi-Fi') { G 0xE701 } else { G 0xE839 }
            New-Linha -Titulo "$($a.Nome)  ·  $($a.Velocidade)" -Texto "IP $($a.Ip)  ·  DNS $(if ($a.Dns) { $a.Dns } else { '-' })$(if (-not $a.DnsEstatico) { ' (automático)' })" -Icone $ic
        })
        $UI.TxtRedeVazia.Text = if ($erro) { "Não foi possível ler as conexões: $erro" } else { 'Nenhuma conexão ativa.' }
        $UI.TxtRedeVazia.Visibility = if ($ads.Count) { 'Collapsed' } else { 'Visible' }
        # Marca o DNS em uso
        $atual = 'auto'
        if ($ads.Count -and $ads[0].DnsEstatico) {
            $primeiro = ($ads[0].DnsEstatico -split '[,\s]+')[0]
            $atual = if ($S.DnsIps.ContainsKey($primeiro)) { $S.DnsIps[$primeiro] } else { '' }
        }
        if ($atual) { $UI[$S.DnsRadios[$atual]].IsChecked = $true }
        $S.DnsAtual = $atual
        $UI.BtnDnsAplicar.IsEnabled = $false
    }
}
$UI.BtnRedeAtualizar.Add_Click({ Update-Rede })

foreach ($k in $S.DnsRadios.Keys) {
    $UI[$S.DnsRadios[$k]].Add_Checked({ $S.DnsEscolhido = [string]$this.Tag; $UI.BtnDnsAplicar.IsEnabled = ($S.DnsEscolhido -ne $S.DnsAtual) })
}

$UI.BtnDnsAplicar.Add_Click({
    $nome = @{ cloudflare = 'Cloudflare'; google = 'Google'; quad9 = 'Quad9'; auto = 'Automático' }[$S.DnsEscolhido]
    Show-Dialogo -Titulo "Usar o DNS $nome?" -Texto 'Vale para todas as conexões ativas. O DNS atual fica guardado e pode ser restaurado em "Voltar ao DNS original". Em rede de empresa com servidor de domínio, prefira o Automático.' `
        -TextoOk 'Aplicar DNS' -Dados $S.DnsEscolhido -Acao {
            param($chave)
            $UI.BtnDnsAplicar.IsEnabled = $false
            Start-Tarefa -Nome 'dns-set' -Script 'Set-DnsServidores $Parametros.Chave' -Parametros @{ Chave = $chave } -AoTerminar {
                param($saida, $erro)
                if ($erro) { Show-Toast "Não foi possível trocar o DNS: $erro" 'erro' } else { Show-Toast 'DNS aplicado e cache limpo.' 'ok' }
                Update-Rede
            }
        }
})

$UI.BtnDnsRestaurar.Add_Click({
    Start-Tarefa -Nome 'dns-rest' -Script 'Restore-DnsOriginal' -AoTerminar {
        param($saida, $erro)
        if ($erro) { Show-Toast $erro 'info' } else { Show-Toast 'DNS original restaurado.' 'ok' }
        Update-Rede
    }
})

$UI.BtnDnsTestar.Add_Click({
    $UI.BtnDnsTestar.IsEnabled = $false
    $S.DnsTeste = New-Object 'System.Collections.ObjectModel.ObservableCollection[Otz.Linha]'
    $UI.ListaDnsTeste.ItemsSource = $S.DnsTeste
    foreach ($t in 'TxtDnsMsCloudflare', 'TxtDnsMsGoogle', 'TxtDnsMsQuad9', 'TxtDnsMsAuto') { $UI[$t].Text = '' }
    Show-Toast 'Testando 8 sites em cada DNS... leva uns 10 segundos.' 'info'
    Start-Tarefa -Nome 'dns-teste' -Script 'Test-VelocidadeDns | Out-Null' -AoEvento {
        param($ev)
        if ($ev.Tipo -ne 'dns') { return }
        $r = $ev.Resultado
        $txt = if ($null -ne $r.Ms) { "$($r.Ms) ms  ($($r.Respostas))" } else { 'sem resposta' }
        $larg = if ($null -ne $r.Ms) { [math]::Max(8, [math]::Min(420, 420 * $r.Ms / 200)) } else { 0 }
        $S.DnsTeste.Add((New-Linha -Titulo $r.Nome -Texto $txt -Valor $larg -Tag ([string]$r.Ms)))
        $alvo = switch -Wildcard ($r.Nome) { 'Cloudflare' { 'TxtDnsMsCloudflare' } 'Google' { 'TxtDnsMsGoogle' } 'Quad9' { 'TxtDnsMsQuad9' } 'Atual*' { if ($S.DnsAtual -eq 'auto') { 'TxtDnsMsAuto' } } }
        if ($alvo -and $null -ne $r.Ms) { $UI[$alvo].Text = "$($r.Ms) ms" }
    } -AoTerminar {
        $UI.BtnDnsTestar.IsEnabled = $true
        $validos = @($S.DnsTeste | Where-Object { $_.Tag -ne '' } | Sort-Object { [int]$_.Tag })
        if ($validos.Count) {
            $melhor = $validos[0]
            Show-Toast "Mais rápido aqui: $($melhor.Titulo) ($($melhor.Tag) ms). Barras menores = mais rápido." 'ok'
        } else { Show-Toast 'Nenhum DNS respondeu. Verifique a conexão.' 'erro' }
    }
})

$UI.BtnLimparDns.Add_Click({
    try { Clear-DnsClientCache -ErrorAction Stop; Write-Log 'Cache DNS limpo (Ferramentas).'; Show-Toast 'Cache de DNS limpo.' 'ok' }
    catch { Show-Toast "Falhou: $($_.Exception.Message)" 'erro' }
})

$UI.BtnResetRede.Add_Click({
    Show-Dialogo -Titulo 'Fazer o reset completo da rede?' -Tipo 'perigo' -TextoOk 'Fazer reset' `
        -Texto 'Executa "netsh winsock reset" e "netsh int ip reset". Use quando nada mais resolver. Depois é OBRIGATÓRIO reiniciar o PC. Redes Wi-Fi salvas continuam; VPNs podem precisar ser reconfiguradas.' `
        -Acao {
            Start-Tarefa -Nome 'reset-rede' -Script 'Reset-PilhaRede' -AoTerminar {
                param($saida, $erro)
                if ($erro) { Show-Toast "Falhou: $erro" 'erro'; return }
                Show-Dialogo -Titulo 'Reset feito. Reiniciar agora?' -Texto 'A rede só volta ao normal depois de reiniciar.' -TextoOk 'Reiniciar agora' -Tipo 'perigo' -Acao {
                    shutdown.exe /r /t 5 /c "Otimizador Vinicius: reiniciando após o reset de rede."
                }
            }
        }
})

# ---------------- Inicialização ----------------
function Update-Inicio {
    $itens = @(Get-ItensInicializacao | Sort-Object @{ e = { -not $_.Ativo } }, Nome)
    $col = New-Object 'System.Collections.ObjectModel.ObservableCollection[Otz.ItemInicio]'
    foreach ($i in $itens) {
        $v = [Otz.ItemInicio]::new()
        $v.Nome = $i.Nome; $v.Comando = $i.Comando; $v.Escopo = $i.Escopo; $v.Aprovado = $i.Aprovado; $v.Ativo = $i.Ativo
        $col.Add($v)
    }
    $S.Inicio = $col
    $UI.ListaInicio.ItemsSource = $col
    Update-InicioResumo
}

function Update-InicioResumo {
    $at = @($S.Inicio | Where-Object Ativo).Count
    $UI.TxtInicioResumo.Text = "$at de $($S.Inicio.Count) programas abrem junto com o Windows"
}

$UI.ListaInicio.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
    param($origem, $e)
    $cb = $e.OriginalSource
    if ($cb -isnot [Windows.Controls.CheckBox]) { return }
    $it = $cb.DataContext
    $novo = [bool]$cb.IsChecked
    try {
        Set-ItemInicializacao $it.Aprovado $it.Nome $novo
        Show-Toast $(if ($novo) { "'$($it.Nome)' volta a abrir com o Windows." } else { "'$($it.Nome)' não abre mais com o Windows." }) 'ok'
    } catch {
        $it.Ativo = -not $novo
        Show-Toast "Não foi possível alterar: $($_.Exception.Message)" 'erro'
    }
    Update-InicioResumo
})
$UI.BtnInicioAtualizar.Add_Click({ Update-Inicio })
$UI.BtnInicioGerTarefas.Add_Click({ Start-Process taskmgr.exe })

# ---------------- Testar servidor ----------------
$S.ServidorHist = New-Object 'System.Collections.ObjectModel.ObservableCollection[Otz.Linha]'
$UI.ListaServidorHist.ItemsSource = $S.ServidorHist

$UI.PainelPortas.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
    param($origem, $e)
    if ($e.OriginalSource.Tag) { $UI.TxtServidorPorta.Text = [string]$e.OriginalSource.Tag; [void]$UI.TxtServidorHost.Focus() }
})

function Start-TesteServidor {
    $h = $UI.TxtServidorHost.Text.Trim() -replace '^\w+://', '' -replace '/.*$', ''
    if ($h -match '^(.+):(\d+)$') { $h = $Matches[1]; $UI.TxtServidorPorta.Text = $Matches[2] }
    $p = 0
    if (-not $h) { Show-Toast 'Digite o endereço do servidor.' 'aviso'; [void]$UI.TxtServidorHost.Focus(); return }
    if (-not [int]::TryParse($UI.TxtServidorPorta.Text.Trim(), [ref]$p) -or $p -lt 1 -or $p -gt 65535) { Show-Toast 'Porta inválida: use um número de 1 a 65535.' 'aviso'; [void]$UI.TxtServidorPorta.Focus(); return }
    $UI.BtnServidorTestar.IsEnabled = $false
    Start-Tarefa -Nome 'tcp' -Script 'Test-PortaTcp -Servidor $Parametros.H -Porta $Parametros.P' -Parametros @{ H = $h; P = $p } -AoTerminar {
        param($saida, $erro)
        $UI.BtnServidorTestar.IsEnabled = $true
        if ($erro -or -not $saida) { Show-Toast "Falhou: $erro" 'erro'; return }
        $r = $saida[0]
        $UI.PainelServidorResultado.Visibility = 'Visible'
        if ($r.Ok) {
            $UI.IcoServidor.Text = G 0xE73E
            Set-Referencia $UI.IcoServidor ([Windows.Controls.TextBlock]::ForegroundProperty) 'Ok'
            Set-Referencia $UI.CirculoServidor ([Windows.Controls.Border]::BackgroundProperty) 'OkSuave'
            $UI.TxtServidorTitulo.Text = "$($r.Servidor):$($r.Porta) respondeu"
        } else {
            $UI.IcoServidor.Text = G 0xE711
            Set-Referencia $UI.IcoServidor ([Windows.Controls.TextBlock]::ForegroundProperty) 'Erro'
            Set-Referencia $UI.CirculoServidor ([Windows.Controls.Border]::BackgroundProperty) 'ErroSuave'
            $UI.TxtServidorTitulo.Text = "$($r.Servidor):$($r.Porta) não respondeu"
        }
        $det = $r.Mensagem
        if ($r.Ip) { $det += "`nIP: $($r.Ip)  ·  DNS resolveu em $($r.DnsMs) ms  ·  Ping: $($r.Ping)" }
        $UI.TxtServidorDetalhe.Text = $det
        Show-Entrada $UI.PainelServidorResultado
        $S.ServidorHist.Insert(0, (New-Linha -Titulo "$($r.Servidor):$($r.Porta)" -Texto $r.Mensagem -Nivel $(if ($r.Ok) { 'ok' } else { 'erro' }) -Extra (Get-Date -Format 'HH:mm:ss')))
        $UI.TxtServidorHistTitulo.Visibility = 'Visible'
        Write-Log "Teste TCP $($r.Servidor):$($r.Porta) = $($r.Mensagem)"
    }
}
$UI.BtnServidorTestar.Add_Click({ Start-TesteServidor })
foreach ($tb in 'TxtServidorHost', 'TxtServidorPorta') {
    $UI[$tb].Add_KeyDown({ param($origem, $e) if ($e.Key -eq 'Return') { Start-TesteServidor } })
}

# ---------------- Drivers e COM ----------------
function Update-Serial {
    $UI.BtnSerialAtualizar.IsEnabled = $false
    Start-Tarefa -Nome 'serial' -Script 'Get-StatusSerial' -AoTerminar {
        param($saida, $erro)
        $UI.BtnSerialAtualizar.IsEnabled = $true
        if ($erro -or -not $saida) { Show-Toast "Falhou: $erro" 'erro'; return }
        $r = $saida[0]
        $UI.ListaChips.ItemsSource = [Otz.Linha[]]@(foreach ($c in $r.Chips) {
            New-Linha -Titulo $c.Nome -Texto $(if ($c.Instalado) { 'Driver instalado' } else { 'Driver não instalado' }) -Nivel $(if ($c.Instalado) { 'ok' } else { 'info' }) -Tag $c.Url
        })
        $UI.ListaPortas.ItemsSource = [Otz.Linha[]]@(foreach ($p in $r.Portas) {
            $txt = @(); if ($p.Chip) { $txt += "Chip $($p.Chip)" }; if (-not $p.Ok) { $txt += "Status: $($p.Status)" }
            New-Linha -Titulo $p.Nome -Texto ($txt -join '  ·  ') -Nivel $(if ($p.Ok) { 'ok' } else { 'alto' })
        })
        $UI.TxtPortasVazio.Visibility = if (@($r.Portas).Count) { 'Collapsed' } else { 'Visible' }
        $UI.ListaUsbErro.ItemsSource = [Otz.Linha[]]@(foreach ($d in $r.Erros) { New-Linha -Titulo $d.Nome -Texto $d.Sugestao -Extra $d.Id -Nivel 'alto' })
        $UI.TxtUsbVazio.Visibility = if (@($r.Erros).Count) { 'Collapsed' } else { 'Visible' }
    }
}
$UI.BtnSerialAtualizar.Add_Click({ Update-Serial })
$UI.BtnSerialGerDisp.Add_Click({ Start-Process devmgmt.msc })
$UI.ListaChips.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
    param($origem, $e)
    if ($e.OriginalSource.Tag) { Start-Process explorer.exe ([string]$e.OriginalSource.Tag) }
})
$UI.BtnSerialInstalar.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Escolha a pasta do driver já extraído (onde estão os arquivos .inf)'
    if ($dlg.ShowDialog() -ne 'OK') { return }
    $UI.BtnSerialInstalar.IsEnabled = $false
    Show-Toast 'Instalando driver...' 'info'
    Start-Tarefa -Nome 'driver' -Script 'Install-DriverPasta $Parametros.Pasta' -Parametros @{ Pasta = $dlg.SelectedPath } -AoTerminar {
        param($saida, $erro)
        $UI.BtnSerialInstalar.IsEnabled = $true
        if ($erro) { Show-Dialogo -Titulo 'Não foi possível instalar' -Texto $erro -Tipo 'info' -SoOk -TextoOk 'Ok'; return }
        $r = $saida[0]
        Show-Dialogo -Titulo $(if ($r.Codigo -eq 0) { 'Driver instalado' } else { "pnputil terminou com código $($r.Codigo)" }) `
            -Texto "Desconecte e reconecte o cabo do equipamento.`n`n$($r.Saida)" -Tipo 'info' -SoOk -TextoOk 'Ok'
        Update-Serial
    }
})

# ---------------- Reparar Windows ----------------
function Start-Reparo([string]$Qual) {
    if (Test-TarefaAtiva 'reparo') { return }
    $cfg = if ($Qual -eq 'dism') {
        @{ Nome = 'DISM'; Arq = "$env:SystemRoot\System32\Dism.exe"; Args = '/Online /Cleanup-Image /RestoreHealth'; Cod = 'oem' }
    } else {
        @{ Nome = 'SFC'; Arq = "$env:SystemRoot\System32\sfc.exe"; Args = '/scannow'; Cod = 'unicode' }
    }
    $UI.BtnDism.IsEnabled = $false; $UI.BtnSfc.IsEnabled = $false
    $UI.LogReparo.Text = ''
    $UI.BarraReparo.BeginAnimation([Windows.Controls.Primitives.RangeBase]::ValueProperty, $null)
    $UI.BarraReparo.Value = 0
    $UI.TxtReparoPct.Text = ''
    $UI.TxtReparoStatus.Text = "Executando $($cfg.Nome)... pode levar vários minutos. Pode continuar usando o PC."
    $S.ReparoNome = $cfg.Nome
    Start-Tarefa -Nome 'reparo' -Script 'Invoke-ProcessoAoVivo -Arquivo $Parametros.Arq -Argumentos $Parametros.Args -Codificacao $Parametros.Cod' -Parametros $cfg -AoEvento {
        param($ev)
        switch ($ev.Tipo) {
            'log'       { $UI.LogReparo.AppendText($ev.Texto + "`r`n"); $UI.LogReparo.ScrollToEnd() }
            'progresso' { Start-Animacao $UI.BarraReparo ([Windows.Controls.Primitives.RangeBase]::ValueProperty) $null $ev.Valor 400; $UI.TxtReparoPct.Text = ('{0:N0}%' -f $ev.Valor) }
        }
    } -AoTerminar {
        param($saida, $erro)
        $UI.BtnDism.IsEnabled = $true; $UI.BtnSfc.IsEnabled = $true
        $cod = if ($saida) { [int]$saida[-1] } else { -1 }
        if ($erro) { $UI.TxtReparoStatus.Text = "$($S.ReparoNome) falhou: $erro" }
        elseif ($cod -eq 0) {
            $UI.TxtReparoStatus.Text = "$($S.ReparoNome) concluído. Leia as últimas linhas do log: elas dizem se algo foi encontrado e corrigido."
            Start-Animacao $UI.BarraReparo ([Windows.Controls.Primitives.RangeBase]::ValueProperty) $null 100 300
            $UI.TxtReparoPct.Text = '100%'
        } else { $UI.TxtReparoStatus.Text = "$($S.ReparoNome) terminou com código $cod. Veja o log abaixo; se pedir, reinicie e rode de novo." }
        Show-Toast "$($S.ReparoNome) terminou." $(if ($cod -eq 0) { 'ok' } else { 'aviso' })
    }
}
$UI.BtnDism.Add_Click({ Start-Reparo 'dism' })
$UI.BtnSfc.Add_Click({ Start-Reparo 'sfc' })

# ---------------- Programas (winget) ----------------
function Initialize-Winget {
    $S.Winget = (Get-Command winget -ErrorAction SilentlyContinue).Source
    $lista = @(Get-ListaWinget)
    $S.WingetLista = New-Object 'System.Collections.ObjectModel.ObservableCollection[Otz.Linha]'
    foreach ($p in $lista) { $S.WingetLista.Add((New-Linha -Titulo $p.Nome -Texto $p.Grupo -Tag $p.Id)) }
    $UI.ListaWinget.ItemsSource = $S.WingetLista
    # Agrupa os cartões por categoria (Grupo)
    $vw = [Windows.Data.CollectionViewSource]::GetDefaultView($S.WingetLista)
    $vw.GroupDescriptions.Clear()
    $vw.GroupDescriptions.Add((New-Object Windows.Data.PropertyGroupDescription 'Texto'))
    $propria = Test-Path (Join-Path $Script:SrcDir 'winget-lista.txt')
    $UI.TxtWingetFonte.Text = if ($propria) { 'Usando a sua lista (src\winget-lista.txt). Marque e clique em Instalar.' }
                              else { 'Lista padrão do otimizador. Para usar a sua, copie config\winget-lista-exemplo.txt para src\winget-lista.txt e edite.' }
    if (-not $S.Winget) {
        $UI.TxtWingetStatus.Text = 'winget não encontrado. Instale ou atualize o "Instalador de Aplicativo" pela Microsoft Store.'
        foreach ($b in 'BtnWingetInstalar', 'BtnWingetAtualizar', 'BtnWingetExportar', 'BtnWingetImportar') { $UI[$b].IsEnabled = $false }
    }
}

function Set-WingetOcupado([bool]$Ocupado) {
    foreach ($b in 'BtnWingetInstalar', 'BtnWingetAtualizar', 'BtnWingetExportar', 'BtnWingetImportar') { $UI[$b].IsEnabled = -not $Ocupado }
}

function Start-Winget([string]$Titulo, [string]$Script, [hashtable]$Parametros) {
    Set-WingetOcupado $true
    $UI.LogWinget.Text = ''
    $UI.BarraWinget.BeginAnimation([Windows.Controls.Primitives.RangeBase]::ValueProperty, $null)
    $UI.BarraWinget.Value = 0
    $UI.TxtWingetStatus.Text = $Titulo
    $Parametros.Winget = $S.Winget
    Start-Tarefa -Nome 'winget' -Script $Script -Parametros $Parametros -AoEvento {
        param($ev)
        switch ($ev.Tipo) {
            'log'       { $UI.LogWinget.AppendText($ev.Texto + "`r`n"); $UI.LogWinget.ScrollToEnd() }
            'progresso' { Start-Animacao $UI.BarraWinget ([Windows.Controls.Primitives.RangeBase]::ValueProperty) $null $ev.Valor 300 }
            'etapa'     { $UI.TxtWingetStatus.Text = $ev.Texto }
        }
    } -AoTerminar {
        param($saida, $erro)
        Set-WingetOcupado $false
        Start-Animacao $UI.BarraWinget ([Windows.Controls.Primitives.RangeBase]::ValueProperty) $null 100 300
        $UI.TxtWingetStatus.Text = if ($erro) { "Falhou: $erro" } else { "Concluído. $(@($saida) -join ' ')" }
        Show-Toast 'winget terminou. Veja o resultado no log.' $(if ($erro) { 'erro' } else { 'ok' })
    }
}

$UI.BtnWingetInstalar.Add_Click({
    $ids = @($S.WingetLista | Where-Object Marcado | ForEach-Object { @{ Id = $_.Tag; Nome = $_.Titulo } })
    if ($ids.Count -eq 0) { Show-Toast 'Marque pelo menos um programa.' 'aviso'; return }
    Start-Winget "Instalando $($ids.Count) programa(s)..." @'
$ok = 0; $n = 0; $total = $Parametros.Itens.Count
foreach ($i in $Parametros.Itens) {
    $n++
    Send-Evento @{ Tipo = 'etapa'; Texto = "($n de $total) Instalando $($i.Nome)..." }
    Send-Evento @{ Tipo = 'log'; Texto = "===== $($i.Nome) ($($i.Id)) =====" }
    $c = Invoke-ProcessoAoVivo -Arquivo $Parametros.Winget -Argumentos "install --id $($i.Id) -e --silent --accept-source-agreements --accept-package-agreements" -Codificacao utf8
    if ($c -eq 0) { $ok++ } else { Send-Evento @{ Tipo = 'log'; Texto = "$($i.Nome): código $c (pode já estar instalado ou o ID mudou: confira com winget search)" } }
    Send-Evento @{ Tipo = 'progresso'; Valor = (100 * $n / $total) }
}
"$ok de $total instalado(s) com sucesso."
'@ @{ Itens = $ids }
})

$UI.BtnWingetAtualizar.Add_Click({
    Show-Dialogo -Titulo 'Atualizar todos os programas?' -Texto 'O winget vai baixar e instalar as versões novas de tudo o que ele reconhecer. Pode demorar e alguns programas podem fechar durante a atualização.' -TextoOk 'Atualizar tudo' -Acao {
        Start-Winget 'Atualizando programas...' 'Invoke-ProcessoAoVivo -Arquivo $Parametros.Winget -Argumentos "upgrade --all --silent --accept-source-agreements --accept-package-agreements" -Codificacao utf8 | Out-Null' @{}
    }
})

$UI.BtnWingetExportar.Add_Click({
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.FileName = "programas-$($env:COMPUTERNAME).json"
    $dlg.InitialDirectory = $Otz.Dados
    $dlg.Filter = 'Lista do winget (*.json)|*.json'
    if (-not $dlg.ShowDialog()) { return }
    Start-Winget 'Exportando a lista de programas...' 'Invoke-ProcessoAoVivo -Arquivo $Parametros.Winget -Argumentos ("export -o `"" + $Parametros.Arq + "`" --accept-source-agreements") -Codificacao utf8 | Out-Null; "Lista salva em " + $Parametros.Arq' @{ Arq = $dlg.FileName }
})

$UI.BtnWingetImportar.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.InitialDirectory = $Otz.Dados
    $dlg.Filter = 'Lista do winget (*.json)|*.json'
    if (-not $dlg.ShowDialog()) { return }
    Start-Winget 'Instalando os programas da lista...' 'Invoke-ProcessoAoVivo -Arquivo $Parametros.Winget -Argumentos ("import -i `"" + $Parametros.Arq + "`" --ignore-unavailable --accept-source-agreements --accept-package-agreements") -Codificacao utf8 | Out-Null' @{ Arq = $dlg.FileName }
})

# ---------------- Relatório ----------------
function Start-Relatorio {
    if (Test-TarefaAtiva 'relatorio') { return }
    $UI.BtnRelatorioGerar.IsEnabled = $false
    $UI.TxtRelatorioStatus.Text = 'Coletando informações (10 a 20 segundos)...'
    Show-Toast 'Gerando o relatório do PC...' 'info'
    Start-Tarefa -Nome 'relatorio' -Script 'New-RelatorioPC' -AoTerminar {
        param($saida, $erro)
        $UI.BtnRelatorioGerar.IsEnabled = $true
        if ($erro -or -not $saida) { $UI.TxtRelatorioStatus.Text = "Falhou: $erro"; Show-Toast "Relatório falhou: $erro" 'erro'; return }
        $arq = [string]$saida[-1]
        $UI.TxtRelatorioStatus.Text = "Salvo em: $arq"
        Write-Log "Relatório: $arq"
        Start-Process explorer.exe "`"$arq`""
        Show-Toast 'Relatório aberto no navegador.' 'ok'
    }
}
$UI.BtnRelatorioGerar.Add_Click({ Start-Relatorio })
$UI.BtnRelatorioPasta.Add_Click({ Start-Process explorer.exe "`"$($Otz.Dados)`"" })

# ---------------- Proteção (antivírus) ----------------
function Update-Protecao {
    $UI.BtnProtAtualizar.IsEnabled = $false
    Start-Tarefa -Nome 'protecao' -Script 'Get-InfoAntivirus; @{ Excl = @(Get-DefenderExclusoes); Pausada = (Test-ProtecaoPausada) }' -AoTerminar {
        param($saida, $erro)
        $UI.BtnProtAtualizar.IsEnabled = $true
        if ($erro -or -not $saida) { $UI.TxtProtTitulo.Text = 'Não foi possível ler a proteção'; $UI.TxtProtDetalhe.Text = [string]$erro; return }
        $av = $saida | Where-Object { $_.Lista } | Select-Object -First 1
        $extra = $saida | Where-Object { $_.Excl -ne $null -or $_.Pausada -ne $null } | Select-Object -First 1
        $S.Av = $av

        $protegido = $true; $nome = 'Microsoft Defender'; $det = ''
        if ($av.TemTerceiro) {
            $nome = $av.Terceiros[0].Nome
            $det = 'Antivírus de outro fabricante no comando. Para pausar, use a janela dele (ícone ao lado do relógio). O otimizador não mexe em antivírus de terceiros.'
            $protegido = $av.Terceiros[0].Ligado
        } elseif ($av.Defender -and $av.Defender.Presente) {
            $protegido = $av.Defender.RealTime
            $tp = if ($av.Defender.TamperProtegido) { 'Proteção contra adulteração: ligada' } else { 'Proteção contra adulteração: desligada' }
            $det = if ($av.Defender.RealTime) { "Proteção em tempo real ligada.  ·  $tp" } else { "Proteção em tempo real DESLIGADA.  ·  $tp" }
        } else {
            $nome = 'Proteção'; $det = 'Não foi possível falar com o Defender.'
        }
        $UI.TxtProtTitulo.Text = if ($protegido) { "$nome protegendo o PC" } else { "$nome com a proteção desligada" }
        $UI.TxtProtDetalhe.Text = $det
        $UI.IcoProt.Text = if ($protegido) { G 0xE72E } else { G 0xE7BA }
        Set-Referencia $UI.IcoProt ([Windows.Controls.TextBlock]::ForegroundProperty) $(if ($protegido) { 'Ok' } else { 'Aviso' })
        Set-Referencia $UI.CirculoProt ([Windows.Controls.Border]::BackgroundProperty) $(if ($protegido) { 'OkSuave' } else { 'AvisoSuave' })

        # Botão Pausar: habilitado só quando dá para agir por script (Defender, tamper OFF, sem terceiro)
        $podePausar = $av.Defender -and $av.Defender.Presente -and -not $av.Defender.TamperProtegido -and -not $av.TemTerceiro
        $UI.BtnProtPausar.IsEnabled = $podePausar -and $protegido
        $UI.TxtProtPausarNota.Visibility = if ($podePausar) { 'Collapsed' } else { 'Visible' }
        $UI.TxtProtPausarNota.Text = if ($av.TemTerceiro) { "Seu antivírus ($nome) é de outro fabricante: pause pela janela dele." }
                                     elseif ($av.Defender -and $av.Defender.TamperProtegido) { 'Bloqueado pela Proteção contra Adulteração. Use o botão "Proteção contra adulteração" abaixo para desligá-la primeiro.' }
                                     else { 'Não é possível pausar por programa neste PC.' }

        $pausada = $extra -and $extra.Pausada -and -not $protegido
        $UI.BannerProtPausada.Visibility = if ($pausada) { 'Visible' } else { 'Collapsed' }
        if ($pausada) { $UI.TxtProtPausadaSub.Text = 'Reative assim que terminar de instalar o programa. Nunca navegue com a proteção desligada.' }

        $excl = @(); if ($extra) { $excl = @($extra.Excl) }
        $UI.ListaExclusoes.ItemsSource = ConvertTo-Linhas @($excl | Where-Object { $_ } | ForEach-Object { New-Linha -Titulo $_ })
    }
}
$UI.BtnProtAtualizar.Add_Click({ Update-Protecao })

$S.TimerProt = New-Object Windows.Threading.DispatcherTimer
$S.TimerProt.Add_Tick({ $S.TimerProt.Stop(); Invoke-ReativarProtecao 'O tempo acabou' })

function Invoke-PausarProtecao {
    Start-Tarefa -Nome 'prot-pausar' -Script 'Suspend-Defender' -AoTerminar {
        param($saida, $erro)
        $r = if ($saida) { $saida[0] } else { @{ Status = 'bloqueado'; Mensagem = [string]$erro } }
        if ($r.Status -eq 'ok') {
            Show-Toast $r.Mensagem 'aviso'
            $min = [int]([string]$UI.CbProtTempo.SelectedItem.Tag)
            if ($min -gt 0) {
                $S.TimerProt.Interval = [TimeSpan]::FromMinutes($min)
                $S.TimerProt.Start()
                Show-Toast "A proteção volta sozinha em $min minutos." 'info'
            }
        } elseif ($r.Status -eq 'bloqueado') {
            Show-Dialogo -Titulo 'O Windows não deixa pausar por programa' -Texto $r.Mensagem -Tipo 'info' -TextoOk 'Abrir Segurança do Windows' -SoOk -Acao { Start-Process 'windowsdefender://threatsettings' }
        } else {
            Show-Dialogo -Titulo 'Antivírus de outro fabricante' -Texto $r.Mensagem -Tipo 'info' -SoOk -TextoOk 'Entendi'
        }
        Update-Protecao
    }
}

function Invoke-ReativarProtecao([string]$Motivo = '') {
    $S.TimerProt.Stop()
    Start-Tarefa -Nome 'prot-reativar' -Script 'Resume-Defender' -AoTerminar {
        param($saida, $erro)
        $r = if ($saida) { $saida[0] } else { @{ Status = 'aviso'; Mensagem = [string]$erro } }
        Show-Toast $r.Mensagem $(if ($r.Status -eq 'ok') { 'ok' } else { 'aviso' })
        Update-Protecao
    }
}

$UI.BtnProtPausar.Add_Click({
    Show-Dialogo -Titulo 'Pausar a proteção contra vírus?' -Tipo 'perigo' -TextoOk 'Pausar proteção' `
        -Texto 'Só faça isso para instalar um programa que você CONFIA e que o antivírus bloqueia por engano. Não baixe nada nem navegue enquanto estiver pausado.' `
        -Linhas @((New-Linha -Titulo 'Pausa só a proteção em tempo real' -Texto 'O resto do Windows continua funcionando.' -Nivel 'info'), (New-Linha -Titulo 'Lembre de reativar' -Texto 'O otimizador avisa e pode reativar sozinho no tempo escolhido.' -Nivel 'info')) `
        -Acao { Invoke-PausarProtecao }
})
$UI.BtnProtReativarTopo.Add_Click({ Invoke-ReativarProtecao })
$UI.BtnProtAbrirSeg.Add_Click({ try { Start-Process 'windowsdefender://threat' } catch { Start-Process 'windowsdefender:' } })
$UI.BtnProtAbrirTamper.Add_Click({ try { Start-Process 'windowsdefender://threatsettings' } catch { Start-Process 'windowsdefender:' } })
$UI.BtnProtExcluir.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Escolha a pasta que o antivírus deve confiar (ex.: onde está o instalador)'
    if ($dlg.ShowDialog() -ne 'OK') { return }
    $pasta = $dlg.SelectedPath
    Start-Tarefa -Nome 'prot-excluir' -Script 'Add-DefenderExclusao $Parametros.P' -Parametros @{ P = $pasta } -AoTerminar {
        param($saida, $erro)
        if ($erro) { Show-Toast "Não foi possível liberar: $erro" 'erro' } else { Show-Toast 'Pasta liberada. Lembre de remover depois.' 'ok' }
        Update-Protecao
    }
})
$UI.ListaExclusoes.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
    param($origem, $e)
    $pasta = [string]$e.OriginalSource.Tag
    if (-not $pasta) { return }
    Start-Tarefa -Nome 'prot-incluir' -Script 'Remove-DefenderExclusao $Parametros.P' -Parametros @{ P = $pasta } -AoTerminar {
        param($saida, $erro)
        if ($erro) { Show-Toast "Falhou: $erro" 'erro' } else { Show-Toast 'Pasta volta a ser verificada pelo antivírus.' 'ok' }
        Update-Protecao
    }
})

# ---------------- Desinstalar Office ----------------
function Update-Office {
    $UI.BtnOfficeAtualizar.IsEnabled = $false
    Start-Tarefa -Nome 'office' -Script 'Get-OfficeInstalado' -AoTerminar {
        param($saida, $erro)
        $UI.BtnOfficeAtualizar.IsEnabled = $true
        $itens = @($saida | Where-Object { $_ -and $_.Nome })
        $S.OfficeItens = $itens
        $UI.ListaOffice.ItemsSource = ConvertTo-Linhas @($itens | ForEach-Object { New-Linha -Titulo $_.Nome -Texto $_.Versao -Tag $_.Tipo })
        $UI.TxtOfficeVazio.Visibility = if ($itens.Count) { 'Collapsed' } else { 'Visible' }
        $UI.BtnOfficeDesinstalar.IsEnabled = ($itens.Count -gt 0)
        $UI.TxtOfficeResumo.Text = if ($itens.Count) { "$($itens.Count) produto(s) do Office encontrados neste PC." } else { 'Nenhum Office instalado. Nada a remover.' }
    }
}
$UI.BtnOfficeAtualizar.Add_Click({ Update-Office })
$UI.BtnOfficeDesinstalar.Add_Click({
    if (-not $S.OfficeItens -or $S.OfficeItens.Count -eq 0) { return }
    $linhas = @($S.OfficeItens | ForEach-Object { New-Linha -Titulo $_.Nome -Nivel 'alto' })
    Show-Dialogo -Titulo 'Desinstalar o Office completamente?' -Tipo 'perigo' -TextoOk 'Desinstalar' `
        -Texto 'O Office inteiro será removido deste PC. Seus arquivos (.docx, .xlsx, .pptx) continuam salvos. Feche Word, Excel e Outlook antes de continuar.' `
        -Linhas $linhas -Acao { Start-DesinstalarOffice }
})

function Start-DesinstalarOffice {
    if (Test-TarefaAtiva 'office-rm') { return }
    $UI.BtnOfficeDesinstalar.IsEnabled = $false
    $UI.LogOffice.Text = ''
    $UI.BarraOffice.Value = 0
    $UI.TxtOfficeStatus.Text = 'Desinstalando o Office... pode levar alguns minutos e uma janela da Microsoft pode aparecer.'
    Start-Tarefa -Nome 'office-rm' -Script @'
$itens = $Parametros.Itens
$n = 0; $falhas = 0
foreach ($i in $itens) {
    $n++
    Send-Evento @{ Tipo = 'etapa'; Texto = "($n de $($itens.Count)) Removendo $($i.Nome)..." }
    Send-Evento @{ Tipo = 'log'; Texto = "===== $($i.Nome) =====" }
    $c = Uninstall-OfficeItem $i
    if ($c -ne 0 -and $null -ne $c) { $falhas++; Send-Evento @{ Tipo = 'log'; Texto = "Codigo de saida: $c" } }
    Send-Evento @{ Tipo = 'progresso'; Valor = (100 * $n / $itens.Count) }
}
"$($itens.Count - $falhas) de $($itens.Count) removido(s)."
'@ -Parametros @{ Itens = $S.OfficeItens } -AoEvento {
        param($ev)
        switch ($ev.Tipo) {
            'log'       { $UI.LogOffice.AppendText($ev.Texto + "`r`n"); $UI.LogOffice.ScrollToEnd() }
            'etapa'     { $UI.TxtOfficeStatus.Text = $ev.Texto }
            'progresso' { Start-Animacao $UI.BarraOffice ([Windows.Controls.Primitives.RangeBase]::ValueProperty) $null $ev.Valor 400 }
        }
    } -AoTerminar {
        param($saida, $erro)
        $UI.BtnOfficeDesinstalar.IsEnabled = $true
        Start-Animacao $UI.BarraOffice ([Windows.Controls.Primitives.RangeBase]::ValueProperty) $null 100 300
        $UI.TxtOfficeStatus.Text = if ($erro) { "Falhou: $erro" } else { "Concluído. $(@($saida) -join ' ') Reinicie o PC para terminar a limpeza." }
        Show-Toast 'Desinstalação do Office concluída. Veja o log.' $(if ($erro) { 'erro' } else { 'ok' })
        Update-Office
    }
}

# ---------------- Atalhos ----------------
function Initialize-Atalhos {
    $at = @(
        ,@(0xE9F5, 'Gerenciador de Tarefas', 'Programas abertos, desempenho e inicialização', 'taskmgr')
        ,@(0xE772, 'Gerenciador de Dispositivos', 'Drivers, portas COM e dispositivos com erro', 'devmgmt')
        ,@(0xE968, 'Conexões de rede', 'Placas de rede, IP fixo e adaptadores', 'ncpa')
        ,@(0xE74D, 'Limpeza de Disco', 'Limpeza do Windows (inclui arquivos do sistema)', 'cleanmgr')
        ,@(0xEC4A, 'Efeitos visuais', 'Ajuste fino das animações e sombras', 'efeitos')
        ,@(0xE81C, 'Restauração do sistema', 'Voltar o Windows para um ponto anterior', 'rstrui')
        ,@(0xEDA2, 'Gerenciamento de disco', 'Partições, letras de unidade, formatar', 'diskmgmt')
        ,@(0xE9D9, 'Monitor de recursos', 'Quem está usando disco, rede e memória', 'resmon')
        ,@(0xE8F1, 'Programas instalados', 'Desinstalar programas (Painel de Controle)', 'appwiz')
        ,@(0xE713, 'Variáveis de ambiente', 'PATH e variáveis do sistema', 'envvars')
        ,@(0xE7BA, 'Visualizador de Eventos', 'Erros e avisos registrados pelo Windows', 'eventvwr')
        ,@(0xE946, 'Informações do sistema', 'Detalhes de hardware e drivers (msinfo32)', 'msinfo')
        ,@(0xE83F, 'Relatório de bateria', 'Capacidade e desgaste (notebooks)', 'bateria')
        ,@(0xE895, 'Reiniciar o Explorer', 'Destrava barra de tarefas e área de trabalho', 'explorer')
        ,@(0xE8A7, 'Pasta do otimizador', 'Logs, valores originais e relatórios', 'dados')
    )
    $UI.ListaAtalhos.ItemsSource = [Otz.Linha[]]@(foreach ($a in $at) { New-Linha -Icone (G $a[0]) -Titulo $a[1] -Texto $a[2] -Tag $a[3] })
}

$UI.ListaAtalhos.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
    param($origem, $e)
    $btn = $e.OriginalSource
    try {
        switch ([string]$btn.Tag) {
            'taskmgr'  { Start-Process taskmgr.exe }
            'devmgmt'  { Start-Process devmgmt.msc }
            'ncpa'     { Start-Process control.exe -ArgumentList 'ncpa.cpl' }
            'cleanmgr' { Start-Process cleanmgr.exe }
            'efeitos'  { Start-Process SystemPropertiesPerformance.exe }
            'rstrui'   { Start-Process rstrui.exe }
            'diskmgmt' { Start-Process diskmgmt.msc }
            'resmon'   { Start-Process resmon.exe }
            'appwiz'   { Start-Process control.exe -ArgumentList 'appwiz.cpl' }
            'envvars'  { Start-Process rundll32.exe -ArgumentList 'sysdm.cpl,EditEnvironmentVariables' }
            'eventvwr' { Start-Process eventvwr.msc }
            'msinfo'   { Start-Process msinfo32.exe }
            'explorer' { Restart-Explorer; Show-Toast 'Explorer reiniciado.' 'ok' }
            'dados'    { Start-Process explorer.exe "`"$($Otz.Dados)`"" }
            'bateria'  {
                $arq = Join-Path $Otz.Dados 'relatorio-bateria.html'
                $saida = powercfg /batteryreport /output "$arq" 2>&1
                if ($LASTEXITCODE -eq 0 -and (Test-Path $arq)) { Start-Process explorer.exe "`"$arq`"" }
                else { Show-Toast "Sem bateria ou não foi possível gerar: $($saida -join ' ')" 'aviso' }
            }
        }
    } catch { Show-Toast "Não foi possível abrir: $($_.Exception.Message)" 'erro' }
})

# ===============================================================
#  Páginas com lista própria de ajustes (Placa de vídeo, Notebook, Serviços)
#  As listas reaproveitam os MESMOS objetos do Otimizar: marcar aqui
#  marca lá, e o estado (Aplicado/Pendente) fica sempre igual.
# ===============================================================
$S.PaginasAjustes = [ordered]@{
    gpu  = @{ Lista = 'ListaGpuAjustes';  Txt = 'TxtGpuSelecao';  Sim = 'BtnGpuSimular';  Apl = 'BtnGpuAplicar';  Col = $null }
    note = @{ Lista = 'ListaNoteAjustes'; Txt = 'TxtNoteSelecao'; Sim = 'BtnNoteSimular'; Apl = 'BtnNoteAplicar'; Col = $null }
    serv = @{ Lista = 'ListaServAjustes'; Txt = 'TxtServSelecao'; Sim = 'BtnServSimular'; Apl = 'BtnServAplicar'; Col = $null }
}
$filtrosPagina = @{
    gpu  = { param($a) $a.Categoria -eq 'Placa de vídeo' -or @($a.Perfis | Where-Object { $_ -like 'gpu-*' }).Count -gt 0 }
    note = { param($a) $a.Categoria -eq 'Notebook e bateria' }
    serv = { param($a) $a.Categoria -eq 'Serviços em segundo plano' }
}
foreach ($k in @($S.PaginasAjustes.Keys)) {
    $p = $S.PaginasAjustes[$k]
    $col = New-Object 'System.Collections.ObjectModel.ObservableCollection[Otz.Ajuste]'
    $itens = @($S.Ajustes | Where-Object { & $filtrosPagina[$k] $_ } | Sort-Object @{ e = { $_.Categoria -ne 'Placa de vídeo' } }, Ordem)
    foreach ($a in $itens) { $col.Add($a) }
    $p.Col = $col
    $UI[$p.Lista].ItemsSource = $col
    $UI[$p.Sim].Tag = $k
    $UI[$p.Apl].Tag = $k
    $UI[$p.Lista].AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
        param($origem, $e)
        if ($e.OriginalSource -is [Windows.Controls.CheckBox]) { Update-Rodape }
    })
    $UI[$p.Sim].Add_Click({ Start-Execucao 'simular' @(Get-SelecaoPagina ([string]$this.Tag) | ForEach-Object Id) })
    $UI[$p.Apl].Add_Click({ Request-Aplicar @(Get-SelecaoPagina ([string]$this.Tag)) })
}

function Get-SelecaoPagina([string]$Chave) { return @($S.PaginasAjustes[$Chave].Col | Where-Object Selecionado) }

function Update-RodapePagina([string]$Chave) {
    $p = $S.PaginasAjustes[$Chave]
    if (-not $p.Col) { return }
    $sel = @(Get-SelecaoPagina $Chave)
    $n = $sel.Count
    $txt = switch ($n) { 0 { 'Nenhum ajuste selecionado' } 1 { '1 ajuste selecionado' } default { "$n ajustes selecionados" } }
    $r = @($sel | Where-Object Reinicio -eq 'reiniciar').Count
    if ($r) { $txt += "  ·  $r só vale(m) após reiniciar" }
    $UI[$p.Txt].Text = $txt
    $UI[$p.Sim].IsEnabled = ($n -gt 0)
    $UI[$p.Apl].IsEnabled = ($n -gt 0)
}

# Marca na página os itens pendentes de um perfil; devolve quantos marcou
function Select-PerfilPagina([string]$Chave, [string]$Perfil) {
    $n = 0
    foreach ($a in $S.PaginasAjustes[$Chave].Col) {
        $a.Selecionado = $a.Habilitado -and $a.Risco -ne 'avancado' -and ($a.Perfis -contains $Perfil) -and $a.Estado -ne 'aplicado'
        if ($a.Selecionado) { $n++ }
    }
    Update-Rodape
    return $n
}

# ---------------- Placa de vídeo ----------------
$S.ModosGpu = @{
    desempenho = 'Desempenho máximo: o Windows prioriza o jogo, sem gravação em segundo plano, com energia e PCI Express no máximo e o monitor na taxa máxima.'
    balanceado = 'Balanceado: Modo de Jogo, HAGS, taxa variável (VRR) e monitor na taxa máxima, sem mexer no visual do Windows.'
    qualidade  = 'Qualidade: HAGS, HDR automático e otimizações para jogos em janela. O visual vem em primeiro lugar.'
}

function Set-ModoGpu([string]$Modo) {
    $S.ModoGpu = $Modo
    $n = Select-PerfilPagina 'gpu' "gpu-$Modo"
    $UI.TxtGpuModoDesc.Text = $S.ModosGpu[$Modo] + $(if ($n) { "  $n ajuste(s) marcado(s): revise e aplique." } else { '  Tudo deste modo já está aplicado neste PC.' })
    Update-PainelGpu
}
foreach ($rb in 'RbGpuDesempenho', 'RbGpuBalanceado', 'RbGpuQualidade') { $UI[$rb].Add_Checked({ Set-ModoGpu ([string]$this.Tag) }) }

function Update-PainelGpu {
    $fab = 'outra'
    if ($S.Gpu -and $S.Gpu.Principal) { $fab = $S.Gpu.Principal.Fabricante }
    $modo = if ($S.ModoGpu) { $S.ModoGpu } else { 'balanceado' }
    $onde = @{ nvidia = 'Painel de Controle NVIDIA > Gerenciar as configurações 3D'; amd = 'AMD Software: Adrenalin Edition > Jogos > Gráficos'; intel = 'Intel Graphics Software'; outra = 'Programa do fabricante da placa' }[$fab]
    $linhas = New-Object System.Collections.Generic.List[object]
    $linhas.Add((New-Linha -Titulo 'Onde fica' -Texto $onde -Extra '>'))
    $i = 0
    foreach ($d in Get-DicasPainelGpu $fab $modo) { $i++; $linhas.Add((New-Linha -Titulo $d.Opcao -Texto $d.Valor -Extra ([string]$i))) }
    $UI.ListaGpuPainel.ItemsSource = ConvertTo-Linhas $linhas
}

function Update-Gpu {
    $S.GpuCarregada = $true
    Start-Tarefa -Nome 'gpu' -Script 'Get-InfoGpu' -AoTerminar {
        param($saida, $erro)
        if ($erro -or -not $saida) { $UI.TxtGpuNome.Text = 'Não foi possível ler a placa de vídeo'; $UI.TxtGpuDetalhe.Text = [string]$erro; return }
        $g = $saida[0]
        $S.Gpu = $g
        $p = $g.Principal
        $UI.TxtGpuNome.Text = $p.Nome
        $partes = New-Object System.Collections.Generic.List[string]
        if ($p.VramGB) { $partes.Add("$($p.VramGB) GB de memória de vídeo") }
        if ($p.Driver) {
            $txtDriver = "driver $($p.Driver)"
            if ($p.DriverData) { $txtDriver += " de $($p.DriverData.ToString('dd/MM/yyyy'))" }
            if ($null -ne $p.DriverDias) { $txtDriver += " (há $($p.DriverDias) dias)" }
            $partes.Add($txtDriver)
        }
        $outras = @($g.Placas | Where-Object { $_.Nome -ne $p.Nome } | ForEach-Object Nome)
        if ($outras.Count) { $partes.Add("também: $($outras -join ', ')") }
        $UI.TxtGpuDetalhe.Text = $partes -join '  ·  '

        $S.PainelGpu = ''
        if ($p.Fabricante -eq 'nvidia' -and $g.PainelNvidiaCp) { $S.PainelGpu = 'nvcp'; $UI.TxtGpuPainel.Text = 'Abrir painel NVIDIA' }
        elseif ($p.Fabricante -eq 'nvidia' -and $g.PainelNvidiaApp) { $S.PainelGpu = 'nvapp'; $UI.TxtGpuPainel.Text = 'Abrir NVIDIA App' }
        elseif ($p.Fabricante -eq 'amd' -and $g.PainelAmd) { $S.PainelGpu = 'amd'; $UI.TxtGpuPainel.Text = 'Abrir AMD Software' }
        $UI.BtnGpuPainel.Visibility = if ($S.PainelGpu) { 'Visible' } else { 'Collapsed' }

        $UI.PainelMonitores.Children.Clear()
        $n = 0
        foreach ($m in $g.Monitores) {
            $n++
            $txt = "Monitor $n  ·  $($m.Largura)x$($m.Altura)  ·  $($m.Hz) Hz"
            $txt += if ($m.Hz -lt $m.HzMaximo) { "  (aceita $($m.HzMaximo) Hz!)" } else { '  ·  no máximo' }
            [void]$UI.PainelMonitores.Children.Add((New-Chip 0xE7F4 $txt $m.Dispositivo))
        }
        Update-PainelGpu
    }
    Update-AppsGpu
}

$UI.BtnGpuPainel.Add_Click({
    try {
        switch ($S.PainelGpu) {
            'nvcp'  { Start-Process explorer.exe 'shell:AppsFolder\NVIDIACorp.NVIDIAControlPanel_56jybvy8sckqj!NVIDIACorp.NVIDIAControlPanel' }
            'nvapp' { Start-Process "$env:ProgramFiles\NVIDIA Corporation\NVIDIA App\CEF\NVIDIA App.exe" }
            'amd'   { Start-Process "$env:ProgramFiles\AMD\CNext\CNext\RadeonSoftware.exe" }
        }
    } catch { Show-Toast "Não foi possível abrir: $($_.Exception.Message)" 'erro' }
})
$UI.BtnGpuDriver.Add_Click({
    $fab = if ($S.Gpu) { $S.Gpu.Principal.Fabricante } else { '' }
    if ($SitesDriver.ContainsKey($fab)) { Start-Process explorer.exe $SitesDriver[$fab] }
    else { Show-Toast 'Fabricante não identificado. Procure o driver no site do fabricante da placa ou do notebook.' 'info' }
})

function Update-AppsGpu {
    $prefs = @{ 0 = 'Windows decide'; 1 = 'Economia de energia'; 2 = 'Alto desempenho' }
    $apps = @(Get-AppsGpu)
    $UI.ListaGpuApps.ItemsSource = [Otz.Linha[]]@(foreach ($a in $apps) { New-Linha -Titulo $a.Nome -Texto $prefs[[int]$a.Preferencia] -Tag $a.Caminho })
    $UI.TxtGpuAppsVazio.Visibility = if ($apps.Count) { 'Collapsed' } else { 'Visible' }
}
$UI.BtnGpuAddApp.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'Programas (*.exe)|*.exe'
    $dlg.Title = 'Escolha o jogo ou programa que deve usar a placa de vídeo mais forte'
    if (-not $dlg.ShowDialog()) { return }
    try {
        Set-AppGpu $dlg.FileName 2
        Update-AppsGpu
        Show-Toast "$([IO.Path]::GetFileName($dlg.FileName)) vai usar a placa de alto desempenho (vale na próxima vez que abrir)." 'ok'
    } catch { Show-Toast "Falhou: $($_.Exception.Message)" 'erro' }
})
$UI.ListaGpuApps.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
    param($origem, $e)
    $caminho = [string]$e.OriginalSource.Tag
    if (-not $caminho) { return }
    Remove-AppGpu $caminho
    Update-AppsGpu
    Show-Toast "$([IO.Path]::GetFileName($caminho)) volta a usar a escolha do Windows." 'ok'
})

# ---------------- Notebook ----------------
function Update-Bateria {
    $S.BateriaCarregada = $true
    $UI.BannerDesktop.Visibility = if (Test-Notebook) { 'Collapsed' } else { 'Visible' }
    Start-Tarefa -Nome 'bateria' -Script 'Get-InfoBateria' -AoTerminar {
        param($saida, $erro)
        $b = $null
        if ($saida) { $b = $saida[0] }
        if (-not $b) {
            $UI.TxtBatSaude.Text = '–'
            $UI.TxtBatSaudeSub.Text = 'Este PC não tem bateria.'
            $UI.TxtBatDetalhe.Text = 'Num notebook, aqui aparece quanto a bateria ainda guarda em relação a quando era nova.'
            $UI.BtnBatRelatorio.IsEnabled = $false
            return
        }
        if ($null -ne $b.Saude) {
            $UI.TxtBatSaude.Text = "$($b.Saude)%"
            $UI.TxtBatSaudeSub.Text = 'da capacidade original. ' + $(if ($b.Saude -ge 80) { 'Bateria em bom estado.' } elseif ($b.Saude -ge 60) { 'Desgaste normal com o tempo.' } else { 'Desgaste alto: a autonomia caiu bastante. Considere trocar.' })
            Start-Animacao $UI.BarraBatSaude ([Windows.Controls.Primitives.RangeBase]::ValueProperty) 0 $b.Saude 900
        } else {
            $UI.TxtBatSaude.Text = "$($b.Carga)%"
            $UI.TxtBatSaudeSub.Text = 'de carga agora. O Windows não informou a capacidade de fábrica; veja o relatório completo.'
            Start-Animacao $UI.BarraBatSaude ([Windows.Controls.Primitives.RangeBase]::ValueProperty) 0 $b.Carga 900
        }
        $det = "Carga agora: $($b.Carga)%  ·  " + $(if ($b.NaTomada) { 'na tomada' } else { 'na bateria' })
        if ($b.MinutosRestantes) { $det += "  ·  cerca de $([math]::Floor($b.MinutosRestantes / 60)) h $($b.MinutosRestantes % 60) min restantes" }
        if ($b.CapacidadeProjeto -and $b.CapacidadeAtual) { $det += "`nCapacidade de fábrica: $('{0:N0}' -f $b.CapacidadeProjeto) mWh  ·  hoje: $('{0:N0}' -f $b.CapacidadeAtual) mWh" }
        $UI.TxtBatDetalhe.Text = $det
    }
}
$UI.BtnBatRelatorio.Add_Click({
    $arq = Join-Path $Otz.Dados 'relatorio-bateria.html'
    $saida = powercfg /batteryreport /output "$arq" 2>&1
    if ($LASTEXITCODE -eq 0 -and (Test-Path $arq)) { Start-Process explorer.exe "`"$arq`"" }
    else { Show-Toast "Não foi possível gerar: $($saida -join ' ')" 'aviso' }
})
$UI.BtnNoteRecomendados.Add_Click({
    $n = Select-PerfilPagina 'note' 'notebook'
    Show-Toast $(if ($n) { "$n ajuste(s) recomendados marcados." } elseif (Test-Notebook) { 'Os recomendados já estão aplicados.' } else { 'Disponível só em notebooks.' }) 'info'
})

# ---------------- Serviços ----------------
function Update-Ram([switch]$Comparar) {
    $m = Get-MemoriaRam
    if ($Comparar -and $S.RamAntes) {
        $dif = $m.LivreBytes - $S.RamAntes.LivreBytes
        if ($dif -gt 5MB) { Show-Toast "Memória livre aumentou cerca de $(Format-Tamanho $dif)." 'ok' }
    }
    $S.RamAntes = $m
    $UI.TxtRamUso.Text = ('{0:N1} de {1:N1} GB em uso ({2}%)' -f $m.UsoGB, $m.TotalGB, $m.UsoPct)
    Start-Animacao $UI.BarraRam ([Windows.Controls.Primitives.RangeBase]::ValueProperty) $null $m.UsoPct 700
    $UI.TxtRamDica.Text = if ($m.TotalGB -le 9) { 'Com 8 GB, cada serviço desligado faz diferença. Os recomendados são seguros para qualquer uso.' }
                          elseif ($m.TotalGB -le 17) { 'Com 16 GB, o ganho é moderado: vale para quem usa navegador com muitas abas e programas pesados ao mesmo tempo.' }
                          else { 'Seu PC tem memória de sobra: desligar serviços traz pouco ganho. Faça só se quiser um sistema mais enxuto.' }
}
$UI.BtnServMedir.Add_Click({ Update-Ram; Start-Deteccao; Show-Toast 'Medindo o uso de memória de cada serviço...' 'info' })
$UI.BtnServRecomendados.Add_Click({
    $n = Select-PerfilPagina 'serv' 'ram'
    Show-Toast $(if ($n) { "$n serviço(s) recomendados marcados. Revise e clique em Aplicar." } else { 'Os recomendados já estão desligados neste PC.' }) 'info'
})

# ---------------- Limpar o segundo plano (programas de terceiros) ----------------
$S.SegSelos = @{ seguro = 'Recomendado'; depende = 'Depende do uso'; desconhecido = 'Não reconhecido' }

function Update-SegundoPlano {
    if (Test-TarefaAtiva 'segundo-plano') { return }
    $S.SegCarregado = $true
    $UI.TxtSegResumo.Text = 'Analisando o que roda neste PC...'
    $UI.BtnSegAplicar.IsEnabled = $false
    $script = @'
$r = [ordered]@{}
$r.Itens = @(Get-ItensSegundoPlano)
$r.Guias = @(Get-GuiasBandejaAtivas)
$r.Escolhidos = (Get-EstadoSegundoPlano).Escolhidos
$r.Mapa = @{}
foreach ($p in Get-MapaProcessos) { $r.Mapa[$p.Id] = $p.Bytes }
[pscustomobject]$r
'@
    Start-Tarefa -Nome 'segundo-plano' -Script $script -AoTerminar {
        param($saida, $erro)
        $d = @($saida | Where-Object { $_ -and $_.PSObject.Properties['Itens'] })[0]
        if (-not $d) { $UI.TxtSegResumo.Text = "Não foi possível analisar: $erro"; return }
        Show-SegundoPlano $d
    }
}

function Show-SegundoPlano($D) {
    $S.SegItens = @($D.Itens)
    $S.SegMapa = $D.Mapa
    $alvo = if ($null -ne $D.Escolhidos) { [string[]]@($D.Escolhidos) } else { [string[]]@($S.SegItens | Where-Object Nivel -eq 'seguro' | ForEach-Object Id) }
    $col = New-Object 'System.Collections.ObjectModel.ObservableCollection[Otz.Linha]'
    for ($n = 0; $n -lt $S.SegItens.Count; $n++) {
        $i = $S.SegItens[$n]
        $selo = $S.SegSelos[[string]$i.Nivel]
        if ($i.Aplicado) { $selo += '  ·  desligado pelo otimizador' }
        $mb = if ($i.Bytes -gt 0) { Format-Tamanho $i.Bytes } elseif ($i.Aplicado) { '—' } else { 'parado' }
        $l = New-Linha -Titulo $i.Nome -Texto "$($i.Grupo)  ·  $($i.Texto)" -Extra "Ao desligar: $($i.Efeito)`n$($i.Tecnico)" -Tag $selo -Icone $mb -Nivel ([string]$i.Nivel)
        $l.Marcado = ($alvo -contains $i.Id) -or [bool]$i.Aplicado
        $l.Valor = [double]$n
        $l.add_PropertyChanged({ param($o, $e) if ($e.PropertyName -eq 'Marcado') { Update-ResumoSeg } })
        $col.Add($l)
    }
    $S.SegLinhas = $col
    $UI.ListaSeg.ItemsSource = $col
    # Guias: o que só se desliga por dentro do próprio programa
    $guias = New-Object System.Collections.Generic.List[Otz.Linha]
    foreach ($g in @($D.Guias)) { $guias.Add((New-Linha -Titulo "$($g.Nome) · $(Format-Tamanho $g.Bytes) agora" -Texto $g.Texto -Nivel 'info')) }
    foreach ($i in $S.SegItens) { if ($i.Bandeja) { $guias.Add((New-Linha -Titulo "$($i.Nome): fechar de verdade" -Texto $i.Bandeja -Nivel 'info')) } }
    $UI.ListaSegGuia.ItemsSource = $guias.ToArray()
    $UI.TxtSegGuiaTitulo.Visibility = if ($guias.Count) { 'Visible' } else { 'Collapsed' }
    $UI.BtnSegDesfazer.Visibility = if (@($S.SegItens | Where-Object Aplicado).Count) { 'Visible' } else { 'Collapsed' }
    $UI.BtnSegAplicar.IsEnabled = $S.SegItens.Count -gt 0
    Update-ResumoSeg
}

# Memória dos itens marcados, sem contar o mesmo processo duas vezes
function Measure-SegBytes($Itens) {
    $pids = New-Object System.Collections.Generic.HashSet[int]
    foreach ($i in $Itens) { foreach ($p in @($i.Pids)) { [void]$pids.Add([int]$p) } }
    $t = 0.0
    foreach ($p in $pids) { if ($S.SegMapa.ContainsKey($p)) { $t += [double]$S.SegMapa[$p] } }
    return $t
}

function Get-SegMarcados { return @($S.SegLinhas | Where-Object Marcado | ForEach-Object { $S.SegItens[[int]$_.Valor] }) }

function Update-ResumoSeg {
    if (-not $S.SegItens -or $S.SegItens.Count -eq 0) { $UI.TxtSegResumo.Text = 'Nada para limpar: nenhum programa de terceiros liga sozinho neste PC.'; return }
    $marc = @(Get-SegMarcados)
    $total = Measure-SegBytes $S.SegItens
    $sel = Measure-SegBytes @($marc | Where-Object { -not $_.Aplicado })
    $feitos = @($S.SegItens | Where-Object Aplicado).Count
    $txt = "$($S.SegItens.Count) programa(s) de terceiros ligam sozinhos e usam $(Format-Tamanho $total) agora. Marcados: $($marc.Count)"
    if ($sel -gt 0) { $txt += " (~$(Format-Tamanho $sel) a menos)" }
    if ($feitos) { $txt += ". Já desligados: $feitos" }
    $UI.TxtSegResumo.Text = "$txt."
}

$UI.BtnSegAtualizar.Add_Click({ Update-SegundoPlano })
$UI.BtnSegAplicar.Add_Click({
    $marc = @(Get-SegMarcados)
    $desligar = @($marc | Where-Object { -not $_.Aplicado })
    $voltar = @($S.SegItens | Where-Object { $_.Aplicado -and ($marc -notcontains $_) })
    if (-not $desligar.Count -and -not $voltar.Count) { Show-Toast 'Nada mudou: a escolha já está aplicada.' 'info'; return }
    $linhas = @()
    foreach ($i in $desligar) { $linhas += New-Linha -Titulo "Desligar: $($i.Nome)" -Texto $i.Tecnico -Nivel $(if ($i.Nivel -eq 'seguro') { 'ok' } else { 'medio' }) }
    foreach ($i in $voltar) { $linhas += New-Linha -Titulo "Voltar ao normal: $($i.Nome)" -Nivel 'info' }
    $ids = [string[]]@($marc | ForEach-Object Id)
    Show-Dialogo -Titulo "Aplicar a escolha ($($desligar.Count) para desligar)?" -Texto 'Serviços vão para Manual (o programa ainda os liga quando precisa) e itens de inicialização são desligados. Vale para sempre e pode ser desfeito aqui ou no Histórico. Uma tarefa semanal (Guardião) desliga de novo o que uma atualização religar.' `
        -Linhas $linhas -TextoOk 'Aplicar' -Dados $ids -Acao {
        param($escolha)
        try { Save-EscolhidosSegundoPlano $escolha } catch { Show-Toast "Não foi possível salvar a escolha: $($_.Exception.Message)" 'erro'; return }
        Start-Execucao 'aplicar' @('serv.segundo-plano')
    }
})
$UI.BtnSegDesfazer.Add_Click({
    Show-Dialogo -Titulo 'Desfazer a limpeza do segundo plano?' -Texto 'Cada serviço volta ao modo que tinha e cada item de inicialização volta a ligar com o Windows.' -TextoOk 'Desfazer tudo' -Tipo 'perigo' -Acao {
        Start-Execucao 'desfazer' @('serv.segundo-plano')
    }
})

# ---------------- Verificar o PC ----------------
$S.Etapas = New-Object 'System.Collections.ObjectModel.ObservableCollection[Otz.Linha]'
$S.NomesEtapas = @('Ajustes do Windows (o que já está otimizado)', 'Segurança: antivírus e firewall', 'Atualizações do Windows', 'Hardware: discos e memória', 'Placa de vídeo e monitores', 'Inicialização, temporários e tempo ligado')
foreach ($t in $S.NomesEtapas) { $S.Etapas.Add((New-Linha -Titulo $t -Nivel 'pendente')) }
$UI.ListaEtapas.ItemsSource = $S.Etapas
$S.Saude = New-Object 'System.Collections.ObjectModel.ObservableCollection[Otz.Linha]'
$UI.ListaSaude.ItemsSource = $S.Saude
$S.RotulosAcao = @{
    defender = 'Abrir Segurança'; firewall = 'Abrir firewall'; reiniciar = 'Reiniciar'; windowsupdate = 'Abrir Windows Update'
    limpeza = 'Limpar agora'; inicializacao = 'Ver programas'; relatorio = 'Gerar relatório'; video = 'Ver placa de vídeo'; 'gpu.hz-maximo' = 'Corrigir'
    estabilidade = 'Ver detalhes'
}

# Mesmo tratamento da detecção da abertura
function Receive-Estado($ev) {
    $a = $S.PorId[$ev.Id]
    if (-not $a) { return }
    $a.Estado = $ev.Estado
    $a.EstadoDetalhe = [string]$ev.Texto
    $a.PodeDesfazer = [bool]$ev.PodeDesfazer
}

function Start-Verificacao {
    if (Test-TarefaAtiva 'verificar') { return }
    $UI.BtnVerificar.IsEnabled = $false
    $UI.TxtBtnVerificar.Text = 'Verificando...'
    $UI.TxtVerConceito.Text = 'Verificando...'
    $UI.TxtVerQuando.Text = 'Cada etapa aparece ao lado conforme termina.'
    $UI.TxtVerNota.Text = '…'
    Set-Arco 0 $UI.ArcoVerificar
    for ($i = 0; $i -lt $S.Etapas.Count; $i++) { $S.Etapas[$i] = New-Linha -Titulo $S.NomesEtapas[$i] -Nivel 'pendente' }
    $S.Saude.Clear()
    $UI.TxtVerSaudeTitulo.Visibility = 'Visible'
    $UI.PainelVerResumo.Visibility = 'Collapsed'
    $script = @'
function Step([int]$i, [string]$n, [string]$x = '') { Send-Evento @{ Tipo = 'etapa'; Indice = $i; Nivel = $n; Extra = $x } }
Step 0 'rodando'; Get-EstadoTodos; Step 0 'ok'
Step 1 'rodando'; $c = @(Get-SaudeSeguranca); Step 1 (Get-PiorNivel $c)
Step 2 'rodando'; $c = @(Get-SaudeAtualizacoes); Step 2 (Get-PiorNivel $c)
Step 3 'rodando'; $info = Get-InfoPC; $c = @(@(Get-SaudeHardware $info) + @(Get-SaudeEstabilidade)); Step 3 (Get-PiorNivel $c)
Step 4 'rodando'; $c = @(Get-SaudeVideo | Where-Object { $_.Titulo }); Step 4 (Get-PiorNivel $c)
Step 5 'rodando'; $c = @(Get-SaudeManutencao $info); Step 5 (Get-PiorNivel $c)
$info
'@
    Start-Tarefa -Nome 'verificar' -Script $script -AoEvento {
        param($ev)
        switch ($ev.Tipo) {
            'estado'   { Receive-Estado $ev }
            'etapa'    { $S.Etapas[[int]$ev.Indice] = New-Linha -Titulo $S.NomesEtapas[[int]$ev.Indice] -Nivel $ev.Nivel -Extra ([string]$ev.Extra) }
            'checagem' {
                $c = $ev.Checagem
                $S.Saude.Add((New-Linha -Titulo $c.Titulo -Texto $c.Texto -Nivel $c.Nivel -Tag $c.Acao -Extra $(if ($c.Acao) { [string]$S.RotulosAcao[$c.Acao] } else { '' })))
            }
        }
    } -AoTerminar {
        param($saida, $erro)
        $UI.BtnVerificar.IsEnabled = $true
        $UI.TxtBtnVerificar.Text = 'Verificar de novo'
        if ($erro) { $UI.TxtVerConceito.Text = 'A verificação falhou'; $UI.TxtVerQuando.Text = $erro; return }
        Update-Compatibilidade
        Update-Anel
        $info = @($saida | Where-Object { $_ -and $_.Tier })[0]
        if ($info) { Show-InfoPC $info }
        Complete-Verificacao
    }
}

function Complete-Verificacao {
    # Nota: 60% ajustes recomendados aplicados + 40% checagens de saúde sem problema
    $base = @($S.Ajustes | Where-Object { $_.Tipo -ne 'acao' -and $_.Habilitado -and $_.Estado -ne 'na' -and $_.Perfis.Count -gt 0 })
    $fracAjustes = if ($base.Count) { @($base | Where-Object Estado -eq 'aplicado').Count / $base.Count } else { 1 }
    $checks = @($S.Saude | Where-Object { $_.Nivel -ne 'info' })
    $fracSaude = if ($checks.Count) { @($checks | Where-Object Nivel -eq 'ok').Count / $checks.Count } else { 1 }
    $nota = [int][math]::Round(60 * $fracAjustes + 40 * $fracSaude)
    $S.VerDe = 0.0; $S.VerPara = $nota / 100; $S.VerNota = $nota; $S.VerInicio = Get-Date
    $S.TimerVer.Start()
    $UI.TxtVerConceito.Text = if ($nota -ge 85) { 'Ótimo! PC em excelente forma' } elseif ($nota -ge 65) { 'Bom: dá para melhorar alguns pontos' } else { 'Pode melhorar bastante' }
    $problemas = @($checks | Where-Object { $_.Nivel -in 'medio', 'alto' }).Count
    $UI.TxtVerQuando.Text = "Verificado às $(Get-Date -Format 'HH:mm'). " + $(if ($problemas) { "$problemas ponto(s) de atenção na saúde do sistema." } else { 'Nenhum problema de saúde encontrado.' })

    # Barras por categoria
    $cats = @($S.Ajustes | ForEach-Object Categoria | Select-Object -Unique)
    $UI.ListaCategorias.ItemsSource = [Otz.Linha[]]@(foreach ($cat in $cats) {
        $itens = @($S.Ajustes | Where-Object { $_.Categoria -eq $cat -and $_.Tipo -ne 'acao' -and $_.Habilitado -and $_.Estado -ne 'na' })
        if ($itens.Count -eq 0) { continue }
        $apl = @($itens | Where-Object Estado -eq 'aplicado').Count
        New-Linha -Titulo $cat -Texto "$apl/$($itens.Count)" -Valor ($apl / $itens.Count)
    })

    # O que falta do perfil sugerido
    $perfil = if ($S.Info) { $S.Info.PerfilSugerido } else { 'basico' }
    $S.VerPerfil = $perfil
    $faltam = @($S.Ajustes | Where-Object { $_.Perfis -contains $perfil -and $_.Habilitado -and $_.Risco -ne 'avancado' -and $_.Tipo -ne 'acao' -and $_.Estado -ne 'aplicado' })
    $UI.TxtVerFaltam.Text = [string]$faltam.Count
    if ($faltam.Count) {
        $UI.TxtVerFaltamSub.Text = "ajuste(s) recomendados para o perfil '$($S.NomePerfis[$perfil])' (sugerido para este PC) ainda não aplicados."
        $UI.BtnVerAplicarFaltam.Visibility = 'Visible'
    } else {
        $UI.TxtVerFaltamSub.Text = "Todos os ajustes recomendados para o perfil '$($S.NomePerfis[$perfil])' já estão aplicados."
        $UI.BtnVerAplicarFaltam.Visibility = 'Collapsed'
    }
    Show-Entrada $UI.PainelVerResumo
    $aplic = @($base | Where-Object Estado -eq 'aplicado').Count
    try { Save-Verificacao $nota "$aplic/$($base.Count)" $problemas 'manual' } catch { Write-Log "Não foi possível salvar a verificação: $($_.Exception.Message)" }
    Show-Evolucao
}

$S.TimerVer = New-Object Windows.Threading.DispatcherTimer
$S.TimerVer.Interval = [TimeSpan]::FromMilliseconds(16)
$S.TimerVer.Add_Tick({
    $t = [math]::Min(1.0, ((Get-Date) - $S.VerInicio).TotalMilliseconds / 1100)
    $e = 1 - [math]::Pow(1 - $t, 3)
    $v = $S.VerDe + ($S.VerPara - $S.VerDe) * $e
    Set-Arco $v $UI.ArcoVerificar
    $UI.TxtVerNota.Text = [string][math]::Round($v * 100)
    if ($t -ge 1) { $S.TimerVer.Stop(); $UI.TxtVerNota.Text = [string]$S.VerNota }
})

$UI.BtnVerificar.Add_Click({ Start-Verificacao })
$UI.BtnVerAplicarFaltam.Add_Click({ Open-Pagina 'NavOtimizar'; Select-Perfil $S.VerPerfil })
$UI.ListaSaude.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
    param($origem, $e)
    try {
        switch ([string]$e.OriginalSource.Tag) {
            'defender'      { Start-Process 'windowsdefender:' }
            'firewall'      { Start-Process control.exe -ArgumentList 'firewall.cpl' }
            'windowsupdate' { Start-Process 'ms-settings:windowsupdate' }
            'reiniciar'     { $UI.BtnExecReiniciar.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
            'limpeza'       { Start-Execucao 'aplicar' @('limpeza.temp') }
            'inicializacao' { Open-Pagina 'NavFerramentas'; Show-Ferramenta 'RbFerInicio' }
            'relatorio'     { Start-Relatorio }
            'video'         { Open-Pagina 'NavVideo' }
            'gpu.hz-maximo' { Request-Aplicar @($S.PorId['gpu.hz-maximo']) }
            'estabilidade'  { Invoke-AcaoAchado 'estabilidade' }
        }
    } catch { Show-Toast "Não foi possível abrir: $($_.Exception.Message)" 'erro' }
})

# ---------------- Espaço em disco ----------------
function Update-Espaco {
    $vol = Get-Volume -DriveLetter $env:SystemDrive.Substring(0, 1) -ErrorAction SilentlyContinue
    if ($vol -and $vol.Size) {
        $usado = [double]$vol.Size - [double]$vol.SizeRemaining
        $pct = [math]::Round(100 * $usado / $vol.Size)
        $UI.TxtEspacoDisco.Text = "Disco $($env:SystemDrive)  ·  $(Format-Tamanho $vol.SizeRemaining) livres"
        $UI.TxtEspacoDiscoSub.Text = "$(Format-Tamanho $usado) usados de $(Format-Tamanho $vol.Size) ($pct%). " + $(if ($pct -ge 85) { 'Acima de 85% o Windows fica lento: vale liberar espaço.' } else { 'Espaço sob controle.' })
        Start-Animacao $UI.BarraEspacoDisco ([Windows.Controls.Primitives.RangeBase]::ValueProperty) 0 $pct 700
    }
    $S.EspacoDados = New-Object System.Collections.Generic.List[object]
    $UI.ListaEspaco.ItemsSource = $null
    $UI.TxtEspacoStatus.Text = 'Medindo as pastas que mais costumam encher o disco...'
    $UI.BtnEspacoAnalisar.IsEnabled = $false
    Start-Tarefa -Nome 'espaco' -Script 'Get-UsoEspaco | Out-Null' -AoEvento {
        param($ev)
        if ($ev.Tipo -ne 'espaco') { return }
        $S.EspacoDados.Add($ev.Local)
        Show-ListaEspaco
    } -AoTerminar {
        $UI.BtnEspacoAnalisar.IsEnabled = $true
        $total = ($S.EspacoDados | Measure-Object Bytes -Sum).Sum
        $limpavel = (@($S.EspacoDados | Where-Object { $_.Acao -like 'item:limpeza.*' }) | Measure-Object Bytes -Sum).Sum
        $UI.TxtEspacoStatus.Text = "Somando tudo: $(Format-Tamanho $total). Dá para liberar cerca de $(Format-Tamanho $limpavel) com as limpezas seguras (botão Limpar)."
    }
}

function Show-ListaEspaco {
    $ordenado = @($S.EspacoDados | Sort-Object Bytes -Descending)
    $max = [double](@($ordenado)[0].Bytes); if ($max -le 0) { $max = 1 }
    $rotulo = { param($a) if ($a -like 'abrir:*') { 'Abrir pasta' } elseif ($a -like 'item:*') { 'Limpar' } elseif ($a -eq 'cleanmgr') { 'Limpeza de Disco' } else { '' } }
    $UI.ListaEspaco.ItemsSource = ConvertTo-Linhas @($ordenado | ForEach-Object {
        New-Linha -Titulo $_.Nome -Texto $_.Dica -Extra (Format-Tamanho $_.Bytes) -Tag $_.Acao -Icone (& $rotulo $_.Acao) -Valor ($_.Bytes / $max)
    })
}

$UI.BtnEspacoAnalisar.Add_Click({ Update-Espaco })
$UI.ListaEspaco.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
    param($origem, $e)
    $acao = [string]$e.OriginalSource.Tag
    if ($acao -like 'abrir:*') { Start-Process explorer.exe "`"$($acao.Substring(6))`"" }
    elseif ($acao -like 'item:*') {
        $a = $S.PorId[$acao.Substring(5)]
        if (-not $a) { return }
        if (-not $a.Habilitado) { Show-Toast $a.Motivo 'info'; return }
        Request-Aplicar @($a)
    }
    elseif ($acao -eq 'cleanmgr') { Start-Process cleanmgr.exe; Show-Toast 'Na Limpeza de Disco, clique em "Limpar arquivos do sistema" e marque "Instalações anteriores do Windows".' 'info' }
})

$UI.BtnGrandesProcurar.Add_Click({
    $UI.BtnGrandesProcurar.IsEnabled = $false
    $UI.TxtGrandesStatus.Text = 'Procurando... pode levar até um minuto em pastas grandes.'
    Start-Tarefa -Nome 'grandes' -Script 'Get-ArquivosGrandes' -AoTerminar {
        param($saida, $erro)
        $UI.BtnGrandesProcurar.IsEnabled = $true
        $lista = @($saida | Where-Object { $_ -and $_.Caminho })
        $UI.ListaGrandes.ItemsSource = ConvertTo-Linhas @($lista | ForEach-Object { New-Linha -Titulo $_.Nome -Tag $_.Caminho -Extra (Format-Tamanho $_.Bytes) -Texto $_.Dica })
        $UI.TxtGrandesStatus.Text = if ($lista.Count) { "$($lista.Count) arquivo(s) acima de 300 MB. A linha azul explica o que é, quando dá para saber. Nada foi apagado." } else { 'Nenhum arquivo acima de 300 MB na sua pasta.' }
    }
})
$UI.ListaGrandes.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
    param($origem, $e)
    $c = [string]$e.OriginalSource.Tag
    if ($c) { Start-Process explorer.exe "/select,`"$c`"" }
})

# ---------------- Evolução da nota (gráfico de linha, uma série) ----------------
function Show-Evolucao {
    $h = @(Get-Verificacoes 30)
    if ($h.Count -eq 0) { $UI.PainelEvolucao.Visibility = 'Collapsed'; return }
    $UI.PainelEvolucao.Visibility = 'Visible'
    $cv = $UI.GraficoEvolucao; $eixo = $UI.EixoEvolucao
    $w = $cv.ActualWidth; $alt = $cv.ActualHeight
    if ($w -lt 20 -or $alt -lt 20) { return }   # redesenha no SizeChanged
    $cv.Children.Clear(); $eixo.Children.Clear()
    $topo = 8.0; $base = $alt - 8.0
    $y = { param($nota) $topo + (1 - [double]$nota / 100) * ($base - $topo) }

    # Grade recessiva + rótulos do eixo (texto em cor de texto, nunca a da série)
    foreach ($v in 0, 50, 100) {
        $ln = [Windows.Shapes.Line]::new(); $ln.X1 = 0; $ln.X2 = $w; $ln.Y1 = (& $y $v); $ln.Y2 = $ln.Y1; $ln.StrokeThickness = 1
        Set-Referencia $ln ([Windows.Shapes.Shape]::StrokeProperty) 'Grade'
        [void]$cv.Children.Add($ln)
        $tb = [Windows.Controls.TextBlock]::new(); $tb.Text = [string]$v; $tb.FontSize = 11; $tb.Width = 28; $tb.TextAlignment = 'Right'
        Set-Referencia $tb ([Windows.Controls.TextBlock]::ForegroundProperty) 'TextoFraco'
        [Windows.Controls.Canvas]::SetTop($tb, (& $y $v) - 8); [void]$eixo.Children.Add($tb)
    }

    $n = $h.Count; $pad = 10.0
    $xs = @(for ($i = 0; $i -lt $n; $i++) { if ($n -eq 1) { $w / 2 } else { $pad + $i * ($w - 2 * $pad) / ($n - 1) } })
    if ($n -gt 1) {
        $pl = [Windows.Shapes.Polyline]::new(); $pl.StrokeThickness = 2; $pl.StrokeLineJoin = 'Round'
        Set-Referencia $pl ([Windows.Shapes.Shape]::StrokeProperty) 'Serie1'
        for ($i = 0; $i -lt $n; $i++) { [void]$pl.Points.Add([Windows.Point]::new($xs[$i], (& $y $h[$i].Nota))) }
        [void]$cv.Children.Add($pl)
    }
    for ($i = 0; $i -lt $n; $i++) {
        $d = $h[$i]
        $data = try { ([datetime]::Parse($d.Data, [Globalization.CultureInfo]::InvariantCulture)).ToString('dd/MM HH:mm') } catch { $d.Data }
        # Alvo de mouse maior que a marca (20 px), com dica
        $alvo = [Windows.Controls.Grid]::new(); $alvo.Width = 20; $alvo.Height = 20; $alvo.Background = [Windows.Media.Brushes]::Transparent
        $alvo.ToolTip = "$data  ·  nota $($d.Nota)  ·  ajustes $($d.Ajustes)  ·  $($d.Problemas) problema(s)  ·  $($d.Origem)"
        $m = [Windows.Shapes.Ellipse]::new(); $m.Width = 10; $m.Height = 10; $m.StrokeThickness = 2
        Set-Referencia $m ([Windows.Shapes.Shape]::FillProperty) 'Serie1'
        Set-Referencia $m ([Windows.Shapes.Shape]::StrokeProperty) 'Superficie'
        [void]$alvo.Children.Add($m)
        [Windows.Controls.Canvas]::SetLeft($alvo, $xs[$i] - 10); [Windows.Controls.Canvas]::SetTop($alvo, (& $y $d.Nota) - 10)
        [void]$cv.Children.Add($alvo)
    }
    # Rótulo direto só no último ponto
    $ult = $h[$n - 1]
    $lbl = [Windows.Controls.TextBlock]::new(); $lbl.Text = [string]$ult.Nota; $lbl.FontWeight = 'SemiBold'; $lbl.FontSize = 12.5
    Set-Referencia $lbl ([Windows.Controls.TextBlock]::ForegroundProperty) 'Texto'
    [Windows.Controls.Canvas]::SetLeft($lbl, [math]::Min($w - 22, $xs[$n - 1] - 8)); [Windows.Controls.Canvas]::SetTop($lbl, [math]::Max(-6, (& $y $ult.Nota) - 26))
    [void]$cv.Children.Add($lbl)

    $fmt = { param($txt) try { ([datetime]::Parse($txt, [Globalization.CultureInfo]::InvariantCulture)).ToString('dd/MM/yyyy') } catch { $txt } }
    $UI.TxtEvolucaoIni.Text = & $fmt $h[0].Data
    $UI.TxtEvolucaoFim.Text = if ($n -gt 1) { & $fmt $ult.Data } else { '' }
    if ($n -gt 1) {
        $dif = [int]$ult.Nota - [int]$h[0].Nota
        $sinal = if ($dif -gt 0) { "+$dif" } else { "$dif" }
        $UI.TxtEvolucaoResumo.Text = "Primeira: $($h[0].Nota)  →  agora: $($ult.Nota)  ($sinal)"
    } else { $UI.TxtEvolucaoResumo.Text = "Nota atual: $($ult.Nota)" }
    $UI.TxtEvolucaoDica.Text = if ($n -eq 1) { 'Este é o primeiro ponto. Verifique de novo depois de otimizar (ou ligue a manutenção automática) para ver a evolução.' }
                               else { "$n verificações. Passe o mouse nos pontos para ver os detalhes. A manutenção automática também adiciona pontos." }
}
$UI.GraficoEvolucao.Add_SizeChanged({ if ($UI.PainelEvolucao.Visibility -eq 'Visible') { Show-Evolucao } })

# ---------------- Monitor de conexão (duas séries, uma escala) ----------------
$S.Mon = @{ Rodando = $false; Controle = $null; Dados = @{}; Nomes = @{} }

foreach ($rb in 'RbMonCloudflare', 'RbMonGoogle', 'RbMonOutro') {
    $UI[$rb].Add_Checked({ $UI.TxtMonOutro.Visibility = if ($UI.RbMonOutro.IsChecked) { 'Visible' } else { 'Collapsed' } })
}

function Get-AlvoInternet {
    if ($UI.RbMonOutro.IsChecked) { return ($UI.TxtMonOutro.Text.Trim() -replace '^\w+://', '' -replace '[/:].*$', '') }
    foreach ($rb in 'RbMonCloudflare', 'RbMonGoogle') { if ($UI[$rb].IsChecked) { return [string]$UI[$rb].Tag } }
    return '1.1.1.1'
}

function Start-Monitor {
    $alvo = Get-AlvoInternet
    if (-not $alvo) { Show-Toast 'Digite o endereço do seu servidor.' 'aviso'; [void]$UI.TxtMonOutro.Focus(); return }
    $gw = Get-GatewayPadrao
    $alvos = New-Object System.Collections.Generic.List[object]
    if ($gw) { $alvos.Add(@{ Chave = 'roteador'; Endereco = $gw }) }
    $alvos.Add(@{ Chave = 'internet'; Endereco = $alvo })
    $S.Mon.Dados = @{ roteador = New-Object System.Collections.Generic.List[object]; internet = New-Object System.Collections.Generic.List[object] }
    $S.Mon.Nomes = @{ roteador = $(if ($gw) { "Roteador ($gw)" } else { 'Roteador (não encontrado)' }); internet = "Internet ($alvo)" }
    $UI.TxtMonRoteadorNome.Text = $S.Mon.Nomes.roteador
    $UI.TxtMonInternetNome.Text = $S.Mon.Nomes.internet
    $S.Mon.Controle = [hashtable]::Synchronized(@{ Parar = $false })
    $S.Mon.Rodando = $true
    $UI.TxtBtnMonitor.Text = 'Parar'; $UI.IcoMonitor.Text = G 0xE71A
    $UI.TxtMonDiag.Text = 'Medindo... deixe rodar pelo menos 30 segundos.'
    Start-Tarefa -Nome 'monitor' -Script 'Watch-Conexao $Parametros.Alvos $Parametros.Controle' -Parametros @{ Alvos = $alvos.ToArray(); Controle = $S.Mon.Controle } -AoEvento {
        param($ev)
        if ($ev.Tipo -ne 'ping') { return }
        $lista = $S.Mon.Dados[[string]$ev.Chave]
        $lista.Add($ev.Ms)
        if ($lista.Count -gt 600) { $lista.RemoveAt(0) }
        if ($ev.Chave -eq 'internet') { Update-Monitor }
    } -AoTerminar {
        $S.Mon.Rodando = $false
        $UI.TxtBtnMonitor.Text = 'Começar'; $UI.IcoMonitor.Text = G 0xE768
    }
}
$UI.BtnMonitor.Add_Click({ if ($S.Mon.Rodando) { $S.Mon.Controle.Parar = $true; $UI.TxtBtnMonitor.Text = 'Parando...' } else { Start-Monitor } })

# Estatísticas: atual, média, perda (%) e variação (jitter: diferença média entre medidas seguidas)
function Get-StatsPing($Lista) {
    $n = $Lista.Count
    if ($n -eq 0) { return $null }
    $okN = 0; $soma = 0.0
    foreach ($v in $Lista) { if ($null -ne $v) { $okN++; $soma += $v } }
    $jit = 0.0; $pares = 0
    for ($i = 1; $i -lt $n; $i++) { if ($null -ne $Lista[$i] -and $null -ne $Lista[$i - 1]) { $jit += [math]::Abs($Lista[$i] - $Lista[$i - 1]); $pares++ } }
    $r = [ordered]@{}
    $r.Atual = $Lista[$n - 1]
    $r.Media = if ($okN) { [math]::Round($soma / $okN, 1) } else { $null }
    $r.Perda = [math]::Round(100 * ($n - $okN) / $n, 1)
    $r.Jitter = if ($pares) { [math]::Round($jit / $pares, 1) } else { 0 }
    $r.N = $n
    return [pscustomobject]$r
}

function Update-Monitor {
    $sr = Get-StatsPing $S.Mon.Dados.roteador
    $si = Get-StatsPing $S.Mon.Dados.internet
    foreach ($par in @(@{ S = $sr; A = 'TxtMonRoteadorAtual'; T = 'TxtMonRoteadorStats' }, @{ S = $si; A = 'TxtMonInternetAtual'; T = 'TxtMonInternetStats' })) {
        if (-not $par.S) { continue }
        $UI[$par.A].Text = if ($null -eq $par.S.Atual) { 'sem resposta' } elseif ($par.S.Atual -eq 0) { '<1 ms' } else { "$($par.S.Atual) ms" }
        $UI[$par.T].Text = "média $(if ($null -ne $par.S.Media) { "$($par.S.Media) ms" } else { '-' })  ·  perda $($par.S.Perda)%  ·  variação $($par.S.Jitter) ms"
    }
    Show-GraficoMonitor
    # Diagnóstico em linguagem simples
    if (-not $si -or $si.N -lt 10) { return }
    $nivel = 'info'; $titulo = 'Diagnóstico'; $txt = ''
    if ($sr -and $sr.Perda -gt 2) {
        $nivel = 'alto'; $titulo = 'O problema está entre o PC e o roteador'
        $txt = "Até o roteador já há $($sr.Perda)% de perda. Isso aponta para Wi-Fi fraco ou com interferência, cabo de rede ruim ou placa de rede. Teste com cabo, aproxime do roteador ou reinicie o roteador."
    } elseif ($si.Perda -gt 2) {
        $nivel = 'alto'; $titulo = 'O problema está na internet (provedor)'
        $txt = "O roteador responde bem, mas $($si.Perda)% das respostas da internet se perdem. O problema é no modem, no provedor ou no destino. Ligue para a operadora informando a perda e o horário."
    } elseif ($si.Media -gt 100 -or $si.Jitter -gt 30) {
        $nivel = 'medio'; $titulo = 'Internet lenta ou instável'
        $txt = "Não há perda, mas o atraso médio é $($si.Media) ms com variação de $($si.Jitter) ms. Para jogos e chamadas, o ideal é abaixo de 60 ms e variação abaixo de 15 ms. Pode ser alguém usando muita banda na rede ou horário de pico do provedor."
    } elseif ($sr -and $sr.Media -gt 10) {
        $nivel = 'medio'; $titulo = 'Atraso alto até o roteador'
        $txt = "O roteador leva $($sr.Media) ms para responder. No cabo deveria ficar abaixo de 2 ms; no Wi-Fi, abaixo de 10 ms. Sinal fraco de Wi-Fi é a causa mais comum."
    } else {
        $nivel = 'ok'; $titulo = 'Conexão estável'
        $txt = "Sem perdas: roteador em $(if ($sr) { "$($sr.Media) ms" } else { '-' }) e internet em $($si.Media) ms, com variação de $($si.Jitter) ms. Se algo está lento, o problema não parece ser a sua conexão."
    }
    $UI.TxtMonDiagTitulo.Text = $titulo
    $UI.TxtMonDiag.Text = $txt
    $mapa = @{ ok = @(0xE73E, 'Ok', 'OkSuave'); medio = @(0xE7BA, 'Aviso', 'AvisoSuave'); alto = @(0xE783, 'Erro', 'ErroSuave'); info = @(0xE946, 'Info', 'InfoSuave') }
    $m = $mapa[$nivel]
    $UI.IcoMonDiag.Text = G $m[0]
    Set-Referencia $UI.IcoMonDiag ([Windows.Controls.TextBlock]::ForegroundProperty) $m[1]
    Set-Referencia $UI.CardMonDiag ([Windows.Controls.Border]::BackgroundProperty) $m[2]
}

function Show-GraficoMonitor {
    $cv = $UI.GraficoMonitor; $eixo = $UI.EixoMonitor
    $w = $cv.ActualWidth; $alt = $cv.ActualHeight
    if ($w -lt 20) { return }
    $cv.Children.Clear(); $eixo.Children.Clear()
    $janela = 60
    $series = @(@{ Chave = 'roteador'; Cor = 'Serie1' }, @{ Chave = 'internet'; Cor = 'Serie2' })
    # Escala única (ms), arredondada para um valor "redondo"
    $vis = @()
    foreach ($serie in $series) { $l = $S.Mon.Dados[$serie.Chave]; if ($l) { $ini = [math]::Max(0, $l.Count - $janela); for ($i = $ini; $i -lt $l.Count; $i++) { if ($null -ne $l[$i]) { $vis += $l[$i] } } } }
    $maxV = if ($vis.Count) { ($vis | Measure-Object -Maximum).Maximum } else { 10 }
    $escala = (10, 20, 50, 100, 200, 500, 1000, 2000 | Where-Object { $_ -ge $maxV * 1.1 } | Select-Object -First 1); if (-not $escala) { $escala = 2000 }
    $topo = 14.0; $base = $alt - 4.0
    $y = { param($v) $base - ([math]::Min($v, $escala) / $escala) * ($base - $topo) }
    $x = { param($i) $w * $i / ($janela - 1) }
    foreach ($v in 0, ($escala / 2), $escala) {
        $ln = [Windows.Shapes.Line]::new(); $ln.X1 = 0; $ln.X2 = $w; $ln.Y1 = (& $y $v); $ln.Y2 = $ln.Y1; $ln.StrokeThickness = 1
        Set-Referencia $ln ([Windows.Shapes.Shape]::StrokeProperty) 'Grade'; [void]$cv.Children.Add($ln)
        $tb = [Windows.Controls.TextBlock]::new(); $tb.Text = "$v ms"; $tb.FontSize = 11; $tb.Width = 36; $tb.TextAlignment = 'Right'
        Set-Referencia $tb ([Windows.Controls.TextBlock]::ForegroundProperty) 'TextoFraco'
        [Windows.Controls.Canvas]::SetTop($tb, (& $y $v) - 8); [void]$eixo.Children.Add($tb)
    }
    $ultimosY = @{}
    foreach ($serie in $series) {
        $l = $S.Mon.Dados[$serie.Chave]
        if (-not $l -or $l.Count -eq 0) { continue }
        $ini = [math]::Max(0, $l.Count - $janela); $desloc = $janela - ($l.Count - $ini)
        $pl = $null
        for ($i = $ini; $i -lt $l.Count; $i++) {
            $px = & $x ($i - $ini + $desloc)
            if ($null -eq $l[$i]) {
                $pl = $null   # quebra a linha na perda
                $xm = [Windows.Controls.TextBlock]::new(); $xm.Text = G 0xE711; $xm.FontFamily = $Win.FindResource('Icones'); $xm.FontSize = 10
                Set-Referencia $xm ([Windows.Controls.TextBlock]::ForegroundProperty) 'Erro'
                [Windows.Controls.Canvas]::SetLeft($xm, $px - 5); [Windows.Controls.Canvas]::SetTop($xm, $(if ($serie.Chave -eq 'roteador') { 0 } else { 12 }) - 4)
                [void]$cv.Children.Add($xm); continue
            }
            if (-not $pl) {
                $pl = [Windows.Shapes.Polyline]::new(); $pl.StrokeThickness = 2; $pl.StrokeLineJoin = 'Round'
                Set-Referencia $pl ([Windows.Shapes.Shape]::StrokeProperty) $serie.Cor; [void]$cv.Children.Add($pl)
            }
            [void]$pl.Points.Add([Windows.Point]::new($px, (& $y $l[$i])))
        }
        if ($null -ne $l[$l.Count - 1]) { $ultimosY[$serie.Chave] = & $y $l[$l.Count - 1] }
    }
    # Rótulos diretos no fim de cada linha (valor atual), sem sobrepor
    $yr = $ultimosY['roteador']; $yi = $ultimosY['internet']
    foreach ($k in 'roteador', 'internet') {
        if (-not $ultimosY.ContainsKey($k)) { continue }
        $yy = $ultimosY[$k] - 18
        if ($k -eq 'internet' -and $null -ne $yr -and [math]::Abs($yi - $yr) -lt 16) { $yy = $ultimosY[$k] + 4 }
        $lb = [Windows.Controls.TextBlock]::new(); $vAtual = $S.Mon.Dados[$k][$S.Mon.Dados[$k].Count - 1]; $lb.Text = if ($vAtual -eq 0) { "<1 ms" } else { "$vAtual ms" }; $lb.FontSize = 11.5; $lb.FontWeight = 'SemiBold'
        Set-Referencia $lb ([Windows.Controls.TextBlock]::ForegroundProperty) 'Texto'
        [Windows.Controls.Canvas]::SetLeft($lb, $w - 44); [Windows.Controls.Canvas]::SetTop($lb, [math]::Max(0, $yy))
        [void]$cv.Children.Add($lb)
    }
    if ($S.Mon.Cruz) { [void]$cv.Children.Add($S.Mon.Cruz) }
}

# Passar o mouse: linha vertical + dica com os dois valores daquele segundo
$S.Mon.Cruz = [Windows.Shapes.Line]::new(); $S.Mon.Cruz.StrokeThickness = 1; $S.Mon.Cruz.Visibility = 'Collapsed'; $S.Mon.Cruz.IsHitTestVisible = $false
Set-Referencia $S.Mon.Cruz ([Windows.Shapes.Shape]::StrokeProperty) 'TextoFraco'
$UI.GraficoMonitor.Add_MouseMove({
    param($origem, $e)
    $w = $UI.GraficoMonitor.ActualWidth; if ($w -lt 20) { return }
    $px = $e.GetPosition($UI.GraficoMonitor).X
    $slot = [int][math]::Round(59 * $px / $w); $px = $w * $slot / 59
    $S.Mon.Cruz.X1 = $px; $S.Mon.Cruz.X2 = $px; $S.Mon.Cruz.Y1 = 0; $S.Mon.Cruz.Y2 = $UI.GraficoMonitor.ActualHeight; $S.Mon.Cruz.Visibility = 'Visible'
    $partes = @()
    foreach ($k in 'roteador', 'internet') {
        $l = $S.Mon.Dados[$k]; if (-not $l -or $l.Count -eq 0) { continue }
        $idx = $l.Count - 1 - (59 - $slot)
        if ($idx -ge 0) { $v = $l[$idx]; $partes += "$($S.Mon.Nomes[$k]): $(if ($null -ne $v) { "$v ms" } else { 'sem resposta' })" }
    }
    $UI.GraficoMonitor.ToolTip = if ($partes) { "há $(59 - $slot) s`n$($partes -join "`n")" } else { $null }
})
$UI.GraficoMonitor.Add_MouseLeave({ $S.Mon.Cruz.Visibility = 'Collapsed' })

# ---------------- Manutenção automática ----------------
function Initialize-Manut {
    if ($UI.CbManutHora.Items.Count -eq 0) { foreach ($h in 6..23) { [void]$UI.CbManutHora.Items.Add(('{0:00}:00' -f $h)) } }
    $cfg = Get-ConfigManutencao
    $UI.RbManutDiaria.IsChecked = ($cfg.Frequencia -eq 'diaria')
    $UI.RbManutSemanal.IsChecked = ($cfg.Frequencia -ne 'diaria')
    foreach ($it in $UI.CbManutDia.Items) { if ([string]$it.Tag -eq [string]$cfg.Dia) { $UI.CbManutDia.SelectedItem = $it } }
    $UI.CbManutHora.SelectedItem = [string]$cfg.Hora
    if ($UI.CbManutHora.SelectedIndex -lt 0) { $UI.CbManutHora.SelectedItem = '12:00' }
    $tar = @($cfg.Tarefas)
    $UI.ChkManutTemp.IsChecked = $tar -contains 'temp'
    $UI.ChkManutDns.IsChecked = $tar -contains 'dns'
    $UI.ChkManutLixeira.IsChecked = $tar -contains 'lixeira'
    $UI.ChkManutVerificar.IsChecked = [bool]$cfg.Verificar
    $UI.ChkManutGuardiao.IsChecked = [bool]$cfg.Guardiao
    Update-StatusManut
}
foreach ($rb in 'RbManutSemanal', 'RbManutDiaria') { $UI[$rb].Add_Checked({ $UI.PainelManutDia.Visibility = if ($UI.RbManutDiaria.IsChecked) { 'Collapsed' } else { 'Visible' } }) }

function Get-ConfigManutTela {
    $tar = @()
    if ($UI.ChkManutTemp.IsChecked) { $tar += 'temp' }
    if ($UI.ChkManutDns.IsChecked) { $tar += 'dns' }
    if ($UI.ChkManutLixeira.IsChecked) { $tar += 'lixeira' }
    return [pscustomobject]@{
        Frequencia = $(if ($UI.RbManutDiaria.IsChecked) { 'diaria' } else { 'semanal' })
        Dia        = [string]$UI.CbManutDia.SelectedItem.Tag
        Hora       = [string]$UI.CbManutHora.SelectedItem
        Tarefas    = $tar
        Verificar  = [bool]$UI.ChkManutVerificar.IsChecked
        Guardiao   = [bool]$UI.ChkManutGuardiao.IsChecked
    }
}

function Update-StatusManut {
    $st = Get-StatusManutencao
    if ($st.Ativa) {
        $UI.TxtManutTitulo.Text = 'Manutenção automática ligada'
        $UI.TxtManutDetalhe.Text = if ($st.Proxima) { "Próxima execução: $($st.Proxima.ToString('dddd, dd/MM \à\s HH:mm'))." } else { 'Agendada.' }
        $UI.IcoManut.Text = G 0xE73E
        Set-Referencia $UI.IcoManut ([Windows.Controls.TextBlock]::ForegroundProperty) 'Ok'
        Set-Referencia $UI.CirculoManut ([Windows.Controls.Border]::BackgroundProperty) 'OkSuave'
        $UI.TxtBtnManutAtivar.Text = 'Salvar alterações'
        $UI.BtnManutDesligar.Visibility = 'Visible'
    } else {
        $UI.TxtManutTitulo.Text = 'Manutenção automática desligada'
        $UI.TxtManutDetalhe.Text = 'Limpa o PC e verifica a saúde sozinho, no dia e hora que você escolher.'
        $UI.IcoManut.Text = G 0xE81C
        Set-Referencia $UI.IcoManut ([Windows.Controls.TextBlock]::ForegroundProperty) 'TextoSec'
        Set-Referencia $UI.CirculoManut ([Windows.Controls.Border]::BackgroundProperty) 'Superficie2'
        $UI.TxtBtnManutAtivar.Text = 'Ligar manutenção'
        $UI.BtnManutDesligar.Visibility = 'Collapsed'
    }
    $r = $st.Resultado
    if ($r) {
        $data = try { ([datetime]::Parse($r.Data, [Globalization.CultureInfo]::InvariantCulture)).ToString('dd/MM/yyyy HH:mm') } catch { $r.Data }
        $UI.TxtManutUltima.Text = "Rodou em $data." + $(if ($null -ne $r.Nota) { " Nota do PC: $($r.Nota)." } else { '' })
        $mapa = @{ ok = 'ok'; erro = 'erro'; aviso = 'aviso'; ignorado = 'ignorado' }
        $UI.ListaManutUltima.ItemsSource = ConvertTo-Linhas @(@($r.Itens) | ForEach-Object { New-Linha -Titulo $_.Nome -Texto ([string]$_.Mensagem) -Nivel $mapa[[string]$_.Status] })
    }
}

$UI.BtnManutAtivar.Add_Click({
    $cfg = Get-ConfigManutTela
    if (@($cfg.Tarefas).Count -eq 0 -and -not $cfg.Verificar -and -not $cfg.Guardiao) { Show-Toast 'Marque pelo menos uma coisa para a manutenção fazer.' 'aviso'; return }
    $UI.BtnManutAtivar.IsEnabled = $false
    Start-Tarefa -Nome 'manut-reg' -Script 'Register-Manutencao $Parametros.Cfg' -Parametros @{ Cfg = $cfg } -AoTerminar {
        param($saida, $erro)
        $UI.BtnManutAtivar.IsEnabled = $true
        if ($erro) { Show-Toast "Não foi possível agendar: $erro" 'erro' } else { Show-Toast 'Manutenção automática agendada no Agendador de Tarefas do Windows.' 'ok' }
        Update-StatusManut
    }
})
$UI.BtnManutDesligar.Add_Click({
    Show-Dialogo -Titulo 'Desligar a manutenção automática?' -Texto 'A tarefa é removida do Agendador do Windows. Você pode ligar de novo quando quiser.' -TextoOk 'Desligar' -Acao {
        Start-Tarefa -Nome 'manut-rm' -Script 'Unregister-Manutencao' -AoTerminar {
            param($saida, $erro)
            if ($erro) { Show-Toast "Falhou: $erro" 'erro' } else { Show-Toast 'Manutenção automática desligada.' 'ok' }
            Update-StatusManut
        }
    }
})
$UI.BtnManutAgora.Add_Click({
    $cfg = Get-ConfigManutTela
    if ($cfg.Tarefas -contains 'lixeira') {
        Show-Dialogo -Titulo 'Rodar a manutenção agora?' -Tipo 'perigo' -TextoOk 'Rodar agora' -Texto 'A Lixeira está marcada: tudo o que está nela será apagado para sempre.' -Dados $cfg -Acao { param($c) Start-ManutAgora $c }
    } else { Start-ManutAgora $cfg }
})
function Start-ManutAgora($Cfg) {
    $UI.BtnManutAgora.IsEnabled = $false
    Show-Toast 'Rodando a manutenção... leva alguns segundos.' 'info'
    Start-Tarefa -Nome 'manut-agora' -Script '$a = Save-ConfigManutencao $Parametros.Cfg; Invoke-ManutencaoAgendada $a' -Parametros @{ Cfg = $Cfg } -AoTerminar {
        param($saida, $erro)
        $UI.BtnManutAgora.IsEnabled = $true
        $r = @($saida | Where-Object { $_ -is [hashtable] })[0]
        if ($erro) { Show-Toast "Falhou: $erro" 'erro' }
        else { Show-Toast $(if ($r -and $null -ne $r.Nota) { "Manutenção concluída. Nota do PC: $($r.Nota)." } else { 'Manutenção concluída.' }) 'ok' }
        Update-StatusManut
        Start-Deteccao
    }
}

# ---------------- Suporte técnico ----------------
function Initialize-Suporte {
    Update-ResumoChamado
    Start-Tarefa -Nome 'sup-ids' -Script '@{ Qa = (Get-AppIdAssistenciaRapida); Any = (Get-IdAnyDesk) }' -AoTerminar {
        param($saida, $erro)
        $r = @($saida | Where-Object { $_ -is [hashtable] })[0]
        $S.AppQuickAssist = if ($r) { [string]$r.Qa } else { '' }
        $UI.TxtSupQuickAssist.Text = if ($S.AppQuickAssist) { 'Abrir Assistência Rápida' } else { 'Instalar Assistência Rápida' }
        if ($r -and $r.Any) { $UI.TxtSupAnyDesk.Text = "Seu ID do AnyDesk: $($r.Any)"; $UI.TxtSupAnyDesk.Visibility = 'Visible' }
    }
}
function Update-ResumoChamado {
    $UI.TxtSupResumo.Text = 'Gerando...'
    Start-Tarefa -Nome 'sup-resumo' -Script 'Get-ResumoChamado' -AoTerminar {
        param($saida, $erro)
        $UI.TxtSupResumo.Text = if ($erro) { "Falhou: $erro" } else { [string](@($saida) -join "`r`n") }
    }
}
$UI.BtnSupGerar.Add_Click({ Update-ResumoChamado })
$UI.BtnSupCopiar.Add_Click({
    try { [Windows.Clipboard]::SetText($UI.TxtSupResumo.Text); Show-Toast 'Resumo copiado. É só colar (Ctrl+V) no chamado ou no WhatsApp.' 'ok' }
    catch { Show-Toast "Não foi possível copiar: $($_.Exception.Message)" 'erro' }
})
$UI.BtnSupRdp.Add_Click({ Start-Process mstsc.exe })
$UI.BtnSupQuickAssist.Add_Click({
    if ($S.AppQuickAssist) { Start-Process explorer.exe "shell:AppsFolder\$($S.AppQuickAssist)"; return }
    Show-Dialogo -Titulo 'Instalar a Assistência Rápida?' -TextoOk 'Instalar' `
        -Texto 'É o app gratuito da Microsoft para ajuda remota (alguém vê e controla a sua tela com um código de 6 dígitos). Será instalado pela Microsoft Store via winget.' -Acao {
            $wg = (Get-Command winget -ErrorAction SilentlyContinue).Source
            if (-not $wg) { Show-Toast 'winget não encontrado. Instale pela Microsoft Store: procure "Assistência Rápida".' 'erro'; return }
            Show-Toast 'Instalando a Assistência Rápida...' 'info'
            Start-Tarefa -Nome 'sup-qa' -Parametros @{ W = $wg } -Script 'Invoke-ProcessoAoVivo -Arquivo $Parametros.W -Argumentos "install --id 9P7BP5VNWKX5 --source msstore --accept-source-agreements --accept-package-agreements" -Codificacao utf8 | Out-Null; Get-AppIdAssistenciaRapida' -AoTerminar {
                param($saida, $erro)
                $id = [string](@($saida) | Where-Object { $_ } | Select-Object -Last 1)
                if ($id) { $S.AppQuickAssist = $id; $UI.TxtSupQuickAssist.Text = 'Abrir Assistência Rápida'; Show-Toast 'Assistência Rápida instalada.' 'ok' }
                else { Show-Toast 'Não foi possível confirmar a instalação. Procure "Assistência Rápida" no Iniciar.' 'aviso' }
            }
        }
})

$S.WifiVisivel = @{}
function Show-ListaWifi {
    $UI.ListaWifi.ItemsSource = ConvertTo-Linhas @(@($S.WifiRedes) | ForEach-Object {
        $ver = $S.WifiVisivel[$_.Nome]
        $txt = if (-not $_.Senha) { '(rede aberta ou senha não salva)' } elseif ($ver) { $_.Senha } else { '••••••••' }
        New-Linha -Titulo $_.Nome -Texto $txt -Tag $_.Nome -Extra $(if ($_.Senha) { if ($ver) { 'Esconder' } else { 'Mostrar' } } else { '' }) -Icone ([string]$_.Senha)
    })
}
$UI.BtnSupWifi.Add_Click({
    $UI.BtnSupWifi.IsEnabled = $false
    Start-Tarefa -Nome 'sup-wifi' -Script 'Get-SenhasWifi' -AoTerminar {
        param($saida, $erro)
        $UI.BtnSupWifi.IsEnabled = $true
        $r = @($saida)[0]
        if ($erro -or -not $r) { Show-Toast "Falhou: $erro" 'erro'; return }
        if ($r.SemWifi) { $UI.TxtSupWifi.Text = $r.Mensagem; $S.WifiRedes = @(); Show-ListaWifi; return }
        $S.WifiRedes = @($r.Redes)
        $UI.TxtSupWifi.Text = if ($S.WifiRedes.Count) { "$($S.WifiRedes.Count) rede(s) salvas. Clique em Mostrar para ver a senha." } else { 'Nenhuma rede Wi-Fi salva neste PC.' }
        Show-ListaWifi
    }
})
$UI.ListaWifi.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
    param($origem, $e)
    $b = $e.OriginalSource
    if ([string]$b.Content -eq 'Copiar') {
        if ($b.Tag) { [Windows.Clipboard]::SetText([string]$b.Tag); Show-Toast 'Senha copiada.' 'ok' } else { Show-Toast 'Esta rede não tem senha salva.' 'info' }
    } elseif ($b.Tag) {
        $S.WifiVisivel[[string]$b.Tag] = -not $S.WifiVisivel[[string]$b.Tag]
        Show-ListaWifi
    }
})

# ---------------- Temperaturas (ao vivo enquanto a aba está aberta) ----------------
$S.Temp = @{ Controle = $null }
function Start-Temperaturas {
    if (Test-TarefaAtiva 'temperaturas') { return }
    $S.Temp.Controle = [hashtable]::Synchronized(@{ Parar = $false })
    $UI.TxtTempStatus.Text = 'Lendo os sensores...'
    $pulso = New-Object Windows.Media.Animation.DoubleAnimation 1, 0.25, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(900)))
    $pulso.AutoReverse = $true; $pulso.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
    $UI.PontoTempAoVivo.BeginAnimation([Windows.UIElement]::OpacityProperty, $pulso)
    Start-Tarefa -Nome 'temperaturas' -Script 'Watch-Temperaturas $Parametros.Controle' -Parametros @{ Controle = $S.Temp.Controle } -AoEvento {
        param($ev)
        if ($ev.Tipo -eq 'temp') { Show-Temperaturas $ev.Dados }
    } -AoTerminar { $UI.PontoTempAoVivo.BeginAnimation([Windows.UIElement]::OpacityProperty, $null) }
}
function Stop-Temperaturas { if ($S.Temp -and $S.Temp.Controle) { $S.Temp.Controle.Parar = $true } }

function Show-Temperaturas($Dados) {
    $sens = @($Dados.Sensores)
    $UI.ListaTemp.ItemsSource = ConvertTo-Linhas @($sens | ForEach-Object {
        New-Linha -Titulo $_.Nome -Extra ([string]$_.Tipo).ToUpperInvariant() -Tag "$($_.Celsius) °C" -Nivel $_.Nivel -Texto "$($_.Detalhe). $($_.Limite)" -Valor ([math]::Min(1, $_.Celsius / 100))
    })
    $UI.CardTempCpu.Visibility = if ($Dados.SemCpu) { 'Visible' } else { 'Collapsed' }
    $UI.TxtTempStatus.Text = if ($sens.Count) { "Atualizado às $(Get-Date -Format 'HH:mm:ss'). Atualiza a cada 2 segundos enquanto esta tela estiver aberta." }
                             else { 'Nenhum sensor disponível sem programas extras. Veja a dica abaixo.' }
}
$UI.BtnTempHwmonitor.Add_Click({
    Show-Ferramenta 'RbFerProgramas'
    if (-not $S.WingetLista) { Initialize-Winget }
    $hw = $S.WingetLista | Where-Object { $_.Tag -eq 'CPUID.HWMonitor' } | Select-Object -First 1
    if ($hw) { $hw.Marcado = $true; Show-Toast 'HWMonitor marcado. Clique em "Instalar selecionados".' 'info' }
})

# ===============================================================
#  Histórico
# ===============================================================
function Update-Historico {
    $hist = @(Get-Historico 60)
    $mapa = @{ ok = 'ok'; erro = 'erro'; aviso = 'aviso'; ignorado = 'ignorado'; simulado = 'info' }
    $UI.ListaHistorico.ItemsSource = [Otz.Linha[]]@(foreach ($h in $hist) {
        $itens = @($h.Itens)
        $ok = @($itens | Where-Object Status -eq 'ok').Count
        $er = @($itens | Where-Object Status -eq 'erro').Count
        $av = @($itens | Where-Object { $_.Status -in 'aviso', 'ignorado' }).Count
        $data = try { ([datetime]::Parse($h.Data, [Globalization.CultureInfo]::InvariantCulture)).ToString('dd/MM/yyyy  HH:mm') } catch { $h.Data }
        $acao = if ($h.Acao -eq 'desfazer') { 'Desfazer' } else { 'Aplicação' }
        $partes = @("$ok ok"); if ($er) { $partes += "$er erro(s)" }; if ($av) { $partes += "$av aviso(s)" }
        $l = New-Linha -Titulo "$acao  ·  $data" -Texto ($partes -join '  ·  ') -Extra "$($itens.Count) item(ns)" -Nivel $(if ($er) { 'alto' } elseif ($av) { 'medio' } else { 'ok' })
        $l.Filhos = [Otz.Linha[]]@(foreach ($i in $itens) { New-Linha -Titulo $i.Nome -Texto ([string]$i.Mensagem) -Nivel $mapa[[string]$i.Status] })
        $l
    })
    $UI.TxtHistoricoVazio.Visibility = if ($hist.Count) { 'Collapsed' } else { 'Visible' }
}

$UI.BtnDesfazerTudo.Add_Click({
    $ids = @($S.Ajustes | Where-Object PodeDesfazer | ForEach-Object Id)
    if ($ids.Count -eq 0) { Show-Toast 'Nada para desfazer: nenhum ajuste foi feito pelo otimizador.' 'info'; return }
    $linhas = @($S.Ajustes | Where-Object PodeDesfazer | ForEach-Object { New-Linha -Titulo $_.Nome -Nivel 'info' })
    Show-Dialogo -Titulo "Desfazer $($ids.Count) ajuste(s)?" -Texto 'Cada um volta ao valor exato que tinha antes do otimizador.' -Linhas $linhas -TextoOk 'Desfazer todos' -Tipo 'perigo' `
        -Dados ([string[]]$ids) -Acao { param($ids) Start-Execucao 'desfazer' $ids }
})
$UI.BtnRstrui.Add_Click({ Start-Process rstrui.exe })
$UI.BtnAbrirDados.Add_Click({ Start-Process explorer.exe "`"$($Otz.Dados)`"" })
$UI.BtnAbrirLog.Add_Click({ if (Test-Path $Otz.ArqLog) { Start-Process notepad.exe "`"$($Otz.ArqLog)`"" } else { Show-Toast 'Ainda não há log hoje.' 'info' } })

# ===============================================================
#  Ajuda
# ===============================================================
$faq = @(
    ,@('Apliquei um ajuste e não gostei. Como volto?', 'Em Otimizar, clique no ajuste e use "Desfazer este ajuste". Para voltar tudo de uma vez: Histórico > Desfazer todos. Antes de mudar qualquer coisa, o otimizador guarda o valor original exato, inclusive se a configuração nem existia.')
    ,@('Algo deu muito errado. E agora?', 'Use o ponto de restauração: Histórico > Abrir restauração (ou Win+R, digite rstrui e Enter). Escolha o ponto "Otimizador Vinicius" com a data certa. O Windows volta a como estava antes, sem apagar seus arquivos pessoais.')
    ,@('O que é um ponto de restauração?', 'É uma "foto" das configurações do Windows. O otimizador cria uma automaticamente antes da primeira alteração, sempre que você abre o programa.')
    ,@('Por que alguns itens estão apagados (cinza)?', 'Eles não existem na sua versão do Windows (por exemplo, itens só do Windows 11) ou não se aplicam ao seu hardware. Passe o mouse por cima do item para ver o motivo.')
    ,@('O que o botão "Simular" faz?', 'Mostra, item por item, o valor atual e o valor que seria gravado, sem alterar nada. Bom para conferir antes de aplicar.')
    ,@('Qual perfil devo escolher?', 'Básico: qualquer PC. Trabalho: escritório e suporte técnico. Gamer: PC de jogos. PC simples: computadores com pouca memória ou HD. A tela Início sugere um perfil de acordo com o seu hardware, e você pode desmarcar o que quiser.')
    ,@('O que é "sair da conta" (logoff)?', 'É fechar a sua sessão sem desligar o PC: Iniciar > clique no seu nome > Sair. Alguns ajustes de teclado e aparência só são lidos quando você entra de novo.')
    ,@('Por que a tela piscou?', 'Alguns ajustes de aparência precisam recarregar a barra de tarefas (o Explorer). As janelas abertas não são fechadas.')
    ,@('Posso usar em notebook?', 'Sim. Os ajustes de energia valem só na tomada; na bateria nada muda. Evite "Num Lock ligado ao iniciar" em notebooks sem teclado numérico separado.')
    ,@('Aparece "gerenciado pela sua organização" nas Configurações. Por quê?', 'Alguns ajustes usam políticas do Windows, as mesmas que as empresas usam. É só um aviso. Ao desfazer o ajuste, a mensagem some.')
    ,@('O antivírus reclamou. É vírus?', 'Não. O otimizador é um script aberto: tudo o que ele faz está nos arquivos da pasta src e fica registrado no log. Alguns antivírus desconfiam de qualquer script que mexa no registro.')
    ,@('Onde ficam os arquivos do otimizador?', "Em $($Otz.Dados): o log de cada dia, os valores originais (originais.json), o histórico (historico.jsonl) e os relatórios.")
)
foreach ($f in $faq) {
    $ex = [Windows.Controls.Expander]::new()
    $ex.Style = $Win.FindResource('Sanfona')
    $h = [Windows.Controls.TextBlock]::new(); $h.Text = $f[0]; $h.FontWeight = 'SemiBold'; $h.TextWrapping = 'Wrap'
    $c = [Windows.Controls.TextBlock]::new(); $c.Text = $f[1]; $c.Style = $Win.FindResource('CorpoSec')
    $ex.Header = $h; $ex.Content = $c
    [void]$UI.PainelFaq.Children.Add($ex)
}
$UI.TxtSobre.Text = "Otimizador Vinicius v$($Otz.Versao). Desenvolvimento próprio, para Windows 10 e 11. Cada ajuste é uma ficha no catálogo (src\catalogo) com explicação, detecção, aplicação e desfazer."
$UI.TxtSobrePasta.Text = "Dados: $($Otz.Dados)"

# ===============================================================
#  Janela: barra de título, tema, atalhos
# ===============================================================
$UI.BtnMinimizar.Add_Click({ $Win.WindowState = 'Minimized' })
$UI.BtnMaximizar.Add_Click({ $Win.WindowState = if ($Win.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' } })
$UI.BtnFechar.Add_Click({ $Win.Close() })
$Win.Add_StateChanged({
    $max = $Win.WindowState -eq 'Maximized'
    $UI.Raiz.Margin = if ($max) { '7' } else { '0' }
    $UI.IcoMaximizar.Text = if ($max) { G 0xE923 } else { G 0xE922 }
})
$UI.BtnTema.Add_Click({
    Set-Tema $(if ($S.Tema -eq 'escuro') { 'claro' } else { 'escuro' })
    Save-Preferencias
})
$Win.Add_Closing({
    param($origem, $e)
    if ($S.Executando) { $e.Cancel = $true; Show-Toast 'Aguarde a execução terminar antes de fechar.' 'aviso'; return }
    if ($S.Mon -and $S.Mon.Controle) { $S.Mon.Controle.Parar = $true }
    Stop-Temperaturas
})
$Win.Add_PreviewKeyDown({
    param($origem, $e)
    if ($e.Key -eq 'Escape' -and $UI.Dialogo.Visibility -eq 'Visible') { Hide-Dialogo; $e.Handled = $true }
    elseif ($e.Key -eq 'F' -and [Windows.Input.Keyboard]::Modifiers -eq 'Control') { Open-Pagina 'NavOtimizar'; [void]$UI.TxtBusca.Focus(); $e.Handled = $true }
})
$Win.Dispatcher.Add_UnhandledException({
    param($origem, $e)
    $e.Handled = $true
    Write-Log "ERRO na interface: $($e.Exception.Message)"
    Show-Toast "Algo deu errado: $($e.Exception.Message)" 'erro'
})

# ===============================================================
#  Diagnóstico (só leitura)
# ===============================================================
$Script:DiagPaineis = [ordered]@{ RbDiagLento = 'DiagLento'; RbDiagBoot = 'DiagBoot'; RbDiagEstab = 'DiagEstab'; RbDiagConexao = 'DiagConexao'; RbDiagBios = 'DiagBios' }
$S.DiagCarregado = @{}

function Show-Diagnostico([string]$Rb) {
    if (-not $UI[$Rb].IsChecked) { $UI[$Rb].IsChecked = $true; return }
    $painel = $DiagPaineis[$Rb]
    foreach ($p in $DiagPaineis.Values) { if ($p -ne $painel) { $UI[$p].Visibility = 'Collapsed' } }
    $UI[$painel].Visibility = 'Visible'
    Start-Animacao $UI[$painel] ([Windows.UIElement]::OpacityProperty) 0 1 220
    if (-not $S.DiagCarregado[$painel]) {
        $S.DiagCarregado[$painel] = $true
        switch ($painel) {
            'DiagLento'   { Start-AnaliseLento }
            'DiagBoot'    { Update-Boot }
            'DiagEstab'   { Update-Estab }
            'DiagConexao' { Update-Conexao }
            'DiagBios'    { Update-Bios }
        }
    }
}
foreach ($rb in $DiagPaineis.Keys) { $UI[$rb].Add_Checked({ Show-Diagnostico $this.Name }) }

# Linha de achado (New-Achado) → Otz.Linha para o modelo ModeloSaude
function ConvertTo-LinhaAchado($a) { return (New-Linha -Titulo $a.Titulo -Texto $a.Texto -Nivel $a.Nivel -Tag ([string]$a.Acao) -Extra ([string]$a.Rotulo)) }

# Botões das listas de achados (todas as telas de diagnóstico)
function Invoke-AcaoAchado([string]$Acao) {
    if (-not $Acao) { return }
    switch -Wildcard ($Acao) {
        'windowsupdate' { Start-Process 'ms-settings:windowsupdate' }
        'reiniciar'     { $UI.BtnExecReiniciar.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
        'temperaturas'  { Open-Pagina 'NavFerramentas'; Show-Ferramenta 'RbFerTemp' }
        'inicializacao' { Open-Pagina 'NavFerramentas'; Show-Ferramenta 'RbFerInicio' }
        'perfmon'       { Start-Process perfmon.exe -ArgumentList '/rel' }
        'bios'          { Open-Pagina 'NavDiagnostico'; Show-Diagnostico 'RbDiagBios' }
        'estabilidade'  { Open-Pagina 'NavDiagnostico'; Show-Diagnostico 'RbDiagEstab' }
        '*.*' {
            $a = $S.PorId[$Acao]
            if (-not $a) { return }
            if (-not $a.Habilitado) { Show-Toast $a.Motivo 'info'; return }
            if ($a.Estado -eq 'aplicado') { Show-Toast "'$($a.Nome)' já está aplicado." 'info'; return }
            Request-Aplicar @($a)
        }
    }
}
foreach ($lista in 'ListaLento', 'ListaBootAtrasos', 'ListaEstab', 'ListaConexao', 'ListaBios') {
    $UI[$lista].AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
        param($origem, $e)
        try { Invoke-AcaoAchado ([string]$e.OriginalSource.Tag) } catch { Show-Toast "Não foi possível abrir: $($_.Exception.Message)" 'erro' }
    })
}

# ---------------- Por que está lento? ----------------
function Start-AnaliseLento {
    if (Test-TarefaAtiva 'lento') { return }
    $UI.BtnLentoAnalisar.IsEnabled = $false
    $UI.TxtLentoStatus.Text = 'Medindo por 2 segundos...'
    Start-Tarefa -Nome 'lento' -Script 'Get-DiagnosticoLentidao' -AoTerminar {
        param($saida, $erro)
        $UI.BtnLentoAnalisar.IsEnabled = $true
        $d = @($saida | Where-Object { $_ -and $null -ne $_.Cpu })[0]
        if (-not $d) { $UI.TxtLentoStatus.Text = "Não foi possível medir: $erro"; return }
        Show-Lento $d
    }
}

function New-LinhaProcesso($P, [double]$Fracao, [string]$Valor) {
    $sub = "$($P.Nome).exe"
    if ($P.Qtd -gt 1) { $sub += "  ·  $($P.Qtd) processos" }
    $botao = if ($P.Nome -in $Script:ProcessosProtegidos -or $P.Nome -eq 'Idle') { '' } else { 'Finalizar' }
    return (New-Linha -Titulo $P.Descricao -Texto $sub -Valor ([math]::Min(1, $Fracao)) -Extra $Valor -Icone $botao -Tag $P.Nome)
}

function Show-Lento($D) {
    $UI.TxtLentoStatus.Text = "Medido às $(Get-Date -Format 'HH:mm:ss'). Clique de novo para medir outra vez."
    $UI.TxtLentoCpu.Text = "$($D.Cpu)%"
    $UI.TxtLentoRam.Text = "$($D.Ram)%"
    $UI.TxtLentoRamSub.Text = "de $(Format-Tamanho $D.RamTotal)  ·  memória virtual em $($D.Commit)%"
    $UI.TxtLentoDisco.Text = "$($D.Disco)%"
    $UI.TxtLentoDiscoSub.Text = (@($D.Discos) | ForEach-Object { "$($_.Nome) $($_.Ocupado)%" }) -join '  ·  '
    Start-Animacao $UI.BarraLentoCpu ([Windows.Controls.Primitives.RangeBase]::ValueProperty) 0 $D.Cpu 600
    Start-Animacao $UI.BarraLentoRam ([Windows.Controls.Primitives.RangeBase]::ValueProperty) 0 $D.Ram 600
    Start-Animacao $UI.BarraLentoDisco ([Windows.Controls.Primitives.RangeBase]::ValueProperty) 0 $D.Disco 600
    $UI.ListaLento.ItemsSource = ConvertTo-Linhas @($D.Achados | ForEach-Object { ConvertTo-LinhaAchado $_ })
    $cpuLista = @($D.TopCpu | Where-Object { $_.Cpu -ge 0.5 })
    if ($cpuLista.Count) { $UI.ListaLentoCpu.ItemsSource = ConvertTo-Linhas @($cpuLista | ForEach-Object { New-LinhaProcesso $_ ($_.Cpu / 100) "$(([double]$_.Cpu).ToString('0.#'))%" }) }
    else { $UI.ListaLentoCpu.ItemsSource = ConvertTo-Linhas @(New-Linha -Titulo 'Processador folgado' -Texto 'Nenhum programa passou de 0,5% durante a medição.') }
    $UI.ListaLentoRam.ItemsSource = ConvertTo-Linhas @($D.TopRam | ForEach-Object { New-LinhaProcesso $_ ($_.Ram / $D.RamTotal) (Format-Tamanho $_.Ram) })
}

$UI.BtnLentoAnalisar.Add_Click({ Start-AnaliseLento })
foreach ($lista in 'ListaLentoCpu', 'ListaLentoRam') {
    $UI[$lista].AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
        param($origem, $e)
        $nome = [string]$e.OriginalSource.Tag
        $l = $e.OriginalSource.DataContext
        if (-not $nome) { return }
        Show-Dialogo -Titulo "Finalizar $($l.Titulo)?" -Texto "Todos os processos de $nome.exe serão fechados na hora. O que não estiver salvo nele será perdido." -TextoOk 'Finalizar' -Tipo 'perigo' -Dados $nome -Acao {
            param($n)
            try {
                Get-Process -Name $n -ErrorAction Stop | Stop-Process -Force -ErrorAction Stop
                Write-Log "Processo finalizado pelo usuário: $n"
                Show-Toast "$n finalizado." 'ok'
            } catch { Show-Toast "Não foi possível finalizar: $($_.Exception.Message)" 'erro' }
            Start-AnaliseLento
        }
    })
}

# ---------------- Tempo para ligar ----------------
function Update-Boot {
    if (Test-TarefaAtiva 'boot') { return }
    $UI.TxtBootUltimo.Text = 'Lendo...'
    Start-Tarefa -Nome 'boot' -Script 'Get-HistoricoBoot 20' -AoTerminar {
        param($saida, $erro)
        $b = @($saida | Where-Object { $_ -and $null -ne $_.Disponivel })[0]
        if (-not $b) { $UI.TxtBootUltimo.Text = 'Não foi possível ler'; $UI.TxtBootSub.Text = $erro; return }
        Show-Boot $b
    }
}

function Format-Segundos([double]$Valor) { return "$($Valor.ToString('0.0')) s" }

# Número com vírgula decimal (o "$x" do PowerShell sempre usa ponto)
function Format-Numero($Valor) {
    if ($Valor -is [double] -or $Valor -is [decimal] -or $Valor -is [single]) { return ([double]$Valor).ToString('0.#') }
    return [string]$Valor
}

function Show-Boot($B) {
    $UI.CardBootLista.Visibility = if ($B.Disponivel) { 'Visible' } else { 'Collapsed' }
    if (-not $B.Disponivel) {
        $UI.TxtBootUltimo.Text = 'Sem medições ainda'
        $UI.TxtBootSub.Text = $B.Motivo
    } else {
        $boots = @($B.Boots)
        $u = $boots[0]
        $media = ($boots | Measure-Object AteAreaDeTrabalho -Average).Average
        $veredito = if ($u.AteAreaDeTrabalho -le 30) { 'rápido' } elseif ($u.AteAreaDeTrabalho -le 60) { 'normal' } else { 'lento' }
        $UI.TxtBootUltimo.Text = "$(Format-Segundos $u.AteAreaDeTrabalho) para ligar ($veredito)"
        $UI.TxtBootSub.Text = "Última inicialização em $($u.Data.ToString('dd/MM HH:mm')): área de trabalho em $(Format-Segundos $u.AteAreaDeTrabalho), tudo carregado em $(Format-Segundos $u.Total). Média das últimas $($boots.Count): $(Format-Segundos $media)."
        $max = ($boots | Measure-Object AteAreaDeTrabalho -Maximum).Maximum; if ($max -le 0) { $max = 1 }
        $UI.ListaBoot.ItemsSource = ConvertTo-Linhas @($boots | ForEach-Object { New-Linha -Titulo $_.Data.ToString('dd/MM/yyyy  HH:mm') -Valor ($_.AteAreaDeTrabalho / $max) -Texto (Format-Segundos $_.AteAreaDeTrabalho) })
    }
    $atrasos = @($B.Atrasos)
    $UI.TxtBootAtrasosTitulo.Visibility = if ($B.Disponivel) { 'Visible' } else { 'Collapsed' }
    if (-not $B.Disponivel) { $UI.ListaBootAtrasos.ItemsSource = $null; return }
    if ($atrasos.Count -eq 0) {
        $UI.ListaBootAtrasos.ItemsSource = ConvertTo-Linhas @(New-Linha -Titulo 'Nada atrasou a inicialização' -Texto 'O Windows não registrou programas, drivers ou serviços lentos nos últimos 60 dias.' -Nivel 'ok')
    } else {
        $UI.ListaBootAtrasos.ItemsSource = ConvertTo-Linhas @($atrasos | ForEach-Object {
            $tag = if ($_.Tipo -eq 'Programa') { 'inicializacao' } else { '' }
            $rot = if ($tag) { 'Ver inicialização' } else { '' }
            New-Linha -Titulo $_.Nome -Texto "$($_.Tipo) que atrasou a inicialização $($_.Vezes) vez(es), em média $(Format-Segundos ($_.Ms / 1000.0 / [math]::Max(1, $_.Vezes))) a mais." -Nivel 'medio' -Tag $tag -Extra $rot
        })
    }
}
$UI.BtnBootAtualizar.Add_Click({ Update-Boot })

# ---------------- Travamentos ----------------
function Update-Estab {
    if (Test-TarefaAtiva 'estab') { return }
    Start-Tarefa -Nome 'estab' -Script 'Get-Estabilidade 30' -AoTerminar {
        param($saida, $erro)
        $e = @($saida | Where-Object { $_ -and $null -ne $_.Dias })[0]
        if (-not $e) { $UI.TxtEstabTitulo.Text = "Não foi possível ler: $erro"; return }
        $UI.TxtEstabIndice.Text = if ($null -ne $e.Indice) { $e.Indice.ToString('0.0') } else { '—' }
        $UI.TxtEstabTitulo.Text = if ($e.TelasAzuis -or $e.Desligamentos -ge 3) { 'O PC está instável: veja os pontos abaixo' }
                                  elseif ($e.Desligamentos -or @($e.Apps).Count) { 'Alguns problemas pontuais' }
                                  else { 'PC estável nos últimos 30 dias' }
        $UI.ListaEstab.ItemsSource = ConvertTo-Linhas @($e.Achados | ForEach-Object { ConvertTo-LinhaAchado $_ })
        $apps = @($e.Apps)
        $UI.TxtEstabAppsTitulo.Visibility = if ($apps.Count) { 'Visible' } else { 'Collapsed' }
        $UI.ListaEstabApps.ItemsSource = ConvertTo-Linhas @($apps | ForEach-Object {
            $partes = @(); if ($_.Erros) { $partes += "fechou com erro $($_.Erros) vez(es)" }; if ($_.Travou) { $partes += "parou de responder $($_.Travou) vez(es)" }
            $dica = if ($_.Sistema) { 'É um componente do Windows: se continuar, use Ferramentas > Reparar Windows.' } else { 'Atualize ou reinstale o programa; se for um jogo, verifique os arquivos pelo launcher.' }
            New-Linha -Titulo $_.App -Texto "$(($partes -join ' e ')) (último: $($_.Ultimo.ToString('dd/MM HH:mm'))). $dica" -Nivel $(if (($_.Erros + $_.Travou) -ge 5) { 'medio' } else { 'info' })
        })
    }
}
$UI.BtnEstabMonitor.Add_Click({ Start-Process perfmon.exe -ArgumentList '/rel' })

# ---------------- Cabo e Wi-Fi ----------------
function Update-Conexao {
    if (Test-TarefaAtiva 'conexao') { return }
    $UI.BtnConexaoAtualizar.IsEnabled = $false
    Start-Tarefa -Nome 'conexao' -Script 'Get-QualidadeConexao' -AoTerminar {
        param($saida, $erro)
        $UI.BtnConexaoAtualizar.IsEnabled = $true
        $UI.ListaConexao.ItemsSource = ConvertTo-Linhas @($saida | Where-Object { $_ -and $_.Titulo } | ForEach-Object { ConvertTo-LinhaAchado $_ })
    }
}
$UI.BtnConexaoAtualizar.Add_Click({ Update-Conexao })

# ---------------- BIOS e hardware ----------------
function Update-Bios {
    if (Test-TarefaAtiva 'bios') { return }
    Start-Tarefa -Nome 'bios' -Script 'Get-ChecklistBios' -AoTerminar {
        param($saida, $erro)
        $UI.ListaBios.ItemsSource = ConvertTo-Linhas @($saida | Where-Object { $_ -and $_.Titulo } | ForEach-Object { ConvertTo-LinhaAchado $_ })
    }
}
$UI.BtnBiosReiniciar.Add_Click({
    Show-Dialogo -Titulo 'Reiniciar e abrir a BIOS?' -Texto 'Salve o que estiver aberto. O PC reinicia em 5 segundos e entra direto na configuração da BIOS (UEFI). Para sair sem mudar nada, use "Exit without saving" / "Sair sem salvar".' -TextoOk 'Reiniciar na BIOS' -Tipo 'perigo' -Acao {
        $saida = & shutdown.exe /r /fw /t 5 2>&1
        if ($LASTEXITCODE -ne 0) { Show-Toast 'Este PC não aceita abrir a BIOS pelo Windows. Reinicie e aperte Del, F2 ou F10 logo que a tela acender.' 'aviso'; Write-Log "shutdown /fw falhou: $($saida -join ' ')" }
        else { Write-Log 'Reinício para a BIOS pedido pelo usuário.' }
    }
})

# ===============================================================
#  Ferramentas novas: modo jogo, apps do Windows, vários PCs
# ===============================================================

# ---------------- Modo jogo agora ----------------
function Update-Jogo {
    $e = Get-EstadoModoJogo
    $ativo = [bool]$e.Ativo
    $UI.BtnJogoAtivar.Visibility = if ($ativo) { 'Collapsed' } else { 'Visible' }
    $UI.BtnJogoDesativar.Visibility = if ($ativo) { 'Visible' } else { 'Collapsed' }
    if ($ativo) {
        $desde = try { ([datetime]::Parse($e.Desde, [Globalization.CultureInfo]::InvariantCulture)).ToString('HH:mm') } catch { '?' }
        $UI.TxtJogoTitulo.Text = "Modo jogo ativo desde $desde"
        $n = @($e.Fechados).Count
        $UI.TxtJogoSub.Text = "$n programa(s) fechado(s)" + $(if ($e.PlanoAnterior) { ' e plano de energia em desempenho máximo.' } else { '.' }) + ' Quando terminar, clique em "Terminei de jogar".'
        $UI.IcoJogo.Text = G 0xE7FC
        Set-Referencia $UI.CirculoJogo ([Windows.Controls.Border]::BackgroundProperty) 'AcentoSuave'
        Set-Referencia $UI.IcoJogo ([Windows.Controls.TextBlock]::ForegroundProperty) 'Acento'
    } else {
        $UI.TxtJogoTitulo.Text = 'Modo jogo desligado'
        $UI.TxtJogoSub.Text = 'Antes de jogar, fecha os programas que você escolher e coloca o PC em desempenho máximo. Ao terminar, volta tudo como estava.'
        Set-Referencia $UI.CirculoJogo ([Windows.Controls.Border]::BackgroundProperty) 'Superficie2'
        Set-Referencia $UI.IcoJogo ([Windows.Controls.TextBlock]::ForegroundProperty) 'TextoSec'
        $UI.ChkJogoPlano.IsChecked = if ($null -ne $e.TrocarPlano) { [bool]$e.TrocarPlano } else { $true }
    }
    $S.JogoPreferidos = [string[]]@($e.Preferidos)
    Start-Tarefa -Nome 'jogo-lista' -Script 'Get-ProgramasAbertos' -AoTerminar {
        param($saida, $erro)
        $lista = @($saida | Where-Object { $_ -and $_.Nome })
        $S.JogoLista = ConvertTo-Linhas @($lista | ForEach-Object {
            $txt = "$($_.Nome).exe" + $(if ($_.Pesa) { '  ·  costuma pesar durante jogos' } else { '' })
            $l = New-Linha -Titulo $_.Descricao -Texto $txt -Extra (Format-Tamanho $_.Ram) -Tag $_.Nome
            $l.Marcado = ($S.JogoPreferidos -contains $_.Nome)
            $l
        })
        $UI.ListaJogo.ItemsSource = $S.JogoLista
        $UI.TxtJogoVazio.Visibility = if ($lista.Count) { 'Collapsed' } else { 'Visible' }
    }
}

$UI.BtnJogoAtualizar.Add_Click({ Update-Jogo })
$UI.BtnJogoAtivar.Add_Click({
    $nomes = [string[]]@($S.JogoLista | Where-Object Marcado | ForEach-Object Tag)
    $plano = [bool]$UI.ChkJogoPlano.IsChecked
    if (-not $nomes.Count -and -not $plano) { Show-Toast 'Marque algum programa para fechar ou ligue o desempenho máximo.' 'info'; return }
    $linhas = @($S.JogoLista | Where-Object Marcado | ForEach-Object { New-Linha -Titulo "Fechar $($_.Titulo)" -Nivel 'medio' })
    if ($plano) { $linhas += New-Linha -Titulo 'Plano de energia em desempenho máximo' -Nivel 'info' }
    Show-Dialogo -Titulo 'Ativar o modo jogo?' -Texto 'Salve o que estiver aberto nos programas marcados: eles serão fechados como se você clicasse no X.' -Linhas $linhas -TextoOk 'Ativar' -Dados @{ Nomes = $nomes; Plano = $plano } -Acao {
        param($d)
        $UI.BtnJogoAtivar.IsEnabled = $false
        $UI.TxtJogoSub.Text = 'Fechando os programas...'
        Start-Tarefa -Nome 'jogo' -Script 'Start-ModoJogo -Nomes $Parametros.Nomes -TrocarPlano $Parametros.Plano' -Parametros @{ Nomes = $d.Nomes; Plano = $d.Plano } -AoTerminar {
            param($saida, $erro)
            $UI.BtnJogoAtivar.IsEnabled = $true
            if ($erro) { Show-Toast "Falhou: $erro" 'erro' }
            $UI.ListaJogoRes.ItemsSource = ConvertTo-Linhas @($saida | Where-Object { $_ -and $_.Titulo } | ForEach-Object { ConvertTo-LinhaAchado $_ })
            Show-Toast 'Modo jogo ativo. Bom jogo!' 'ok'
            Update-Jogo
        }
    }
})
$UI.BtnJogoDesativar.Add_Click({
    $UI.BtnJogoDesativar.IsEnabled = $false
    Start-Tarefa -Nome 'jogo' -Script 'Stop-ModoJogo -Reabrir $Parametros.Reabrir' -Parametros @{ Reabrir = [bool]$UI.ChkJogoReabrir.IsChecked } -AoTerminar {
        param($saida, $erro)
        $UI.BtnJogoDesativar.IsEnabled = $true
        if ($erro) { Show-Toast "Falhou: $erro" 'erro' }
        $UI.ListaJogoRes.ItemsSource = ConvertTo-Linhas @($saida | Where-Object { $_ -and $_.Titulo } | ForEach-Object { ConvertTo-LinhaAchado $_ })
        Show-Toast 'Modo jogo desligado: tudo voltou ao normal.' 'ok'
        Update-Jogo
    }
})

# ---------------- Apps que vieram com o Windows ----------------
function Update-Apps {
    $UI.TxtAppsStatus.Text = 'Procurando...'
    Start-Tarefa -Nome 'apps' -Script 'Get-AppsPreInstalados' -AoTerminar {
        param($saida, $erro)
        $lista = @($saida | Where-Object { $_ -and $_.Pacote })
        $UI.ListaApps.ItemsSource = ConvertTo-Linhas @($lista | ForEach-Object {
            $l = New-Linha -Titulo $_.Nome -Texto $_.Texto -Extra $_.Atencao -Tag $_.Pacote -Icone 'Remover'
            $l.Nivel = ''
            $l
        })
        $UI.TxtAppsStatus.Text = if ($lista.Count) { "$($lista.Count) app(s) que muita gente não usa. Remova só o que você não usa: um por vez, e todos podem ser reinstalados pela Microsoft Store. Apps essenciais (Store, Fotos, Calculadora, Bloco de Notas, Câmera) nem aparecem aqui." }
                                 else { 'Nenhum app desnecessário conhecido foi encontrado neste PC.' }
    }
}
$UI.ListaApps.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
    param($origem, $e)
    $l = $e.OriginalSource.DataContext
    if (-not $l -or -not $l.Tag) { return }
    $linhas = @(); if ($l.Extra) { $linhas += New-Linha -Titulo $l.Extra -Nivel 'medio' }
    Show-Dialogo -Titulo "Remover $($l.Titulo)?" -Texto "$($l.Texto) Para reinstalar depois, procure pelo nome na Microsoft Store." -Linhas $linhas -TextoOk 'Remover' -Tipo 'perigo' -Dados $l.Tag -Acao {
        param($pacote)
        Start-Tarefa -Nome 'apps-remover' -Script 'Remove-AppPreInstalado $Parametros.Pacote' -Parametros @{ Pacote = $pacote } -AoTerminar {
            param($saida, $erro)
            $r = @($saida | Where-Object { $_ -and $_.Status })[0]
            if ($r) { Show-Toast $r.Mensagem $(if ($r.Status -eq 'ok') { 'ok' } elseif ($r.Status -eq 'erro') { 'erro' } else { 'info' }) } else { Show-Toast "Falhou: $erro" 'erro' }
            Update-Apps
        }
    }
})

# ---------------- Desinstalar programas por completo ----------------
function Get-AvisoDesinstalar($P) {
    if ($P.Tipo -eq 'app') {
        if ($P.Pacote -match '^Microsoft\.(WindowsCalculator|WindowsNotepad|Windows\.Photos|WindowsTerminal|Paint|ScreenSketch|WindowsCamera|GamingServices|XboxIdentityProvider|MicrosoftEdge)') { return 'Faz parte do Windows. Dá para reinstalar pela Microsoft Store.' }
        if ($P.Pacote -match 'Gaming|Xbox') { return 'Jogos do Game Pass e da Store podem depender disto.' }
        return ''
    }
    if ($P.Nome -match 'Visual C\+\+|\.NET|DirectX|Runtime|Redistributable|WebView2') { return 'Outros programas e jogos dependem disto: desinstale só se souber que nada usa.' }
    if ($P.Nome -match '(?i)driver|chipset|controller|audio|áudio|bluetooth|wireless|wi-fi') { return 'Parece um driver: sem ele, algum dispositivo pode parar de funcionar.' }
    if ($P.Nome -match 'Microsoft Edge') { return 'Navegador do Windows: alguns recursos do sistema dependem dele.' }
    return ''
}

function Update-Desinstalar {
    if (Test-TarefaAtiva 'des-lista') { return }
    $UI.TxtDesSelecao.Text = 'Lendo os programas instalados...'
    Start-Tarefa -Nome 'des-lista' -Script 'Get-ProgramasInstalados' -AoTerminar {
        param($saida, $erro)
        $S.DesTodos = @($saida | Where-Object { $_ -and $_.Id })
        $S.DesLinhas = @{}
        foreach ($p in $S.DesTodos) {
            $partes = New-Object System.Collections.Generic.List[string]
            $partes.Add($(if ($p.Tipo -eq 'app') { 'App da Store' } else { 'Programa' }))
            if ($p.Editor) { $partes.Add($p.Editor) }
            if ($p.Versao) { $partes.Add("versão $($p.Versao)") }
            if ($p.Data) { $partes.Add("instalado em $($p.Data.ToString('dd/MM/yyyy'))") }
            $tam = if ($p.Bytes -gt 0) { Format-Tamanho $p.Bytes } else { '' }
            $l = New-Linha -Titulo $p.Nome -Texto ($partes -join '  ·  ') -Extra (Get-AvisoDesinstalar $p) -Tag $p.Id -Icone $tam
            $l.add_PropertyChanged({ param($o, $e) if ($e.PropertyName -eq 'Marcado') { Update-SelecaoDes } })
            $S.DesLinhas[$p.Id] = $l
        }
        Show-ListaDes
        Update-SelecaoDes
    }
}

function Show-ListaDes {
    if (-not $S.DesTodos) { return }
    $busca = Remove-Acentos $UI.TxtDesBusca.Text.Trim()
    $tipo = if ($UI.RbDesProgramas.IsChecked) { 'programa' } elseif ($UI.RbDesApps.IsChecked) { 'app' } else { '' }
    $lista = New-Object System.Collections.Generic.List[Otz.Linha]
    foreach ($p in @($S.DesTodos | Sort-Object @{ Expression = { $_.Bytes }; Descending = $true }, Nome)) {
        if ($tipo -and $p.Tipo -ne $tipo) { continue }
        if ($busca -and (Remove-Acentos "$($p.Nome) $($p.Editor)") -notlike "*$busca*") { continue }
        $lista.Add($S.DesLinhas[$p.Id])
    }
    $UI.ListaDes.ItemsSource = $lista.ToArray()
}

function Get-DesMarcados { return @($S.DesTodos | Where-Object { $S.DesLinhas[$_.Id].Marcado }) }

function Update-SelecaoDes {
    $m = @(Get-DesMarcados)
    $t = 0.0; foreach ($p in $m) { $t += $p.Bytes }
    $UI.TxtDesSelecao.Text = if ($m.Count) { "$($m.Count) marcado(s)" + $(if ($t -gt 0) { "  ·  ~$(Format-Tamanho $t)" } else { '' }) } else { "$(@($S.DesTodos).Count) programas e apps. Marque o que quer remover." }
    $UI.BtnDesinstalar.IsEnabled = $m.Count -gt 0 -and -not (Test-TarefaAtiva 'desinstalar')
}

$UI.TxtDesBusca.Add_TextChanged({ Show-ListaDes })
foreach ($rb in 'RbDesTodos', 'RbDesProgramas', 'RbDesApps') { $UI[$rb].Add_Checked({ Show-ListaDes }) }
$UI.BtnDesAtualizar.Add_Click({ Update-Desinstalar })

$UI.BtnDesinstalar.Add_Click({
    $m = @(Get-DesMarcados)
    if (-not $m.Count) { return }
    $linhas = @($m | ForEach-Object {
        $aviso = Get-AvisoDesinstalar $_
        New-Linha -Titulo $_.Nome -Texto $aviso -Nivel $(if ($aviso) { 'medio' } else { 'info' })
    })
    $silencioso = [bool]$UI.ChkDesSilencioso.IsChecked
    $texto = 'Cada um é removido pelo desinstalador oficial' + $(if ($silencioso) { ' (sem janelas quando o programa permite; os outros abrem a janela deles: siga as instruções)' } else { ' (cada um abre a própria janela: siga as instruções)' }) +
             '. Depois o otimizador procura o que ficou para trás e mostra para você conferir antes de apagar.'
    Show-Dialogo -Titulo "Desinstalar $($m.Count) programa(s)?" -Texto $texto -Linhas $linhas -TextoOk 'Desinstalar' -Tipo 'perigo' -Dados $m -Acao {
        param($progs)
        Start-Desinstalacao $progs
    }
})

function Start-Desinstalacao($Progs) {
    $UI.BtnDesinstalar.IsEnabled = $false
    $UI.CardSobras.Visibility = 'Collapsed'
    $S.DesMsg = @{}
    $S.DesRes = New-Object 'System.Collections.ObjectModel.ObservableCollection[Otz.Linha]'
    $UI.ListaDesRes.ItemsSource = $S.DesRes
    $UI.RolagemDes.ScrollToTop()
    $script = @'
$sobras = New-Object System.Collections.Generic.List[object]
foreach ($p in $Parametros.Progs) {
    Send-Evento @{ Tipo = 'des'; Nome = $p.Nome; Status = 'executando'; Mensagem = '' }
    $r = Invoke-DesinstalarPrograma $p $Parametros.Silencioso $Parametros.Todos
    Send-Evento @{ Tipo = 'des'; Nome = $p.Nome; Status = $r.Status; Mensagem = $r.Mensagem }
    if ($r.Status -eq 'ok' -or $r.Orfao) {
        Send-Evento @{ Tipo = 'des'; Nome = $p.Nome; Status = 'sobras'; Mensagem = '' }
        foreach ($s in @(Find-SobrasPrograma $p)) { $sobras.Add($s) }
    }
}
$sobras.ToArray()
'@
    Start-Tarefa -Nome 'desinstalar' -Script $script -Parametros @{ Progs = @($Progs); Silencioso = [bool]$UI.ChkDesSilencioso.IsChecked; Todos = [bool]$UI.ChkDesTodosUsuarios.IsChecked } -AoEvento {
        param($ev)
        if ($ev.Tipo -ne 'des') { return }
        $nivel = switch ($ev.Status) { 'ok' { 'ok' } 'erro' { 'erro' } 'aviso' { 'medio' } default { 'info' } }
        $txt = switch ($ev.Status) {
            'executando' { 'Desinstalando... se abrir a janela do desinstalador, siga as instruções dela.' }
            'sobras'     { 'Desinstalado. Procurando o que ficou para trás...' }
            default      { [string]$ev.Mensagem }
        }
        if ($ev.Status -eq 'ok') { $S.DesMsg[$ev.Nome] = [string]$ev.Mensagem }
        $nova = New-Linha -Titulo $ev.Nome -Texto $txt -Nivel $nivel
        for ($i = 0; $i -lt $S.DesRes.Count; $i++) { if ($S.DesRes[$i].Titulo -eq $ev.Nome) { $S.DesRes[$i] = $nova; return } }
        $S.DesRes.Add($nova)
    } -AoTerminar {
        param($saida, $erro)
        if ($erro) { Show-Toast "Falhou: $erro" 'erro' }
        $sob = @($saida | Where-Object { $_ -and $_.Alvo })
        # A linha "Procurando o que ficou" volta a mostrar o resultado da desinstalação
        for ($i = 0; $i -lt $S.DesRes.Count; $i++) { if ($S.DesRes[$i].Texto -like 'Desinstalado. Procurando*') { $S.DesRes[$i] = New-Linha -Titulo $S.DesRes[$i].Titulo -Texto ([string]$S.DesMsg[$S.DesRes[$i].Titulo]) -Nivel 'ok' } }
        if ($sob.Count) { Show-Sobras $sob } else { Show-Toast 'Desinstalação concluída. Nenhuma sobra encontrada.' 'ok' }
        Update-Desinstalar
    }
}

function Show-Sobras($Sobras) {
    $S.Sobras = @($Sobras)
    $col = New-Object System.Collections.Generic.List[Otz.Linha]
    $total = 0.0
    $progs = @($S.Sobras | ForEach-Object Programa | Select-Object -Unique).Count
    for ($n = 0; $n -lt $S.Sobras.Count; $n++) {
        $sobra = $S.Sobras[$n]   # nunca $s: é o mesmo que $S (o PowerShell não diferencia maiúsculas)
        $total += $sobra.Bytes
        $alvo = if ($sobra.Tipo -eq 'inicio') { ($sobra.Alvo -split '\|', 3)[2] } else { $sobra.Alvo }
        $l = New-Linha -Titulo "$($sobra.Programa): $($sobra.Texto)" -Texto $alvo -Icone $(if ($sobra.Bytes -gt 0) { Format-Tamanho $sobra.Bytes } else { '' }) `
            -Extra $(if (-not $sobra.Certeza) { 'Confira antes: pode não ser só deste programa.' } else { '' })
        $l.Marcado = [bool]$sobra.Certeza
        $l.Valor = [double]$n
        $col.Add($l)
    }
    $S.SobrasLinhas = $col.ToArray()
    $UI.ListaSobras.ItemsSource = $S.SobrasLinhas
    $UI.TxtSobras.Text = "$($S.Sobras.Count) item(ns) de $progs programa(s)" + $(if ($total -gt 0) { ", ~$(Format-Tamanho $total)" } else { '' }) + '. Já vêm marcados os que com certeza eram do programa. Pastas vão para a Lixeira; chaves de registro ganham backup antes.'
    $UI.CardSobras.Visibility = 'Visible'
    $UI.RolagemDes.ScrollToTop()
}

$UI.BtnSobrasIgnorar.Add_Click({ $UI.CardSobras.Visibility = 'Collapsed' })
$UI.BtnSobrasApagar.Add_Click({
    $marc = @($S.SobrasLinhas | Where-Object Marcado | ForEach-Object { $S.Sobras[[int]$_.Valor] })
    if (-not $marc.Count) { Show-Toast 'Marque o que quer apagar.' 'info'; return }
    Show-Dialogo -Titulo "Apagar $($marc.Count) sobra(s)?" -Texto 'Pastas e atalhos vão para a Lixeira (dá para recuperar). Chaves de registro são salvas em Documentos\OtimizadorVinicius\Backups antes de apagar.' -TextoOk 'Apagar' -Tipo 'perigo' -Dados $marc -Acao {
        param($sel)
        $UI.CardSobras.Visibility = 'Collapsed'
        Start-Tarefa -Nome 'sobras' -Script 'Remove-Sobras $Parametros.Sobras' -Parametros @{ Sobras = @($sel) } -AoTerminar {
            param($saida, $erro)
            $res = @($saida | Where-Object { $_ -and $_.Titulo })
            foreach ($r in $res) { $S.DesRes.Add((New-Linha -Titulo $r.Titulo -Texto $r.Texto -Nivel $r.Nivel)) }
            $erros = @($res | Where-Object Nivel -eq 'erro').Count
            Show-Toast $(if ($erros) { "$($res.Count - $erros) apagado(s), $erros com erro (veja a lista)." } else { "$($res.Count) sobra(s) apagada(s)." }) $(if ($erros) { 'aviso' } else { 'ok' })
        }
    }
})

# ---------------- Espaço: arquivos repetidos e programas por tamanho ----------------
function Show-ListaDup {
    $grupos = @($S.Dup)
    $UI.ListaDup.ItemsSource = ConvertTo-Linhas @(for ($i = 0; $i -lt $grupos.Count; $i++) {
        $g = $grupos[$i]
        $n = @($g.Copias).Count
        $txt = "Fica: $($g.Manter)`n" + ((@($g.Copias) | ForEach-Object { "Cópia: $_" }) -join "`n")
        $l = New-Linha -Titulo "$($g.Nome)  ($n cópia(s) a mais)" -Texto $txt -Tag ([string]$i) -Icone 'Cópias para a Lixeira'
        $l.Nivel = Format-Tamanho $g.Desperdicio
        $l
    })
    $total = 0.0; foreach ($g in $grupos) { $total += $g.Desperdicio }
    $UI.BtnDupTodos.Visibility = if ($grupos.Count -gt 1) { 'Visible' } else { 'Collapsed' }
    $UI.TxtDupStatus.Text = if ($grupos.Count) { "$($grupos.Count) arquivo(s) com cópias. As cópias somam $(Format-Tamanho $total). Em cada grupo fica o arquivo da primeira linha; as cópias vão para a Lixeira (dá para recuperar)." }
                            else { 'Nenhum arquivo repetido acima de 1 MB nas suas pastas.' }
}

function Invoke-DupLixeira([object[]]$Grupos) {
    $copias = [string[]]@($Grupos | ForEach-Object { $_.Copias })
    $linhas = @($copias | Select-Object -First 12 | ForEach-Object { New-Linha -Titulo (Split-Path $_ -Leaf) -Texto $_ -Nivel 'info' })
    $tam = 0.0; foreach ($g in $Grupos) { $tam += $g.Desperdicio }
    Show-Dialogo -Titulo "Mandar $($copias.Count) cópia(s) para a Lixeira?" -Texto "Libera $(Format-Tamanho $tam) depois que a Lixeira for esvaziada. O arquivo original de cada grupo fica onde está." -Linhas $linhas -TextoOk 'Mandar para a Lixeira' -Dados $Grupos -Acao {
        param($gs)
        $r = Move-ParaLixeira ([string[]]@($gs | ForEach-Object { $_.Copias }))
        if ($r.Erros.Count) { Show-Toast "$($r.Ok) enviada(s); $($r.Erros.Count) falharam: $($r.Erros[0])" 'aviso' } else { Show-Toast "$($r.Ok) cópia(s) na Lixeira." 'ok' }
        $S.Dup = @($S.Dup | Where-Object { $gs -notcontains $_ })
        Show-ListaDup
    }
}

$UI.BtnDupProcurar.Add_Click({
    $UI.BtnDupProcurar.IsEnabled = $false
    $UI.TxtDupStatus.Text = 'Procurando... compara o conteúdo dos arquivos de mesmo tamanho, pode levar alguns minutos.'
    Start-Tarefa -Nome 'duplicados' -Script 'Get-ArquivosDuplicados' -AoTerminar {
        param($saida, $erro)
        $UI.BtnDupProcurar.IsEnabled = $true
        $S.Dup = @($saida | Where-Object { $_ -and $_.Manter })
        Show-ListaDup
    }
})
$UI.BtnDupTodos.Add_Click({ if (@($S.Dup).Count) { Invoke-DupLixeira @($S.Dup) } })
$UI.ListaDup.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
    param($origem, $e)
    $i = [int][string]$e.OriginalSource.Tag
    $g = @($S.Dup)[$i]
    if ($g) { Invoke-DupLixeira @($g) }
})

function Update-ProgTam {
    Start-Tarefa -Nome 'prog-tamanho' -Script 'Get-ProgramasPorTamanho 15' -AoTerminar {
        param($saida, $erro)
        $S.ProgTam = @($saida | Where-Object { $_ -and $_.Desinstalar })
        $UI.ListaProgTam.ItemsSource = ConvertTo-Linhas @(for ($i = 0; $i -lt $S.ProgTam.Count; $i++) {
            $p = $S.ProgTam[$i]
            $partes = @(); if ($p.Data) { $partes += "instalado em $($p.Data.ToString('dd/MM/yyyy'))" }; if ($p.Editor) { $partes += $p.Editor }
            $l = New-Linha -Titulo $p.Nome -Texto ($partes -join '  ·  ') -Tag ([string]$i) -Icone 'Desinstalar'
            $l.Nivel = Format-Tamanho $p.Bytes
            $l
        })
    }
}
$UI.BtnProgTamApps.Add_Click({ Start-Process 'ms-settings:appsfeatures' })
$UI.ListaProgTam.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
    param($origem, $e)
    $p = @($S.ProgTam)[[int][string]$e.OriginalSource.Tag]
    if (-not $p) { return }
    # Vai para o desinstalador completo (remove e procura sobras), já filtrado no programa
    Show-Ferramenta 'RbFerDesinstalar'
    $UI.RbDesTodos.IsChecked = $true
    $UI.TxtDesBusca.Text = Get-NomeBase $p.Nome
    Show-Toast "Marque '$($p.Nome)' e clique em Desinstalar." 'info'
})

# ---------------- Vários PCs (inventário) ----------------
function Get-PastaFrota {
    $p = $UI.TxtFrotaPasta.Text.Trim()
    if (-not $p) { Show-Toast 'Escolha a pasta primeiro.' 'info'; return $null }
    if ($p -ne $S.PastaFrota) { $S.PastaFrota = $p; Save-Preferencias }
    return $p
}

function Update-Frota {
    $pasta = Get-PastaFrota
    if (-not $pasta) { return }
    $UI.TxtFrotaStatus.Text = 'Lendo a pasta...'
    Start-Tarefa -Nome 'frota' -Script 'Get-InventarioPasta $Parametros.Pasta' -Parametros @{ Pasta = $pasta } -AoTerminar {
        param($saida, $erro)
        $lista = @($saida | Where-Object { $_ -and $_.Computador })
        $UI.ListaFrota.ItemsSource = ConvertTo-Linhas @($lista | ForEach-Object {
            $o = $_
            $data = try { [datetime]::Parse($o.Data, [Globalization.CultureInfo]::InvariantCulture) } catch { $null }
            $quando = if ($data) { "atualizado $($data.ToString('dd/MM HH:mm'))" } else { '' }
            $nivel = if ($o.Nota -ge 85) { 'ok' } elseif ($o.Nota -ge 65) { 'medio' } else { 'alto' }
            $disco = "$($o.DiscoTipo)"; if ($null -ne $o.DiscoLivreGB) { $disco += " ($($o.DiscoLivreGB) GB livres)" }
            $l = New-Linha -Titulo "$($o.Computador)  ·  $($o.Usuario)" -Texto "$($o.Cpu)  ·  $($o.RamGB) GB  ·  $disco  ·  $($o.GpuNome)  ·  $($o.Windows)" -Extra ([string]$o.Nota) -Tag $quando -Nivel $nivel
            $avisos = New-Object System.Collections.Generic.List[Otz.Linha]
            if ($o.TelasAzuis30d) { $avisos.Add((New-Linha -Titulo "$($o.TelasAzuis30d) tela(s) azul(is) em 30 dias")) }
            if ($o.Desligamentos30d) { $avisos.Add((New-Linha -Titulo "$($o.Desligamentos30d) desligamento(s) inesperado(s) em 30 dias")) }
            foreach ($a in @($o.Alertas)) { if ($a) { $avisos.Add((New-Linha -Titulo $a)) } }
            $l.Filhos = $avisos.ToArray()
            $l
        })
        $UI.TxtFrotaStatus.Text = if ($lista.Count) { "$($lista.Count) PC(s), do pior para o melhor (nota de 0 a 100)." } else { 'Nenhum inventário nesta pasta ainda. Clique em "Salvar este PC na pasta" ou rode o Inventario-PC.bat nos outros PCs.' }
    }
}

$UI.BtnFrotaEscolher.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = 'Pasta onde cada PC grava o inventário (pode ser uma pasta de rede).'
    if ($UI.TxtFrotaPasta.Text) { $d.SelectedPath = $UI.TxtFrotaPasta.Text }
    if ($d.ShowDialog() -eq 'OK') { $UI.TxtFrotaPasta.Text = $d.SelectedPath; Update-Frota }
})
$UI.BtnFrotaAtualizar.Add_Click({ Update-Frota })
$UI.BtnFrotaSalvar.Add_Click({
    $pasta = Get-PastaFrota
    if (-not $pasta) { return }
    $UI.BtnFrotaSalvar.IsEnabled = $false
    $UI.TxtFrotaStatus.Text = 'Coletando o resumo deste PC (leva uns 15 segundos)...'
    Start-Tarefa -Nome 'frota-salvar' -Script 'Save-InventarioPC $Parametros.Pasta' -Parametros @{ Pasta = $pasta } -AoTerminar {
        param($saida, $erro)
        $UI.BtnFrotaSalvar.IsEnabled = $true
        if ($erro) { Show-Toast "Não foi possível salvar: $erro" 'erro'; $UI.TxtFrotaStatus.Text = ''; return }
        Show-Toast 'Inventário deste PC salvo.' 'ok'
        Update-Frota
    }
})
$UI.BtnFrotaCsv.Add_Click({
    $pasta = Get-PastaFrota
    if (-not $pasta) { return }
    $S.FrotaCsv = Join-Path $pasta ("inventario_$(Get-Date -Format 'yyyy-MM-dd_HHmm').csv")
    Start-Tarefa -Nome 'frota-csv' -Script 'Export-InventarioCsv $Parametros.Pasta $Parametros.Destino' -Parametros @{ Pasta = $pasta; Destino = $S.FrotaCsv } -AoTerminar {
        param($saida, $erro)
        if ($erro) { Show-Toast "Não foi possível exportar: $erro" 'erro'; return }
        Show-Toast 'Planilha criada na pasta do inventário.' 'ok'
        Start-Process explorer.exe "/select,`"$($S.FrotaCsv)`""
    }
})
$UI.BtnFrotaAbrir.Add_Click({ $p = Get-PastaFrota; if ($p -and (Test-Path $p)) { Start-Process explorer.exe "`"$p`"" } })

# ===============================================================
#  Antes × depois (Histórico)
# ===============================================================
function Update-Comparacao {
    if (Test-TarefaAtiva 'comparacao') { return }
    $UI.BtnCompMedir.IsEnabled = $false
    Start-Tarefa -Nome 'comparacao' -Script 'Get-Comparacao' -AoTerminar {
        param($saida, $erro)
        $UI.BtnCompMedir.IsEnabled = $true
        $c = @($saida | Where-Object { $_ -and $_.Agora })[0]
        if (-not $c) {
            $UI.TxtCompSub.Text = 'Na primeira vez que você aplicar ajustes, o otimizador grava uma "foto" do PC antes de mudar qualquer coisa. Depois, esta tela mostra o que melhorou: tempo para ligar, programas na inicialização, serviços e memória.'
            $UI.CabecalhoComp.Visibility = 'Collapsed'
            $UI.BtnCompNova.Visibility = 'Collapsed'
            $UI.TxtCompMedir.Text = 'Gravar referência agora'
            $UI.ListaComparacao.ItemsSource = $null
            $S.CompSemRef = $true
            return
        }
        $S.CompSemRef = -not $c.TemReferencia
        $UI.TxtCompMedir.Text = if ($c.TemReferencia) { 'Medir agora' } else { 'Gravar referência agora' }
        $UI.BtnCompNova.Visibility = if ($c.TemReferencia) { 'Visible' } else { 'Collapsed' }
        $UI.CabecalhoComp.Visibility = 'Visible'
        $UI.TxtCompSub.Text = if ($c.TemReferencia) { "Referência (antes) gravada em $($c.DataReferencia.ToString('dd/MM/yyyy HH:mm')). O tempo para ligar compara as inicializações antes e depois de $($c.DataCorte.ToString('dd/MM HH:mm')). Menor é melhor em todas as linhas." }
                              else { "Os ajustes foram aplicados antes de existir esta comparação. O tempo para ligar vem do registro do Windows e compara as inicializações antes e depois da primeira otimização ($($c.DataCorte.ToString('dd/MM HH:mm'))). Para acompanhar programas, serviços e memória daqui para frente, grave uma referência agora." }
        $linhas = New-Object System.Collections.Generic.List[Otz.Linha]
        function Add-Comparacao([string]$Nome, $Antes, $Agora, [string]$Unidade, [string]$Nota = '', [double]$Tolerancia = 0) {
            $txtAntes = if ($null -ne $Antes) { "$(Format-Numero $Antes)$Unidade" } else { '—' }
            $txtAgora = if ($null -ne $Agora) { "$(Format-Numero $Agora)$Unidade" } else { '—' }
            if ($null -eq $Antes -or $null -eq $Agora) {
                $l = New-Linha -Titulo $Nome -Texto $txtAntes -Extra $txtAgora -Icone 'sem dados' -Nivel 'info' -Tag $Nota
            } else {
                $dif = [double]$Agora - [double]$Antes
                $nivel = if ([math]::Abs($dif) -le $Tolerancia) { 'info' } elseif ($dif -lt 0) { 'ok' } else { 'medio' }
                $txtDif = if ([math]::Abs($dif) -le $Tolerancia) { 'igual' } elseif ($dif -lt 0) { "$(Format-Numero ([math]::Abs($dif)))$Unidade a menos" } else { "$(Format-Numero $dif)$Unidade a mais" }
                $l = New-Linha -Titulo $Nome -Texto $txtAntes -Extra $txtAgora -Icone $txtDif -Nivel $nivel -Tag $Nota
            }
            $linhas.Add($l)
        }
        $notaBoot = if (-not $c.BootDisponivel) { 'Abra como administrador para ler o tempo de inicialização.' }
                    elseif ($null -eq $c.BootAntes) { 'O Windows não guardou inicializações de antes da otimização.' }
                    elseif ($null -eq $c.BootDepois) { 'Reinicie o PC (Reiniciar, não Desligar) para medir o "depois".' }
                    else { "Média de até 5 inicializações antes e $($c.BootsDepois) depois." }
        Add-Comparacao 'Tempo para ligar' $c.BootAntes $c.BootDepois ' s' $notaBoot 0.5
        if (-not $c.TemReferencia) { $UI.ListaComparacao.ItemsSource = $linhas.ToArray(); return }
        Add-Comparacao 'Programas na inicialização' $c.Antes.Inicializacao $c.Agora.Inicializacao ''
        Add-Comparacao 'Serviços rodando' $c.Antes.Servicos $c.Agora.Servicos '' '' 2
        Add-Comparacao 'Processos abertos' $c.Antes.Processos $c.Agora.Processos '' 'Depende dos programas abertos no momento de cada medição.' 5
        Add-Comparacao 'Memória em uso' ([math]::Round($c.Antes.RamUsoMB / 1024.0, 1)) ([math]::Round($c.Agora.RamUsoMB / 1024.0, 1)) ' GB' 'Compare com os mesmos programas abertos: o navegador sozinho muda bastante.' 0.2
        $UI.ListaComparacao.ItemsSource = $linhas.ToArray()
    }
}
$UI.BtnCompMedir.Add_Click({
    if ($S.CompSemRef) {
        Start-Tarefa -Nome 'comparacao-ref' -Script '[void](Save-MedicaoReferencia)' -AoTerminar { Show-Toast 'Referência gravada.' 'ok'; Update-Comparacao }
    } else { Update-Comparacao }
})
$UI.BtnCompNova.Add_Click({
    Show-Dialogo -Titulo 'Gravar uma nova referência?' -Texto 'A medição de agora passa a ser o "antes". Use depois de reinstalar programas ou trocar peças. A referência antiga é descartada.' -TextoOk 'Gravar nova referência' -Acao {
        Start-Tarefa -Nome 'comparacao-ref' -Script '[void](Save-MedicaoReferencia)' -AoTerminar { Show-Toast 'Nova referência gravada.' 'ok'; Update-Comparacao }
    }
})

# Barra de status e aviso de conta
$papel = if ($ehAdmin) { 'Administrador' } else { 'Sem administrador (só visualização)' }
$UI.TxtBarraStatus.Text = "$papel  ·  $(if ($Otz.IsWin11) { 'Windows 11' } else { 'Windows 10' }) $($Otz.VersaoWin)  ·  build $($Otz.Build).$($Otz.Ubr)"
$UI.TxtVersao.Text = "v$($Otz.Versao)"
if ($Otz.SidAlvo) {
    $UI.TxtAvisoConta.Text = "Aberto com a conta de administrador '$([Security.Principal.WindowsIdentity]::GetCurrent().Name)'. Os ajustes de usuário vão para '$(Get-NomeConta $Otz.SidAlvo)', a conta que está usando o PC."
    $UI.AvisoConta.Visibility = 'Visible'
} elseif (-not $ehAdmin) {
    $UI.TxtAvisoConta.Text = 'Aberto sem administrador: dá para ver tudo, mas aplicar vai falhar. Use o Executar-Otimizador.bat.'
    $UI.AvisoConta.Visibility = 'Visible'
}

# ===============================================================
#  Início
# ===============================================================
Set-Tema (Get-TemaInicial)

# Modo simples/avançado: lembra a última escolha (padrão: simples)
$S.ModoAvancado = $false
try {
    if (Test-Path $S.ArqPrefs) {
        $prefs = [IO.File]::ReadAllText($S.ArqPrefs) | ConvertFrom-Json
        $S.ModoAvancado = [bool]$prefs.Avancado
        $S.PastaFrota = [string]$prefs.PastaFrota
    }
} catch { }
$UI.ChkAvancado.IsChecked = $S.ModoAvancado
Set-ModoAvancado $S.ModoAvancado

# Glossário na Ajuda
$UI.ListaGlossario.ItemsSource = ConvertTo-Linhas @($Glossario | ForEach-Object { New-Linha -Titulo $_.Termo -Texto $_.Explicacao })
Set-Saudacao
Set-Perfil 'personalizado'
Update-Compatibilidade

$Win.Add_ContentRendered({
    Show-Entrada $UI.PagInicio
    Start-Deteccao
    Start-InfoPC
})

# Modo de captura (teste visual): salva PNGs de cada tela e fecha
if ($Captura) {
    New-Item -ItemType Directory -Path $Captura -Force | Out-Null
    $Win.WindowStartupLocation = 'Manual'
    $Win.Left = -5000; $Win.Top = 0
    $Win.ShowActivated = $false
    function Save-Captura([string]$Nome) {
        $Win.UpdateLayout()
        $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$Win.ActualWidth), ([int]$Win.ActualHeight), 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
        $bmp.Render($Win)
        $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
        $fs = [IO.File]::Create((Join-Path $Captura "$Nome.png")); $enc.Save($fs); $fs.Close()
    }
    $S.Passos = New-Object System.Collections.Queue
    @(
        { }
        { }
        { }
        { Save-Captura '1-inicio' }
        { Open-Pagina 'NavOtimizar'; Select-Perfil 'trabalho'; $UI.ListaAjustes.SelectedItem = $S.PorId['ui.menu-classico'] }
        { Save-Captura '2-otimizar' }
        { Start-Execucao 'simular' @($S.Ajustes | Where-Object Selecionado | Select-Object -First 6 | ForEach-Object Id) }
        { }
        { Save-Captura '3-simulacao' }
        { Hide-Overlay; Open-Pagina 'NavFerramentas' }
        { Save-Captura '4-ferramentas-rede' }
        { Show-Ferramenta 'RbFerInicio' }
        { Save-Captura '5-ferramentas-inicio' }
        { Show-Ferramenta 'RbFerAtalhos' }
        { Save-Captura '6-ferramentas-atalhos' }
        { Open-Pagina 'NavVerificar'; Start-Verificacao }
        { Save-Captura '11-verificar-andamento' }
        { }
        { }
        { }
        { }
        { }
        { Save-Captura '12-verificar-resultado' }
        { $UI.PagVerificar.ScrollToVerticalOffset(520) }
        { Save-Captura '13-verificar-saude' }
        { Open-Pagina 'NavVideo' }
        { }
        { $UI.RbGpuDesempenho.IsChecked = $true }
        { Save-Captura '14-video' }
        { $UI.PagVideo.ScrollToVerticalOffset(560) }
        { Save-Captura '15-video-painel' }
        { Open-Pagina 'NavNotebook' }
        { Save-Captura '16-notebook' }
        { Open-Pagina 'NavServicos' }
        { }
        { }
        { Save-Captura '17a-segundo-plano' }
        { $UI.PagServicos.ScrollToVerticalOffset(520) }
        { Save-Captura '17b-segundo-plano-lista' }
        { $UI.PagServicos.ScrollToTop(); $UI.BtnServRecomendados.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
        { Save-Captura '17-servicos' }
        { Request-Aplicar @($S.PorId['serv.sysmain'], $S.PorId['serv.impressao'], $S.PorId['gpu.vrr'], $S.PorId['game.hags']) }
        { Save-Captura '18-confirmar-aplicar' }
        { Hide-Dialogo }
        { Open-Pagina 'NavFerramentas'; Show-Ferramenta 'RbFerProtecao' }
        { }
        { Save-Captura '19-protecao' }
        { Show-Ferramenta 'RbFerOffice' }
        { }
        { Save-Captura '20-office' }
        { Show-Ferramenta 'RbFerProgramas' }
        { }
        { Save-Captura '21-programas' }
        { Open-Pagina 'NavOtimizar'; $UI.ListaAjustes.SelectedItem = $S.PorId['game.hags']; $UI.ListaAjustes.ScrollIntoView($S.PorId['game.hags']) }
        { }
        { Save-Captura '22-detalhe-simples' }
        { $UI.RolagemDetalhe.ScrollToVerticalOffset(330) }
        { Save-Captura '22b-detalhe-previa' }
        { $UI.RolagemDetalhe.ScrollToTop() }
        { $UI.ChkAvancado.IsChecked = $true; Set-ModoAvancado $true }
        { Save-Captura '23-detalhe-avancado' }
        { Set-ModoAvancado $false; $UI.ChkAvancado.IsChecked = $false; Open-Pagina 'NavAjuda' }
        { $UI.PagAjuda.ScrollToEnd() }
        { Save-Captura '24-glossario' }
        { Open-Pagina 'NavFerramentas'; Show-Ferramenta 'RbFerEspaco' }
        { }
        { }
        { Save-Captura '25-espaco' }
        { Open-Pagina 'NavVerificar' }
        { $UI.PagVerificar.ScrollToVerticalOffset(470) }
        { Save-Captura '26-evolucao' }
        { $S.DadosReais = $Otz.Dados; $Otz.Dados = 'C:\Users\vinic\AppData\Local\Temp\claude\c--Users-vinic-Documents-Programa--o-Otimizador-PC\fb12e4dc-9795-4a02-a9c5-2b76d0b2166e\scratchpad\dados-teste'; Show-Evolucao }
        { Save-Captura '27-evolucao-varios' }
        { Set-Tema 'claro'; Show-Evolucao }
        { Save-Captura '28-evolucao-claro' }
        { Set-Tema 'escuro'; $Otz.Dados = $S.DadosReais }
        { Open-Pagina 'NavFerramentas'; Show-Ferramenta 'RbFerMonitor' }
        { Start-Monitor }
        { }
        { }
        { }
        { }
        { }
        { }
        { }
        { }
        { }
        { Save-Captura '29-monitor' }
        { $S.Mon.Controle.Parar = $true; Show-Ferramenta 'RbFerManut' }
        { }
        { Save-Captura '30-manutencao' }
        { Show-Ferramenta 'RbFerSuporte' }
        { }
        { }
        { Save-Captura '31-suporte' }
        { Show-Ferramenta 'RbFerTemp' }
        { }
        { }
        { Save-Captura '32-temperaturas' }
        { Open-Pagina 'NavOtimizar'; $UI.TxtBusca.Text = 'navegador' }
        { Save-Captura '33-navegadores' }
        { $UI.TxtBusca.Text = '' }
        { Open-Pagina 'NavDiagnostico' }
        { }
        { }
        { }
        { Save-Captura '34-lento' }
        { $UI.DiagLento.ScrollToEnd() }
        { Save-Captura '34b-lento-processos' }
        { Show-Diagnostico 'RbDiagBoot' }
        { }
        { Save-Captura '35-boot' }
        { Show-Diagnostico 'RbDiagEstab' }
        { }
        { Save-Captura '36-estabilidade' }
        { Show-Diagnostico 'RbDiagConexao' }
        { }
        { Save-Captura '37-conexao' }
        { Show-Diagnostico 'RbDiagBios' }
        { }
        { }
        { Save-Captura '38-bios' }
        { Open-Pagina 'NavFerramentas'; Show-Ferramenta 'RbFerJogo' }
        { }
        { Save-Captura '39-modo-jogo' }
        { Show-Ferramenta 'RbFerApps' }
        { }
        { Save-Captura '40-apps' }
        { Show-Ferramenta 'RbFerDesinstalar' }
        { }
        { $UI.TxtDesBusca.Text = 'radmin'; $S.DesLinhas[@($S.DesTodos | Where-Object { $_.Nome -like 'Radmin*' })[0].Id].Marcado = $true }
        { Save-Captura '40b-desinstalar' }
        { $UI.TxtDesBusca.Text = ''; $p = @($S.DesTodos | Where-Object { $_.Nome -like 'Radmin*' })[0]; $S.DesLinhas[$p.Id].Marcado = $false; Show-Sobras @(Find-SobrasPrograma $p) }
        { Save-Captura '40c-sobras' }
        { $UI.CardSobras.Visibility = 'Collapsed' }
        { $S.PastaFrota = Join-Path $Captura 'frota'; $UI.TxtFrotaPasta.Text = $S.PastaFrota; Show-Ferramenta 'RbFerFrota'; $UI.BtnFrotaSalvar.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
        { }
        { }
        { }
        { }
        { }
        { }
        { }
        { }
        { Save-Captura '41-varios-pcs' }
        { Show-Ferramenta 'RbFerEspaco' }
        { $UI.BtnDupProcurar.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
        { }
        { }
        { $UI.FerEspaco.ScrollToVerticalOffset(560) }
        { Save-Captura '42-espaco-repetidos' }
        { $UI.FerEspaco.ScrollToEnd() }
        { Save-Captura '43-espaco-programas' }
        { Open-Pagina 'NavHistorico' }
        { Save-Captura '7-historico' }
        { Open-Pagina 'NavAjuda' }
        { Save-Captura '8-ajuda' }
        { Set-Tema 'claro'; Open-Pagina 'NavOtimizar' }
        { Save-Captura '9-otimizar-claro' }
        { Show-Dialogo -Titulo 'Aplicar 12 ajuste(s)?' -Texto 'Cada ajuste pode ser desfeito depois.' -Linhas @((New-Linha -Titulo 'Um ponto de restauração será criado antes' -Nivel 'ok'), (New-Linha -Titulo 'Desligar hibernação' -Texto 'A hibernação será desligada.' -Nivel 'alto')) -TextoOk 'Aplicar agora' }
        { Save-Captura '10-dialogo-claro' }
        { $Win.Close() }
    ) | ForEach-Object { $S.Passos.Enqueue($_) }
    $tc = New-Object Windows.Threading.DispatcherTimer
    $tc.Interval = [TimeSpan]::FromMilliseconds(1600)
    $tc.Add_Tick({ if ($S.Passos.Count) { try { & ($S.Passos.Dequeue()) } catch { Write-Host "Captura: $($_.Exception.Message) | $($_.ScriptStackTrace -replace "`r?`n", ' <- ')" } } })
    $Win.Add_ContentRendered({ $S.TimerCaptura.Start() })
    $S.TimerCaptura = $tc
    # Dá tempo para a detecção e o hardware carregarem antes da primeira imagem
    $S.TimerCaptura.Interval = [TimeSpan]::FromMilliseconds(1600)
}

[void]$Win.ShowDialog()
Write-Log 'Otimizador fechado.'
