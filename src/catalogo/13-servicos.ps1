# Catálogo: Serviços em segundo plano
# Lista CONSERVADORA: só serviços que o Windows não precisa para funcionar.
# Nunca entram: rede, áudio, Wi-Fi, Windows Update, Defender, impressão com impressora instalada.
# Perfil 'ram' = recomendados na página Serviços para PCs com pouca memória.
$cat = 'Serviços em segundo plano'

@(
    # Programas de terceiros (src\segundoplano.ps1 + src\conhecidos.ps1). A tela Serviços
    # salva a escolha do usuário; sem escolha (perfis, Aplicar-Perfil.bat) vale só o "seguro".
    @{
        Id        = 'serv.segundo-plano'
        Categoria = $cat
        Nome      = 'Limpar o segundo plano (programas de terceiros)'
        Resumo    = 'Desliga agentes do fabricante, atualizadores e programas que abrem sozinhos com o Windows. Vale para sempre, com desfazer.'
        Detalhe   = 'Serviços de terceiros passam de Automático para Manual (o programa ainda liga o serviço quando precisa) e itens de inicialização são desligados como no Gerenciador de Tarefas. Sem escolha feita na página Serviços, entram só os itens reconhecidos como seguros. Anti-cheat, drivers, ventoinhas, antivírus e programas da Microsoft nunca entram. Uma tarefa semanal ("Guardião") desliga de novo o que uma atualização religar.'
        Indicado  = 'Notebooks e PCs de fábrica (Dell, HP, Lenovo...), PCs com 8 ou 16 GB e quem joga.'
        Atencao   = 'Cria a tarefa "Otimizador Vinicius - Manutencao" no Agendador, se ainda não existir, para o Guardião semanal.'
        Risco     = 'seguro'
        Perfis    = @('gamer', 'leve', 'ram')
        Tecnico   = "sc config <serviço> start= demand`nStartupApproved\Run: 03 (desligado)`nEstado e valores originais: Documentos\OtimizadorVinicius\segundo-plano.json"
        Detectar  = {
            $itens = @(Get-ItensSegundoPlano)
            $alvo = Get-IdsAlvoSegundoPlano $itens
            $pend = @($itens | Where-Object { $alvo -contains $_.Id -and -not $_.Aplicado })
            $feitos = @($itens | Where-Object Aplicado)
            if ($pend.Count) {
                $mb = 0.0; foreach ($i in $pend) { $mb += $i.Bytes }
                return @{ Estado = $(if ($feitos.Count) { 'parcial' } else { 'nao' }); Texto = "$($pend.Count) item(ns) para desligar (~$(Format-Tamanho $mb) agora)" }
            }
            if ($feitos.Count) { return @{ Estado = 'aplicado'; Texto = "$($feitos.Count) item(ns) desligado(s)" } }
            return @{ Estado = 'aplicado'; Texto = 'Nada a desligar neste PC' }
        }
        Simular   = {
            $itens = @(Get-ItensSegundoPlano)
            $alvo = Get-IdsAlvoSegundoPlano $itens
            foreach ($i in $itens) {
                if ($alvo -contains $i.Id -and -not $i.Aplicado) { "→ $($i.Tecnico)  (~$(Format-Tamanho $i.Bytes))" }
                elseif ($i.Aplicado -and $alvo -notcontains $i.Id) { "← $($i.Nome): volta ao original (saiu da escolha)" }
                elseif ($i.Aplicado) { "= $($i.Nome) já está desligado" }
            }
        }
        Aplicar   = {
            $itens = @(Get-ItensSegundoPlano)
            $alvo = Get-IdsAlvoSegundoPlano $itens
            $r = Sync-SegundoPlano $alvo
            if (-not (Get-Original 'serv.segundo-plano')) { Set-Original 'serv.segundo-plano' @{ Data = (Get-Date).ToString('s') } }
            $guardiao = $false
            try { $guardiao = Enable-GuardiaoSegundoPlano } catch { Write-Log "Guardião não ativado: $($_.Exception.Message)" }
            $partes = @("$(@($r.Aplicados).Count) desligado(s), ~$(Format-Tamanho $r.Bytes) a menos")
            if ($r.Voltaram) { $partes += "$($r.Voltaram) voltaram ao original" }
            if ($guardiao) { $partes += 'Guardião semanal ativo' }
            if (@($r.Erros).Count) { return @{ Status = 'aviso'; Mensagem = (($partes -join '; ') + '. Falhou: ' + (@($r.Erros) -join ' | ')) } }
            return @{ Status = 'ok'; Mensagem = (($partes -join '; ') + '. A inicialização vale a partir do próximo login.') }
        }
        Desfazer  = {
            param($orig)
            $r = Undo-SegundoPlano
            if (@($r.Erros).Count) { return @{ Status = 'erro'; Mensagem = (@($r.Erros) -join ' | ') } }
            return @{ Status = 'ok'; Mensagem = "$($r.Desfeitos) item(ns) voltaram ao que eram." }
        }
    }
    @{
        Id        = 'serv.telemetria'
        Categoria = $cat
        Nome      = 'Telemetria (Experiência do Usuário Conectado)'
        Resumo    = 'Para o serviço que coleta e envia dados de uso à Microsoft o tempo todo.'
        Detalhe   = 'Desativa "Experiências do Usuário Conectado e Telemetria" (DiagTrack) e o roteador de mensagens push ligado a ele (dmwappushservice). O Windows funciona normalmente sem eles.'
        Indicado  = 'Todo mundo, principalmente PCs com 8 GB.'
        Risco     = 'seguro'
        Perfis    = @('leve', 'gamer', 'ram')
        Servicos  = @(
            @{ Nome = 'DiagTrack';        Modo = 'disabled' }
            @{ Nome = 'dmwappushservice'; Modo = 'disabled' }
        )
    }
    @{
        Id        = 'serv.rastreamento-links'
        Categoria = $cat
        Nome      = 'Rastreamento de atalhos em rede'
        Resumo    = 'Serviço que acompanha arquivos movidos entre PCs de um domínio. Em casa e em empresas pequenas, não é usado.'
        Detalhe   = 'Muda o "Cliente de Rastreamento de Link Distribuído" (TrkWks) para Manual: ele só roda se algum programa pedir.'
        Indicado  = 'PCs fora de domínio corporativo (Active Directory).'
        Risco     = 'seguro'
        Perfis    = @('leve', 'ram')
        Servicos  = @( @{ Nome = 'TrkWks'; Modo = 'demand' } )
    }
    @{
        Id        = 'serv.compatibilidade'
        Categoria = $cat
        Nome      = 'Assistente de compatibilidade de programas'
        Resumo    = 'Fica vigiando instalações para avisar "este programa pode não ter sido instalado corretamente".'
        Detalhe   = 'Muda o "Serviço Auxiliar de Compatibilidade de Programas" (PcaSvc) para Manual.'
        Indicado  = 'Quem só usa programas atuais.'
        Atencao   = 'Os avisos automáticos de compatibilidade para programas muito antigos deixam de aparecer.'
        Risco     = 'seguro'
        Perfis    = @('leve', 'ram')
        Servicos  = @( @{ Nome = 'PcaSvc'; Modo = 'demand' } )
    }
    @{
        Id        = 'serv.mapas'
        Categoria = $cat
        Nome      = 'Gerenciador de mapas baixados'
        Resumo    = 'Só serve para o app Mapas offline. Fica em Manual e roda apenas se você usar.'
        Detalhe   = 'Muda o "Gerenciador de Mapas Baixados" (MapsBroker) para Manual.'
        Indicado  = 'Quem não usa o app Mapas do Windows.'
        Risco     = 'seguro'
        Perfis    = @('leve', 'ram')
        Servicos  = @( @{ Nome = 'MapsBroker'; Modo = 'demand' } )
    }
    @{
        Id        = 'serv.fax'
        Categoria = $cat
        Nome      = 'Fax'
        Resumo    = 'Serviço de envio de fax pelo modem do PC.'
        Detalhe   = 'Desativa o serviço "Fax". Em muitas instalações ele nem existe; nesse caso o item fica cinza.'
        Indicado  = 'Todo mundo que não envia fax pelo computador.'
        Risco     = 'seguro'
        Perfis    = @('leve', 'ram')
        Servicos  = @( @{ Nome = 'Fax'; Modo = 'disabled' } )
    }
    @{
        Id        = 'serv.sysmain'
        Categoria = $cat
        Nome      = 'SysMain (pré-carregamento de programas)'
        Resumo    = 'Pré-carrega na RAM os programas que você mais usa. Em SSD o ganho é pequeno, e ele ocupa memória e disco.'
        Detalhe   = 'Desativa o SysMain (antigo Superfetch). Em PCs com SSD e pouca RAM, libera memória e reduz o uso de disco em segundo plano.'
        Indicado  = 'PCs com SSD e 8 GB de RAM que ficam lentos com o disco em 100%.'
        Atencao   = 'Em HD mecânico o SysMain AJUDA: deixe ligado. Os programas podem demorar um pouco mais para abrir na primeira vez.'
        Risco     = 'moderado'
        Perfis    = @()
        Servicos  = @( @{ Nome = 'SysMain'; Modo = 'disabled' } )
    }
    @{
        Id        = 'serv.busca'
        Categoria = $cat
        Nome      = 'Indexação da pesquisa (Windows Search)'
        Resumo    = 'O indexador lê o disco o tempo todo para deixar a pesquisa de arquivos instantânea. Usa RAM e disco.'
        Detalhe   = 'Desativa o "Windows Search". A pesquisa de programas e configurações no Iniciar continua funcionando; a busca por CONTEÚDO de arquivos fica bem mais lenta.'
        Indicado  = 'PCs com 8 GB e HD, ou quem usa outro buscador (ex.: Everything).'
        Atencao   = 'O Outlook usa o índice para pesquisar e-mails: a busca dele fica lenta ou incompleta.'
        Risco     = 'moderado'
        Perfis    = @()
        Servicos  = @( @{ Nome = 'WSearch'; Modo = 'disabled' } )
    }
    @{
        Id        = 'serv.xbox'
        Categoria = $cat
        Nome      = 'Serviços Xbox Live'
        Resumo    = 'Login, salvamento na nuvem e rede do Xbox. Sem eles, jogos da Steam e da Epic funcionam normalmente.'
        Detalhe   = 'Desativa Gerenciador de Autenticação Xbox Live, Salvamento de Jogos Xbox Live e Serviço de Rede Xbox Live. O serviço de acessórios (controle Xbox) NÃO é mexido.'
        Indicado  = 'Quem não usa Game Pass, o app Xbox nem jogos da Microsoft Store.'
        Atencao   = 'Game Pass, app Xbox, Minecraft (launcher) e conquistas Xbox param de funcionar até desfazer.'
        Risco     = 'moderado'
        Perfis    = @()
        Servicos  = @(
            @{ Nome = 'XblAuthManager'; Modo = 'disabled' }
            @{ Nome = 'XblGameSave';    Modo = 'disabled' }
            @{ Nome = 'XboxNetApiSvc';  Modo = 'disabled' }
        )
    }
    @{
        Id        = 'serv.impressao'
        Categoria = $cat
        Nome      = 'Spooler de impressão (sem impressora)'
        Resumo    = 'Sem impressora instalada, o serviço de impressão só ocupa memória e já teve falhas de segurança graves.'
        Detalhe   = 'Desativa o "Spooler de Impressão". Só fica disponível quando não há impressora física instalada.'
        Indicado  = 'PCs que nunca imprimem.'
        Atencao   = 'Imprimir (inclusive "Microsoft Print to PDF") para de funcionar até desfazer.'
        Confirmar = 'Imprimir, inclusive para PDF, para de funcionar até desfazer este ajuste.'
        Risco     = 'moderado'
        Requisito = { if (Test-ImpressoraFisica) { 'Há impressora instalada neste PC: desligar o serviço impediria imprimir.' } }
        Perfis    = @()
        Servicos  = @( @{ Nome = 'Spooler'; Modo = 'disabled' } )
    }
)
