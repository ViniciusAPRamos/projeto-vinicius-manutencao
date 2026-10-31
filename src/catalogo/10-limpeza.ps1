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
)
