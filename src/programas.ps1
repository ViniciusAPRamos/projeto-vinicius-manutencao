#Requires -Version 5.1
<#
    Programas (Otimizador Vinicius v2.0)
      - Get-AppsPreInstalados / Remove-AppPreInstalado   apps que vieram com o Windows
      - Get-ProgramasPorTamanho / Start-DesinstaladorPrograma
      - Modo jogo agora: Get-ProgramasAbertos, Start-ModoJogo, Stop-ModoJogo
    Depende do nucleo.ps1.
#>

# ===============================================================
#  10. Apps que vieram com o Windows (remoção um por um, reinstaláveis pela Store)
#  Padrao = nome do pacote (aceita curinga). Atencao preenchida = pense antes.
# ===============================================================
$Script:AppsConhecidos = @(
    @{ Padrao = 'Clipchamp.Clipchamp';                    Nome = 'Clipchamp';                Texto = 'Editor de vídeo simples da Microsoft.' }
    @{ Padrao = 'Microsoft.BingNews';                     Nome = 'Notícias';                 Texto = 'Notícias do MSN.' }
    @{ Padrao = 'Microsoft.BingWeather';                  Nome = 'Clima';                    Texto = 'Previsão do tempo do MSN. O clima da barra de tarefas não depende dele.' }
    @{ Padrao = 'Microsoft.MicrosoftSolitaireCollection'; Nome = 'Paciência (Solitaire)';    Texto = 'Jogos de cartas com anúncios.' }
    @{ Padrao = 'Microsoft.GetHelp';                      Nome = 'Obter Ajuda';              Texto = 'Chat de suporte da Microsoft.' }
    @{ Padrao = 'Microsoft.Getstarted';                   Nome = 'Dicas';                    Texto = 'Dicas de uso do Windows.' }
    @{ Padrao = 'Microsoft.WindowsFeedbackHub';           Nome = 'Hub de Comentários';       Texto = 'Envia sugestões e problemas para a Microsoft.' }
    @{ Padrao = 'Microsoft.MicrosoftOfficeHub';           Nome = 'Microsoft 365 (Office)';   Texto = 'Atalho para o Office na web. Remover NÃO desinstala o Word/Excel instalados.' }
    @{ Padrao = 'Microsoft.PowerAutomateDesktop';         Nome = 'Power Automate';           Texto = 'Automação de tarefas para usuários avançados.' }
    @{ Padrao = 'Microsoft.Todos';                        Nome = 'Microsoft To Do';          Texto = 'Lista de tarefas.'; Atencao = 'Se você usa suas listas nele, mantenha.' }
    @{ Padrao = 'Microsoft.ZuneVideo';                    Nome = 'Filmes e TV';              Texto = 'Player de vídeo antigo; o Media Player continua.' }
    @{ Padrao = 'Microsoft.WindowsMaps';                  Nome = 'Mapas';                    Texto = 'Mapas offline da Microsoft.' }
    @{ Padrao = 'Microsoft.People';                       Nome = 'Pessoas';                  Texto = 'Contatos (substituído pelo Outlook).' }
    @{ Padrao = 'Microsoft.SkypeApp';                     Nome = 'Skype';                    Texto = 'O Skype foi encerrado pela Microsoft em 2025.' }
    @{ Padrao = 'Microsoft.Microsoft3DViewer';            Nome = 'Visualizador 3D';          Texto = 'Abre modelos 3D.' }
    @{ Padrao = 'Microsoft.MixedReality.Portal';          Nome = 'Portal de Realidade Misturada'; Texto = 'Só para óculos de realidade virtual Windows.' }
    @{ Padrao = 'Microsoft.549981C3F5F10';                Nome = 'Cortana';                  Texto = 'Assistente descontinuada.' }
    @{ Padrao = 'Microsoft.Windows.DevHome';              Nome = 'Dev Home';                 Texto = 'Painel para programadores, descontinuado pela Microsoft.' }
    @{ Padrao = 'Microsoft.WindowsCommunicationsApps';    Nome = 'Email e Calendário';       Texto = 'Apps antigos, substituídos pelo novo Outlook.' }
    @{ Padrao = 'Microsoft.XboxApp';                      Nome = 'Xbox Console Companion';   Texto = 'App antigo do Xbox (o novo é o "Xbox").' }
    @{ Padrao = 'MicrosoftTeams';                         Nome = 'Teams (pessoal)';          Texto = 'Chat pessoal do Windows 11.'; Atencao = 'Não é o Teams do trabalho, mas confira antes.' }
    @{ Padrao = 'Microsoft.Copilot';                      Nome = 'Copilot';                  Texto = 'Assistente de IA da Microsoft.'; Atencao = 'Se você usa o Copilot, mantenha.' }
    @{ Padrao = 'MSTeams';                                Nome = 'Microsoft Teams';          Texto = 'Teams de trabalho/escola.'; Atencao = 'Se você usa Teams no trabalho ou na escola, mantenha.' }
    @{ Padrao = 'Microsoft.OutlookForWindows';            Nome = 'Outlook (novo)';           Texto = 'Novo app de e-mail do Windows.'; Atencao = 'Se você lê e-mails nele, mantenha.' }
    @{ Padrao = 'Microsoft.YourPhone';                    Nome = 'Vincular ao Celular';      Texto = 'Mostra notificações e fotos do celular no PC.'; Atencao = 'Se você usa o celular pelo PC, mantenha.' }
    @{ Padrao = 'Microsoft.GamingApp';                    Nome = 'Xbox';                     Texto = 'Loja e biblioteca de jogos do Xbox/Game Pass.'; Atencao = 'Necessário para jogar Game Pass no PC.' }
    @{ Padrao = 'SpotifyAB.SpotifyMusic';                 Nome = 'Spotify';                  Texto = 'Às vezes vem pré-instalado.'; Atencao = 'Se você usa, mantenha.' }
    @{ Padrao = 'Disney.37853FA22FAF4';                   Nome = 'Disney+';                  Texto = 'Atalho de propaganda que vem instalado.' }
    @{ Padrao = '*CandyCrush*';                           Nome = 'Candy Crush';              Texto = 'Jogo de propaganda que vem instalado.' }
    @{ Padrao = '*TikTok*';                               Nome = 'TikTok';                   Texto = 'Atalho de propaganda que vem instalado.'; Atencao = 'Se você usa, mantenha.' }
    @{ Padrao = 'Facebook.*';                             Nome = 'Facebook / Instagram';     Texto = 'Atalho de propaganda que vem instalado.'; Atencao = 'Se você usa, mantenha.' }
    @{ Padrao = '7EE7776C.LinkedInforWindows';            Nome = 'LinkedIn';                 Texto = 'Atalho de propaganda que vem instalado.' }
    # Fabricantes (prefixo do editor na Microsoft Store)
    @{ Padrao = 'AD2F1837.*';                  Nome = 'App da HP';      Texto = 'Programa do fabricante HP.';      Fabricante = $true }
    @{ Padrao = 'DellInc.*';                   Nome = 'App da Dell';    Texto = 'Programa do fabricante Dell.';    Fabricante = $true }
    @{ Padrao = 'E046963F.*';                  Nome = 'App da Lenovo';  Texto = 'Programa do fabricante Lenovo.';  Fabricante = $true }
    @{ Padrao = 'B9ECED6F.*';                  Nome = 'App da ASUS';    Texto = 'Programa do fabricante ASUS.';    Fabricante = $true }
    @{ Padrao = 'AcerIncorporated.*';          Nome = 'App da Acer';    Texto = 'Programa do fabricante Acer.';    Fabricante = $true }
    @{ Padrao = '9426MICRO-STARINTERNATION.*'; Nome = 'App da MSI';     Texto = 'Programa do fabricante MSI.';     Fabricante = $true }
    @{ Padrao = 'SAMSUNGELECTRONICSCO.LTD.*';  Nome = 'App da Samsung'; Texto = 'Programa do fabricante Samsung.'; Fabricante = $true }
)

function Get-AppsPreInstalados {
    $instalados = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { -not $_.IsFramework -and -not $_.NonRemovable })
    $lista = New-Object System.Collections.Generic.List[object]
    $vistos = @{}
    foreach ($c in $Script:AppsConhecidos) {
        foreach ($p in @($instalados | Where-Object { $_.Name -like $c.Padrao })) {
            if ($vistos.ContainsKey($p.Name)) { continue }
            $vistos[$p.Name] = $true
            $nome = $c.Nome
            $atencao = [string]$c.Atencao
            if ($c.Fabricante) {
                $nome = "$($c.Nome): $(($p.Name -split '\.', 2)[1])"
                $atencao = 'Apps do fabricante às vezes controlam bateria, ventoinhas, teclas especiais e atualizações de driver. Remova só se souber que não usa.'
            }
            $r = [ordered]@{}
            $r.Nome = $nome; $r.Texto = $c.Texto; $r.Atencao = $atencao
            $r.Pacote = $p.Name; $r.Completo = $p.PackageFullName; $r.Familia = $p.PackageFamilyName
            $lista.Add([pscustomobject]$r)
        }
    }
    return $lista.ToArray()
}

function Remove-AppPreInstalado([string]$Pacote) {
    $p = @(Get-AppxPackage -Name $Pacote -ErrorAction SilentlyContinue)
    if (-not $p.Count) { return @{ Status = 'aviso'; Mensagem = 'O app já não está instalado.' } }
    try {
        foreach ($x in $p) { Remove-AppxPackage -Package $x.PackageFullName -ErrorAction Stop }
        Write-Log "App removido: $Pacote"
        return @{ Status = 'ok'; Mensagem = 'Removido. Para reinstalar, procure pelo nome na Microsoft Store.' }
    } catch {
        Write-Log "Falha ao remover $($Pacote): $($_.Exception.Message)"
        return @{ Status = 'erro'; Mensagem = $_.Exception.Message }
    }
}

# ===============================================================
#  13. Programas que mais ocupam espaço (tamanho informado pelo instalador)
# ===============================================================
function Get-ProgramasPorTamanho([int]$Quantidade = 15) {
    $chaves = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $lista = New-Object System.Collections.Generic.List[object]
    $vistos = @{}
    foreach ($p in @(Get-ItemProperty $chaves -ErrorAction SilentlyContinue)) {
        if (-not $p.DisplayName -or -not $p.EstimatedSize -or $p.SystemComponent -eq 1 -or $p.ParentKeyName -or $p.ReleaseType -match 'Update|Hotfix') { continue }
        if (-not $p.UninstallString) { continue }
        if ($vistos.ContainsKey($p.DisplayName)) { continue }
        $vistos[$p.DisplayName] = $true
        $data = $null
        if ([string]$p.InstallDate -match '^\d{8}$') { try { $data = [datetime]::ParseExact($p.InstallDate, 'yyyyMMdd', $null) } catch { } }
        $r = [ordered]@{}
        $r.Nome = [string]$p.DisplayName
        $r.Bytes = [double]$p.EstimatedSize * 1KB
        $r.Editor = [string]$p.Publisher
        $r.Data = $data
        $r.Desinstalar = [string]$p.UninstallString
        $lista.Add([pscustomobject]$r)
    }
    return @($lista | Sort-Object Bytes -Descending | Select-Object -First $Quantidade)
}

# Abre o desinstalador do próprio programa (com a janela dele: o usuário confirma lá)
function Start-DesinstaladorPrograma([string]$Comando) {
    $c = $Comando.Trim()
    if ($c -match '(?i)msiexec(\.exe)?\s+.*?/I\s*(\{[0-9A-F-]+\})') { $c = "MsiExec.exe /X$($Matches[2])" }
    Write-Log "Desinstalador aberto: $c"
    Start-Process cmd.exe -ArgumentList '/c', "`"$c`"" -WindowStyle Hidden
}

# ===============================================================
#  14. Modo jogo agora
#  Fecha os programas escolhidos (pedindo para fechar, sem forçar),
#  troca o plano de energia e guarda tudo para desfazer ao sair.
# ===============================================================
$Script:SemJanelaFechaveis = @('OneDrive', 'Spotify', 'ms-teams', 'Teams', 'Dropbox', 'GoogleDriveFS', 'AdobeCollabSync', 'Creative Cloud', 'CCXProcess', 'iCloudServices', 'WhatsApp', 'Telegram')
$Script:PesamEmJogo = @('chrome', 'msedge', 'firefox', 'opera', 'brave', 'ms-teams', 'Teams', 'OneDrive', 'Spotify', 'WhatsApp', 'Telegram', 'Slack', 'olk', 'OUTLOOK',
    'WINWORD', 'EXCEL', 'POWERPNT', 'Code', 'Dropbox', 'GoogleDriveFS', 'Creative Cloud', 'AnyDesk', 'Zoom')
$Script:NuncaFechar = @('explorer', 'ApplicationFrameHost', 'TextInputHost', 'ShellExperienceHost', 'StartMenuExperienceHost', 'SystemSettings', 'SearchHost',
    'powershell', 'pwsh', 'WindowsTerminal', 'conhost', 'dwm', 'LockApp', 'Widgets', 'PhoneExperienceHost', 'NVIDIA Overlay', 'Discord', 'steam', 'steamwebhelper',
    'EpicGamesLauncher', 'Battle.net', 'RiotClientServices', 'EADesktop', 'GalaxyClient', 'XboxPcApp')

function Get-ArqModoJogo { return (Join-Path $Script:Otz.Dados 'modo-jogo.json') }

# GUID do plano "Vinicius - Desempenho Maximo", se já foi criado (ajuste energia.plano)
function Get-PlanoOtimizador {
    foreach ($l in @(powercfg /list 2>$null)) {
        if ($l -like "*$($Script:Otz.NomePlano)*" -and $l -match "($Script:RegexGuid)") { return $Matches[1] }
    }
    return $null
}

function Get-EstadoModoJogo {
    $arq = Get-ArqModoJogo
    if (-not (Test-Path $arq)) { return [pscustomobject]@{ Ativo = $false; Preferidos = @(); TrocarPlano = $true } }
    try { return ([IO.File]::ReadAllText($arq, [Text.Encoding]::UTF8) | ConvertFrom-Json) } catch { return [pscustomobject]@{ Ativo = $false; Preferidos = @(); TrocarPlano = $true } }
}

function Save-EstadoModoJogo($Estado) {
    [IO.File]::WriteAllText((Get-ArqModoJogo), (ConvertTo-Json -InputObject $Estado -Depth 4), (New-Object Text.UTF8Encoding $false))
}

function Get-ProgramasAbertos {
    $grupos = @{}
    foreach ($p in [Diagnostics.Process]::GetProcesses()) {
        $n = $p.ProcessName
        if ($n -in $Script:NuncaFechar -or $p.Id -eq $PID -or $p.SessionId -eq 0) { continue }
        $temJanela = $p.MainWindowHandle -ne [IntPtr]::Zero
        if (-not $temJanela -and $n -notin $Script:SemJanelaFechaveis) { continue }
        if (-not $grupos.ContainsKey($n)) {
            $r = [ordered]@{}
            $r.Nome = $n; $r.Descricao = $n; $r.Caminho = ''; $r.Ram = [double]0; $r.Qtd = 0; $r.Pesa = $n -in $Script:PesamEmJogo
            $grupos[$n] = [pscustomobject]$r
        }
        $g = $grupos[$n]
        $g.Qtd++
        try { $g.Ram += [double]$p.WorkingSet64 } catch { }
        if (-not $g.Caminho) {
            try { $m = $p.MainModule; $g.Caminho = $m.FileName; if ($m.FileVersionInfo.FileDescription) { $g.Descricao = $m.FileVersionInfo.FileDescription.Trim() } } catch { }
        }
    }
    # A RAM do grupo inclui os processos sem janela do mesmo programa (ex.: abas do Chrome)
    foreach ($p in [Diagnostics.Process]::GetProcesses()) {
        if ($grupos.ContainsKey($p.ProcessName) -and $p.MainWindowHandle -eq [IntPtr]::Zero -and $p.ProcessName -notin $Script:SemJanelaFechaveis) {
            try { $grupos[$p.ProcessName].Ram += [double]$p.WorkingSet64 } catch { }
        }
    }
    return @($grupos.Values | Sort-Object Ram -Descending)
}

function Start-ModoJogo([string[]]$Nomes, [bool]$TrocarPlano) {
    $estado = Get-EstadoModoJogo
    $res = New-Object System.Collections.Generic.List[object]
    $fechados = New-Object System.Collections.Generic.List[object]
    $planoAnterior = $null
    if ($TrocarPlano) {
        $ativo = Get-PlanoAtivo
        $alvo = Get-PlanoOtimizador
        if (-not $alvo) { $alvo = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }   # Alto desempenho
        if ($ativo -and $ativo.Guid -ne $alvo) {
            $saida = powercfg /setactive $alvo 2>&1
            if ($LASTEXITCODE -eq 0) { $planoAnterior = $ativo.Guid; $res.Add((New-Achado 'Plano de energia' "Trocado para desempenho máximo (antes: $($ativo.Nome))." 'ok')) }
            else { $res.Add((New-Achado 'Plano de energia' "Não foi possível trocar: $($saida -join ' ')" 'medio')) }
        } else { $res.Add((New-Achado 'Plano de energia' 'Já estava em desempenho máximo.' 'ok')) }
    }
    foreach ($n in $Nomes) {
        $procs = @([Diagnostics.Process]::GetProcessesByName($n))
        if (-not $procs.Count) { continue }
        $caminho = ''
        foreach ($p in $procs) { if (-not $caminho) { try { $caminho = $p.MainModule.FileName } catch { } } }
        $comJanela = @($procs | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero })
        if ($comJanela.Count) { foreach ($p in $comJanela) { try { [void]$p.CloseMainWindow() } catch { } } }
        elseif ($n -eq 'OneDrive' -and $caminho) { Start-Process $caminho -ArgumentList '/shutdown' -WindowStyle Hidden }
        elseif ($n -in $Script:SemJanelaFechaveis) { foreach ($p in $procs) { try { $p.Kill() } catch { } } }
        $fim = (Get-Date).AddSeconds(6)
        while ((Get-Date) -lt $fim -and @([Diagnostics.Process]::GetProcessesByName($n)).Count) { Start-Sleep -Milliseconds 300 }
        if (@([Diagnostics.Process]::GetProcessesByName($n)).Count) {
            $res.Add((New-Achado $n 'Não fechou: pode estar perguntando se você quer salvar algo. Confira a janela dele.' 'medio'))
        } else {
            $res.Add((New-Achado $n 'Fechado.' 'ok'))
            if ($caminho) { $fechados.Add([pscustomobject]@{ Nome = $n; Caminho = $caminho }) }
        }
    }
    $novo = [ordered]@{}
    $novo.Ativo = $true
    $novo.Desde = (Get-Date).ToString('s')
    $novo.PlanoAnterior = $planoAnterior
    $novo.Fechados = $fechados.ToArray()
    $novo.Preferidos = [string[]]$Nomes
    $novo.TrocarPlano = $TrocarPlano
    Save-EstadoModoJogo $novo
    Write-Log "Modo jogo ligado: fechados $(@($fechados | ForEach-Object Nome) -join ', '); plano anterior $planoAnterior"
    return $res.ToArray()
}

function Stop-ModoJogo([bool]$Reabrir) {
    $e = Get-EstadoModoJogo
    $res = New-Object System.Collections.Generic.List[object]
    if ($e.PlanoAnterior) {
        $saida = powercfg /setactive $e.PlanoAnterior 2>&1
        if ($LASTEXITCODE -eq 0) { $res.Add((New-Achado 'Plano de energia' 'Voltou ao plano anterior.' 'ok')) }
        else { $res.Add((New-Achado 'Plano de energia' "Não foi possível voltar: $($saida -join ' ')" 'medio')) }
    }
    if ($Reabrir) {
        foreach ($f in @($e.Fechados)) {
            if (-not $f.Caminho -or -not (Test-Path $f.Caminho)) { continue }
            if (@([Diagnostics.Process]::GetProcessesByName($f.Nome)).Count) { continue }
            try { Start-Process $f.Caminho; $res.Add((New-Achado $f.Nome 'Reaberto.' 'ok')) } catch { $res.Add((New-Achado $f.Nome "Não reabriu: $($_.Exception.Message)" 'medio')) }
        }
    }
    $novo = [ordered]@{}
    $novo.Ativo = $false
    $novo.Preferidos = @($e.Preferidos)
    $novo.TrocarPlano = [bool]$e.TrocarPlano
    Save-EstadoModoJogo $novo
    Write-Log 'Modo jogo desligado.'
    return $res.ToArray()
}
