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
    @{
        Id        = 'sistema.paginacao'
        Categoria = $cat
        Nome      = 'Arquivo de paginação gerenciado pelo Windows'
        Resumo    = 'Evita travamentos e programas fechando sozinhos quando a memória RAM enche.'
        Detalhe   = 'O arquivo de paginação (pagefile.sys) é a "memória reserva" no disco. Desligar ou fixar um tamanho pequeno é uma dica antiga que causa erros de "memória insuficiente", principalmente com 8 ou 16 GB. Este ajuste devolve o controle ao Windows, que aumenta e diminui o arquivo conforme a necessidade.'
        Indicado  = 'Todo PC em que alguém mexeu na memória virtual, principalmente com 8 ou 16 GB.'
        Risco     = 'seguro'
        Reinicio  = 'reiniciar'
        Perfis    = @('basico', 'trabalho', 'gamer', 'leve')
        Tecnico   = "Win32_ComputerSystem.AutomaticManagedPagefile = True`n(Sistema > Configurações avançadas > Desempenho > Avançado > Memória virtual)"
        Detectar  = {
            $cs = Get-CimInstance Win32_ComputerSystem -Property AutomaticManagedPagefile
            if ($cs.AutomaticManagedPagefile) { return @{ Estado = 'aplicado'; Texto = 'Gerenciado pelo Windows' } }
            $cfg = @(Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue)
            if (-not $cfg.Count) { return @{ Estado = 'nao'; Texto = 'Desligado (sem arquivo de paginação)' } }
            $txt = ($cfg | ForEach-Object { if ($_.MaximumSize) { "$($_.Name): $($_.InitialSize)-$($_.MaximumSize) MB" } else { "$($_.Name): gerenciado pelo sistema" } }) -join '; '
            return @{ Estado = 'nao'; Texto = "Configurado à mão ($txt)" }
        }
        Aplicar   = {
            $cs = Get-CimInstance Win32_ComputerSystem
            if ($cs.AutomaticManagedPagefile) { return @{ Status = 'ok'; Mensagem = 'Já estava gerenciado pelo Windows.' } }
            if (-not (Get-Original 'sistema.paginacao')) {
                $cfg = @(Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue | ForEach-Object { @{ Name = $_.Name; InitialSize = [int]$_.InitialSize; MaximumSize = [int]$_.MaximumSize } })
                Set-Original 'sistema.paginacao' @{ Data = (Get-Date).ToString('s'); Automatico = $false; Arquivos = $cfg }
            }
            Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true } -ErrorAction Stop
            return @{ Status = 'ok'; Mensagem = 'Memória virtual gerenciada pelo Windows. Vale após reiniciar.' }
        }
        Desfazer  = {
            param($orig)
            if (-not $orig) { return @{ Status = 'aviso'; Mensagem = 'A memória virtual não foi alterada pelo otimizador.' } }
            $cs = Get-CimInstance Win32_ComputerSystem
            Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $false } -ErrorAction Stop
            foreach ($a in @($orig.Arquivos)) {
                if (-not $a.Name) { continue }
                $atual = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue | Where-Object Name -eq $a.Name
                if (-not $atual) { $atual = New-CimInstance -ClassName Win32_PageFileSetting -Property @{ Name = $a.Name } -ErrorAction Stop }
                Set-CimInstance -InputObject $atual -Property @{ InitialSize = [uint32]$a.InitialSize; MaximumSize = [uint32]$a.MaximumSize } -ErrorAction Stop
            }
            return @{ Status = 'ok'; Mensagem = 'Configuração anterior da memória virtual restaurada. Vale após reiniciar.' }
        }
    }
    @{
        Id        = 'sistema.trim'
        Categoria = $cat
        Nome      = 'TRIM e otimização semanal do SSD ligados'
        Resumo    = 'Mantém o SSD rápido com o tempo: o Windows avisa o disco sobre o que foi apagado.'
        Detalhe   = 'Garante duas coisas que vêm ligadas de fábrica, mas às vezes são desligadas por programas "otimizadores": o TRIM (o Windows avisa o SSD quais blocos foram apagados) e a tarefa semanal "Otimizar unidades".'
        Indicado  = 'Todo PC com SSD.'
        Risco     = 'seguro'
        Perfis    = @('basico', 'trabalho', 'gamer', 'leve')
        Requisito = { if (-not @(Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { [string]$_.MediaType -eq 'SSD' -or [string]$_.BusType -eq 'NVMe' }).Count) { 'Este PC não tem SSD.' } }
        Tecnico   = "fsutil behavior set DisableDeleteNotify 0`nEnable-ScheduledTask '\Microsoft\Windows\Defrag\ScheduledDefrag'"
        Detectar  = {
            $q = (fsutil behavior query DisableDeleteNotify 2>$null) -join "`n"
            $trim = if ($q -match 'NTFS DisableDeleteNotify\s*=\s*(\d)') { [int]$Matches[1] -eq 0 } else { $null }
            $t = Get-ScheduledTask -TaskPath '\Microsoft\Windows\Defrag\' -TaskName 'ScheduledDefrag' -ErrorAction SilentlyContinue
            $agenda = $t -and [string]$t.State -ne 'Disabled'
            if ($trim -and $agenda) { return @{ Estado = 'aplicado'; Texto = 'TRIM ligado; otimização semanal ativa' } }
            $faltam = @(); if ($trim -eq $false) { $faltam += 'TRIM desligado' }; if (-not $agenda) { $faltam += 'otimização semanal desativada' }
            if ($null -eq $trim -and $agenda) { return @{ Estado = 'na'; Texto = 'Não foi possível ler o TRIM' } }
            return @{ Estado = 'nao'; Texto = ($faltam -join '; ') }
        }
        Aplicar   = {
            $q = (fsutil behavior query DisableDeleteNotify 2>$null) -join "`n"
            $antes = if ($q -match 'NTFS DisableDeleteNotify\s*=\s*(\d)') { [int]$Matches[1] } else { 0 }
            $t = Get-ScheduledTask -TaskPath '\Microsoft\Windows\Defrag\' -TaskName 'ScheduledDefrag' -ErrorAction SilentlyContinue
            $agendaAntes = $t -and [string]$t.State -ne 'Disabled'
            if (-not (Get-Original 'sistema.trim')) { Set-Original 'sistema.trim' @{ Data = (Get-Date).ToString('s'); DisableDeleteNotify = $antes; Agenda = [bool]$agendaAntes } }
            $saida = fsutil behavior set DisableDeleteNotify 0 2>&1
            if ($LASTEXITCODE -ne 0) { return @{ Status = 'erro'; Mensagem = "fsutil: $($saida -join ' ')" } }
            if ($t -and -not $agendaAntes) { Enable-ScheduledTask -InputObject $t -ErrorAction Stop | Out-Null }
            return @{ Status = 'ok'; Mensagem = 'TRIM ligado e otimização semanal ativa.' }
        }
        Desfazer  = {
            param($orig)
            if (-not $orig) { return @{ Status = 'aviso'; Mensagem = 'Nada foi alterado pelo otimizador.' } }
            if ([int]$orig.DisableDeleteNotify -ne 0) { fsutil behavior set DisableDeleteNotify $([int]$orig.DisableDeleteNotify) 2>&1 | Out-Null }
            if (-not $orig.Agenda) { Get-ScheduledTask -TaskPath '\Microsoft\Windows\Defrag\' -TaskName 'ScheduledDefrag' -ErrorAction SilentlyContinue | Disable-ScheduledTask | Out-Null }
            return @{ Status = 'ok'; Mensagem = 'Configuração anterior restaurada.' }
        }
    }
    @{
        Id        = 'sistema.apps-segundo-plano'
        Categoria = $cat
        Nome      = 'Apps da Microsoft Store não rodam em segundo plano'
        Resumo    = 'Apps da Store (Clima, Notícias, Fotos, Xbox...) param de rodar escondidos depois de fechados.'
        Detalhe   = 'Aplica a política oficial "Permitir que aplicativos do Windows sejam executados em segundo plano" como "Forçar Negação". Economiza memória e bateria. Programas tradicionais (Chrome, Discord, Steam) não são afetados.'
        Indicado  = 'PCs com 8 GB e notebooks em que a bateria dura pouco.'
        Atencao   = 'Apps da Store fechados deixam de receber notificações e de sincronizar (ex.: WhatsApp e Teams versão Store, Email, Vincular ao Celular). Abertos, funcionam normalmente.'
        Risco     = 'moderado'
        Perfis    = @()
        Registro  = @(
            @{ Chave = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'; Nome = 'LetAppsRunInBackground'; Valor = 2; Tipo = 'DWord' }
        )
    }
)
