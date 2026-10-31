# Catálogo: Navegadores
# Políticas oficiais do Microsoft Edge e do Google Chrome. Depois de aplicar,
# confira em edge://policy e chrome://policy (aparecem como "Obrigatória").
$cat = 'Navegadores'
$avisoNav = 'Por ser política, o navegador mostra "Gerenciado pela sua organização" no menu. É normal; some ao desfazer.'
$temEdge = { if (-not (Test-RegChave 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe')) { 'O Microsoft Edge não está instalado.' } }
$temChrome = { if (-not (Test-RegChave 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe')) { 'O Google Chrome não está instalado.' } }

@(
    @{
        Id        = 'nav.edge-segundo-plano'
        Categoria = $cat
        Nome      = 'Edge fecha de verdade ao clicar no X'
        Resumo    = 'O Edge para de ficar rodando escondido (e gastando memória) depois que você fecha a janela.'
        Detalhe   = 'Desliga "Continuar executando extensões e aplicativos em segundo plano quando o Microsoft Edge for fechado".'
        Indicado  = 'Todo mundo, principalmente PCs com 8 GB.'
        Atencao   = $avisoNav
        Risco     = 'seguro'
        Requisito = $temEdge
        Perfis    = @('leve', 'trabalho', 'gamer')
        Registro  = @( @{ Chave = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Nome = 'BackgroundModeEnabled'; Valor = 0; Tipo = 'DWord' } )
    }
    @{
        Id        = 'nav.edge-inicializacao'
        Categoria = $cat
        Nome      = 'Edge sem pré-carregamento ao ligar o PC'
        Resumo    = 'O Windows para de abrir o Edge escondido no início só para ele parecer mais rápido depois.'
        Detalhe   = 'Desliga o "Aumento de inicialização" (Startup Boost). O Windows liga mais leve; o Edge leva um instante a mais para abrir na primeira vez.'
        Indicado  = 'Quem usa outro navegador ou tem PC simples.'
        Atencao   = $avisoNav
        Risco     = 'seguro'
        Requisito = $temEdge
        Perfis    = @('leve', 'trabalho')
        Registro  = @( @{ Chave = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Nome = 'StartupBoostEnabled'; Valor = 0; Tipo = 'DWord' } )
    }
    @{
        Id        = 'nav.edge-abas-dormir'
        Categoria = $cat
        Nome      = 'Edge: abas paradas "dormem"'
        Resumo    = 'Abas que você não usa há um tempo liberam memória e processador. Voltam na hora quando clicadas.'
        Detalhe   = 'Garante as "Guias suspensas" (Sleeping Tabs) ligadas. Útil para quem trabalha com muitas abas abertas.'
        Indicado  = 'Quem deixa 10, 20, 50 abas abertas.'
        Atencao   = $avisoNav
        Risco     = 'seguro'
        Requisito = $temEdge
        Perfis    = @('leve', 'trabalho')
        Registro  = @( @{ Chave = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Nome = 'SleepingTabsEnabled'; Valor = 1; Tipo = 'DWord' } )
    }
    @{
        Id        = 'nav.chrome-segundo-plano'
        Categoria = $cat
        Nome      = 'Chrome fecha de verdade ao clicar no X'
        Resumo    = 'O Chrome para de ficar rodando escondido (e gastando memória) depois que você fecha a janela.'
        Detalhe   = 'Desliga "Continuar executando apps em segundo plano quando o Google Chrome estiver fechado".'
        Indicado  = 'Todo mundo, principalmente PCs com 8 GB.'
        Atencao   = $avisoNav
        Risco     = 'seguro'
        Requisito = $temChrome
        Perfis    = @('leve', 'trabalho', 'gamer')
        Registro  = @( @{ Chave = 'HKLM\SOFTWARE\Policies\Google\Chrome'; Nome = 'BackgroundModeEnabled'; Valor = 0; Tipo = 'DWord' } )
    }
)
