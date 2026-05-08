# cashback-engine

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-blue?logo=postgresql)
![Python](https://img.shields.io/badge/Python-3.11+-yellow?logo=python)
![License](https://img.shields.io/badge/license-MIT-green)

> Motor transacional de cashback construído inteiramente em PostgreSQL, com dataload em Python.

## O Problema

Sistemas de cashback simples não têm transparência: o cliente não sabe se o valor está pendente ou disponível, não há rastreabilidade das campanhas aplicadas, e regras de negócio ficam espalhadas na aplicação. Qualquer falha no código pode liberar cashback indevido ou deixar valores presos indefinidamente.

## A Solução

Toda a lógica de negócio vive dentro do banco:

- **Campanhas temporárias** com vigência por data e segmentação por categoria de estabelecimento (MCC)
- **Cashback calculado automaticamente** com a porcentagem correta — campanha vigente ou padrão da variante do cartão
- **Liberação controlada por trigger** — o cashback só muda de `PENDENTE` para `LIBERADO` após confirmação do pagamento da fatura
- **Auditoria completa** via logs específicos por entidade e log global em JSONB

## Fluxo Transacional

```mermaid
flowchart TD
    A[Cliente passa o cartão] --> B[Valida BIN e Bandeira]
    B --> C[Verifica limite disponível]
    C --> D{Limite OK?}
    D -->|Não| E[Transação RECUSADA]
    D -->|Sim| F[Cria Transação PENDENTE]
    F --> G{Campanha vigente\npara o MCC?}
    G -->|Sim| H[Usa % da Campanha]
    G -->|Não| I[Usa % da Variante do Cartão]
    H --> J[Cria Cashback PENDENTE]
    I --> J
    J --> K[Transação APROVADA]
    K --> L{Fatura paga?}
    L -->|Não| M[Cashback permanece PENDENTE]
    L -->|Sim| N[Trigger libera Cashback]
    N --> O[Cashback LIBERADO]
    M --> P{Conta inativa\n+1 ano?}
    P -->|Sim| Q[Procedure expira Cashback]
    Q --> R[Cashback EXPIRADO]
```

## Relação entre Tabelas

```mermaid
erDiagram
    endereco ||--o{ cliente : "mora em"
    endereco ||--o{ estabelecimento : "localizado em"

    cliente ||--o{ cartao : "possui"
    bandeira ||--o{ bin : "identifica"
    bin ||--o{ cartao : "prefixo de"
    variante ||--o{ cartao : "tipo de"
    limite_tipo ||--o{ cartao : "nível de"

    mcc ||--o{ estabelecimento : "categoriza"
    mcc }o--o{ campanha_cashback : "campanha_mcc"

    cartao ||--o{ transacao : "realiza"
    estabelecimento ||--o{ transacao : "recebe"
    campanha_cashback ||--o{ transacao : "aplicada em"

    transacao ||--o| cashback : "gera"

    transacao ||--o{ log_transacao : "auditada em"
    cashback ||--o{ log_cashback : "auditado em"
```

## Arquitetura do Banco

O modelo é composto por 16 tabelas normalizadas organizadas em camadas:

**Cadastro base**
- `endereco` — endereços compartilhados entre clientes e estabelecimentos
- `cliente` — dados do portador com perfil de risco e faixa etária calculada automaticamente
- `bandeira` / `bin` — identificação do emissor a partir dos 6 primeiros dígitos do cartão
- `variante` — tipo do cartão (Gold, Platinum, Black) com porcentagem base de cashback
- `limite_tipo` — níveis de limite (L1 a L5) com teto fixo

**Cartão**
- `cartao` — vínculo entre cliente, BIN, variante e limite; controla `limite_usado` e `fatura_paga`

**Estabelecimento**
- `mcc` — código de categoria do estabelecimento (padrão internacional); categoria derivada automaticamente do código via função imutável
- `estabelecimento` — empresa credenciada com vínculo ao MCC e endereço

**Campanhas e Transações**
- `campanha_cashback` — campanhas com vigência por `data_inicio` / `data_fim` e bônus de limite temporário
- `campanha_mcc` — segmentação da campanha por categoria de estabelecimento (N:N)
- `transacao` — registro de cada compra com vínculo ao cartão, estabelecimento e campanha vigente
- `cashback` — valor calculado por transação aprovada com porcentagem aplicada e status de ciclo de vida

**Auditoria**
- `log_transacao` — rastreia mudanças de status de cada transação
- `log_cashback` — rastreia o ciclo `PENDENTE → LIBERADO → EXPIRADO`
- `log_global` — audit trail genérico em JSONB para as demais tabelas

## Como Rodar

**Pré-requisitos**
- PostgreSQL 14+
- Python 3.11+

**Instalação e execução**

```bash
cp .env.example .env
# edite o .env com sua URI do banco
make run
```

**Outros comandos**

```bash
make reseed   # limpa e repopula os dados
make schema   # recria só a estrutura
make seed     # popula sem recriar a estrutura
```

## Configuração

```env
DB_URI=postgresql://usuario:senha@host:porta/banco?sslmode=require
```
