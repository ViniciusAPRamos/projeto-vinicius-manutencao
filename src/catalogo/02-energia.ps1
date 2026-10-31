# Catálogo: Energia
# Os ajustes finos usam "setacvalueindex": valem só NA TOMADA. Bateria não é afetada.
$cat = 'Energia'

@(
    @{
        Id        = 'energia.plano'
        Categoria = $cat
        Nome      = 'Plano de energia Desempenho Máximo'
        Resumo    = 'O processador para de economizar justo na hora em que você precisa dele.'
        Detalhe   = 'Cria (ou reaproveita) o plano "Vinicius - Desempenho Maximo", baseado no Desempenho Máximo do Windows (ou no Alto desempenho, se o PC não aceitar o primeiro), e deixa esse plano ativo.'
        Indicado  = 'Desktops, e notebooks que ficam a maior parte do tempo na tomada.'
        Atencao   = 'Gasta um pouco mais de energia. Em notebook usado na bateria, a autonomia diminui.'
        Risco     = 'seguro'
        Perfis    = @('trabalho', 'gamer', 'gpu-desempenho', 'gpu-balanceado')
        Tecnico   = "powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61  (Desempenho Máximo)`nse falhar: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (Alto desempenho)`npowercfg /setactive <novo plano>"
        ComoDesfazer = 'O desfazer reativa o plano que estava em uso antes (ex.: Equilibrado). O plano criado continua na lista, caso você queira usar de novo.'
        Detectar  = {
            $p = Get-PlanoAtivo
            if (-not $p) { return @{ Estado = 'erro'; Texto = 'Não foi possível ler o plano ativo.' } }
            if ($p.Nome -eq $Script:Otz.NomePlano) { return @{ Estado = 'aplicado'; Texto = '' } }
            return @{ Estado = 'nao'; Texto = "Plano atual: $($p.Nome)" }
        }
        Simular   = {
            $p = Get-PlanoAtivo
            if ($p.Nome -eq $Script:Otz.NomePlano) { "= Plano ativo já é '$($p.Nome)'" }
            else { "→ Plano ativo: '$($p.Nome)'  →  '$($Script:Otz.NomePlano)'" }
        }
        Aplicar   = {
            $atual = Get-PlanoAtivo
            if (-not (Get-Original 'energia.plano')) {
                Set-Original 'energia.plano' @{ Data = (Get-Date).ToString('s'); Plano = $atual.Guid; NomePlano = $atual.Nome }
            }
            $guid = $null
            foreach ($l in (powercfg /list)) {
                if ($l -like "*$($Script:Otz.NomePlano)*" -and $l -match "($Script:RegexGuid)") { $guid = $Matches[1] }
            }
            $msg = 'Plano já existia e foi reativado.'
            if (-not $guid) {
                $bases = [ordered]@{ 'e9a42b02-d5df-448d-aa00-03f14749eb61' = 'Desempenho Máximo'; '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' = 'Alto desempenho' }
                foreach ($b in $bases.Keys) {
                    $o = (powercfg -duplicatescheme $b 2>&1) -join ' '
                    if ($LASTEXITCODE -eq 0 -and $o -match "($Script:RegexGuid)") {
                        $guid = $Matches[1]
                        powercfg -changename $guid $Script:Otz.NomePlano 'Plano criado pelo Otimizador Vinicius' | Out-Null
                        $msg = "Plano criado a partir de '$($bases[$b])'."
                        break
                    }
                }
            }
            if (-not $guid) {
                return @{ Status = 'erro'; Mensagem = 'Este PC só aceita o plano Equilibrado (comum em notebooks com Modern Standby). Os outros ajustes de energia continuam funcionando.' }
            }
            $saida = powercfg /setactive $guid 2>&1
            if ($LASTEXITCODE -ne 0) { return @{ Status = 'erro'; Mensagem = "powercfg: $($saida -join ' ')" } }
            return @{ Status = 'ok'; Mensagem = $msg }
        }
        Desfazer  = {
            param($orig)
            if (-not $orig -or -not $orig.Plano) { return @{ Status = 'aviso'; Mensagem = 'Não há plano anterior guardado.' } }
            $saida = powercfg /setactive $orig.Plano 2>&1
            if ($LASTEXITCODE -ne 0) { return @{ Status = 'erro'; Mensagem = "powercfg: $($saida -join ' ')" } }
            return @{ Status = 'ok'; Mensagem = "Voltou para o plano '$($orig.NomePlano)'." }
        }
    }
    @{
        Id        = 'energia.usb-seletivo'
        Categoria = $cat
        Nome      = 'USB sem economia de energia (na tomada)'
        Resumo    = 'Evita que leitores, adaptadores USB-serial e periféricos "desconectem" sozinhos.'
        Detalhe   = 'Desliga a "Suspensão seletiva de USB" no plano ativo. Com ela, o Windows corta a energia de portas USB paradas, e alguns equipamentos não voltam direito.'
        Indicado  = 'Quem configura equipamentos por USB/serial, usa leitores, balanças, impressoras térmicas ou dongles.'
        Risco     = 'seguro'
        Perfis    = @('trabalho', 'gamer')
        Energia   = @(
            @{ Sub = '2a737441-1930-4402-8d77-b2bebba308a3'; Config = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'; Valor = 0 }
        )
    }
    @{
        Id        = 'energia.suspensao'
        Categoria = $cat
        Nome      = 'Não suspender nem desligar o disco (na tomada)'
        Resumo    = 'O PC não "dorme" no meio de downloads, atualizações ou acesso remoto.'
        Detalhe   = 'Define "Suspender" e "Desligar disco rígido" como Nunca no plano ativo, só na tomada. A tela continua apagando normalmente.'
        Indicado  = 'PCs acessados remotamente (AnyDesk, RustDesk), servidores de teste e downloads longos.'
        Atencao   = 'O PC fica ligado até você desligar.'
        Risco     = 'seguro'
        Perfis    = @('trabalho', 'gamer')
        Energia   = @(
            @{ Sub = 'SUB_SLEEP'; Config = 'STANDBYIDLE'; Valor = 0 }
            @{ Sub = 'SUB_DISK';  Config = 'DISKIDLE';    Valor = 0 }
        )
    }
    @{
        Id        = 'energia.pcie-aspm'
        Categoria = $cat
        Nome      = 'PCI Express sem economia de energia (na tomada)'
        Resumo    = 'Reduz pequenos atrasos da placa de vídeo, da rede e do SSD NVMe ao "acordar".'
        Detalhe   = 'Desliga o "Gerenciamento de energia do estado de link" (ASPM) do PCI Express no plano ativo.'
        Indicado  = 'Jogos e uso pesado em desktop.'
        Risco     = 'seguro'
        Perfis    = @('gamer', 'gpu-desempenho')
        Energia   = @(
            @{ Sub = '501a4d13-42af-4429-9fd1-a8218c268e20'; Config = 'ee12f906-d277-404b-b6da-e5fa1a576df5'; Valor = 0 }
        )
    }
    @{
        Id        = 'energia.cpu-minimo'
        Categoria = $cat
        Nome      = 'Processador sempre no máximo (na tomada)'
        Resumo    = 'O processador não reduz o clock, nem parado.'
        Detalhe   = 'Define o "Estado mínimo do processador" como 100% no plano ativo. Tira o pequeno atraso para o processador acelerar.'
        Indicado  = 'Jogos competitivos e desktops com boa refrigeração.'
        Atencao   = 'Aumenta temperatura e consumo mesmo com o PC parado. Em notebooks finos, a ventoinha trabalha mais.'
        Risco     = 'moderado'
        Perfis    = @('gamer')
        Energia   = @(
            @{ Sub = 'SUB_PROCESSOR'; Config = 'PROCTHROTTLEMIN'; Valor = 100 }
        )
    }
)
