# Otimizador Vinicius — Contexto do projeto

> Documento de continuidade. Resume tudo o que foi feito na conversa original (claude.ai) e o que precisa ser feito a partir daqui.
> Leia por completo antes de propor ou alterar código.

---

## 1. Sobre o projeto

**Otimizador Vinicius** é um otimizador de Windows de **desenvolvimento próprio** do Vinícius (analista de sistemas na área de IoT, telemetria e rastreamento de frotas).

- **Hoje:** v2.0, interface gráfica WPF + catálogo de ajustes (**em teste**: falta validar a aplicação com administrador, ver `docs/plano-de-testes.md`). A v1.1 (menu de texto) continua como alternativa.
- **Futuro:** aplicativo C# com `.exe`, instalador e atualização (v3.0).

### Arquivos atuais (v2.0)

| Arquivo | Função |
|---|---|
| `src/Executar-Otimizador.bat` | Abre a interface (`-STA -WindowStyle Hidden`). O `.ps1` se autoeleva. `.bat` = ASCII sem BOM + CRLF. |
| `src/Otimizador-Vinicius-GUI.ps1` | Janela: navegação, eventos, tarefas em segundo plano. Parâmetros de desenvolvimento: `-SemElevar` e `-Captura <pasta>` (salva PNG de cada tela e fecha). |
| `src/nucleo.ps1` | Motor: registro via .NET (HKCU/HKLM/HKU, valor padrão, tipos exatos), powercfg, originais, catálogo, `Invoke-Plano`, ponto de restauração, histórico, log. |
| `src/diagnostico.ps1` | Placa de vídeo (`Get-InfoGpu`, dicas do painel por fabricante/modo, placa por programa), bateria, memória e as checagens da página Verificar (`Get-Saude*`, evento `checagem`). |
| `src/manutencao.ps1` | Manutenção automática: tarefa no Agendador (`Register-/Unregister-Manutencao`) e o que ela roda (`Invoke-ManutencaoAgendada`, modo `-Manutencao`). |
| `src/glossario.ps1` | Termos técnicos em linguagem simples + `Get-GlossarioTexto` (painel de detalhes e Ajuda). |
| `src/Aplicar-Perfil.bat` | Modo silencioso: `Aplicar-Perfil.bat <basico\|trabalho\|gamer\|leve\|arquivo.json>` (sem janela, resumo no console). |
| `src/seguranca.ps1` | Office (detectar + desinstalar pela string oficial) e Proteção/antivírus (estado real do Defender, pausar/reativar quando o Tamper Protection permite, exclusão de pasta, atalhos para a Segurança do Windows). |
| `src/analise.ps1` | Página Diagnóstico (só leitura): `Get-DiagnosticoLentidao` (contadores brutos Win32_PerfRawData, 2 leituras), `Get-HistoricoBoot` (log Diagnostics-Performance, eventos 100/101-109, exige admin), `Get-Estabilidade` (Kernel-Power 41, BugCheck 1001, WHEA, Application 1000/1002, índice de confiabilidade), `Get-QualidadeConexao`, `Get-ChecklistBios`, e o antes × depois (`Save-/Get-MedicaoReferencia`, `Get-Comparacao`). |
| `src/programas.ps1` | Apps que vieram com o Windows (`$Script:AppsConhecidos`, remoção um por um), programas por tamanho (EstimatedSize) e Modo jogo (`Start-/Stop-ModoJogo`, estado em `modo-jogo.json`). |
| `src/inventario.ps1` + `src/Inventario-PC.bat` | Inventário de vários PCs: `<PC>.json` numa pasta (sem admin), tabela em Ferramentas > Vários PCs e CSV para o Excel. Parâmetro `-Inventario <pasta>`. |
| `src/ui/Tela.cs` | Win32 `EnumDisplaySettings`/`ChangeDisplaySettingsEx`: Hz atual e máximo de cada monitor. |
| `src/ferramentas.ps1` | `Get-InfoPC`, relatório HTML, inicialização, drivers serial, DNS, teste TCP, `Invoke-ProcessoAoVivo` (SFC/DISM/winget), lista winget. |
| `src/catalogo/NN-*.ps1` | Um arquivo por categoria; cada item é um hashtable (ver `docs/catalogo.md`). 78 itens em 14 categorias. Tipos de mudança suportados pelo motor: `Registro`, `Energia` (com `Corrente = 'dc'` para bateria), `Servicos` (sc config), `DirectX` (string global de jogos) ou código próprio. |
| `src/ui/Janela.xaml` | Layout, estilos e paleta (escuro; o tema claro troca os pincéis em `Set-Tema`). |
| `src/ui/Modelos.cs` | View models com `INotifyPropertyChanged` (`Otz.Ajuste`, `Otz.ItemInicio`, `Otz.Linha`), compilados com `Add-Type` (C# 5). |
| `src/Otimizador-Vinicius.ps1` + `Executar-Modo-Texto.bat` | v1.1 (menu de texto), com as correções da revisão. |
| `tools/verificar.ps1` | Normaliza BOM/CRLF, faz o parse de todos os `.ps1` e carrega os `.xaml`. **Rodar antes de cada commit.** |
| `docs/` | `revisao-v1.1.md`, `catalogo.md`, `plano-de-testes.md`, `telas/`. |
| `config/winget-lista-exemplo.txt` | Modelo de lista de programas. Copiado para `src/winget-lista.txt`, substitui a lista padrão. |

### Como a v2.0 funciona (resumo)

- **Tarefas em segundo plano:** `Start-Tarefa` cria um runspace (STA) que carrega `nucleo.ps1` + `ferramentas.ps1` e roda um script em texto. Eventos (`Send-Evento`) vão para uma `ConcurrentQueue`, que um `DispatcherTimer` (90 ms) lê na interface. Nunca passar scriptblocks entre runspaces.
- **Desfazer:** na primeira aplicação, `originais.json` guarda, por item, o valor original exato (`Existia`, `Tipo`, `Valor`, `ChaveCriada`). O desfazer restaura ou apaga e remove as chaves vazias até a que foi criada. Itens com código próprio guardam o próprio estado com `Set-Original`.
- **Dados:** `Documentos\OtimizadorVinicius\` → `originais.json`, `historico.jsonl`, `log_<data>.txt`, `preferencias.json` (tema), relatórios.
- **Perfis** só marcam itens do perfil que estão **pendentes**; itens `avancado` nunca entram. Clicar numa caixa muda para "Personalizado".

---

## 2. Como trabalhar comigo (preferências do Vinícius)

- Respostas **claras, práticas e objetivas**, em **português**.
- Explicar o raciocínio quando o assunto for novo ou complexo.
- **Nunca inventar comandos, chaves de registro, parâmetros ou funcionalidades.** Se não tiver certeza, dizer o que precisa ser confirmado (documentação, teste em VM, evidência).
- Quando houver várias demandas, separar o que é urgente, importante e o que pode esperar.
- Pensar sempre no **UI/UX do usuário final**.
- Ir **sugerindo melhorias** proativamente.

---

## 3. Histórico do que foi feito

1. **Pergunta inicial:** como remover o seletor de idioma do teclado → explicado (remover layouts extras ou ocultar o indicador).
2. **Comando para desativar Alt+Shift** → chaves em `HKCU\Keyboard Layout\Toggle` (`Hotkey`, `Language Hotkey`, `Layout Hotkey` = `3`).
3. **v1.0 do script:** mouse, teclado, energia, modo game, interface, privacidade, limpeza, inicialização rápida, menu clássico do Win11, backup e restauração.
4. **v1.1:** adicionadas 5 ferramentas — Rede/DNS, Programas de inicialização, Drivers USB-serial, Relatório do PC em HTML (com classificação Low/Mid/High-end) e Winget.
5. **Sugestões de desempenho por tipo de PC** (Low/Mid/High-end) — ver seção 7.
6. **Decisão de UX:** o menu de texto não mostra o que está acontecendo nem se deu certo. O projeto deve evoluir para interface gráfica (seção 8).

---

## 4. Estado atual — v1.1 (o que o script faz)

### 4.1 Infraestrutura

- **Autoelevação:** se não for admin, reabre com `Start-Process -Verb RunAs`.
- **Pasta de dados:** `Documentos\OtimizadorVinicius` (via `[Environment]::GetFolderPath('MyDocuments')`, compatível com OneDrive).
  - `Backups\<data_hora>\*.reg` — export de cada chave antes de alterar (uma vez por sessão por chave).
  - `Backups\<data_hora>\dns.json` — DNS anterior por adaptador (estático ou automático).
  - `log_<data>.txt` — `Start-Transcript`.
  - `Relatorio_PC_<data>.html`, `winget-programas.json`.
- **Ponto de restauração:** criado antes da primeira alteração. Libera temporariamente a limitação de 24 h (`SystemRestorePointCreationFrequency = 0`) e remove depois.
- **`Set-Reg`:** função central — faz backup da chave, cria se não existir e grava com `New-ItemProperty -Force`. Tipos: DWord, String, QWord, Binary.
- **Detecção de versão:** `CurrentBuildNumber` do registro; Windows 11 = build ≥ 22000.

### 4.2 Otimizações (menu 1–9)

| # | Módulo | O que altera |
|---|---|---|
| 1 | **Mouse** | `HKCU\Control Panel\Mouse`: `MouseSpeed`, `MouseThreshold1`, `MouseThreshold2` = `0`; `MouseSensitivity` = `10`. Aplica na hora via `SystemParametersInfo` (SPI_SETMOUSE `0x0004`, SPI_SETMOUSESPEED `0x0071`). |
| 2 | **Teclado** | `HKCU\Control Panel\Accessibility`: `StickyKeys\Flags=506`, `ToggleKeys\Flags=58`, `Keyboard Response\Flags=122`. `HKCU\Keyboard Layout\Toggle` (3 valores) = `3`. Requer logoff. |
| 3 | **Energia** | Duplica o plano Ultimate (`e9a42b02-d5df-448d-aa00-03f14749eb61`); se falhar, usa Alto desempenho (`8c5e7fda-...`). Reutiliza se já existir (nome "Vinicius - Desempenho Maximo"). Somente AC: CPU mínima 100%, USB seletivo OFF, PCIe ASPM OFF, disco e suspensão nunca. Avisa se for notebook. |
| 4 | **Modo Game** | `GameBar`: `AutoGameModeEnabled`/`AllowAutoGameMode` = 1. Game DVR OFF (`GameConfigStore\GameDVR_Enabled`, `GameDVR\AppCaptureEnabled`). HAGS: `GraphicsDrivers\HwSchMode=2` (build ≥ 19041, reinício). MMCSS: `SystemResponsiveness=10`, `Tasks\Games` (GPU Priority 8, Priority 6, Scheduling/SFIO "High"). |
| 5 | **Interface** | `MenuShowDelay=50`, `MinAnimate=0`, `EnableTransparency=0`, `TaskbarAnimations=0`, `HideFileExt=0`, `Serialize\StartupDelayInMSec=0`. Reinicia o Explorer. |
| 6 | **Privacidade** | `AdvertisingInfo\Enabled=0`; `ContentDeliveryManager` (SilentInstalledApps, SystemPaneSuggestions, SoftLanding, SubscribedContent-338388/338389/353694/353696) = 0; `DisableSearchBoxSuggestions=1` (Bing no Iniciar); `AllowTelemetry=0` (vira mínimo da edição); `PublishUserActivities=0`. |
| 7 | **Limpeza** | `%TEMP%` e `C:\Windows\Temp`, `ipconfig /flushdns`, Lixeira **só com confirmação**. |
| 8 | **Inicialização rápida** | `Session Manager\Power\HiberbootEnabled=0`. Hibernação (`powercfg -h off`) só com confirmação. Ajuda com drivers USB/serial. |
| 9 | **Menu clássico (Win11)** | `HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32` com valor padrão vazio. Desfazer pela opção **D**. |
| A | **Aplicar recomendados** | Executa 1 a 7 após confirmação. |

### 4.3 Ferramentas (v1.1)

| Tecla | Ferramenta | Detalhes |
|---|---|---|
| **N** | **Rede** | DNS Cloudflare/Google/Quad9/automático por adaptador físico ativo (`Set-DnsClientServerAddress`). Salva o DNS anterior lendo `Tcpip\Parameters\Interfaces\{GUID}\NameServer` (vazio = automático). Teste de latência com `Resolve-DnsName -Server -DnsOnly -NoHostsFile -QuickTimeout`. Energia da placa: `Set-NetAdapterPowerManagement -AllowComputerToTurnOffDevice/-SelectiveSuspend` e `*EEE` via `Set-NetAdapterAdvancedProperty`. |
| **S** | **Inicialização** | Lê `Run` (HKCU, HKLM, WOW6432Node) e pastas Startup (usuário e comum). Liga/desliga via `Explorer\StartupApproved` (`Run`, `Run32`, `StartupFolder`) com valor binário de 12 bytes: primeiro byte `02` = ativo, `03` = desativado. Mesmo mecanismo do Gerenciador de Tarefas. |
| **U** | **Drivers USB-serial** | Verifica no `pnputil /enum-drivers`: `silabser.inf` (CP210x), `ch341ser.inf` (CH340), `ftdiport.inf/ftdibus.inf` (FTDI), `ser2pl.inf` (PL2303). Lista portas COM (`Win32_PnPEntity`) e dispositivos USB com erro (`Get-PnpDevice -Status ERROR,UNKNOWN`), sugerindo o chip pelo VID (10C4, 1A86, 0403, 067B). Abre site oficial ou instala de pasta com `pnputil /add-driver *.inf /subdirs /install`. |
| **H** | **Relatório do PC** | HTML (claro/escuro) com sistema, CPU, pentes de RAM, GPU, discos físicos (saúde, temperatura, desgaste, horas via `Get-StorageReliabilityCounter`) e partições. **Classificação:** Low (≤ 8 GB, HDD ou ≤ 4 threads), High (≥ 32 GB, ≥ 12 threads e NVMe), Mid (resto). Alertas: HDD no sistema, RAM < 16 GB, single channel, RAM abaixo da velocidade nominal (XMP), disco < 15% livre, > 10 itens na inicialização, uptime > 7 dias, plano não-desempenho, monitor abaixo do Hz máximo, disco com saúde ruim, SSD ≥ 80% de desgaste. |
| **W** | **Winget** | Instala da lista (padrão no script ou `winget-lista.txt` no formato `Id;Nome`), `upgrade --all`, `export` e `import --ignore-unavailable`. |
| **R** | **Restaurar** | Importa os `.reg` de um backup escolhido, restaura DNS e opcionalmente volta ao plano Equilibrado. `.reg` não apaga valores que não existiam antes → para reverter 100%, usar o ponto de restauração. |

### 4.4 Convenções técnicas obrigatórias

- **Compatível com Windows PowerShell 5.1** (padrão do Windows). Não usar recursos exclusivos do PowerShell 7 (`??`, `?:`, `ForEach-Object -Parallel` etc.).
- **Codificação:** `.ps1` em **UTF-8 com BOM** e **CRLF**. Sem BOM, o PowerShell 5.1 lê como ANSI e quebra os acentos.
- Antes de qualquer alteração: **ponto de restauração + backup**.
- Ações destrutivas (lixeira, hibernação) **sempre pedem confirmação**.
- Funções com verbos aprovados do PowerShell quando possível (`Set-`, `Get-`, `Show-`...).

### 4.5 Limitações conhecidas

- ⚠️ **v2.0: a aplicação real com administrador ainda não foi testada.** Testado sem admin no PC do Vinícius (Win11 25H2, build 26200, Ryzen 7 5700, 32 GB, RTX 5070): abertura, todas as telas, detecção, simulação, hardware, rede, inicialização e o motor de aplicar/desfazer numa chave isolada. Revisão da v1.1 em `docs/revisao-v1.1.md`.
- O PC do Vinícius já tem a v1.1 aplicada em parte (plano "Vinicius - Desempenho Maximo" ativo, mouse sem aceleração etc.): 28 de 38 ajustes recomendados aparecem como "Aplicado". Esses não têm original guardado, então o "Desfazer" não age neles.
- Se o usuário logado não for administrador e elevar com outra conta, as alterações em `HKCU` vão para a conta errada.
- Winget: IDs da lista padrão devem ser conferidos com `winget search`.
- Ajustes de MMCSS/`SystemResponsiveness` têm efeito discutível; manter como opcionais.

---

## 5. Pendências imediatas (urgente)

1. **Executar o `docs/plano-de-testes.md`** (v2.0 com administrador), fase por fase, e corrigir o que falhar.
2. ~~Colocar o projeto no **Git**~~ ✅ feito (estrutura `src/`, `config/`, `docs/`; `.gitattributes` força CRLF).
3. Validar os IDs do winget, o StartupApproved no Win10, o valor do Num Lock (`2` ou `2147483650`), os nomes `VRROptimizeEnable`/`AutoHDREnable` e os GUIDs de tampa/economia de bateria num notebook.
4. Testar num **Windows 10** (VM): itens exclusivos, fonte Segoe MDL2 e notícias e interesses.
6. Validar a 5ª rodada (plano de testes, fase 5d): campos do log de boot (só com admin), `New-CimInstance Win32_PageFileSetting` no desfazer da paginação, leitura do Wi-Fi em português, nomes de pacote dos apps de fabricante (prefixos AD2F1837/E046963F/B9ECED6F etc.), heurística do Resizable BAR (BAR1 ≈ VRAM) contra o Painel NVIDIA.
5. Validar os itens dos lotes B–E (plano de testes, fase 5c): leitura de senhas Wi-Fi do `netsh` em português (só testável com placa Wi-Fi), políticas de navegador em `edge://policy`/`chrome://policy`, `Aplicar-Perfil.bat` e a tarefa agendada de manutenção.

---

## 6. Requisitos definidos pelo Vinícius para a v2.0

- **Caixas de seleção** para cada ajuste, com **explicação do que cada um faz**.
- **Ver o que está sendo executado** e **se cada item deu certo ou erro**.
- **Opção para indicar Windows 10 ou 11**, para o configurador escolher os comandos certos.
- **Perfis por tipo de PC** (Low / Mid / High-end).
- Foco em **UI/UX do usuário**.
- Possibilidade de migrar para um ambiente de desenvolvimento completo depois.

---

## 7. Proposta de UX para a v2.0

### Wireframe

```
┌─ Otimizador Vinicius ───────────────────────────────────────────┐
│ Windows: [Windows 11 ▼] (detectado: 11, build 26100)            │
│ PC: Mid-end · Desktop · 16 GB · NVMe   [Ver relatório]          │
│ Perfil: (Trabalho) (Gamer) (Básico) (Personalizado)             │
├──────────────────────┬──────────────────────────────────────────┤
│ ▼ Mouse e teclado    │ Desativar aceleração do mouse            │
│  ☑ Aceleração OFF ✓  │                                          │
│  ☑ Alt+Shift OFF     │ O que faz: desliga "Aumentar precisão    │
│ ▼ Energia            │ do ponteiro" para o mouse mover 1:1.     │
│  ☑ Desempenho máximo │ Risco: 🟢 Seguro   Reinício: não         │
│  ☐ Hibernação OFF 🟡 │ Como desfazer: botão Desfazer.           │
│ ▼ Jogos              │ Status atual: ✓ já aplicado              │
│  ☐ HAGS (Win10 2004+)│                                          │
├──────────────────────┴──────────────────────────────────────────┤
│ 7 selecionados · 2 exigem reinício   [Simular]  [Aplicar ▶]     │
└─────────────────────────────────────────────────────────────────┘
```

### Decisões de UX

- **Windows 10/11:** detecção automática + seletor manual. Itens incompatíveis ficam **desabilitados (cinza)** com o motivo no tooltip.
- **Status atual:** cada item tem uma função `Detectar` que lê o estado antes. Mostra "✓ já aplicado".
- **Risco:** 🟢 Seguro, 🟡 Moderado, 🔴 Avançado. Itens 🔴 **nunca** vêm marcados em perfis.
- **Painel de detalhes:** o que faz, o que muda (chaves/comandos), se exige reinício/logoff, como desfazer.
- **Tela de execução:** lista ao vivo por item — ⏳ executando, ✅ ok, ❌ erro (mensagem real), ⚠️ não se aplica — com barra de progresso e log expansível.
- **Resumo final:** X ok, Y erros, Z exigem reinício + botão **Reiniciar agora** + exportar resultado.
- **Modo Simular (dry-run):** mostra o que mudaria sem alterar nada.
- **Desfazer por item** (não só por sessão) e **histórico** de execuções.
- **Perfis** só pré-marcam as caixas; o usuário sempre revisa antes de aplicar. A classificação Low/Mid/High apenas **sugere** um perfil.

---

## 8. Arquitetura proposta: catálogo de ajustes

A mudança principal é **separar dados de código**. Cada ajuste vira um item de catálogo com:

- **Metadados** (nome, descrição, categoria, risco, Windows suportados, perfis, tipo de reinício).
- **`Detectar`** → retorna se já está aplicado.
- **`Aplicar`** → executa e retorna sucesso/erro com mensagem.
- **`Desfazer`** → volta ao estado anterior (usando backup quando possível).

```json
{
  "id": "mouse.aceleracao",
  "nome": "Desativar aceleração do mouse",
  "descricao": "Desliga 'Aumentar precisão do ponteiro' para o mouse mover 1:1.",
  "categoria": "Mouse e teclado",
  "risco": "seguro",
  "windows": ["10", "11"],
  "buildMinima": null,
  "perfis": ["trabalho", "gamer", "basico"],
  "reinicio": "nenhum"
}
```

Benefícios: a interface se monta a partir do catálogo, adicionar um ajuste não exige mexer na tela, e o catálogo é reaproveitado na migração para C#.

### Inventário de IDs sugeridos (a partir da v1.1)

`mouse.aceleracao`, `mouse.sensibilidade`, `teclado.aderencia`, `teclado.filtro`, `teclado.alternancia`, `teclado.altshift`, `energia.plano`, `energia.cpu-minimo`, `energia.usb-seletivo`, `energia.pcie-aspm`, `energia.suspensao`, `game.modo-jogo`, `game.dvr`, `game.hags`, `game.mmcss`, `ui.menu-delay`, `ui.animacoes`, `ui.transparencia`, `ui.extensoes`, `ui.startup-delay`, `ui.menu-classico`, `priv.anuncios`, `priv.sugestoes`, `priv.bing`, `priv.telemetria`, `priv.atividades`, `sistema.inicializacao-rapida`, `sistema.hibernacao`, `limpeza.temp`, `limpeza.dns`, `limpeza.lixeira`, `rede.dns`, `rede.energia-placa`.

### Perfis iniciais (proposta, a validar)

| Perfil | Inclui |
|---|---|
| **Básico** | Seguros: mouse, teclado, interface, privacidade, limpeza de temp |
| **Trabalho** | Básico + energia máxima + inicialização rápida OFF + extensões visíveis |
| **Gamer** | Trabalho + modo game, DVR OFF, HAGS, MMCSS |
| **Low-end** | Básico + efeitos visuais em desempenho + revisão de inicialização |

---

## 9. Roadmap

| Versão | Tecnologia | Entrega |
|---|---|---|
| **v1.1** ✅ | PowerShell (menu texto) | Mantida como modo texto, com correções |
| **v1.2** ✅ | PowerShell | Catálogo (Detectar/Simular/Aplicar/Desfazer): feito junto com a v2.0 |
| **v2.0** 🧪 | PowerShell + **WPF (XAML)** | Janela gráfica conforme seção 7: feita, em teste |
| **v3.0** | **C# .NET 8** + WPF ou WinUI 3 | `.exe`, instalador, atualização automática, assinatura digital |

Evitar Electron (pesado demais para um otimizador).

---

## 10. Backlog de ideias

**Alta prioridade**
- Detecção de estado atual de cada ajuste.
- Modo Simular.
- Desfazer por item + histórico de execuções.
- Seletor manual de Windows 10/11.

**Feitos na v2.0:** perfil exportável + modo silencioso (`Aplicar-Perfil.bat`), aba Técnico (drivers, COM, teste TCP), reparo DISM/SFC, manutenção agendada, evolução da nota (antes/depois), espaço em disco, monitor de conexão, suporte técnico, temperaturas (sem componente externo), navegadores. 5ª rodada: página Diagnóstico (lentidão, boot, estabilidade, cabo/Wi-Fi, checklist de BIOS), antes × depois, paginação, TRIM, WinSxS, apps em segundo plano, apps do Windows, modo jogo, arquivos repetidos, programas por tamanho, inventário de vários PCs.

**Média prioridade**
- **Teste UDP** (precisa de um programa que responda no servidor).
- ~~Checklist de BIOS~~ ✅ feito (Diagnóstico > BIOS e hardware). Falta: levar para o relatório HTML.
- Efeitos visuais "melhor desempenho" como item do perfil Low-end.

**Futuro (v3)**
- Assinatura digital (evitar alerta do SmartScreen).
- Atualização automática.
- Instalador.

**Serviços:** entraram só 9, conservadores, um por um, com consumo medido e desfazer (pedido do Vinícius para PCs de 8/16 GB). Continua fora: desativar serviços em massa.

**Antivírus:** o app NÃO desliga o Defender à força. Mostra o estado real e, com Tamper Protection ligada (padrão), leva à tela do Windows; pausa por script só quando o Windows deixa; prefere exclusão de pasta. Não mexe em antivírus de terceiros (sem API única). **Ativadores de Windows/Office (irm get.activated.win | iex) ficam DE FORA:** script remoto, pirataria e contra o propósito do app.

**Deixados de fora de propósito** (risco alto ou ganho duvidoso): ~~desativar Defender~~ (ver acima), `bcdedit`/timer resolution, remover apps nativos (debloat agressivo).

---

## 11. Sugestões de desempenho por tipo de PC (referência para os perfis)

**Low-end:** SSD no lugar do HD (maior ganho), 16 GB em dual channel, efeitos visuais em desempenho, enxugar inicialização, só o Defender como antivírus, remover bloatware do fabricante, navegador com abas em suspensão.

**Mid-end:** XMP/EXPO na BIOS, BIOS/chipset/vídeo atualizados pelo fabricante, Resizable BAR, Windows no NVMe, limpeza interna e pasta térmica se CPU > 85 °C.

**High-end:** monitor no Hz máximo com G-Sync/FreeSync e cabo na GPU, desligar overlays em jogos competitivos, Reflex/Anti-Lag, opcional desligar Integridade de Memória (VBS) — ganha FPS, reduz segurança; só em PC de jogo.

---

## 12. Próximo passo sugerido

Decidido: v1.2 + v2.0 foram feitas juntas (catálogo + WPF). Próximo: rodar o plano de testes com administrador. Depois, pela ordem do backlog: perfil exportável e modo silencioso (`/perfil x.json`), manutenção agendada e comparação antes/depois do relatório.

Estrutura original sugerida (a atual está na seção 1):

```
otimizador-vinicius/
├─ CLAUDE.md              ← este arquivo
├─ README.md
├─ CHANGELOG.md
├─ src/
│  ├─ Otimizador-Vinicius.ps1
│  ├─ Executar-Otimizador.bat
│  ├─ catalogo/            ← itens de ajuste (v1.2+)
│  └─ ui/                  ← XAML (v2.0)
├─ config/
│  └─ winget-lista-exemplo.txt
└─ docs/
```

---

## 13. Armadilhas do PowerShell 5.1 (encontradas nos testes da v2.0)

Todas causaram bugs reais. Conferir sempre que escrever código novo.

| Armadilha | Sintoma | Como fazer |
|---|---|---|
| Arquivo salvo sem BOM | Acentos viram `Ã¡` | Rodar `tools\verificar.ps1` depois de editar. |
| `@($null).Count` é **1** | Item sem `Energia` indexava `$null[0]` | Testar com `if ($Item.Energia)`. |
| `New-Object` devolve PSObject embrulhado | WPF recusa como pincel, `Content`/`Header` mostram o nome do tipo, `SelectedItem` não acha o item | Usar `[Tipo]::new()` em tudo que vai para propriedade `object` do WPF; `ItemsSource` com lista tipada (`[Otz.Linha[]]@(...)` ou `ObservableCollection[T]`). |
| `@( @(a,b) @(c,d) )` | As listas internas são "achatadas" | Vírgula na frente: `,@(a,b)`. |
| `return $array` | O array é desmontado; `byte[]` vira `object[]` e o `SetValue` Binary falha | `return , $array`. |
| `if`/pipeline dentro de `[pscustomobject]@{...}` grande, ou `@($lista)` em função com função aninhada | `Os tipos de argumento não correspondem` | Montar o objeto com `$r = [ordered]@{}; $r.X = ...`; usar `$lista.ToArray()`. |
| `$sender` como parâmetro | Variável automática | Usar `param($origem, $e)`. |
| `$x:` em string | `"$sug: texto"` é lido como unidade/escopo | `"$($sug): texto"`. |
| Scriptblock entre runspaces | Trava ou roda na thread errada | Passar código como **texto** ao runspace. |
| `[T[]]@($lista)` com `List[object]` | `Os tipos de argumento não correspondem` (quase quebrou o diálogo de Aplicar) | Converter com laço + `List[T].ToArray()` (`ConvertTo-Linhas`). |
| Apelido de `powercfg` que não existe | `LIDACTION`, `ESBATTTHRESHOLD`, `SUB_ENERGYSAVER` e `PERFBOOSTMODE` NÃO existem neste Windows | Conferir com `powercfg /aliases`; usar o GUID. |
| `.bat` com BOM | O `cmd` quebra na 1ª linha | `.bat` em ASCII + CRLF. |
| Variáveis não diferenciam maiúsculas | `foreach ($s in ...)` ou `param($s, $e)` sobrescreve o estado global `$S` (quebrou o Enter do teste de servidor) | Nunca usar `$s`, `$ui`, `$win`, `$otz` como variável local. |
| Função com nome de apelido | `function R { }` perde para o apelido `R` (Invoke-History) | Nomes descritivos (`Substituir`), nunca 1 letra. |
| `Get-WinEvent -FilterHashtable` sem permissão | "Acesso negado" vira "Nenhum evento encontrado" (o boot parecia nunca ter sido medido) | Testar antes com `Get-WinEvent -LogName X -MaxEvents 1` e capturar `UnauthorizedAccessException`. |
| `.GetNewClosure()` em evento da janela | O bloco perde as funções do script (ficam no escopo do script, não no global) | Guardar o valor em `$S.Algo` e ler dentro do bloco. |
| `"a" + (lista) -join "x"` | `+` vem antes do `-join`: junta errado | Parênteses: `"a" + ((lista) -join "x")`. |
| `Get-Counter '\Processo(*)\...'` | Caminho dos contadores muda com o idioma do Windows | Usar `Win32_PerfRawData_*` (CIM) e calcular a diferença entre 2 leituras. |
| `\\` como variável | É automática do PowerShell; atribuir quebra | Usar outro nome (`\\`). |