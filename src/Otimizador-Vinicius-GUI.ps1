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
    [string]$Manutencao
)

$ErrorActionPreference = 'Stop'
$Script:SrcDir = $PSScriptRoot
$Script:Silencioso = [bool]($Perfil -or $Manutencao)

# ---------------------------------------------------------------
#  Elevação (repassa os parâmetros do modo silencioso)
# ---------------------------------------------------------------
$ehAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $ehAdmin -and -not $SemElevar -and -not $Captura) {
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
        Initialize-Otz -SrcDir $Script:SrcDir -SidAlvo (Get-SidUsuarioSessao)
        if ($Manutencao) {
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
        Info = '#60A5FA'; InfoSuave = '#2660A5FA'; Scrim = '#A6000000'
    }
    claro = @{
        Fundo = '#E9EDF3'; Palco = '#F5F7FA'; Superficie = '#FFFFFF'; Superficie2 = '#EEF1F6'; SuperficieHover = '#E3E8EF'; Borda = '#DCE2EA'
        Texto = '#111827'; TextoSec = '#5B6474'; TextoFraco = '#9AA3B2'; Acento = '#0D9488'; AcentoSuave = '#1F0D9488'; SobreAcento = '#FFFFFF'
        Ok = '#059669'; OkSuave = '#1F059669'; Aviso = '#B45309'; AvisoSuave = '#1FB45309'; Erro = '#DC2626'; ErroSuave = '#1FDC2626'
        Info = '#2563EB'; InfoSuave = '#1F2563EB'; Scrim = '#66000000'
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
    try { [IO.File]::WriteAllText($S.ArqPrefs, (@{ Tema = $S.Tema; Avancado = [bool]$S.ModoAvancado } | ConvertTo-Json), (New-Object Text.UTF8Encoding $false)) } catch { }
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
    NavInicio = 'PagInicio'; NavVerificar = 'PagVerificar'; NavOtimizar = 'PagOtimizar'; NavVideo = 'PagVideo'; NavNotebook = 'PagNotebook'
    NavServicos = 'PagServicos'; NavFerramentas = 'PagFerramentas'; NavHistorico = 'PagHistorico'; NavAjuda = 'PagAjuda'
}

function Show-Pagina([string]$Pagina) {
    foreach ($p in $Paginas.Values) { if ($p -ne $Pagina) { $UI[$p].Visibility = 'Collapsed' } }
    Show-Entrada $UI[$Pagina]
    switch ($Pagina) {
        'PagHistorico'   { Update-Historico }
        'PagVideo'       { if (-not $S.GpuCarregada) { Update-Gpu } }
        'PagNotebook'    { if (-not $S.BateriaCarregada) { Update-Bateria } }
        'PagServicos'    { Update-Ram }
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
    Start-Tarefa -Nome 'execucao' -Script 'Invoke-Plano -Ids $Parametros.Ids -Modo $Parametros.Modo -CriarPonto $Parametros.CriarPonto' `
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
        if (@($okItens | Where-Object { $_.Id -like 'gpu.*' }).Count) { $S.GpuCarregada = $false }
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
    RbFerProtecao = 'FerProtecao'; RbFerOffice = 'FerOffice'; RbFerAtalhos = 'FerAtalhos'
}

function Show-Ferramenta([string]$Rb) {
    if (-not $UI[$Rb].IsChecked) { $UI[$Rb].IsChecked = $true; return }   # o evento Checked chama de novo
    $painel = $FerPaineis[$Rb]
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
    $UI[$tb].Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { Start-TesteServidor } })
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
Step 3 'rodando'; $info = Get-InfoPC; $c = @(Get-SaudeHardware $info); Step 3 (Get-PiorNivel $c)
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
        }
    } catch { Show-Toast "Não foi possível abrir: $($_.Exception.Message)" 'erro' }
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
    if ($S.Executando) { $e.Cancel = $true; Show-Toast 'Aguarde a execução terminar antes de fechar.' 'aviso' }
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
try { if (Test-Path $S.ArqPrefs) { $S.ModoAvancado = [bool](([IO.File]::ReadAllText($S.ArqPrefs) | ConvertFrom-Json).Avancado) } } catch { }
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
        { $UI.BtnServRecomendados.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
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
