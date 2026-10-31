# Catálogo: Barra de tarefas e Iniciar
$cat     = 'Barra de tarefas e Iniciar'
$avisoGp = 'Por ser uma política, as Configurações podem mostrar "Algumas configurações são gerenciadas pela sua organização". É normal.'

@(
    @{
        Id          = 'ui.finalizar-tarefa'
        Categoria   = $cat
        Nome        = '"Finalizar tarefa" no clique direito da barra'
        Resumo      = 'Fecha um programa travado direto pela barra de tarefas, sem abrir o Gerenciador.'
        Detalhe     = 'Ativa a opção oficial do Windows 11 (Configurações > Sistema > Para desenvolvedores > Finalizar tarefa). Clique com o botão direito no ícone do programa na barra e escolha "Finalizar tarefa".'
        Indicado    = 'Todo mundo.'
        Risco       = 'seguro'
        Windows     = @('11')
        BuildMinima = 22631
        Perfis      = @('trabalho', 'gamer')
        Registro    = @(
            @{ Chave = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings'; Nome = 'TaskbarEndTask'; Valor = 1; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'ui.alinhar-esquerda'
        Categoria = $cat
        Nome      = 'Iniciar no canto esquerdo'
        Resumo    = 'Botão Iniciar e ícones da barra à esquerda, como no Windows 10.'
        Detalhe   = 'Muda o "Alinhamento da barra de tarefas" de Centro para Esquerda.'
        Indicado  = 'Quem veio do Windows 10 ou usa monitor ultrawide.'
        Risco     = 'seguro'
        Windows   = @('11')
        Perfis    = @()
        Registro  = @(
            @{ Chave = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Nome = 'TaskbarAl'; Valor = 0; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'ui.widgets'
        Categoria = $cat
        Nome      = 'Desligar Widgets (notícias e clima)'
        Resumo    = 'Remove o painel de notícias que abre sozinho ao passar o mouse e consome memória.'
        Detalhe   = 'Desativa os Widgets pela política oficial do Windows 11. O botão some da barra e o processo de notícias para de rodar.'
        Indicado  = 'PCs simples, PCs de trabalho e quem não usa o painel.'
        Atencao   = $avisoGp
        Risco     = 'seguro'
        Windows   = @('11')
        Reinicio  = 'explorer'
        Perfis    = @('gamer', 'leve')
        Registro  = @(
            @{ Chave = 'HKLM\SOFTWARE\Policies\Microsoft\Dsh'; Nome = 'AllowNewsAndInterests'; Valor = 0; Tipo = 'DWord' }
        )
    }
    @{
        Id          = 'ui.noticias-win10'
        Categoria   = $cat
        Nome        = 'Desligar Notícias e interesses'
        Resumo      = 'Remove o clima e as notícias da barra de tarefas do Windows 10.'
        Detalhe     = 'Desativa o "Notícias e interesses" pela política oficial do Windows 10.'
        Indicado    = 'PCs simples, PCs de trabalho e quem não usa o recurso.'
        Atencao     = $avisoGp
        Risco       = 'seguro'
        Windows     = @('10')
        BuildMinima = 19041
        Reinicio    = 'explorer'
        Perfis      = @('gamer', 'leve')
        Registro    = @(
            @{ Chave = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds'; Nome = 'EnableFeeds'; Valor = 0; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'ui.pesquisa-icone'
        Categoria = $cat
        Nome      = 'Pesquisa como ícone'
        Resumo    = 'A caixa de pesquisa vira só uma lupa e libera espaço na barra.'
        Detalhe   = 'A pesquisa continua igual: clique na lupa ou aperte a tecla Windows e comece a digitar.'
        Indicado  = 'Telas pequenas e quem tem muitos programas fixados.'
        Risco     = 'seguro'
        Reinicio  = 'explorer'
        Perfis    = @()
        Registro  = @(
            @{ Chave = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Search'; Nome = 'SearchboxTaskbarMode'; Valor = 1; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'ui.task-view'
        Categoria = $cat
        Nome      = 'Ocultar botão Visão de Tarefas'
        Resumo    = 'Tira o botão de áreas de trabalho virtuais da barra (Win+Tab continua funcionando).'
        Detalhe   = 'Só esconde o botão. O recurso continua disponível pelo atalho Windows+Tab.'
        Indicado  = 'Quem não usa várias áreas de trabalho.'
        Risco     = 'seguro'
        Perfis    = @()
        Registro  = @(
            @{ Chave = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Nome = 'ShowTaskViewButton'; Valor = 0; Tipo = 'DWord' }
        )
    }
)
