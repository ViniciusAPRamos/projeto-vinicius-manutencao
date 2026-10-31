# Base de conhecimento da "Limpar o segundo plano"
# ---------------------------------------------------------------
# Programas e serviços de terceiros que ficam rodando sem o usuário pedir.
# Cada item:
#   Id, Nome, Grupo
#   Nivel     seguro   = vem marcado (e entra nos perfis e no Aplicar-Perfil.bat)
#             depende  = aparece desmarcado, com a explicação
#             manter   = nunca aparece (anti-cheat, drivers, ventoinhas...)
#   Servicos  regex do NOME do serviço (só serviços em Automático viram candidatos)
#   Inicio    regex do nome OU do executável do item de inicialização
#   Processos regex do nome dos processos que somem junto (para estimar a RAM)
#   Texto     o que é;  Efeito  o que muda ao desligar;  Bandeja  como impedir dentro do app
# O primeiro item que combinar vence: deixe os mais específicos em cima.
# Para incluir um programa novo, copie um item parecido. Rode tools\verificar.ps1 depois.
# ---------------------------------------------------------------
@(
    # ===== Manter (nunca listados) =====
    @{ Id = 'riot.vanguard';  Nome = 'Riot Vanguard (anti-cheat)'; Grupo = 'Anti-cheat'; Nivel = 'manter'
       Servicos = @('^vgc$', '^vgk$'); Inicio = @('Riot Vanguard', 'vgtray\.exe')
       Texto = 'Anti-cheat do VALORANT e do League of Legends: precisa ligar junto com o Windows.' }
    @{ Id = 'anticheat';      Nome = 'Anti-cheat de jogos'; Grupo = 'Anti-cheat'; Nivel = 'manter'
       Servicos = @('^EAAntiCheat', '^EasyAntiCheat', '^BEService$', '^FACEIT', '^Faceit', '^mhyprot', '^PnkBstr')
       Texto = 'Anti-cheat: os jogos online dependem dele.' }
    @{ Id = 'fabricante.desempenho'; Nome = 'Controle de desempenho e ventoinhas do fabricante'; Grupo = 'Fabricante'; Nivel = 'manter'
       Servicos = @('^AWCC', '^OCControl', '^AlienwareOSD', '^LenovoVantageService$', '^ArmouryCrateService$', '^AsusOptimization$', '^MSI_Center', '^HPOmenCap')
       Texto = 'Controla ventoinhas, modos de desempenho, bateria e teclas especiais.' }
    @{ Id = 'perifericos';    Nome = 'Programas de mouse, teclado e headset'; Grupo = 'Periféricos'; Nivel = 'manter'
       Servicos = @('^Corsair', '^LGHUB', '^logi_', '^Razer', '^SteelSeries', '^HyperX')
       Texto = 'Controla macros, luzes e perfis de periféricos.' }
    @{ Id = 'atualizadores';  Nome = 'Atualizadores de navegador'; Grupo = 'Atualizadores'; Nivel = 'manter'
       Servicos = @('^GoogleUpdater', '^gupdate', '^MozillaMaintenance$', '^brave', '^edgeupdate', '^MicrosoftEdgeElevationService$')
       Texto = 'Mantêm o navegador atualizado (segurança). Ficam parados e só ligam para atualizar.' }
    @{ Id = 'nvidia.base';    Nome = 'NVIDIA'; Grupo = 'Vídeo'; Nivel = 'manter'
       Servicos = @('^NVDisplay\.Container', '^NvContainerLocalSystem$')
       Texto = 'Painel de Controle NVIDIA e recursos do driver.' }

    # ===== Dell =====
    @{ Id = 'dell.supportassist'; Nome = 'Dell SupportAssist'; Grupo = 'Fabricante (Dell)'; Nivel = 'seguro'
       Servicos = @('^SupportAssistAgent$'); Processos = @('^SupportAssistAgent$')
       Texto = 'Assistente de suporte da Dell: faz verificações automáticas e envia dados do PC para a Dell.'
       Efeito = 'Para de verificar sozinho. Abrir o SupportAssist pelo menu Iniciar continua funcionando.' }
    @{ Id = 'dell.techhub';   Nome = 'Dell TechHub e agentes'; Grupo = 'Fabricante (Dell)'; Nivel = 'seguro'
       Servicos = @('^DellTechHub$'); Processos = @('^Dell\.TechHub', '^Dell\.CoreServices\.Client$')
       Texto = 'Plataforma da Dell que mantém rodando os agentes de diagnóstico, telemetria e instrumentação (6 processos).'
       Efeito = 'O SupportAssist e o MyDell podem levar alguns segundos a mais para abrir.' }
    @{ Id = 'dell.connected'; Nome = 'Dell Connected Service Delivery'; Grupo = 'Fabricante (Dell)'; Nivel = 'seguro'
       Servicos = @('^DellConnectedServiceDelivery$'); Processos = @('^Dell\.Connected\.Service\.Delivery')
       Texto = 'Entrega de ofertas e serviços conectados da Dell.'
       Efeito = 'Nenhum no uso do dia a dia.' }
    @{ Id = 'dell.update';    Nome = 'Dell Update (procura de drivers)'; Grupo = 'Fabricante (Dell)'; Nivel = 'seguro'
       Servicos = @('^DellClientManagementService$'); Processos = @('^Dell\.Update\.SubAgent$', '^ServiceShell$')
       Texto = 'Procura atualizações de driver e BIOS da Dell em segundo plano.'
       Efeito = 'Não procura atualizações sozinho: abra o Dell Update (ou o site da Dell) uma vez por mês.' }

    # ===== Outros fabricantes =====
    @{ Id = 'hp.analytics';   Nome = 'HP Touchpoint Analytics'; Grupo = 'Fabricante (HP)'; Nivel = 'seguro'
       Servicos = @('^HpTouchpointAnalyticsService$')
       Texto = 'Telemetria da HP: envia dados de uso do PC para a HP.'
       Efeito = 'Nenhum no uso do dia a dia.' }
    @{ Id = 'lenovo.smartconnect'; Nome = 'Smart Connect (Lenovo / Motorola Ready For)'; Grupo = 'Fabricante (Lenovo)'; Nivel = 'seguro'
       Servicos = @('^SmartConnect$'); Inicio = @('SmartConnect'); Processos = @('^SmartConnect$', '^ReadyForService$')
       Texto = 'Liga um celular Motorola ao PC (Ready For).'
       Efeito = 'Para usar o celular no PC, abra o Smart Connect antes.' }

    # ===== Acesso remoto =====
    @{ Id = 'anydesk.bandeja'; Nome = 'AnyDesk (ícone na bandeja)'; Grupo = 'Acesso remoto'; Nivel = 'seguro'
       Inicio = @('AnyDesk')
       Texto = 'Abre a janela do AnyDesk escondida ao ligar o PC.'
       Efeito = 'O AnyDesk continua instalado e abre normalmente quando você clica nele.' }
    @{ Id = 'anydesk.servico'; Nome = 'AnyDesk (acesso sem ninguém na frente)'; Grupo = 'Acesso remoto'; Nivel = 'depende'
       Servicos = @('^AnyDesk$'); Processos = @('^AnyDesk$')
       Texto = 'Serviço que deixa o PC sempre pronto para receber acesso remoto.'
       Efeito = 'Ninguém consegue acessar este PC sem alguém na frente. Para receber suporte, abra o AnyDesk e passe o número. Também é mais seguro.' }
    @{ Id = 'rustdesk';       Nome = 'RustDesk'; Grupo = 'Acesso remoto'; Nivel = 'depende'
       Servicos = @('^RustDesk$'); Inicio = @('RustDesk'); Processos = @('^rustdesk$')
       Texto = 'Serviço de acesso remoto do RustDesk.'
       Efeito = 'Ninguém consegue acessar este PC sem alguém na frente. Se você já usa o AnyDesk, manter dois programas de acesso remoto ligados não é necessário.' }
    @{ Id = 'teamviewer';     Nome = 'TeamViewer'; Grupo = 'Acesso remoto'; Nivel = 'depende'
       Servicos = @('^TeamViewer$'); Inicio = @('TeamViewer'); Processos = @('^TeamViewer')
       Texto = 'Serviço de acesso remoto do TeamViewer.'
       Efeito = 'Ninguém consegue acessar este PC sem alguém na frente.' }
    @{ Id = 'radmin';         Nome = 'Radmin VPN'; Grupo = 'Rede'; Nivel = 'depende'
       Servicos = @('^RvControlSvc$'); Inicio = @('RadminVPN', 'RvRvpnGui'); Processos = @('^RvControlSvc$', '^RvRvpnGui$')
       Texto = 'Rede virtual para jogar em LAN com amigos pela internet.'
       Efeito = 'Com o serviço em Manual, a rede do Radmin pode não conectar até o serviço ser iniciado. Desligue só se não usa.' }

    # ===== Comunicação e launchers (ficam na bandeja depois de fechar a janela) =====
    @{ Id = 'discord.instalador'; Nome = 'Instalador do Discord para outros usuários'; Grupo = 'Comunicação'; Nivel = 'seguro'
       Inicio = @('SquirrelMachineInstalls')
       Texto = 'Verifica a cada login se o Discord precisa ser instalado para outro usuário do PC. Não é o Discord em si.'
       Efeito = 'Nenhum: o Discord continua abrindo normalmente.' }
    @{ Id = 'discord';        Nome = 'Discord'; Grupo = 'Comunicação'; Nivel = 'depende'
       Inicio = @('Discord'); Processos = @('^Discord')
       Texto = 'Abre escondido ao ligar o PC e fica na bandeja mesmo depois de fechar a janela.'
       Efeito = 'Abre só quando você clicar.'
       Bandeja = 'No Discord: Configurações > Configurações do Windows > desligue "Abrir o Discord" e "Minimizar para a bandeja".' }
    @{ Id = 'steam';          Nome = 'Steam'; Grupo = 'Launchers de jogos'; Nivel = 'depende'
       Inicio = @('^Steam$', '\\steam\.exe'); Processos = @('^steam$', '^steamwebhelper$')
       Texto = 'Abre escondida ao ligar o PC; o navegador interno (steamwebhelper) ocupa centenas de MB.'
       Efeito = 'Abre só quando você clicar. Atualizações de jogos acontecem quando ela estiver aberta.'
       Bandeja = 'Na Steam: Steam > Configurações > Interface > desmarque "Executar a Steam ao iniciar o computador". Para fechar de verdade, use Steam > Sair (o X só esconde).' }
    @{ Id = 'ea';             Nome = 'App EA'; Grupo = 'Launchers de jogos'; Nivel = 'depende'
       Inicio = @('EADM', 'EALauncher'); Processos = @('^EADesktop$', '^EACefSubProcess$', '^EABackgroundService$', '^EALocalHostSvc$', '^EAAntiCheat\.GameService$')
       Texto = 'Launcher da EA. Quando abre, liga junto o anti-cheat (Javelin), que sozinho ocupa ~280 MB.'
       Efeito = 'Abre só quando você clicar. O anti-cheat só liga junto com ele.'
       Bandeja = 'No app EA, procure em Configurações as opções de iniciar com o Windows e de continuar rodando ao fechar a janela. Para fechar de verdade, use o ícone da bandeja > Sair.' }
    @{ Id = 'epic';           Nome = 'Epic Games Launcher'; Grupo = 'Launchers de jogos'; Nivel = 'depende'
       Inicio = @('EpicGamesLauncher'); Processos = @('^EpicGamesLauncher$', '^EpicWebHelper$')
       Texto = 'Launcher da Epic, abre escondido ao ligar o PC.'
       Efeito = 'Abre só quando você clicar.' }
    @{ Id = 'riot.client';    Nome = 'Riot Client (launcher)'; Grupo = 'Launchers de jogos'; Nivel = 'depende'
       Inicio = @('RiotClient'); Processos = @('^RiotClient')
       Texto = 'Launcher da Riot aberto em segundo plano. O Vanguard (anti-cheat) é outro item e continua ligado.'
       Efeito = 'Abre só quando você clicar no jogo.' }
    @{ Id = 'ubisoft';        Nome = 'Ubisoft Connect'; Grupo = 'Launchers de jogos'; Nivel = 'depende'
       Inicio = @('Ubisoft', 'upc\.exe'); Processos = @('^upc$', '^UplayWebCore$')
       Texto = 'Launcher da Ubisoft.'
       Efeito = 'Abre só quando você clicar.' }
    @{ Id = 'battlenet';      Nome = 'Battle.net'; Grupo = 'Launchers de jogos'; Nivel = 'depende'
       Inicio = @('Battle\.net'); Processos = @('^Battle\.net$')
       Texto = 'Launcher da Blizzard.'
       Efeito = 'Abre só quando você clicar.' }
    @{ Id = 'spotify';        Nome = 'Spotify'; Grupo = 'Comunicação'; Nivel = 'depende'
       Inicio = @('Spotify'); Processos = @('^Spotify$')
       Texto = 'Abre escondido ao ligar o PC.'
       Efeito = 'Abre só quando você clicar.' }
    @{ Id = 'teams';          Nome = 'Microsoft Teams'; Grupo = 'Comunicação'; Nivel = 'depende'
       Inicio = @('ms-teams', 'Teams'); Processos = @('^ms-teams$', '^Teams$', '^msedgewebview2$')
       Texto = 'Abre ao ligar o PC para receber mensagens.'
       Efeito = 'Mensagens só chegam com o Teams aberto.' }
    @{ Id = 'onedrive';       Nome = 'OneDrive'; Grupo = 'Nuvem'; Nivel = 'depende'
       Inicio = @('^OneDrive$'); Processos = @('^OneDrive$')
       Texto = 'Sincroniza arquivos com a nuvem da Microsoft.'
       Efeito = 'A sincronização só acontece com o OneDrive aberto.' }
    @{ Id = 'utorrent';       Nome = 'uTorrent'; Grupo = 'Outros'; Nivel = 'depende'
       Inicio = @('utweb', 'uTorrent'); Processos = @('^utweb$', '^uTorrent$')
       Texto = 'Abre ao ligar o PC para continuar downloads.'
       Efeito = 'Downloads só continuam com ele aberto.' }

    # ===== Navegadores =====
    @{ Id = 'navegador.precarga'; Nome = 'Pré-carregamento do navegador'; Grupo = 'Navegadores'; Nivel = 'seguro'
       Inicio = @('MicrosoftEdgeAutoLaunch', 'GoogleChromeAutoLaunch', 'BraveSoftware.*AutoLaunch', 'Opera.*Browser')
       Texto = 'Abre o navegador escondido ao ligar o PC, só para ele parecer mais rápido depois.'
       Efeito = 'O navegador leva um instante a mais na primeira abertura do dia.' }

    # ===== Vídeo e utilitários =====
    @{ Id = 'nvidia.frameview'; Nome = 'NVIDIA FrameView (estatísticas na tela)'; Grupo = 'Vídeo'; Nivel = 'depende'
       Servicos = @('^FvSvc$'); Processos = @('^FvContainer', '^nvfvsdksvc', '^PresentMon', '^nvrla$')
       Texto = 'Mede FPS e latência para a sobreposição do NVIDIA App.'
       Efeito = 'As estatísticas de desempenho na tela do NVIDIA App param de funcionar.' }
    @{ Id = 'gigabyte.easytune'; Nome = 'GIGABYTE EasyTune'; Grupo = 'Fabricante (GIGABYTE)'; Nivel = 'depende'
       Servicos = @('^EasyTuneEngineService$', '^OCButtonService$')
       Texto = 'Overclock e curvas de ventoinha pelo Windows.'
       Efeito = 'Se você ajustou ventoinhas ou overclock pelo GIGABYTE Control Center, eles voltam ao padrão da BIOS.' }
    @{ Id = 'gigabyte.lcd';   Nome = 'GIGABYTE AORUS LCD'; Grupo = 'Fabricante (GIGABYTE)'; Nivel = 'depende'
       Servicos = @('^AorusLcdService$', '^GBTECService$')
       Texto = 'Controla telas LCD/OLED de placas de vídeo e coolers AORUS.'
       Efeito = 'Só faz diferença se você tem uma peça AORUS com tela.' }
    @{ Id = 'adobe.update';   Nome = 'Atualizador da Adobe'; Grupo = 'Atualizadores'; Nivel = 'seguro'
       Servicos = @('^AdobeARMservice$')
       Texto = 'Procura atualizações do Acrobat/Reader o tempo todo.'
       Efeito = 'O Acrobat ainda se atualiza quando você o abre.' }
)

# Guias para programas que não dá para desligar por aqui (ficam rodando por dentro de outro programa)
$Script:GuiasBandeja = @(
    @{ Nome = 'NVIDIA Overlay (até ~570 MB)'; Processos = @('^NVIDIA Overlay$')
       Texto = 'No NVIDIA App: Configurações > Funções > desligue a "Sobreposição do NVIDIA App" (Alt+Z). Ela também grava vídeos e mostra estatísticas; desligue se não usa.' }
    @{ Nome = 'Overlay do Alienware Command Center'; Processos = @('^AWCCOverlay$', '^GameEyeApp$')
       Texto = 'No Alienware Command Center, desligue a sobreposição em jogos (overlay). O controle de ventoinhas e desempenho continua.' }
)
