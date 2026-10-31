# Otimizador Vinicius

Otimizador de Windows 10/11 em PowerShell: ajustes de mouse, teclado, energia, jogos, interface e privacidade, além de ferramentas de rede, inicialização, drivers USB-serial, relatório do PC e winget. Tudo com backup e ponto de restauração antes de qualquer alteração.

> ⚠️ **Versão 1.1 ainda não testada em Windows real.** Use em VM ou PC de testes.

## Como usar

1. Baixe a pasta `src/`.
2. Dê dois cliques em `Executar-Otimizador.bat` (o script pede elevação para administrador).
3. Escolha as opções no menu.

### Lista de programas personalizada (opcional)

Copie `config/winget-lista-exemplo.txt` para `src/winget-lista.txt` (ao lado do script) e edite. Formato: `Id;Nome`, um por linha.

## Onde ficam os dados

`Documentos\OtimizadorVinicius\`

- `Backups\<data_hora>\` – `.reg` de cada chave alterada e `dns.json`
- `log_<data>.txt` – transcrição da sessão
- `Relatorio_PC_<data>.html` – relatório gerado pela opção **H**

## Como desfazer

- Opção **R** no menu: reimporta os `.reg` de um backup e restaura o DNS.
- Para reverter 100% (inclusive valores que não existiam antes): use o ponto de restauração criado pelo script.

## Requisitos

- Windows 10 ou 11
- Windows PowerShell 5.1 (já vem no Windows)
- Conta de administrador

## Estrutura

```
src/        script, atalho .bat, catálogo (v1.2) e interface XAML (v2.0)
config/     modelos de configuração
docs/       documentação
```

Roadmap e decisões de projeto: ver [CLAUDE.md](CLAUDE.md).
