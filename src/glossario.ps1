#Requires -Version 5.1
<#
    Glossário do Otimizador Vinicius: palavras técnicas em linguagem simples.
    Cada termo: Termo, Explicacao e Busca (regex que encontra o termo nos textos
    dos ajustes). Usado no painel de detalhes e na página Ajuda.
#>
$Script:Glossario = @(
    @{ Termo = 'HAGS';                  Busca = 'HAGS|Agendamento de GPU';            Explicacao = 'Agendamento de GPU acelerado por hardware: a placa de vídeo organiza a própria fila de trabalho, em vez do Windows.' }
    @{ Termo = 'VRR';                   Busca = 'VRR|taxa de atualização variável';   Explicacao = 'Taxa de atualização variável: o monitor acompanha o FPS do jogo e evita "rasgos" na imagem.' }
    @{ Termo = 'G-Sync / FreeSync';     Busca = 'G-Sync|FreeSync';                    Explicacao = 'Nomes que a NVIDIA e a AMD dão para a taxa de atualização variável (VRR).' }
    @{ Termo = 'Hz';                    Busca = '\bHz\b';                             Explicacao = 'Quantas vezes por segundo o monitor redesenha a imagem. Mais Hz = movimento mais fluido.' }
    @{ Termo = 'FPS';                   Busca = '\bFPS\b';                            Explicacao = 'Quadros por segundo que o jogo consegue gerar.' }
    @{ Termo = 'HDR';                   Busca = '\bHDR\b';                            Explicacao = 'Imagem com mais brilho, contraste e cores. Precisa de monitor compatível.' }
    @{ Termo = 'DLSS / FSR / XeSS';     Busca = 'DLSS|\bFSR\b|XeSS';                  Explicacao = 'O jogo desenha numa resolução menor e a placa reconstrói a imagem: mais FPS com pouca perda visual.' }
    @{ Termo = 'DNS';                   Busca = '\bDNS\b';                            Explicacao = 'Serviço que traduz o nome de um site (google.com) para o endereço numérico (IP).' }
    @{ Termo = 'Cache';                 Busca = '\bcache\b';                          Explicacao = 'Cópia temporária de dados para o próximo acesso ser mais rápido. Pode ser apagada sem perder nada.' }
    @{ Termo = 'Telemetria';            Busca = 'telemetria';                         Explicacao = 'Dados de uso e diagnóstico que o Windows envia para a Microsoft.' }
    @{ Termo = 'Política';              Busca = 'política|gerenciad';                 Explicacao = 'Configuração no formato que as empresas usam. Por isso o Windows mostra "gerenciado pela sua organização".' }
    @{ Termo = 'Ponto de restauração';  Busca = 'ponto de restauração';               Explicacao = '"Foto" das configurações do Windows para voltar atrás se algo der errado. Não apaga seus arquivos.' }
    @{ Termo = 'Logoff';                Busca = 'logoff|sair da conta|sair e entrar'; Explicacao = 'Sair da sua conta sem desligar o PC (Iniciar > seu nome > Sair).' }
    @{ Termo = 'Explorer';              Busca = '\bExplorer\b';                       Explicacao = 'Programa do Windows que desenha a barra de tarefas, o Iniciar e as pastas.' }
    @{ Termo = 'Serviço';               Busca = 'serviço';                            Explicacao = 'Programa do Windows que roda em segundo plano, sem janela.' }
    @{ Termo = 'Plano de energia';      Busca = 'plano de energia|plano ativo';       Explicacao = 'Conjunto de regras do Windows que decide entre economizar energia e entregar desempenho.' }
    @{ Termo = 'PCI Express / ASPM';    Busca = 'PCI Express|PCIe|ASPM';              Explicacao = 'PCI Express é a ligação entre a placa-mãe e as placas de vídeo, rede e SSD. ASPM é a economia de energia dessa ligação.' }
    @{ Termo = 'Turbo';                 Busca = '\bturbo\b|Precision Boost';          Explicacao = 'Aumento automático e temporário do clock do processador quando há trabalho pesado.' }
    @{ Termo = 'MMCSS';                 Busca = 'MMCSS';                              Explicacao = 'Agendador do Windows que dá prioridade a áudio, vídeo e jogos.' }
    @{ Termo = 'SysMain';               Busca = 'SysMain|Superfetch';                 Explicacao = 'Serviço que deixa na memória os programas que você mais usa, para abrirem mais rápido.' }
    @{ Termo = 'Spooler';               Busca = 'Spooler';                            Explicacao = 'Serviço que organiza a fila do que vai para a impressora.' }
    @{ Termo = 'P2P';                   Busca = '\bP2P\b';                            Explicacao = 'Troca direta entre computadores, sem passar por um servidor central.' }
    @{ Termo = 'VBS / HVCI';            Busca = 'VBS|HVCI|Integridade de memória';    Explicacao = 'Proteções do Windows que usam virtualização para impedir que drivers maliciosos rodem.' }
    @{ Termo = 'Game DVR';              Busca = 'Game DVR';                           Explicacao = 'Gravação automática de jogo em segundo plano feita pelo Windows (Xbox Game Bar).' }
    @{ Termo = 'SSD / NVMe';            Busca = '\bSSD\b|NVMe';                       Explicacao = 'Discos sem partes móveis, muito mais rápidos que o HD. O NVMe é o tipo mais rápido.' }
    @{ Termo = 'XMP / EXPO';            Busca = 'XMP|EXPO';                           Explicacao = 'Opção da BIOS que faz a memória RAM rodar na velocidade da caixa. Vem desligada de fábrica.' }
    @{ Termo = 'Dual channel';          Busca = 'dual channel|single channel';        Explicacao = 'Dois pentes de memória trabalhando juntos, o que dobra a velocidade de acesso à RAM.' }
    @{ Termo = 'Winget';                Busca = 'winget';                             Explicacao = 'Instalador oficial de programas do Windows: baixa direto do site do fabricante.' }
    @{ Termo = 'Proteção contra adulteração'; Busca = 'adulteração|Tamper';           Explicacao = 'Trava do Microsoft Defender que impede que programas desliguem a proteção sem você clicar.' }
    @{ Termo = 'Modern Standby';        Busca = 'Modern Standby';                     Explicacao = 'Modo de suspensão de notebooks recentes, que funciona como o de um celular.' }
)

# Monta o texto "Termo: explicação" das palavras que aparecem num texto (até 4)
function Get-GlossarioTexto([string]$Texto) {
    $achados = New-Object System.Collections.Generic.List[string]
    foreach ($g in $Script:Glossario) {
        if ($achados.Count -ge 4) { break }
        if ($Texto -match $g.Busca) { $achados.Add("$($g.Termo): $($g.Explicacao)") }
    }
    return ($achados -join "`n`n")
}
