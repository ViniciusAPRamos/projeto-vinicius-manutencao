# Catálogo: Limpeza (ações únicas: não têm "desfazer")
$cat = 'Limpeza'
$semDesfazer = 'Ação única, não tem desfazer. São arquivos que os programas recriam quando precisam.'

@(
    @{
        Id           = 'limpeza.temp'
        Categoria    = $cat
        Tipo         = 'acao'
        Nome         = 'Apagar arquivos temporários'
        Resumo       = 'Remove sobras de instalações e programas nas pastas Temp.'
        Detalhe      = 'Apaga o conteúdo da sua pasta Temp e de C:\Windows\Temp. Arquivos em uso por programas abertos são pulados automaticamente, sem risco.'
        Indicado     = 'Todo mundo, de vez em quando.'
        Risco        = 'seguro'
        Perfis       = @('basico', 'trabalho', 'gamer', 'leve')
        ComoDesfazer = $semDesfazer
        Tecnico      = "Remove-Item `"$env:TEMP\*`" -Recurse -Force`nRemove-Item `"$env:SystemRoot\Temp\*`" -Recurse -Force"
        Detectar     = {
            $t = Get-TamanhoPastas @($env:TEMP, "$env:SystemRoot\Temp")
            return @{ Estado = 'acao'; Texto = "cerca de $(Format-Tamanho $t) para liberar" }
        }
        Simular      = {
            $t = Get-TamanhoPastas @($env:TEMP, "$env:SystemRoot\Temp")
            "→ Apagaria até $(Format-Tamanho $t) em $env:TEMP e $env:SystemRoot\Temp"
        }
        Aplicar      = {
            $pastas = @($env:TEMP, "$env:SystemRoot\Temp")
            $antes = Get-TamanhoPastas $pastas
            foreach ($p in $pastas) {
                if (Test-Path $p) {
                    Get-ChildItem $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            $depois = Get-TamanhoPastas $pastas
            return @{ Status = 'ok'; Mensagem = "Liberados $(Format-Tamanho ([math]::Max(0, $antes - $depois))). Arquivos em uso foram mantidos." }
        }
    }
    @{
        Id           = 'limpeza.dns'
        Categoria    = $cat
        Tipo         = 'acao'
        Nome         = 'Limpar cache de DNS'
        Resumo       = 'Resolve sites que "não abrem" depois de mudanças de servidor ou de rede.'
        Detalhe      = 'Esvazia a memória de endereços de sites que o Windows guarda. Na próxima visita, o endereço é consultado de novo.'
        Indicado     = 'Quando um site ou servidor mudou de IP e o PC insiste no antigo.'
        Risco        = 'seguro'
        Perfis       = @('basico', 'trabalho', 'gamer', 'leve')
        ComoDesfazer = 'Ação única. O cache se reconstrói sozinho enquanto você navega.'
        Tecnico      = 'Clear-DnsClientCache  (igual a ipconfig /flushdns)'
        Aplicar      = {
            Clear-DnsClientCache -ErrorAction Stop
            return @{ Status = 'ok'; Mensagem = 'Cache de DNS limpo.' }
        }
    }
    @{
        Id           = 'limpeza.lixeira'
        Categoria    = $cat
        Tipo         = 'acao'
        Nome         = 'Esvaziar a Lixeira'
        Resumo       = 'Apaga para sempre o que está na Lixeira de todos os discos.'
        Detalhe      = 'Esvazia a Lixeira. Depois disso, os arquivos só voltam com programas de recuperação, e nem sempre.'
        Indicado     = 'Quando você já conferiu que não precisa de nada que está lá.'
        Confirmar    = 'Tudo o que está na Lixeira será apagado para sempre.'
        Risco        = 'moderado'
        Perfis       = @()
        ComoDesfazer = 'Não tem como desfazer. Confira a Lixeira antes.'
        Tecnico      = 'Clear-RecycleBin -Force'
        Detectar     = {
            $t = Get-TamanhoLixeira
            if ($null -eq $t) { return @{ Estado = 'acao'; Texto = '' } }
            if ($t -eq 0) { return @{ Estado = 'acao'; Texto = 'Lixeira já está vazia' } }
            return @{ Estado = 'acao'; Texto = "$(Format-Tamanho $t) na Lixeira" }
        }
        Aplicar      = {
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            return @{ Status = 'ok'; Mensagem = 'Lixeira esvaziada.' }
        }
    }
    @{
        Id           = 'limpeza.navegadores'
        Categoria    = $cat
        Tipo         = 'acao'
        Nome         = 'Limpar cache dos navegadores'
        Resumo       = 'Apaga os arquivos temporários de sites do Chrome, Edge e Firefox. Senhas, favoritos e histórico ficam.'
        Detalhe      = 'Remove só as pastas de cache (cópias de imagens e scripts de sites já visitados). Não mexe em senhas, favoritos, histórico, extensões nem em contas logadas.'
        Indicado     = 'Quando o disco está cheio ou um site insiste em mostrar uma versão antiga.'
        Atencao      = 'Feche os navegadores antes: com eles abertos, parte do cache fica em uso e é pulada. Na primeira visita, os sites podem abrir um pouco mais devagar.'
        Risco        = 'seguro'
        Perfis       = @()
        ComoDesfazer = 'Ação única. O navegador recria o cache sozinho enquanto você navega.'
        Tecnico      = "Apaga o conteúdo de:`n%LOCALAPPDATA%\Google\Chrome\User Data\*\Cache e Code Cache`n%LOCALAPPDATA%\Microsoft\Edge\User Data\*\Cache e Code Cache`n%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*\cache2"
        Detectar     = {
            $t = Get-TamanhoPastas (Get-PastasCacheNavegador)
            return @{ Estado = 'acao'; Texto = "cerca de $(Format-Tamanho $t) em cache" }
        }
        Simular      = {
            $abertos = Get-NavegadoresAbertos
            "→ Apagaria até $(Format-Tamanho (Get-TamanhoPastas (Get-PastasCacheNavegador))) de cache"
            if ($abertos) { "⚠ Abertos agora: $($abertos -join ', '). Feche antes para limpar tudo." }
        }
        Aplicar      = { return (Clear-CacheNavegadores) }
    }
    @{
        Id           = 'limpeza.windows-update'
        Categoria    = $cat
        Tipo         = 'acao'
        Nome         = 'Apagar atualizações do Windows já baixadas'
        Resumo       = 'Remove os instaladores de atualizações que o Windows já baixou. Costuma liberar alguns GB.'
        Detalhe      = 'Para o Windows Update por alguns segundos, apaga o conteúdo de C:\Windows\SoftwareDistribution\Download e liga o serviço de novo. Se ainda faltar alguma atualização, o Windows baixa de novo.'
        Indicado     = 'Disco cheio, ou atualização que fica "presa" baixando.'
        Atencao      = 'Não use enquanto uma atualização estiver instalando (tela "Trabalhando nas atualizações" ou reinício pendente).'
        Risco        = 'seguro'
        Perfis       = @()
        ComoDesfazer = 'Ação única. O Windows baixa de novo o que precisar.'
        Tecnico      = "Stop-Service wuauserv, bits`nRemove-Item C:\Windows\SoftwareDistribution\Download\*`nStart-Service wuauserv, bits"
        Detectar     = {
            $t = Get-TamanhoPastas @("$env:SystemRoot\SoftwareDistribution\Download")
            return @{ Estado = 'acao'; Texto = "cerca de $(Format-Tamanho $t) baixados" }
        }
        Aplicar      = { return (Clear-CacheWindowsUpdate) }
    }
)
