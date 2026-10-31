# Como adicionar um ajuste ao catálogo

Cada arquivo em `src/catalogo/` é uma categoria. A ordem dos arquivos (`01-`, `02-`...) define a ordem na tela.
A interface se monta sozinha a partir do catálogo: **não é preciso mexer no XAML nem no script da janela.**

## Ajuste de registro (o caso mais comum)

```powershell
@{
    Id        = 'ui.exemplo'                 # único, formato categoria.nome
    Categoria = $cat
    Nome      = 'Nome curto e claro'
    Resumo    = 'Uma frase: o benefício para o usuário.'
    Detalhe   = 'O que acontece, em linguagem simples.'
    Indicado  = 'Para quem é.'
    Atencao   = 'Efeito colateral (opcional; aparece em amarelo).'
    Risco     = 'seguro'                     # seguro | moderado | avancado (avancado nunca entra em perfil)
    Windows   = @('10', '11')                # opcional (padrão: os dois)
    BuildMinima = 22631                      # opcional
    Reinicio  = 'nenhum'                     # nenhum | explorer | logoff | reiniciar
    Perfis    = @('basico', 'trabalho')      # basico | trabalho | gamer | leve
    Registro  = @(
        @{ Chave = 'HKCU\Software\...'; Nome = 'Valor'; Valor = 0; Tipo = 'DWord' }  # DWord | QWord | String | ExpandString | Binary | MultiString
    )
}
```

Com `Registro`, o motor faz tudo sozinho: **detectar**, **simular**, **aplicar** (guardando o original) e **desfazer**.
`Nome = ''` grava o valor "(Padrão)" da chave.

## Ajuste de energia (powercfg, só na tomada)

```powershell
Energia = @( @{ Sub = 'SUB_SLEEP'; Config = 'STANDBYIDLE'; Valor = 0 } )
```

## Ajuste com código próprio

Use quando não for registro nem powercfg (ex.: `energia.plano`, `rede.energia-placa`, `sistema.hibernacao`):

| Campo | Recebe | Devolve |
|---|---|---|
| `Detectar` | — | `@{ Estado = 'aplicado'/'nao'/'parcial'/'acao'/'na'; Texto = '...' }` |
| `Simular` | — | linhas de texto (`'→ X: a → b'` ou `'= X já é b'`) |
| `Aplicar` | — | `@{ Status = 'ok'/'erro'/'aviso'/'ignorado'; Mensagem = '...' }` |
| `Desfazer` | `param($orig)` | igual ao Aplicar |
| `AposAplicar` / `AposDesfazer` | — | nada (ex.: `Update-MouseAoVivo`) |
| `Requisito` | — | texto com o motivo se NÃO puder aplicar (deixa o item cinza) |
| `Confirmar` | — | texto mostrado no diálogo antes de aplicar (ações destrutivas) |
| `Tecnico` | — | texto extra em "O que muda no sistema" |
| `ComoDesfazer` | — | texto próprio para "Como desfazer" |

No `Aplicar` com código próprio, guarde o estado anterior **só na primeira vez**:

```powershell
if (-not (Get-Original 'meu.id')) { Set-Original 'meu.id' @{ Data = (Get-Date).ToString('s'); Valor = $atual } }
```

`Tipo = 'acao'` marca ações únicas (limpezas): elas não criam ponto de restauração e não têm desfazer.

## Regras

- **Nunca inventar chaves ou comandos.** Só entram ajustes documentados ou conferidos em VM.
- Escreva para quem não é técnico: diga o benefício antes do detalhe.
- Depois de editar, rode `tools\verificar.ps1` (garante BOM e CRLF e confere a sintaxe).
