# Catálogo: Mouse e teclado
# Cada item é uma ficha. Campos: ver docs\catalogo.md
$cat = 'Mouse e teclado'

@(
    @{
        Id        = 'mouse.aceleracao'
        Categoria = $cat
        Nome      = 'Mouse sem aceleração'
        Resumo    = 'O ponteiro anda exatamente o quanto a sua mão anda.'
        Detalhe   = 'Desliga a opção "Aumentar precisão do ponteiro". Com ela ligada, o Windows acelera o ponteiro quando você mexe rápido, e a mesma distância na mesa vira distâncias diferentes na tela. Sem ela, o movimento fica previsível e a mão "aprende" mais rápido.'
        Indicado  = 'Todo mundo. Faz mais diferença em jogos, planilhas, desenho e CAD.'
        Atencao   = 'Nos primeiros minutos o mouse pode parecer mais lento. Se precisar, aumente o DPI no programa do mouse.'
        Risco     = 'seguro'
        Perfis    = @('basico', 'trabalho', 'gamer', 'leve', 'gpu-desempenho', 'gpu-balanceado')
        Registro  = @(
            @{ Chave = 'HKCU\Control Panel\Mouse'; Nome = 'MouseSpeed';      Valor = '0'; Tipo = 'String' }
            @{ Chave = 'HKCU\Control Panel\Mouse'; Nome = 'MouseThreshold1'; Valor = '0'; Tipo = 'String' }
            @{ Chave = 'HKCU\Control Panel\Mouse'; Nome = 'MouseThreshold2'; Valor = '0'; Tipo = 'String' }
        )
        AposAplicar  = { Update-MouseAoVivo }
        AposDesfazer = { Update-MouseAoVivo }
    }
    @{
        Id        = 'mouse.sensibilidade'
        Categoria = $cat
        Nome      = 'Velocidade do ponteiro no padrão (6 de 11)'
        Resumo    = 'Nessa posição o Windows não pula pixels. A velocidade fica por conta do DPI do mouse.'
        Detalhe   = 'Coloca o controle "Velocidade do ponteiro" no meio (6º risco). Acima disso o Windows multiplica o movimento e pula pixels; abaixo, descarta movimentos. No meio, cada movimento do sensor vira exatamente um pixel.'
        Indicado  = 'Quem joga ou usa mouse com DPI ajustável.'
        Atencao   = 'Se você escolheu uma velocidade de propósito, ela será trocada pela padrão.'
        Risco     = 'seguro'
        Perfis    = @('gamer')
        Registro  = @(
            @{ Chave = 'HKCU\Control Panel\Mouse'; Nome = 'MouseSensitivity'; Valor = '10'; Tipo = 'String' }
        )
        AposAplicar  = { Update-MouseAoVivo }
        AposDesfazer = { Update-MouseAoVivo }
    }
    @{
        Id        = 'teclado.altshift'
        Categoria = $cat
        Nome      = 'Alt+Shift não troca mais o idioma do teclado'
        Resumo    = 'Acaba com a troca acidental de layout (ABNT2 para US) no meio da digitação.'
        Detalhe   = 'Desliga os atalhos Alt+Shift e Ctrl+Shift que trocam o idioma ou o layout do teclado. Quando quiser trocar de propósito, use Windows+Espaço.'
        Indicado  = 'Quem tem mais de um layout instalado e vive vendo o "ç" virar ";".'
        Atencao   = 'Se você troca de idioma com frequência, passe a usar Windows+Espaço.'
        Risco     = 'seguro'
        Reinicio  = 'logoff'
        Perfis    = @('basico', 'trabalho', 'gamer', 'leve')
        Registro  = @(
            @{ Chave = 'HKCU\Keyboard Layout\Toggle'; Nome = 'Hotkey';          Valor = '3'; Tipo = 'String' }
            @{ Chave = 'HKCU\Keyboard Layout\Toggle'; Nome = 'Language Hotkey'; Valor = '3'; Tipo = 'String' }
            @{ Chave = 'HKCU\Keyboard Layout\Toggle'; Nome = 'Layout Hotkey';   Valor = '3'; Tipo = 'String' }
        )
    }
    @{
        Id        = 'teclado.aderencia'
        Categoria = $cat
        Nome      = 'Shift 5 vezes não abre mais as Teclas de Aderência'
        Resumo    = 'Fim da janela que aparece do nada no meio do jogo ou da digitação.'
        Detalhe   = 'Desliga só o ATALHO (apertar Shift 5 vezes). O recurso de acessibilidade continua disponível em Configurações > Acessibilidade > Teclado, para quem precisa.'
        Indicado  = 'Todo mundo que não usa o recurso de acessibilidade.'
        Risco     = 'seguro'
        Reinicio  = 'logoff'
        Perfis    = @('basico', 'trabalho', 'gamer', 'leve')
        Registro  = @(
            @{ Chave = 'HKCU\Control Panel\Accessibility\StickyKeys'; Nome = 'Flags'; Valor = '506'; Tipo = 'String' }
        )
    }
    @{
        Id        = 'teclado.filtro'
        Categoria = $cat
        Nome      = 'Segurar Shift não liga mais as Teclas de Filtragem'
        Resumo    = 'Segurar o Shift direito por 8 segundos não faz mais o teclado "ignorar" teclas.'
        Detalhe   = 'As Teclas de Filtragem fazem o Windows ignorar toques rápidos ou repetidos. O atalho dispara sem querer, e parece que o teclado quebrou. Aqui só o atalho é desligado.'
        Indicado  = 'Todo mundo que não usa o recurso de acessibilidade.'
        Risco     = 'seguro'
        Reinicio  = 'logoff'
        Perfis    = @('basico', 'trabalho', 'gamer', 'leve')
        Registro  = @(
            @{ Chave = 'HKCU\Control Panel\Accessibility\Keyboard Response'; Nome = 'Flags'; Valor = '122'; Tipo = 'String' }
        )
    }
    @{
        Id        = 'teclado.alternancia'
        Categoria = $cat
        Nome      = 'Num Lock não liga mais o bipe das Teclas de Alternância'
        Resumo    = 'Segurar Num Lock por 5 segundos não ativa mais os bipes.'
        Detalhe   = 'As Teclas de Alternância tocam um som ao apertar Caps Lock, Num Lock e Scroll Lock. Aqui só o atalho que liga o recurso é desligado.'
        Indicado  = 'Todo mundo que não usa o recurso de acessibilidade.'
        Risco     = 'seguro'
        Reinicio  = 'logoff'
        Perfis    = @('basico', 'trabalho', 'gamer', 'leve')
        Registro  = @(
            @{ Chave = 'HKCU\Control Panel\Accessibility\ToggleKeys'; Nome = 'Flags'; Valor = '58'; Tipo = 'String' }
        )
    }
    @{
        Id        = 'teclado.numlock'
        Categoria = $cat
        Nome      = 'Num Lock ligado ao iniciar'
        Resumo    = 'O teclado numérico já começa funcionando, inclusive na tela de senha.'
        Detalhe   = 'Liga o Num Lock na tela de entrada (usuário padrão do sistema) e na sua conta. Assim a senha com números funciona de primeira.'
        Indicado  = 'Teclados com bloco numérico separado (desktops e notebooks de 15" ou mais).'
        Atencao   = 'Em notebooks pequenos SEM teclado numérico separado, algumas letras viram números. Não use nesses modelos.'
        Risco     = 'seguro'
        Reinicio  = 'reiniciar'
        Perfis    = @('trabalho')
        Registro  = @(
            @{ Chave = 'HKU\.DEFAULT\Control Panel\Keyboard'; Nome = 'InitialKeyboardIndicators'; Valor = '2'; Tipo = 'String' }
            @{ Chave = 'HKCU\Control Panel\Keyboard';        Nome = 'InitialKeyboardIndicators'; Valor = '2'; Tipo = 'String' }
        )
    }
)
