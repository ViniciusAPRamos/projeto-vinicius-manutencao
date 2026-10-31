# Otimizador Vinicius — Contexto do projeto

> Documento de continuidade. Resume tudo o que foi feito na conversa original (claude.ai) e o que precisa ser feito a partir daqui.
> Leia por completo antes de propor ou alterar código.

---

## 1. Sobre o projeto

**Otimizador Vinicius** é um otimizador de Windows de **desenvolvimento próprio** do Vinícius (analista de sistemas na área de IoT, telemetria e rastreamento de frotas).

- **Hoje:** script PowerShell com menu de texto (v1.1).
- **Próximo:** interface gráfica com caixas de seleção, explicação de cada ajuste e feedback visual de execução (v2.0).
- **Futuro:** aplicativo C# com `.exe`, instalador e atualização (v3.0).

### Arquivos atuais (v1.1)

| Arquivo | Função |
|---|---|
| `src/Otimizador-Vinicius.ps1` | Script principal (~1000 linhas). Menu, módulos, backup e restauração. |
| `src/Executar-Otimizador.bat` | Atalho: chama o `.ps1` com `-ExecutionPolicy Bypass`. O `.ps1` se autoeleva para administrador. |
| `config/winget-lista-exemplo.txt` | Modelo de lista de programas. Copiado para `src/winget-lista.txt` (ao lado do script), substitui a lista padrão. |

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

- ⚠️ **O script nunca foi executado.** Foi escrito em ambiente Linux sem PowerShell. A sintaxe foi revisada manualmente, mas **precisa de teste real** (de preferência em VM ou PC de testes, item por item).
- Se o usuário logado não for administrador e elevar com outra conta, as alterações em `HKCU` vão para a conta errada.
- Winget: IDs da lista padrão devem ser conferidos com `winget search`.
- Ajustes de MMCSS/`SystemResponsiveness` têm efeito discutível; manter como opcionais.

---

## 5. Pendências imediatas (urgente)

1. **Testar a v1.1 no Windows real**, opção por opção, e corrigir erros encontrados.
2. ~~Colocar o projeto no **Git**~~ ✅ feito (estrutura `src/`, `config/`, `docs/`; `.gitattributes` força CRLF).
3. Validar os IDs do winget e o comportamento da opção **S** (StartupApproved) no Win10 e no Win11.

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
| **v1.1** ✅ | PowerShell (menu texto) | Atual — falta testar |
| **v1.2** | PowerShell | Refatorar para **catálogo** (Detectar/Aplicar/Desfazer) mantendo o menu |
| **v2.0** | PowerShell + **WPF (XAML)** | Janela gráfica conforme seção 7, ainda sem instalação |
| **v3.0** | **C# .NET 8** + WPF ou WinUI 3 | `.exe`, instalador, atualização automática, assinatura digital |

Evitar Electron (pesado demais para um otimizador).

---

## 10. Backlog de ideias

**Alta prioridade**
- Detecção de estado atual de cada ajuste.
- Modo Simular.
- Desfazer por item + histórico de execuções.
- Seletor manual de Windows 10/11.

**Média prioridade**
- **Perfil exportável + modo silencioso por linha de comando** (`/perfil trabalho.json`) para padronizar vários PCs da empresa.
- **Aba Técnico:** drivers serial, portas COM e **teste de conexão TCP** (`Test-NetConnection -Port`) para servidores/plataformas. UDP não é testável do mesmo jeito; precisa de abordagem própria.
- **Reparo do Windows** (`sfc /scannow`, `DISM /Online /Cleanup-Image /RestoreHealth`) com progresso.
- **Manutenção agendada** (limpeza semanal pelo Agendador de Tarefas).
- **Comparar antes/depois:** gerar o relatório H antes e depois da otimização.
- **Checklist de BIOS** (XMP/EXPO, Resizable BAR) no relatório — só orienta, não altera.
- Efeitos visuais "melhor desempenho" como item do perfil Low-end.

**Futuro (v3)**
- Assinatura digital (evitar alerta do SmartScreen).
- Atualização automática.
- Instalador.

**Deixados de fora de propósito** (risco alto ou ganho duvidoso): desativar Defender, desativar serviços em massa, `bcdedit`/timer resolution, remover apps nativos (debloat agressivo).

---

## 11. Sugestões de desempenho por tipo de PC (referência para os perfis)

**Low-end:** SSD no lugar do HD (maior ganho), 16 GB em dual channel, efeitos visuais em desempenho, enxugar inicialização, só o Defender como antivírus, remover bloatware do fabricante, navegador com abas em suspensão.

**Mid-end:** XMP/EXPO na BIOS, BIOS/chipset/vídeo atualizados pelo fabricante, Resizable BAR, Windows no NVMe, limpeza interna e pasta térmica se CPU > 85 °C.

**High-end:** monitor no Hz máximo com G-Sync/FreeSync e cabo na GPU, desligar overlays em jogos competitivos, Reflex/Anti-Lag, opcional desligar Integridade de Memória (VBS) — ganha FPS, reduz segurança; só em PC de jogo.

---

## 12. Próximo passo sugerido

Decisão pendente com o Vinícius: **refatorar primeiro para o catálogo (v1.2)** ou **ir direto para a v2.0 com WPF já usando o catálogo**.

Recomendação: começar pelo **teste da v1.1 + Git**, depois **v1.2 (catálogo)**, pois a v2.0 depende dele.

Estrutura de pastas sugerida:

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
