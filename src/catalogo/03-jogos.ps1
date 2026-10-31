# Catálogo: Jogos
$cat = 'Jogos'

@(
    @{
        Id        = 'game.modo-jogo'
        Categoria = $cat
        Nome      = 'Modo de Jogo do Windows'
        Resumo    = 'O Windows dá prioridade ao jogo aberto e segura atualizações durante a partida.'
        Detalhe   = 'Garante que o Modo de Jogo esteja ligado. Ele já vem ativo na maioria das instalações, mas alguns "otimizadores" e atualizações desligam.'
        Indicado  = 'Quem joga.'
        Risco     = 'seguro'
        Perfis    = @('gamer', 'gpu-desempenho', 'gpu-balanceado', 'gpu-qualidade')
        Registro  = @(
            @{ Chave = 'HKCU\Software\Microsoft\GameBar'; Nome = 'AutoGameModeEnabled'; Valor = 1; Tipo = 'DWord' }
            @{ Chave = 'HKCU\Software\Microsoft\GameBar'; Nome = 'AllowAutoGameMode';   Valor = 1; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'game.dvr'
        Categoria = $cat
        Nome      = 'Desligar gravação em segundo plano (Game DVR)'
        Resumo    = 'Para de gravar o jogo escondido, o que economiza placa de vídeo e disco.'
        Detalhe   = 'O Game DVR grava continuamente os últimos minutos de jogo para o recurso "Gravar o que aconteceu". Isso custa desempenho o tempo todo.'
        Indicado  = 'Quem não usa o Win+Alt+G para salvar trechos de jogo.'
        Atencao   = 'O "Gravar o que aconteceu" para de funcionar. Gravação manual (OBS, ShadowPlay etc.) continua normal.'
        Risco     = 'seguro'
        Perfis    = @('gamer', 'gpu-desempenho', 'gpu-balanceado')
        Registro  = @(
            @{ Chave = 'HKCU\System\GameConfigStore';                            Nome = 'GameDVR_Enabled';   Valor = 0; Tipo = 'DWord' }
            @{ Chave = 'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR'; Nome = 'AppCaptureEnabled'; Valor = 0; Tipo = 'DWord' }
        )
    }
    @{
        Id          = 'game.hags'
        Categoria   = $cat
        Nome        = 'Agendamento de GPU acelerado por hardware'
        Resumo      = 'A placa de vídeo organiza a própria fila de trabalho. Pode reduzir a latência.'
        Detalhe     = 'Liga o HAGS: a placa de vídeo passa a gerenciar a própria memória e fila de tarefas, em vez de o Windows fazer isso. É exigido por alguns recursos, como o DLSS Frame Generation.'
        Indicado    = 'PCs com placa de vídeo dedicada recente e driver atualizado.'
        Atencao     = 'Placa ou driver antigo ignora o ajuste. Se um jogo começar a travar, desfaça.'
        Risco       = 'seguro'
        BuildMinima = 19041
        Reinicio    = 'reiniciar'
        Perfis      = @('gamer', 'gpu-desempenho', 'gpu-balanceado', 'gpu-qualidade')
        Registro    = @(
            @{ Chave = 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Nome = 'HwSchMode'; Valor = 2; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'game.mmcss'
        Categoria = $cat
        Nome      = 'Prioridade de CPU e GPU para jogos (MMCSS)'
        Resumo    = 'Pede ao Windows para reservar menos processador para tarefas de fundo durante jogos.'
        Detalhe   = 'Ajusta o agendador multimídia do Windows: reserva para segundo plano de 20% para 10% e prioridade alta para a categoria "Games".'
        Indicado  = 'Opcional. Para quem quer espremer o máximo do PC.'
        Atencao   = 'Efeito pequeno e discutível: muitos testes não mostram diferença. Mantenha só se notar melhora.'
        Risco     = 'moderado'
        Reinicio  = 'reiniciar'
        Perfis    = @('gamer', 'gpu-desempenho')
        Registro  = @(
            @{ Chave = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile';             Nome = 'SystemResponsiveness'; Valor = 10;     Tipo = 'DWord' }
            @{ Chave = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Nome = 'GPU Priority';         Valor = 8;      Tipo = 'DWord' }
            @{ Chave = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Nome = 'Priority';             Valor = 6;      Tipo = 'DWord' }
            @{ Chave = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Nome = 'Scheduling Category';  Valor = 'High'; Tipo = 'String' }
            @{ Chave = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Nome = 'SFIO Priority';        Valor = 'High'; Tipo = 'String' }
        )
    }
    @{
        Id        = 'game.vbs'
        Categoria = $cat
        Nome      = 'Desligar Integridade de Memória (VBS/HVCI)'
        Resumo    = 'Pode render alguns FPS a mais, em troca de menos proteção contra drivers maliciosos.'
        Detalhe   = 'Desliga o "Isolamento de núcleo > Integridade de memória" da Segurança do Windows. Esse recurso usa virtualização para impedir que drivers adulterados rodem, e isso tem custo de desempenho.'
        Indicado  = 'Somente PC dedicado a jogos, nunca PC de trabalho ou da empresa.'
        Atencao   = 'Reduz a segurança do Windows. Se estiver bloqueado pela BIOS/UEFI ou por política da empresa, o ajuste é ignorado.'
        Risco     = 'avancado'
        Reinicio  = 'reiniciar'
        Perfis    = @()
        Registro  = @(
            @{ Chave = 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'; Nome = 'Enabled'; Valor = 0; Tipo = 'DWord' }
        )
    }
)
