# Catálogo: Visual e desempenho
$cat = 'Visual e desempenho'

@(
    @{
        Id        = 'ui.menu-delay'
        Categoria = $cat
        Nome      = 'Menus abrem mais rápido'
        Resumo    = 'Submenus aparecem quase na hora (o padrão espera 0,4 segundo).'
        Detalhe   = 'Reduz o tempo que o Windows espera antes de abrir um submenu, de 400 ms para 50 ms. Deixa a sensação de "PC esperto".'
        Indicado  = 'Todo mundo.'
        Risco     = 'seguro'
        Reinicio  = 'logoff'
        Perfis    = @('basico', 'trabalho', 'gamer', 'leve')
        Registro  = @(
            @{ Chave = 'HKCU\Control Panel\Desktop'; Nome = 'MenuShowDelay'; Valor = '50'; Tipo = 'String' }
        )
    }
    @{
        Id        = 'ui.animacoes'
        Categoria = $cat
        Nome      = 'Janelas sem animação de minimizar'
        Resumo    = 'Minimizar, maximizar e a barra de tarefas respondem sem efeito de transição.'
        Detalhe   = 'Desliga a animação ao minimizar/maximizar janelas e as animações da barra de tarefas.'
        Indicado  = 'Todo mundo, principalmente PCs com vídeo integrado.'
        Risco     = 'seguro'
        Reinicio  = 'logoff'
        Perfis    = @('basico', 'trabalho', 'gamer', 'leve')
        Registro  = @(
            @{ Chave = 'HKCU\Control Panel\Desktop\WindowMetrics';                     Nome = 'MinAnimate';        Valor = '0'; Tipo = 'String' }
            @{ Chave = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Nome = 'TaskbarAnimations'; Valor = 0;   Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'ui.transparencia'
        Categoria = $cat
        Nome      = 'Sem transparência'
        Resumo    = 'Barra de tarefas, Iniciar e janelas ficam sólidos. Alivia placas de vídeo fracas.'
        Detalhe   = 'Desliga os "Efeitos de transparência" (Configurações > Personalização > Cores).'
        Indicado  = 'PCs simples, notebooks na bateria e quem acha mais legível sem transparência.'
        Risco     = 'seguro'
        Perfis    = @('gamer', 'leve', 'gpu-desempenho')
        Registro  = @(
            @{ Chave = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Nome = 'EnableTransparency'; Valor = 0; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'ui.efeitos-leves'
        Categoria = $cat
        Nome      = 'Efeitos visuais leves'
        Resumo    = 'Desliga sombras, seleção translúcida e o "espiar área de trabalho". Ajuda PCs simples.'
        Detalhe   = 'Muda os Efeitos visuais para "Personalizado" e desliga a seleção translúcida, as sombras dos rótulos de ícones e o Aero Peek. Fonte suavizada e miniaturas continuam ligadas.'
        Indicado  = 'PCs com pouca memória ou vídeo integrado antigo.'
        Atencao   = 'O visual fica um pouco mais "seco". Para controle total, use Ferramentas > Atalhos > Efeitos visuais.'
        Risco     = 'seguro'
        Reinicio  = 'explorer'
        Perfis    = @('leve')
        Registro  = @(
            @{ Chave = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Nome = 'VisualFXSetting';     Valor = 3; Tipo = 'DWord' }
            @{ Chave = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';      Nome = 'ListviewAlphaSelect'; Valor = 0; Tipo = 'DWord' }
            @{ Chave = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';      Nome = 'ListviewShadow';      Valor = 0; Tipo = 'DWord' }
            @{ Chave = 'HKCU\Software\Microsoft\Windows\DWM';                                   Nome = 'EnableAeroPeek';      Valor = 0; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'ui.startup-delay'
        Categoria = $cat
        Nome      = 'Sem espera artificial na inicialização'
        Resumo    = 'Os programas que abrem com o Windows começam logo, sem a pausa de cerca de 10 segundos.'
        Detalhe   = 'O Windows segura os programas de inicialização por alguns segundos depois do logon. Este ajuste tira essa espera.'
        Indicado  = 'PCs com SSD. Em HD mecânico, a espera ajuda o PC a "respirar" ao ligar.'
        Risco     = 'seguro'
        Reinicio  = 'reiniciar'
        Perfis    = @('basico', 'trabalho', 'gamer')
        Registro  = @(
            @{ Chave = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize'; Nome = 'StartupDelayInMSec'; Valor = 0; Tipo = 'DWord' }
        )
    }
)
