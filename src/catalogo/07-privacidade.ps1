# Catálogo: Privacidade e anúncios
$cat     = 'Privacidade e anúncios'
$avisoGp = 'Por ser uma política, as Configurações podem mostrar "Algumas configurações são gerenciadas pela sua organização". É normal.'
$cdm     = 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'

@(
    @{
        Id        = 'priv.sugestoes'
        Categoria = $cat
        Nome      = 'Sem apps sugeridos e propaganda no Iniciar'
        Resumo    = 'O Windows para de instalar "sugestões" sozinho e de mostrar dicas e ofertas.'
        Detalhe   = 'Desliga a instalação silenciosa de aplicativos patrocinados, as sugestões no Iniciar, as dicas ao usar o Windows e o conteúdo sugerido nas Configurações.'
        Indicado  = 'Todo mundo.'
        Risco     = 'seguro'
        Perfis    = @('basico', 'trabalho', 'gamer', 'leve')
        Registro  = @(
            @{ Chave = $cdm; Nome = 'SilentInstalledAppsEnabled';      Valor = 0; Tipo = 'DWord' }
            @{ Chave = $cdm; Nome = 'SystemPaneSuggestionsEnabled';    Valor = 0; Tipo = 'DWord' }
            @{ Chave = $cdm; Nome = 'SoftLandingEnabled';              Valor = 0; Tipo = 'DWord' }
            @{ Chave = $cdm; Nome = 'SubscribedContent-338388Enabled'; Valor = 0; Tipo = 'DWord' }
            @{ Chave = $cdm; Nome = 'SubscribedContent-338389Enabled'; Valor = 0; Tipo = 'DWord' }
            @{ Chave = $cdm; Nome = 'SubscribedContent-338393Enabled'; Valor = 0; Tipo = 'DWord' }
            @{ Chave = $cdm; Nome = 'SubscribedContent-353694Enabled'; Valor = 0; Tipo = 'DWord' }
            @{ Chave = $cdm; Nome = 'SubscribedContent-353696Enabled'; Valor = 0; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'priv.anuncios'
        Categoria = $cat
        Nome      = 'Desligar ID de publicidade'
        Resumo    = 'Os aplicativos deixam de receber um identificador para mostrar anúncios personalizados.'
        Detalhe   = 'Desliga "Permitir que os aplicativos me mostrem anúncios personalizados usando minha ID de publicidade".'
        Indicado  = 'Todo mundo.'
        Risco     = 'seguro'
        Perfis    = @('basico', 'trabalho', 'gamer', 'leve')
        Registro  = @(
            @{ Chave = 'HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Nome = 'Enabled'; Valor = 0; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'priv.tela-bloqueio'
        Categoria = $cat
        Nome      = 'Tela de bloqueio sem curiosidades e ofertas'
        Resumo    = 'Remove os textos "Gostou do que vê?", as dicas e as propagandas por cima da imagem.'
        Detalhe   = 'Desliga "Obter curiosidades, dicas e muito mais na tela de bloqueio". A imagem de fundo continua igual.'
        Indicado  = 'Todo mundo.'
        Risco     = 'seguro'
        Perfis    = @('basico', 'trabalho', 'gamer', 'leve')
        Registro  = @(
            @{ Chave = $cdm; Nome = 'RotatingLockScreenOverlayEnabled'; Valor = 0; Tipo = 'DWord' }
            @{ Chave = $cdm; Nome = 'SubscribedContent-338387Enabled';  Valor = 0; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'priv.configuracao'
        Categoria = $cat
        Nome      = 'Sem a tela "Vamos terminar de configurar"'
        Resumo    = 'Para de aparecer, depois de atualizações, a tela azul que oferece OneDrive, Microsoft 365 e afins.'
        Detalhe   = 'Desliga "Sugerir maneiras de concluir a configuração do dispositivo".'
        Indicado  = 'Todo mundo.'
        Risco     = 'seguro'
        Perfis    = @('basico', 'trabalho', 'gamer', 'leve')
        Registro  = @(
            @{ Chave = 'HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement'; Nome = 'ScoobeSystemSettingEnabled'; Valor = 0; Tipo = 'DWord' }
        )
    }
    @{
        Id          = 'priv.recomendacoes-iniciar'
        Categoria   = $cat
        Nome        = 'Iniciar sem recomendações de apps'
        Resumo      = 'A seção "Recomendado" do Iniciar para de sugerir apps da Loja e dicas.'
        Detalhe     = 'Desliga "Mostrar recomendações de dicas, atalhos, novos aplicativos e muito mais" no Iniciar. Seus arquivos recentes continuam aparecendo.'
        Indicado    = 'Todo mundo.'
        Risco       = 'seguro'
        Windows     = @('11')
        BuildMinima = 22621
        Reinicio    = 'explorer'
        Perfis      = @('basico', 'trabalho', 'gamer', 'leve')
        Registro    = @(
            @{ Chave = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Nome = 'Start_IrisRecommendations'; Valor = 0; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'priv.bing'
        Categoria = $cat
        Nome      = 'Pesquisa do Iniciar sem Bing'
        Resumo    = 'A pesquisa do Iniciar procura só no seu PC. Fica mais rápida e não envia o que você digita.'
        Detalhe   = 'Desativa as sugestões da web (Bing) na caixa de pesquisa. Programas, arquivos e configurações continuam aparecendo normalmente.'
        Indicado  = 'Todo mundo.'
        Atencao   = $avisoGp
        Risco     = 'seguro'
        Reinicio  = 'explorer'
        Perfis    = @('basico', 'trabalho', 'gamer', 'leve')
        Registro  = @(
            @{ Chave = 'HKCU\Software\Policies\Microsoft\Windows\Explorer'; Nome = 'DisableSearchBoxSuggestions'; Valor = 1; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'priv.atividades'
        Categoria = $cat
        Nome      = 'Não registrar histórico de atividades'
        Resumo    = 'O Windows para de guardar o histórico de programas e arquivos que você abre.'
        Detalhe   = 'Desativa a publicação do histórico de atividades (Linha do tempo) por política.'
        Indicado  = 'Todo mundo.'
        Atencao   = $avisoGp
        Risco     = 'seguro'
        Perfis    = @('basico', 'trabalho', 'gamer', 'leve')
        Registro  = @(
            @{ Chave = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System'; Nome = 'PublishUserActivities'; Valor = 0; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'priv.telemetria'
        Categoria = $cat
        Nome      = 'Telemetria no mínimo permitido'
        Resumo    = 'Envia à Microsoft só os dados de diagnóstico obrigatórios.'
        Detalhe   = 'Define a política "Permitir dados de diagnóstico" no menor nível. Nas edições Home e Pro, o mínimo real é "dados obrigatórios" (o nível zero só existe no Enterprise).'
        Indicado  = 'Quem prefere enviar o mínimo de dados.'
        Atencao   = 'As Configurações passam a mostrar "gerenciado pela sua organização" em Privacidade. Alguns recursos de diagnóstico ficam indisponíveis.'
        Risco     = 'moderado'
        Perfis    = @()
        Registro  = @(
            @{ Chave = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Nome = 'AllowTelemetry'; Valor = 0; Tipo = 'DWord' }
        )
    }
)
