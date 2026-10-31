# Plano de testes da v2.0 (Windows real, com administrador)

O que já foi testado **sem administrador e sem alterar o sistema**:
- abertura da janela e navegação por todas as telas (dark e light);
- detecção do estado dos 50 ajustes;
- simulação;
- relatório de hardware, conexões de rede e lista de inicialização;
- motor de aplicar e desfazer numa chave de teste isolada (String, DWord, Binary, MultiString, valor padrão, chave criada).

O que **falta** é rodar com administrador e aplicar de verdade. Siga as fases em ordem e anote o que der errado.
O log fica em `Documentos\OtimizadorVinicius\log_<data>.txt` (Histórico > Log de hoje).

## Fase 0: abrir
- [ ] Dois cliques em `src\Executar-Otimizador.bat`, aceitar o UAC, e a janela abre sem console atrás.
- [ ] A barra superior mostra "Administrador".
- [ ] Início: nome do PC, classificação, os chips e o anel aparecem em alguns segundos.

## Fase 1: só leitura (risco zero)
- [ ] Ferramentas > Relatório do PC: gera e abre no navegador.
- [ ] Ferramentas > Drivers e portas COM: lista os chips; com um equipamento conectado, a porta COM aparece.
- [ ] Ferramentas > Rede > Testar velocidade: as barras aparecem uma a uma.
- [ ] Ferramentas > Testar servidor: `google.com` 443 dá verde; `google.com` 81 dá vermelho por tempo esgotado.
- [ ] Otimizar > perfil Trabalho > Simular: a lista mostra `→` e `=` por item, e o Histórico NÃO registra nada.

## Fase 2: poucos ajustes seguros, com desfazer
- [ ] Marcar só "Histórico da área de transferência" e aplicar. Confirmar que o ponto de restauração foi criado (verde) e que Win+V funciona.
- [ ] Abrir `rstrui` e ver o ponto "Otimizador Vinicius".
- [ ] No mesmo item, "Desfazer este ajuste": Win+V volta ao que era antes.
- [ ] Histórico mostra as 2 execuções.

## Fase 3: inicialização e rede
- [ ] Inicialização: desligar um programa sem importância. Conferir no Gerenciador de Tarefas > Aplicativos de inicialização que aparece como Desabilitado. Religar.
- [ ] DNS: escolher Cloudflare, aplicar, conferir em Conexões ativas e depois "Voltar ao DNS original".

## Fase 4: perfil completo
- [ ] Perfil sugerido > Aplicar. Conferir itens verdes e vermelhos (anotar a mensagem dos vermelhos).
- [ ] Usar o botão "Reiniciar agora" do resumo.
- [ ] Depois do reinício: abrir o otimizador e conferir que os itens aparecem como "Aplicado".
- [ ] Num Lock: liga na tela de senha? (ver `revisao-v1.1.md`)

## Fase 5: ferramentas longas
- [ ] Reparar Windows > SFC: a barra avança e o log mostra o texto com acentos certos.
- [ ] Programas: instalar 1 programa pequeno da lista (ex.: 7-Zip).

## Fase 5b: páginas novas
- [ ] Verificar o PC: as 6 etapas giram e ficam verdes; a nota anima; os botões dos itens amarelos/vermelhos levam ao lugar certo.
- [ ] Placa de vídeo: "Abrir painel NVIDIA" abre o Painel de Controle; trocar o modo muda as dicas.
- [ ] Placa de vídeo: aplicar "VRR", conferir em Configurações > Sistema > Tela > Gráficos > "Taxa de atualização variável" e desfazer. (Valida o nome VRROptimizeEnable; fazer o mesmo com HDR automático = AutoHDREnable.)
- [ ] Placa de vídeo por programa: escolher um .exe e conferir em Configurações > Tela > Gráficos; remover.
- [ ] Serviços: aplicar "Rastreamento de atalhos em rede", conferir em services.msc (TrkWks = Manual, parado) e desfazer (volta Automático e rodando).
- [ ] **Num notebook:** página Notebook mostra a saúde da bateria; aplicar os 4 ajustes e conferir no powercfg /q (os GUIDs da tampa e da economia de bateria só existem em notebook).

## Fase 5c: lotes B a E
- [ ] Otimizar > Exportar com 3 itens marcados; Importar o arquivo: os mesmos 3 voltam marcados.
- [ ] `src\Aplicar-Perfil.bat basico` num PC de teste: o console lista [OK]/[ERRO] e o Histórico registra.
- [ ] Modo avançado liga/desliga e é lembrado ao reabrir.
- [ ] Espaço em disco > Limpar o cache dos navegadores (com o navegador fechado) e conferir o tamanho caindo.
- [ ] Manutenção automática > Ligar; conferir em `taskschd.msc` a tarefa "Otimizador Vinicius - Manutencao"; Rodar agora; Desligar remove a tarefa.
- [ ] Monitor de conexão: tirar o cabo/Wi-Fi por 5 s e ver as marcas de "sem resposta" e o diagnóstico mudar.
- [ ] Suporte técnico **num notebook com Wi-Fi**: "Mostrar redes salvas" lista as redes e a senha confere (valida a leitura do `netsh` em português).
- [ ] Assistência Rápida: instalar pelo botão e abrir.
- [ ] Navegadores: aplicar os 4 itens e conferir em `edge://policy` e `chrome://policy` (aparecem como obrigatórios); desfazer e conferir que somem.
- [ ] Temperaturas: rodar um jogo e ver a GPU subir; trocar de aba e confirmar que a leitura para.

## Fase 5d: diagnóstico e ferramentas da 5ª rodada
- [ ] Diagnóstico > Por que está lento?: abrir um jogo ou vídeo pesado e clicar em Analisar; o programa aparece no topo e "Finalizar" pede confirmação.
- [ ] Diagnóstico > Tempo para ligar **com administrador**: Reiniciar o PC (não Desligar) e conferir os segundos e a lista "O que atrasou" (valida os campos BootTime/MainPathBootTime e FriendlyName/DegradationTime do log).
- [ ] Diagnóstico > Travamentos: o número de desligamentos confere com o Visualizador de Eventos (Sistema, Kernel-Power 41).
- [ ] Diagnóstico > BIOS **com administrador**: o TPM aparece como 2.0; comparar o Resizable BAR com o Painel NVIDIA > Informações do sistema.
- [ ] "Reiniciar direto na BIOS" entra na BIOS (shutdown /r /fw).
- [ ] **Num notebook com Wi-Fi:** Diagnóstico > Cabo e Wi-Fi mostra sinal %, faixa (2,4/5 GHz) e taxa (valida o `netsh wlan show interfaces` em português).
- [ ] Ajuste "Arquivo de paginação gerenciado pelo Windows": num PC de teste, fixar a memória virtual em 512 MB à mão, aplicar, reiniciar e conferir; desfazer volta os 512 MB (valida o New-CimInstance Win32_PageFileSetting).
- [ ] Ajuste "TRIM e otimização semanal": desligar com `fsutil behavior set DisableDeleteNotify 1`, aplicar e conferir 0; desfazer volta 1.
- [ ] Limpeza "Versões antigas de componentes (WinSxS)": Simular mostra tamanho e recomendação; aplicar e conferir o espaço liberado.
- [ ] "Otimizar os SSDs agora": aplicar e conferir no Visualizador de Eventos (Aplicativo, Defrag) ou em "Otimizar unidades" a data da última execução.
- [ ] "Apps da Store não rodam em segundo plano": conferir em Configurações que a opção fica bloqueada; desfazer libera.
- [ ] Ferramentas > Apps do Windows: remover um app sem importância (ex.: Dicas) e reinstalar pela Store.
- [ ] Ferramentas > Modo jogo: marcar o navegador, ativar (fecha e troca o plano), Terminei de jogar (volta o plano e reabre).
- [ ] Espaço em disco > Arquivos repetidos: mandar uma cópia para a Lixeira e restaurar pela Lixeira.
- [ ] Espaço em disco > Programas que mais ocupam: "Desinstalar" abre o desinstalador do programa (testar com um MSI e com um .exe).
- [ ] `src\Inventario-PC.bat <pasta>` sem administrador grava o .json; Ferramentas > Vários PCs lê a pasta e exporta a planilha (abre certo no Excel).
- [ ] Histórico > Antes × depois: aplicar algo pela primeira vez grava a referência; depois de reiniciar, o tempo para ligar aparece nas duas colunas.

## Fase 5e: segundo plano e desinstalador
- [ ] **Dell G15:** Serviços > Limpar o segundo plano lista Dell SupportAssist/TechHub/Connected/Update como "Recomendado" e Discord, Steam, EA e AnyDesk como "Depende do uso". Anotar a RAM antes, aplicar, reiniciar e anotar de novo (meta: de ~60% para ~45%).
- [ ] Depois de aplicar: `services.msc` mostra os serviços em Manual; o Gerenciador de Tarefas > Inicializar mostra os itens desativados; a tarefa "Otimizador Vinicius - Manutencao" existe com o Guardião.
- [ ] Desmarcar um item e "Aplicar a escolha": ele volta ao normal. "Desfazer tudo" volta todos (serviços religados).
- [ ] Página Serviços abre no notebook sem travar (o WMI de serviços travava lá).
- [ ] `Aplicar-Perfil.bat gamer`: aplica só os itens "Recomendado".
- [ ] Desinstalar um programa MSI pequeno (ex.: Flameshot) sem janelas; conferir a lista de sobras e apagar; a pasta aparece na Lixeira e o .reg em Backups.
- [ ] Desinstalar um programa NSIS/.exe (abre a janela do desinstalador): o otimizador espera terminar.
- [ ] Remover um app da Store "de todas as contas" e conferir que não aparece em uma conta nova.

## Fase 6: desfazer tudo
- [ ] Histórico > Desfazer todos. Conferir que os itens voltam para "Pendente" (exceto os que já estavam aplicados antes do otimizador).
