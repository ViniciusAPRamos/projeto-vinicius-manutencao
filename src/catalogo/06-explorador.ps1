# Catálogo: Explorador e produtividade
$cat = 'Explorador e produtividade'

@(
    @{
        Id        = 'ui.extensoes'
        Categoria = $cat
        Nome      = 'Mostrar extensões de arquivos'
        Resumo    = 'Mostra .exe, .pdf e .bat. Ajuda a identificar arquivos falsos, como "fatura.pdf.exe".'
        Detalhe   = 'Liga "Extensões de nomes de arquivos" no Explorador. É uma das dicas de segurança mais simples e eficazes contra vírus por e-mail.'
        Indicado  = 'Todo mundo.'
        Risco     = 'seguro'
        Reinicio  = 'explorer'
        Perfis    = @('basico', 'trabalho', 'gamer', 'leve')
        Registro  = @(
            @{ Chave = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Nome = 'HideFileExt'; Valor = 0; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'ui.historico-clipboard'
        Categoria = $cat
        Nome      = 'Histórico da área de transferência (Win+V)'
        Resumo    = 'Windows+V mostra as últimas coisas que você copiou, não só a última.'
        Detalhe   = 'Ativa o histórico da área de transferência. Copie vários textos ou imagens e depois aperte Windows+V para escolher qual colar. Dá para fixar itens usados sempre.'
        Indicado  = 'Todo mundo. Economiza muito tempo no dia a dia.'
        Atencao   = 'Senhas copiadas também ficam no histórico até reiniciar. Use "Limpar tudo" no Win+V se copiar algo sensível.'
        Risco     = 'seguro'
        Perfis    = @('basico', 'trabalho', 'gamer', 'leve')
        Registro  = @(
            @{ Chave = 'HKCU\Software\Microsoft\Clipboard'; Nome = 'EnableClipboardHistory'; Valor = 1; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'ui.este-computador'
        Categoria = $cat
        Nome      = 'Explorador abre em "Este Computador"'
        Resumo    = 'Win+E vai direto para os discos (C:, D:, pendrives), sem passar pelo Acesso rápido.'
        Detalhe   = 'Muda a opção "Abrir o Explorador de Arquivos em" para "Este Computador".'
        Indicado  = 'Quem trabalha com pendrives, cartões SD e várias unidades.'
        Risco     = 'seguro'
        Perfis    = @('trabalho')
        Registro  = @(
            @{ Chave = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Nome = 'LaunchTo'; Valor = 1; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'ui.menu-classico'
        Categoria = $cat
        Nome      = 'Menu de clique direito completo'
        Resumo    = 'Todas as opções aparecem direto, sem precisar clicar em "Mostrar mais opções".'
        Detalhe   = 'Volta o menu de contexto clássico (estilo Windows 10) no Windows 11. Programas como 7-Zip e Notepad++ aparecem sem o clique extra.'
        Indicado  = 'Quem usa muito o clique direito: 7-Zip, Git, Notepad++, antivírus.'
        Risco     = 'seguro'
        Windows   = @('11')
        Reinicio  = 'explorer'
        Perfis    = @('trabalho')
        Registro  = @(
            @{ Chave = 'HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'; Nome = ''; Valor = ''; Tipo = 'String' }
        )
    }
    @{
        Id        = 'ui.modo-escuro'
        Categoria = $cat
        Nome      = 'Modo escuro'
        Resumo    = 'Windows e aplicativos com fundo escuro. Cansa menos a vista à noite.'
        Detalhe   = 'Muda o modo do Windows e o modo padrão dos aplicativos para Escuro (Configurações > Personalização > Cores).'
        Indicado  = 'Preferência pessoal.'
        Risco     = 'seguro'
        Perfis    = @()
        Registro  = @(
            @{ Chave = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Nome = 'AppsUseLightTheme';   Valor = 0; Tipo = 'DWord' }
            @{ Chave = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Nome = 'SystemUsesLightTheme'; Valor = 0; Tipo = 'DWord' }
        )
        AposAplicar  = { Send-MudancaConfiguracao 'ImmersiveColorSet' }
        AposDesfazer = { Send-MudancaConfiguracao 'ImmersiveColorSet' }
    }
)
