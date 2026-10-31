# Catálogo: Placa de vídeo
# Perfis gpu-desempenho / gpu-balanceado / gpu-qualidade = modos da página "Placa de vídeo".
# As opções DirectX são as mesmas de Configurações > Sistema > Tela > Gráficos.
$cat = 'Placa de vídeo'

@(
    @{
        Id        = 'gpu.hz-maximo'
        Categoria = $cat
        Nome      = 'Monitor na taxa máxima (Hz)'
        Resumo    = 'Usa todos os quadros por segundo que o monitor aguenta. É comum um monitor de 144 Hz estar rodando a 60.'
        Detalhe   = 'Para cada monitor, procura a maior taxa de atualização disponível na resolução atual e passa a usá-la. Tudo fica mais fluido: mouse, rolagem de páginas e jogos.'
        Indicado  = 'Todo mundo com monitor acima de 60 Hz. Notebooks gamer costumam vir de fábrica em 60 Hz.'
        Atencao   = 'A tela pisca uma vez ao trocar. Se o cabo for antigo (HDMI 1.4), a taxa máxima pode não aparecer.'
        Risco     = 'seguro'
        Perfis    = @('basico', 'trabalho', 'gamer', 'leve', 'gpu-desempenho', 'gpu-balanceado', 'gpu-qualidade')
        Tecnico   = 'ChangeDisplaySettingsEx (user32): mesma resolução, maior dmDisplayFrequency disponível.'
        ComoDesfazer = 'O desfazer volta cada monitor para a taxa que ele tinha antes.'
        Detectar  = {
            $mons = @([Otz.Tela]::Listar())
            if ($mons.Count -eq 0) { return @{ Estado = 'na'; Texto = 'Nenhum monitor encontrado.' } }
            $abaixo = @($mons | Where-Object { $_.Hz -lt $_.HzMaximo })
            $txt = (@($mons) | ForEach-Object { "$($_.Largura)x$($_.Altura) em $($_.Hz) Hz" + $(if ($_.Hz -lt $_.HzMaximo) { " (aceita $($_.HzMaximo) Hz)" } else { '' }) }) -join ' · '
            if ($abaixo.Count -eq 0) { return @{ Estado = 'aplicado'; Texto = $txt } }
            return @{ Estado = 'nao'; Texto = $txt }
        }
        Simular   = {
            foreach ($m in [Otz.Tela]::Listar()) {
                if ($m.Hz -lt $m.HzMaximo) { "→ $($m.Dispositivo): $($m.Hz) Hz  →  $($m.HzMaximo) Hz" } else { "= $($m.Dispositivo) já está em $($m.Hz) Hz (máximo)" }
            }
        }
        Aplicar   = {
            $mons = @([Otz.Tela]::Listar())
            if (-not (Get-Original 'gpu.hz-maximo')) {
                Set-Original 'gpu.hz-maximo' @{ Data = (Get-Date).ToString('s'); Monitores = @($mons | ForEach-Object { @{ Dispositivo = $_.Dispositivo; Hz = $_.Hz } }) }
            }
            $feitos = New-Object System.Collections.Generic.List[string]
            foreach ($m in $mons | Where-Object { $_.Hz -lt $_.HzMaximo }) {
                $r = [Otz.Tela]::DefinirHz($m.Dispositivo, $m.HzMaximo)
                if ($r -eq 0 -or $r -eq 1) { $feitos.Add("$($m.Hz) → $($m.HzMaximo) Hz") }
                else { return @{ Status = 'erro'; Mensagem = "O Windows recusou $($m.HzMaximo) Hz em $($m.Dispositivo) (código $r)." } }
            }
            if ($feitos.Count -eq 0) { return @{ Status = 'ok'; Mensagem = 'Todos os monitores já estavam na taxa máxima.' } }
            return @{ Status = 'ok'; Mensagem = "Monitor(es): $($feitos -join ', ')." }
        }
        Desfazer  = {
            param($orig)
            if (-not $orig) { return @{ Status = 'aviso'; Mensagem = 'Não há taxa anterior guardada.' } }
            foreach ($m in @($orig.Monitores)) { [void][Otz.Tela]::DefinirHz($m.Dispositivo, [int]$m.Hz) }
            return @{ Status = 'ok'; Mensagem = 'Monitores de volta à taxa anterior.' }
        }
    }
    @{
        Id          = 'gpu.janela-otimizada'
        Categoria   = $cat
        Nome        = 'Otimizações para jogos em janela'
        Resumo      = 'Jogos em janela ou "tela cheia sem bordas" ganham a latência de tela cheia.'
        Detalhe     = 'Liga a opção oficial "Otimizações para jogos em janela": jogos antigos (DirectX 10 e 11) em janela passam a usar o modo de apresentação moderno, com menos atraso e suporte a taxa variável.'
        Indicado    = 'Quem joga em janela ou sem bordas para alternar rápido com outros programas.'
        Risco       = 'seguro'
        Windows     = @('11')
        BuildMinima = 22621
        Perfis      = @('gamer', 'gpu-desempenho', 'gpu-balanceado', 'gpu-qualidade')
        DirectX     = @( @{ Chave = 'SwapEffectUpgradeEnable'; Valor = '1' } )
    }
    @{
        Id          = 'gpu.vrr'
        Categoria   = $cat
        Nome        = 'Taxa de atualização variável (VRR)'
        Resumo      = 'Liga o G-Sync/FreeSync também em jogos que não têm suporte próprio. Menos "rasgos" na imagem.'
        Detalhe     = 'Ativa a opção "Taxa de atualização variável" do Windows para jogos DirectX 11 que não suportam VRR sozinhos.'
        Indicado    = 'Monitores com G-Sync, G-Sync Compatible, FreeSync ou HDMI VRR.'
        Atencao     = 'Sem um monitor compatível não faz diferença. O G-Sync/FreeSync também precisa estar ligado no painel da placa e no monitor.'
        Risco       = 'seguro'
        BuildMinima = 19041
        Perfis      = @('gamer', 'gpu-desempenho', 'gpu-balanceado')
        DirectX     = @( @{ Chave = 'VRROptimizeEnable'; Valor = '1' } )
    }
    @{
        Id          = 'gpu.auto-hdr'
        Categoria   = $cat
        Nome        = 'HDR automático'
        Resumo      = 'Jogos antigos ganham cores e brilho de HDR automaticamente.'
        Detalhe     = 'Liga o "HDR automático" do Windows 11: jogos DirectX 11 e 12 feitos sem HDR passam a ser convertidos para HDR.'
        Indicado    = 'Quem tem monitor HDR (HDR400 ou melhor) e prefere visual a FPS.'
        Atencao     = 'Só funciona com monitor HDR e "Usar HDR" ligado nas Configurações de tela. Custa um pouco de desempenho.'
        Risco       = 'seguro'
        Windows     = @('11')
        Perfis      = @('gpu-qualidade')
        DirectX     = @( @{ Chave = 'AutoHDREnable'; Valor = '1' } )
    }
)
