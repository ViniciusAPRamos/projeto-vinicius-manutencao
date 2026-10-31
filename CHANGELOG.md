# Changelog

## [2.1.0] — TechPulse

### Novo
- O app passa a se chamar **TechPulse**, com ícone próprio, `TechPulse.exe` (pede administrador no clique, sem janela de console) e **instalador** (`TechPulse-Setup-x.y.z.exe`, Inno Setup) com atalhos e desinstalação pelo Windows.
- **Atualização automática:** ao abrir, consulta as Releases do GitHub; se houver versão nova, mostra o aviso no Início e atualiza com um clique (fecha, instala em silêncio e reabre). Canal estável ou de teste em Ajuda > Atualizações.
- **Publicação automática** (GitHub Actions): cada push no `main` vira versão de teste; cada tag `v*` vira versão estável.
- Os dados continuam em `Documentos\OtimizadorVinicius` e a tarefa agendada mantém o nome, para não perder nada de quem já usava.

## [2.0] — em teste

### Novo (6ª rodada: segundo plano e desinstalador)
- **Limpar o segundo plano** (página Serviços): programas de terceiros que ligam sozinhos com o Windows (agentes do fabricante, launchers, acesso remoto, atualizadores), com a RAM de cada um e a explicação do que muda. Recomendados vêm marcados; "depende do uso" e não reconhecidos, nunca. Aplica uma vez (serviço → Manual, inicialização desligada), com desfazer e um **Guardião** semanal que desliga de novo o que uma atualização religar. Anti-cheat (Vanguard, EA, BattlEye...), drivers, ventoinhas e Microsoft nunca entram. Também é o ajuste `serv.segundo-plano` (perfis Gamer/PC simples e `Aplicar-Perfil.bat`, só com os recomendados).
- Guia "fechar de verdade" para quem continua rodando na bandeja (Discord, Steam, EA, NVIDIA Overlay, overlay do AWCC).
- **Desinstalar** (Ferramentas): todos os programas e apps da Store, com busca e filtro. Usa o desinstalador oficial (sem janelas quando o programa permite), procura as sobras e mostra para conferir; pastas vão para a Lixeira e o registro ganha backup. Nunca apaga pasta compartilhada com outro programa. Apps da Store saem de todas as contas.
- Correção: serviços lidos sem WMI (`Win32_Service` travava num Dell G15).

### Novo (5ª rodada: diagnóstico e ferramentas)
- **Página Diagnóstico** (só leitura):
  - **Por que está lento?** CPU, RAM e disco em 2 segundos, quem mais usa cada um (com nome amigável e botão Finalizar) e conclusões em linguagem simples (Defender verificando, Windows Update instalando, navegador com muita memória, disco em 100%, GPU quente...).
  - **Tempo para ligar:** segundos até a área de trabalho em cada inicialização e o que atrasou (programas, drivers, serviços), lido do log de desempenho do Windows (precisa de administrador).
  - **Travamentos e desligamentos:** índice de confiabilidade do Windows, desligamentos inesperados (Kernel-Power 41), telas azuis, erros de hardware (WHEA) e programas que fecharam com erro. Também entra na página Verificar.
  - **Cabo e Wi-Fi:** velocidade negociada do cabo (alerta quando uma placa gigabit cai para 100 Mbps), half duplex, sinal/faixa/taxa do Wi-Fi.
  - **BIOS e hardware:** UEFI, Secure Boot, TPM, XMP/EXPO, dual channel, Resizable BAR (NVIDIA RTX 30+), virtualização e idade da BIOS, com onde ligar cada opção. Botão "Reiniciar direto na BIOS".
- **Antes × depois** no Histórico: referência gravada antes da primeira otimização; tempo para ligar comparado desde a primeira aplicação.
- **Ajustes novos:** arquivo de paginação gerenciado pelo Windows, TRIM e otimização semanal do SSD, apps da Store sem segundo plano (moderado), limpeza de componentes do Windows (WinSxS, DISM sem /ResetBase) e otimizar SSDs agora (ReTrim). Total: 78.
- **Ferramentas:** Modo jogo (fecha os programas escolhidos sem forçar, desempenho máximo e volta tudo ao terminar), Apps do Windows (lista curada, remoção um por um, reinstaláveis pela Store), Vários PCs (inventário em pasta compartilhada, tabela do pior para o melhor e planilha CSV) e `Inventario-PC.bat` (sem administrador).
- **Espaço em disco:** arquivos repetidos (mesmo conteúdo, pula arquivos só na nuvem; cópias vão para a Lixeira) e programas que mais ocupam espaço com botão Desinstalar.
- Glossário: TRIM, arquivo de paginação, WinSxS, BIOS/UEFI, Secure Boot, TPM, Resizable BAR.

### Novo (4ª rodada: lotes B a E)
- **Perfis exportáveis e modo silencioso:** Exportar/Importar perfil (.json) em Otimizar; `Aplicar-Perfil.bat <basico|trabalho|gamer|leve|arquivo.json>` aplica sem janela, com resumo no console. Para padronizar vários PCs.
- **Entender o que é feito:** "O que mudou" em linguagem simples depois de aplicar; prévia "agora → depois" de cada ajuste no seu PC; modo **simples/avançado** (o simples esconde detalhes técnicos e ajustes avançados); **glossário** de palavras difíceis no painel de detalhes e na Ajuda.
- **Espaço em disco:** onde está o espaço (Downloads, caches, temporários, atualizações, Windows.old, hibernação), limpar com um clique e maiores arquivos com explicação do que são. Novas limpezas: cache dos navegadores e atualizações do Windows já baixadas.
- **Evolução da nota:** cada verificação vira um ponto num gráfico de linha.
- **Manutenção automática:** tarefa no Agendador do Windows (semanal/diária) que limpa e verifica o PC sem janela; Rodar agora; resultado da última execução.
- **Monitor de conexão:** roteador e internet lado a lado, a cada segundo, com perda, variação, gráfico de 60 s e diagnóstico (Wi-Fi/cabo ou provedor).
- **Suporte técnico:** resumo do PC para chamado (copiar), ID do AnyDesk, senhas de Wi-Fi salvas, Assistência Rápida (abre ou instala) e Área de Trabalho Remota.
- **Navegadores** (catálogo): Edge e Chrome fecham de verdade, Edge sem pré-carregamento e com abas que "dormem".
- **Temperaturas ao vivo:** placa de vídeo NVIDIA (nvidia-smi), discos e sensor da placa-mãe quando existe; sem sensor de CPU, indica o HWMonitor.
- Ferramentas reorganizadas em grupos (Rede, PC, Programas e proteção, Suporte).
- Correção: Enter no teste de servidor quebrava o estado da janela (`$s`/`$S`).

### Novo (3ª rodada)
- **Programas (winget):** lista agrupada por categoria e novos programas (Flameshot, WinRAR, Radmin VPN e a suíte ArtCraft: PdfCraft, VectorCraft, CadCraft, EffectCraft, FilmCraft, GridCraft, SoundCraft). IDs conferidos com `winget search`; RustDesk removido (saiu do winget). A lista pessoal agora aceita `Id;Nome;Grupo`.
- **Desinstalar Office:** detecta Word/Excel/Outlook/Microsoft 365 (Click-to-Run, MSI e Store) e remove tudo usando a string de desinstalação oficial do próprio Office, com log ao vivo. Pede confirmação; não apaga seus arquivos.
- **Proteção (antivírus):** mostra o antivírus ativo e o estado real (tempo real e Proteção contra Adulteração). Pausa a proteção do Defender quando o Windows permite (com reativação automática por tempo e botão "Reativar agora"); quando o Windows bloqueia (Tamper Protection) ou o antivírus é de terceiros, leva à tela certa com o passo a passo. Opção mais segura: liberar só uma pasta (exclusão) em vez de desligar tudo.

### Novo (2ª rodada)
- **Verificar o PC:** varredura em 6 etapas ao vivo, nota de 0 a 100, barras por categoria, "o que falta" para o perfil sugerido e saúde do sistema (antivírus, firewall, atualizações, reinício pendente, discos, RAM/XMP, driver de vídeo, Hz dos monitores, inicialização, temporários), com botão para resolver cada ponto.
- **Placa de vídeo:** nome, VRAM, driver (versão no formato do fabricante) e monitores. Modos Desempenho máximo, Balanceado e Qualidade: marcam os ajustes do Windows e mostram o que conferir no painel NVIDIA/AMD/Intel. Abrir painel, baixar driver e placa por programa.
- **Ajustes de vídeo:** monitor na taxa máxima (Hz), otimizações para jogos em janela, VRR e HDR automático.
- **Notebook:** saúde da bateria, dicas e 4 ajustes de bateria/tampa.
- **Serviços:** memória em uso e 9 serviços desnecessários (lista conservadora) com o consumo real de RAM de cada um.
- Motor: serviços (`sc config` + parar), energia na bateria (`setdcvalueindex`) e opções globais do DirectX, todos com desfazer.

### Novo
- **Interface gráfica (WPF)** com 5 áreas: Início, Otimizar, Ferramentas, Histórico e Ajuda. Tema claro e escuro, animações, notificações e diálogos próprios.
- **Catálogo de ajustes** (`src/catalogo`): cada ajuste tem explicação, indicação, cuidados, risco, tipo de reinício e o que muda no sistema.
- **Detecção** do estado de cada ajuste (Aplicado, Pendente, Parcial) e anel de progresso no Início.
- **Simular:** mostra o valor atual e o novo em cada item, sem alterar nada.
- **Desfazer por item e "Desfazer todos"**, com o valor original exato (inclusive apagar o que não existia).
- **Histórico** de execuções e tela de execução ao vivo, com ícone por item e resumo final (reiniciar ou sair da conta com um clique).
- **Perfis** Básico, Trabalho, Gamer e PC simples, com sugestão automática pelo hardware.
- Seletor de **Windows 10/11**: itens incompatíveis ficam cinza, com o motivo.
- **Ajustes novos:** Finalizar tarefa na barra, histórico da área de transferência, Num Lock ao iniciar, Explorador em "Este Computador", Iniciar à esquerda, Widgets/Notícias, pesquisa como ícone, Visão de Tarefas, modo escuro, efeitos visuais leves, tela de bloqueio sem ofertas, "Vamos terminar de configurar", recomendações do Iniciar, Windows Update sem reinício automático, Otimização de Entrega sem P2P, Sensor de Armazenamento, VBS/HVCI (avançado). Energia dividida em itens independentes.
- **Ferramentas novas:** teste de servidor TCP (com portas comuns e ping), reparo do Windows (DISM/SFC com progresso), reset de rede, teste de DNS com barras, atalhos do Windows e relatório de bateria.
- Suporte a administrador em outra conta: ajustes de usuário vão para a conta logada.
- `tools/verificar.ps1`: garante UTF-8 com BOM e CRLF e confere a sintaxe dos scripts e do XAML.

### Corrigido (v1.1 / modo texto)
- Item fantasma na lista de inicialização quando a chave Run estava vazia.
- Ponto de restauração anunciado como criado quando o Windows recusava; valor de frequência do usuário era apagado.
- Explorer podia não voltar após o reinício.
- Limpeza mostrava MB analisados, não liberados.

## [1.1] — não testada

- Ferramentas: Rede/DNS (**N**), Programas de inicialização (**S**), Drivers USB-serial (**U**), Relatório do PC em HTML com classificação Low/Mid/High-end (**H**) e Winget (**W**).

## [1.0]

- Ajustes de mouse, teclado, energia, modo game, interface, privacidade, limpeza, inicialização rápida e menu clássico do Windows 11.
- Backup `.reg` por chave, ponto de restauração e restauração (**R**).
