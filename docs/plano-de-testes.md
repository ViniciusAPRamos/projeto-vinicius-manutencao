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

## Fase 6: desfazer tudo
- [ ] Histórico > Desfazer todos. Conferir que os itens voltam para "Pendente" (exceto os que já estavam aplicados antes do otimizador).
