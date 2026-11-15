# Mercado

Plugin do [Omarchy shell](https://omarchy.org) com cotações do Yahoo Finance: um ativo na barra (o dólar, por padrão) e um painel com ações da B3, índices e moedas.

## Instalação

```bash
omarchy plugin add https://github.com/LoganMerazzi/omarchy-mercado.git --enable
```

Não depende de nada além do `python3`: o helper usa só a biblioteca padrão e não precisa de chave de API.

## Configuração

Nas configurações do widget na barra:

- **Ativos:** símbolos do Yahoo Finance separados por vírgula. Tickers da B3, como `PETR4`, ganham `.SA` automaticamente. Padrão: `USDBRL=X, ^BVSP, PETR4, VALE3, ITUB4`
- **Ativo exibido na barra:** padrão `USDBRL=X`
- **Intervalo de atualização:** padrão 120 s. As respostas ficam em cache em `~/.cache/omarchy-mercado`.

## Atualizar

```bash
omarchy plugin update logan.mercado && omarchy restart shell
```
