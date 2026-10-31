# Revisão da v1.1

Revisão linha a linha do `src/Otimizador-Vinicius.ps1` (1030 linhas), feita antes da primeira execução com administrador.
Sintaxe: o parser do PowerShell 5.1 não encontrou nenhum erro. Os problemas abaixo são de lógica e de comportamento.

## Bugs corrigidos na própria v1.1 (modo texto)

| # | Onde | Problema | Correção |
|---|---|---|---|
| B1 | Inicialização (S) | Uma chave `Run` sem valores gerava um item "fantasma" sem nome; alternar esse item dava erro. | Pula chaves vazias. |
| B2 | Ponto de restauração | `Checkpoint-Computer` só **avisa** (não dá erro) quando não cria o ponto, e o script dizia "criado". Além disso, apagava `SystemRestorePointCreationFrequency` mesmo que o usuário já tivesse um valor próprio. | Lê os avisos (`-WarningVariable`) e devolve o valor anterior. |
| B3 | Interface (5), Menu clássico (9/D) | `Stop-Process explorer` sem garantir que o Explorer volte. Se o reinício automático estiver desligado, a barra de tarefas some. | `Restart-Explorer`: espera 3 s e abre manualmente se preciso. |
| B4 | Limpeza (7) | Mostrava os MB "analisados" antes de apagar, não o que foi liberado. | Mede antes e depois. |

## Limitações de projeto (resolvidas na v2.0)

| # | Problema na v1.1 | Como a v2.0 resolve |
|---|---|---|
| L1 | A restauração por `.reg` não apaga valores nem chaves que não existiam antes. | Antes da primeira alteração, cada ajuste guarda o valor original exato, inclusive "não existia". O desfazer apaga o que foi criado e remove as chaves vazias. **Testado** numa chave isolada. |
| L2 | `Write-Ok` era mostrado mesmo quando o comando falhava (erros do `Set-Reg`, códigos de saída do `powercfg`). | Cada ajuste devolve `ok`, `erro` ou `aviso` com a mensagem real. O `powercfg` confere `$LASTEXITCODE`. |
| L3 | Se o Desempenho Máximo falhasse, o script assumia que o "Alto desempenho" existia, o que não vale em PCs com Modern Standby. | Tenta duplicar os dois. Se nenhum funcionar, mostra um erro claro. |
| L4 | Elevando com outra conta de administrador, os ajustes de `HKCU` iam para a conta errada. | Detecta o dono do `explorer.exe` da sessão e grava em `HKU\<SID>` dessa conta, com aviso na tela. |
| L5 | A energia da placa de rede não tinha backup. | Guarda o estado de cada placa antes de mudar. |
| L6 | O menu clássico tinha um "desfazer" separado (opção D). | Desfazer genérico para qualquer ajuste. |

## Observações para validar em teste real

- **Num Lock:** neste PC, `HKU\.DEFAULT\Control Panel\Keyboard\InitialKeyboardIndicators` vale `"2147483648"`. O ajuste grava `"2"`. Conferir se o Num Lock liga na tela de senha. Se não ligar, testar `"2147483650"` (o mesmo valor com o bit do Num Lock).
- **DNS:** só o DNS IPv4 é trocado e guardado. Se o roteador entrega DNS IPv6, ele continua em uso.
- **Limpeza com outra conta de administrador:** `$env:TEMP` é o da conta que elevou, não o do usuário logado.
- **Winget:** conferir os IDs da lista padrão com `winget search`.
- **Políticas** (Bing, telemetria, Widgets, Windows Update): as Configurações passam a mostrar "gerenciado pela sua organização". Isso agora está explicado no próprio ajuste.
