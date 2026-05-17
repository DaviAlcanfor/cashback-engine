# cashback-engine

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-blue?logo=postgresql)
![Python](https://img.shields.io/badge/Python-3.11+-yellow?logo=python)
![License](https://img.shields.io/badge/license-MIT-green)

> Motor transacional de cashback construído inteiramente em PostgreSQL, com dataload e simulador em Python.

## O Problema

Sistemas de cashback simples não têm transparência: o cliente não sabe se o valor está pendente ou disponível, não há rastreabilidade das campanhas aplicadas, e regras de negócio ficam espalhadas na aplicação. Qualquer falha no código pode liberar cashback indevido ou deixar valores presos indefinidamente.

## A Solução

Toda a lógica de negócio vive dentro do banco:

- **Campanhas temporárias** com vigência por data e segmentação por categoria de estabelecimento (MCC)
- **Cashback calculado automaticamente** com a porcentagem correta — campanha vigente somada ao padrão da variante do cartão
- **Liberação controlada por trigger** — o cashback só muda de `PENDENTE` para `LIBERADO` após confirmação do pagamento da fatura
- **Validação de transação** — cartão, cliente e limite são verificados antes de qualquer aprovação via `fn_validar_cartao`
- **Auditoria completa** via logs específicos por entidade e log global em JSONB

## Fluxo Transacional

```mermaid
flowchart TD
    A[Cliente passa o cartão] --> B[fn_validar_cartao]
    B --> C{Cartão e cliente ativos?\nLimite suficiente?}
    C -->|Não| E[Transação RECUSADA\nmotivo_recusa preenchido]
    C -->|Sim| F[Transação APROVADA]
    F --> G{Campanha vigente\npara o MCC?}
    G -->|Sim| H[% campanha + % variante]
    G -->|Não| I[% base da variante]
    H --> J[fn_calcular_cashback]
    I --> J
    J --> K[Cashback PENDENTE criado]
    K --> L{Fatura paga?}
    L -->|Sim| N[Trigger libera Cashback]
    N --> O[Cashback LIBERADO]
    L -->|Não| P{Conta inativa\n+1 ano?}
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
- `cliente` — dados do portador com perfil de risco e faixa etária calculada automaticamente via função imutável
- `bandeira` / `bin` — identificação do emissor a partir dos 6 primeiros dígitos do cartão
- `variante` — tipo do cartão (Gold, Platinum, Black) com porcentagem base de cashback
- `limite_tipo` — níveis de limite (L1 a L5) com teto fixo

**Cartão**
- `cartao` — vínculo entre cliente, BIN, variante e limite; controla `limite_usado`, `valor_fatura` e `fatura_paga`

**Estabelecimento**
- `mcc` — código de categoria do estabelecimento (padrão internacional); categoria derivada automaticamente do código via função imutável
- `estabelecimento` — empresa credenciada com vínculo ao MCC e endereço

**Campanhas e Transações**
- `campanha_cashback` — campanhas com vigência por `data_inicio` / `data_fim` e bônus de limite temporário
- `campanha_mcc` — segmentação da campanha por categoria de estabelecimento (N:N)
- `transacao` — registro de cada compra com status, motivo de recusa e vínculo ao cartão, estabelecimento e campanha vigente
- `cashback` — valor calculado por transação aprovada com porcentagem aplicada e status de ciclo de vida

**Auditoria**
- `log_transacao` — rastreia mudanças de status de cada transação
- `log_cashback` — rastreia o ciclo `PENDENTE → LIBERADO → EXPIRADO`
- `log_global` — audit trail genérico em JSONB para as demais tabelas

## Objetos de Banco

**Functions**
- `fn_validar_cartao` — valida status do cartão, do cliente e limite disponível antes de aprovar
- `fn_buscar_campanha` — busca a campanha ativa vigente na data da compra para o MCC do estabelecimento
- `fn_calcular_cashback` — soma a porcentagem da campanha com a base da variante e calcula o valor final
- `fn_buscar_pct_vigente` — retorna a porcentagem vigente na data exata da compra
- `fn_age_group` / `fn_mcc_categoria` — colunas geradas automaticamente via função imutável

**Triggers**
- `trg_validar_transacao` — valida e define o status antes do INSERT via `fn_validar_cartao`
- `trg_processar_transacao` — após aprovação, atualiza limite do cartão e cria o cashback
- `trg_liberar_cashback` — libera o cashback quando a transação é confirmada
- `trg_log_transacao` / `trg_log_cashback` — auditoria específica de mudanças de status
- `trg_log_global_transacao` / `trg_log_global_cashback` — audit trail completo em JSONB usando `TG_OP`, `OLD`, `NEW` e `CURRENT_USER`

**Procedures**
- `pr_registrar_transacao` — ponto de entrada do sistema; dispara toda a cadeia de triggers
- `pr_expirar_cashbacks` — expira automaticamente cashbacks pendentes de contas inativas por mais de 1 ano

**View**
- `vw_painel_cliente` — extrato completo por cartão com limite disponível, valor de fatura e cashback separado por status

## Simulador

O simulador gera transações em tempo real contra o banco, exibindo o resultado no terminal com output colorido via `rich`:

```bash
make simulate
```

```
✅ APROVADA
CLIENTE  : Ryan Dias
CARTÃO   : **** 3633 (CREDITO)
VARIANTE : BLACK
VALOR    : R$ 3,129.92
CASHBACK : R$ 62.60 (2.00%)
CAMPANHA : Campanha Eveniet 10
CÁLCULO  : R$ 3,129.92 × 2.00% = R$ 62.60

❌ RECUSADA
CLIENTE  : Enzo Barbosa
CARTÃO   : **** 8169
VALOR    : R$ 2,317.57
MOTIVO   : CLIENTE_INATIVO_OU_BLOQUEADO
```

## Estrutura do Projeto

```
cashback-engine/
    sql/
        schema.sql
        functions.sql
        triggers.sql
        procedures.sql
        views.sql
    dataload/
        dataload.py
        requirements.txt
    scripts/
        simulador.py
    script.sql
    .env.example
    Makefile
    README.md
```

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
make reseed    # limpa e repopula os dados
make schema    # recria só a estrutura
make seed      # popula sem recriar a estrutura
make simulate  # inicia o simulador de transações
make script    # executa o script.sql consolidado no banco
```

## Configuração

```env
DB_URI=postgresql://usuario:senha@host:porta/banco?sslmode=require
```
