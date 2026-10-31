# Changelog

## [2.0] — em teste

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
