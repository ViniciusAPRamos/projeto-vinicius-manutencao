# Catálogo: Notebook e bateria
# Só ficam disponíveis em PCs com bateria. Corrente = 'dc' grava a configuração "na bateria".
# GUIDs da tampa e da economia de bateria: documentação de energia da Microsoft
# (não aparecem em desktop; validar num notebook, ver docs/plano-de-testes.md).
$cat = 'Notebook e bateria'
$soNotebook = { if (-not (Test-Notebook)) { 'Só para notebooks: este PC não tem bateria.' } }

@(
    @{
        Id        = 'note.tela-bateria'
        Categoria = $cat
        Nome      = 'Na bateria: tela apaga em 3 min e suspende em 10'
        Resumo    = 'A tela é o que mais gasta bateria. Apagar mais cedo quando você sai de perto rende bastante.'
        Detalhe   = 'No plano de energia ativo, só na bateria: desligar a tela após 3 minutos sem uso e suspender após 10 minutos. Na tomada nada muda.'
        Indicado  = 'Notebooks que você usa fora da tomada.'
        Risco     = 'seguro'
        Requisito = $soNotebook
        Perfis    = @('notebook')
        Energia   = @(
            @{ Sub = 'SUB_VIDEO'; Config = 'VIDEOIDLE';   Valor = 180; Corrente = 'dc' }
            @{ Sub = 'SUB_SLEEP'; Config = 'STANDBYIDLE'; Valor = 600; Corrente = 'dc' }
        )
    }
    @{
        Id        = 'note.economia-30'
        Categoria = $cat
        Nome      = 'Economia de bateria liga em 30%'
        Resumo    = 'O modo economia entra antes (o padrão é 20%), e sobra mais tempo quando a carga está acabando.'
        Detalhe   = 'Muda o nível em que a "Economia de bateria" liga sozinha de 20% para 30%. Ela reduz atividade em segundo plano e o brilho.'
        Indicado  = 'Quem costuma ficar sem carga no fim do dia.'
        Risco     = 'seguro'
        Requisito = $soNotebook
        Perfis    = @('notebook')
        Energia   = @(
            @{ Sub = 'de830923-a562-41af-a086-e3a2c6bad2da'; Config = 'e69653ca-cf7f-4f05-aa73-cb833fa90ad4'; Valor = 30; Corrente = 'dc' }
        )
    }
    @{
        Id        = 'note.sem-turbo-bateria'
        Categoria = $cat
        Nome      = 'Na bateria: processador sem turbo'
        Resumo    = 'Notebook mais frio, silencioso e com mais bateria. Na tomada o desempenho continua total.'
        Detalhe   = 'Limita o "Estado máximo do processador" a 99% só na bateria. Esse 1% a menos desliga o Turbo Boost/Precision Boost, que é o que mais esquenta e gasta energia.'
        Indicado  = 'Uso de escritório, estudo e navegador fora da tomada.'
        Atencao   = 'Tarefas pesadas (renderizar, jogar) ficam mais lentas na bateria. Na tomada nada muda.'
        Risco     = 'moderado'
        Requisito = $soNotebook
        Perfis    = @('notebook')
        Energia   = @(
            @{ Sub = 'SUB_PROCESSOR'; Config = 'PROCTHROTTLEMAX'; Valor = 99; Corrente = 'dc' }
        )
    }
    @{
        Id        = 'note.tampa-tomada'
        Categoria = $cat
        Nome      = 'Tampa fechada na tomada: continua ligado'
        Resumo    = 'Para usar o notebook fechado com monitor, teclado e mouse externos.'
        Detalhe   = 'Muda a ação de "Fechar a tampa" na tomada para "Nada a fazer". Na bateria, fechar a tampa continua suspendendo, como sempre.'
        Indicado  = 'Notebook usado em dock ou como "desktop" na mesa.'
        Atencao   = 'Não guarde o notebook na mochila ligado na tomada: ele continua ligado e esquenta.'
        Risco     = 'seguro'
        Requisito = $soNotebook
        Perfis    = @()
        Energia   = @(
            @{ Sub = 'SUB_BUTTONS'; Config = '5ca83367-6e45-459f-a27b-476b1d01c936'; Valor = 0 }
        )
    }
)
