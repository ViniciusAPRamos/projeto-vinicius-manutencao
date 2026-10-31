# Catálogo: Sistema e atualizações
$cat     = 'Sistema e atualizações'
$avisoGp = 'Por ser uma política, as Configurações podem mostrar "Algumas configurações são gerenciadas pela sua organização". É normal.'

@(
    @{
        Id        = 'sistema.inicializacao-rapida'
        Categoria = $cat
        Nome      = 'Desligar a Inicialização rápida'
        Resumo    = '"Desligar" passa a desligar de verdade. Resolve drivers USB/serial que travam.'
        Detalhe   = 'Com a Inicialização rápida, "Desligar" na verdade hiberna o núcleo do Windows. Drivers e equipamentos USB podem voltar travados, e o "Ligado há" nunca zera. Sem ela, cada desligamento é limpo.'
        Indicado  = 'Quem usa equipamentos USB-serial, dual boot ou tem problemas que "só resolvem reiniciando".'
        Atencao   = 'O PC pode levar alguns segundos a mais para ligar.'
        Risco     = 'seguro'
        Perfis    = @('trabalho', 'gamer')
        Registro  = @(
            @{ Chave = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Nome = 'HiberbootEnabled'; Valor = 0; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'sistema.reinicio-update'
        Categoria = $cat
        Nome      = 'Windows Update não reinicia com você logado'
        Resumo    = 'Chega de voltar ao PC e encontrar tudo fechado porque o Windows reiniciou sozinho.'
        Detalhe   = 'Com alguém conectado, as atualizações automáticas esperam você reiniciar quando puder. As atualizações continuam sendo baixadas e instaladas normalmente.'
        Indicado  = 'PCs de trabalho, máquinas que rodam processos longos e acesso remoto.'
        Atencao   = "Reinicie de vez em quando para concluir as atualizações. Funciona no Pro e no Enterprise; o Home pode ignorar. $avisoGp"
        Risco     = 'seguro'
        Perfis    = @('trabalho', 'gamer')
        Registro  = @(
            @{ Chave = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Nome = 'NoAutoRebootWithLoggedOnUsers'; Valor = 1; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'sistema.entrega-otimizada'
        Categoria = $cat
        Nome      = 'Não compartilhar atualizações com outros PCs'
        Resumo    = 'Seu PC para de enviar pedaços de atualizações para outros computadores e não gasta a sua internet.'
        Detalhe   = 'Configura a Otimização de Entrega para baixar só dos servidores da Microsoft, sem troca entre PCs (P2P).'
        Indicado  = 'Internet limitada, 4G/roteador móvel e redes de empresa.'
        Atencao   = $avisoGp
        Risco     = 'seguro'
        Perfis    = @('trabalho', 'gamer', 'leve')
        Registro  = @(
            @{ Chave = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; Nome = 'DODownloadMode'; Valor = 0; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'sistema.storage-sense'
        Categoria = $cat
        Nome      = 'Sensor de Armazenamento (limpeza automática)'
        Resumo    = 'O Windows apaga sozinho temporários e lixo antigo quando o disco começa a encher.'
        Detalhe   = 'Liga o Sensor de Armazenamento com as regras padrão do Windows: limpa arquivos temporários de apps e itens da Lixeira com mais de 30 dias. A pasta Downloads NÃO é mexida por padrão.'
        Indicado  = 'Todo mundo, principalmente SSDs pequenos.'
        Atencao   = 'Para mudar as regras: Configurações > Sistema > Armazenamento > Sensor de Armazenamento.'
        Risco     = 'seguro'
        Perfis    = @('basico', 'trabalho', 'leve')
        Registro  = @(
            @{ Chave = 'HKCU\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'; Nome = '01'; Valor = 1; Tipo = 'DWord' }
        )
    }
    @{
        Id        = 'sistema.hibernacao'
        Categoria = $cat
        Nome      = 'Desligar hibernação e apagar o hiberfil.sys'
        Resumo    = 'Libera vários GB no disco C: (o tamanho aparece ao lado).'
        Detalhe   = 'Executa "powercfg /h off": desliga a hibernação e apaga o arquivo hiberfil.sys, que ocupa uma boa parte do tamanho da sua RAM. A Inicialização rápida também deixa de existir.'
        Indicado  = 'Desktops e PCs com SSD pequeno. Não recomendado em notebooks que você deixa hibernando.'
        Atencao   = 'A opção "Hibernar" some. Em notebook, se a bateria acabar com o PC suspenso, o trabalho não salvo é perdido.'
        Confirmar = 'A hibernação será desligada e o arquivo hiberfil.sys apagado.'
        Risco     = 'moderado'
        Perfis    = @()
        Tecnico   = "powercfg /h off   (desfazer: powercfg /h on)"
        Detectar  = {
            $h = Read-RegValor 'HKLM\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled'
            $arq = Join-Path $env:SystemDrive 'hiberfil.sys'
            $tam = 0
            try { $tam = (Get-Item $arq -Force -ErrorAction Stop).Length } catch { }
            if ($h.Existe -and [int]$h.Valor -eq 0) { return @{ Estado = 'aplicado'; Texto = '' } }
            $txt = if ($tam -gt 0) { "hiberfil.sys ocupa $(Format-Tamanho $tam)" } else { '' }
            return @{ Estado = 'nao'; Texto = $txt }
        }
        Aplicar   = {
            if (-not (Get-Original 'sistema.hibernacao')) { Set-Original 'sistema.hibernacao' @{ Data = (Get-Date).ToString('s'); Hibernacao = $true } }
            $saida = powercfg /h off 2>&1
            if ($LASTEXITCODE -ne 0) { return @{ Status = 'erro'; Mensagem = "powercfg: $($saida -join ' ')" } }
            return @{ Status = 'ok'; Mensagem = 'Hibernação desligada e hiberfil.sys removido.' }
        }
        Desfazer  = {
            param($orig)
            if (-not $orig) { return @{ Status = 'aviso'; Mensagem = 'A hibernação não foi desligada pelo otimizador.' } }
            $saida = powercfg /h on 2>&1
            if ($LASTEXITCODE -ne 0) { return @{ Status = 'erro'; Mensagem = "powercfg: $($saida -join ' ')" } }
            return @{ Status = 'ok'; Mensagem = 'Hibernação religada.' }
        }
    }
)
