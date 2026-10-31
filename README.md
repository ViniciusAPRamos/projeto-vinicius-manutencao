# Otimizador Vinicius

Otimizador de Windows 10/11 com interface gráfica, feito em PowerShell + WPF.
Cada ajuste vem explicado em linguagem simples, mostra se já está aplicado e pode ser **desfeito individualmente**, voltando ao valor exato que existia antes.

![Tela Otimizar](docs/telas/otimizar.png)

> ⚠️ **v2.0 em teste.** A interface e a detecção foram testadas; a aplicação com administrador ainda passa pelo [plano de testes](docs/plano-de-testes.md). Use primeiro num PC de testes ou crie um ponto de restauração.

## Como usar

1. Dois cliques em **`src\Executar-Otimizador.bat`** e aceite o pedido de administrador.
2. **Início:** resumo do PC, classificação (Low/Mid/High-end) e perfil sugerido.
3. **Otimizar:** escolha um perfil (Básico, Trabalho, Gamer, PC simples) ou marque item por item. Use **Simular** para ver o que mudaria e **Aplicar** para executar.
4. Acompanhe cada item ficar verde ✓ ou vermelho ✗ (com o motivo). No final, o resumo diz se precisa reiniciar.

O menu de texto antigo (v1.1) continua em `src\Executar-Modo-Texto.bat`.

## O que tem

- **Verificar o PC:** nota de 0 a 100, o que já está otimizado e a saúde do sistema, com botão para resolver cada ponto.
- **67 ajustes** em 13 categorias, incluindo placa de vídeo, notebook e serviços.
- **Placa de vídeo:** modos Desempenho máximo / Balanceado / Qualidade, monitor na taxa máxima e guia do painel NVIDIA/AMD/Intel.
- **Notebook:** saúde da bateria e ajustes só para bateria. **Serviços:** desliga serviços desnecessários mostrando quanta RAM cada um usa.
- **Ferramentas:** DNS com teste de velocidade, programas de inicialização (liga/desliga), teste de servidor TCP, drivers USB-serial e portas COM, reparo do Windows (DISM/SFC com progresso), instalação de programas (winget), relatório do PC em HTML e atalhos do Windows.
- **Segurança:** ponto de restauração antes da primeira alteração, valores originais guardados por ajuste, desfazer individual ou total, histórico de execuções e log diário.
- Tema claro e escuro.

## Onde ficam os dados

`Documentos\OtimizadorVinicius\`: `log_<data>.txt`, `originais.json` (valores antes de cada ajuste), `historico.jsonl` e relatórios.

## Requisitos

Windows 10 ou 11, Windows PowerShell 5.1 (já vem no Windows) e uma conta de administrador.

## Estrutura

```
src/
  Executar-Otimizador.bat      abre a interface
  Otimizador-Vinicius-GUI.ps1  janela (WPF)
  nucleo.ps1                   motor: detectar / simular / aplicar / desfazer
  ferramentas.ps1              relatório, rede, inicialização, drivers, reparo, winget
  catalogo/*.ps1               os ajustes (um arquivo por categoria)
  ui/Janela.xaml, Modelos.cs   layout e modelos de tela
  Otimizador-Vinicius.ps1      v1.1 (modo texto)
config/   modelo da lista de programas do winget
docs/     revisão da v1.1, guia do catálogo, plano de testes
tools/    verificar.ps1 (codificação + sintaxe; rode antes de cada commit)
```

Para adicionar um ajuste, veja [docs/catalogo.md](docs/catalogo.md). Decisões de projeto e roadmap: [CLAUDE.md](CLAUDE.md).
