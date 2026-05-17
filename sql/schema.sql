-- ============================================================
-- RESET
-- ============================================================
DROP TABLE IF EXISTS log_global          CASCADE;
DROP TABLE IF EXISTS log_cashback        CASCADE;
DROP TABLE IF EXISTS log_transacao       CASCADE;
DROP TABLE IF EXISTS cashback            CASCADE;
DROP TABLE IF EXISTS transacao           CASCADE;
DROP TABLE IF EXISTS campanha_mcc        CASCADE;
DROP TABLE IF EXISTS campanha_cashback   CASCADE;
DROP TABLE IF EXISTS estabelecimento     CASCADE;
DROP TABLE IF EXISTS mcc                 CASCADE;
DROP TABLE IF EXISTS cartao              CASCADE;
DROP TABLE IF EXISTS bin                 CASCADE;
DROP TABLE IF EXISTS bandeira            CASCADE;
DROP TABLE IF EXISTS limite_tipo         CASCADE;
DROP TABLE IF EXISTS variante            CASCADE;
DROP TABLE IF EXISTS cliente             CASCADE;
DROP TABLE IF EXISTS endereco            CASCADE;

DROP FUNCTION IF EXISTS fn_mcc_categoria(VARCHAR) CASCADE;

DROP TYPE IF EXISTS enum_estabelecimento  CASCADE;
DROP TYPE IF EXISTS enum_operacao_log     CASCADE;
DROP TYPE IF EXISTS enum_status_cashback  CASCADE;
DROP TYPE IF EXISTS enum_status_campanha  CASCADE;
DROP TYPE IF EXISTS enum_status_transacao CASCADE;
DROP TYPE IF EXISTS enum_tipo_transacao   CASCADE;
DROP TYPE IF EXISTS enum_status_cartao    CASCADE;
DROP TYPE IF EXISTS enum_status_estab     CASCADE;
DROP TYPE IF EXISTS enum_tamanho          CASCADE;
DROP TYPE IF EXISTS enum_variante         CASCADE;
DROP TYPE IF EXISTS enum_status_cliente   CASCADE;
DROP TYPE IF EXISTS enum_profile          CASCADE;
DROP TYPE IF EXISTS enum_motivo_recusa    CASCADE;

-- ============================================================
-- ENUMS
-- ============================================================
CREATE TYPE enum_profile          AS ENUM ('BAIXO', 'MEDIO', 'ALTO', 'PREMIUM');
CREATE TYPE enum_status_cliente   AS ENUM ('ATIVO', 'INATIVO', 'BLOQUEADO');
CREATE TYPE enum_variante         AS ENUM ('GOLD', 'PLATINUM', 'BLACK');
CREATE TYPE enum_estabelecimento  AS ENUM ('RESTAURANTE', 'MERCADO', 'AGRICOLA', 'TRANSPORTE', 'COMERCIO', 'SAUDE', 'VIAGEM', 'VESTUARIO', 'UTILIDADE', 'GOVERNO', 'CONSTRUCAO');
CREATE TYPE enum_tamanho          AS ENUM ('MICRO', 'PEQUENO', 'MEDIO', 'GRANDE');
CREATE TYPE enum_status_estab     AS ENUM ('ATIVO', 'INATIVO');
CREATE TYPE enum_status_cartao    AS ENUM ('ATIVO', 'BLOQUEADO', 'CANCELADO');
CREATE TYPE enum_tipo_transacao   AS ENUM ('DEBITO', 'CREDITO');
CREATE TYPE enum_status_transacao AS ENUM ('PENDENTE', 'APROVADA', 'RECUSADA', 'CANCELADA');
CREATE TYPE enum_status_campanha  AS ENUM ('ATIVA', 'ENCERRADA');
CREATE TYPE enum_status_cashback  AS ENUM ('PENDENTE', 'LIBERADO', 'EXPIRADO');
CREATE TYPE enum_operacao_log     AS ENUM ('INSERT', 'UPDATE', 'DELETE');
CREATE TYPE enum_motivo_recusa    AS ENUM ('LIMITE_INSUFICIENTE','CARTAO_EXPIRADO','CLIENTE_BLOQUEADO','CARTAO_CANCELADO');

-- ============================================================
-- ENDERECO
-- ============================================================
CREATE TABLE endereco (
    endereco_id SERIAL       PRIMARY KEY,
    pais        VARCHAR(50)  NOT NULL DEFAULT 'Brasil',
    estado      VARCHAR(2)   NOT NULL,
    cidade      VARCHAR(100) NOT NULL,
    bairro      VARCHAR(100) NOT NULL,
    rua         VARCHAR(150) NOT NULL,
    numero      VARCHAR(10)  NOT NULL,
    complemento VARCHAR(100),
    created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- CLIENTE
-- ============================================================


CREATE OR REPLACE FUNCTION fn_age_group(data_nascimento DATE)
RETURNS TEXT
IMMUTABLE
LANGUAGE SQL
AS $$
    SELECT CASE
        WHEN EXTRACT(YEAR FROM AGE(data_nascimento)) < 18 THEN 'MENOR'
        WHEN EXTRACT(YEAR FROM AGE(data_nascimento)) < 25 THEN '18-24'
        WHEN EXTRACT(YEAR FROM AGE(data_nascimento)) < 35 THEN '25-34'
        WHEN EXTRACT(YEAR FROM AGE(data_nascimento)) < 50 THEN '35-49'
        ELSE '50+'
    END;
$$;

CREATE TABLE cliente (
    client_id       SERIAL              PRIMARY KEY,
    nome            VARCHAR(150)        NOT NULL,
    cpf             VARCHAR(11)         NOT NULL UNIQUE,
    email           VARCHAR(150)        NOT NULL UNIQUE,
    telefone        VARCHAR(15),
    data_nascimento DATE                NOT NULL,
    age_group TEXT GENERATED ALWAYS AS (fn_age_group(data_nascimento)) STORED,
    profile         enum_profile        NOT NULL,
    renda_mensal    NUMERIC(10,2)       NOT NULL CHECK (renda_mensal >= 0),
    status          enum_status_cliente NOT NULL DEFAULT 'ATIVO',
    endereco_id     INT                 NOT NULL REFERENCES endereco(endereco_id),
    created_at      TIMESTAMP           NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- VARIANTE
-- ============================================================
CREATE TABLE variante (
    variante_id  SERIAL        PRIMARY KEY,
    nome         enum_variante NOT NULL UNIQUE,
    cashback_pct NUMERIC(5,2)  NOT NULL CHECK (cashback_pct >= 0),
    descricao    TEXT
);

-- ============================================================
-- LIMITE_TIPO
-- ============================================================
CREATE TABLE limite_tipo (
    limite_tipo_id SERIAL        PRIMARY KEY,
    codigo         VARCHAR(5)    NOT NULL UNIQUE,
    descricao      VARCHAR(100)  NOT NULL,
    valor_teto     NUMERIC(10,2) NOT NULL CHECK (valor_teto > 0)
);

-- ============================================================
-- BANDEIRA
-- ============================================================
CREATE TABLE bandeira (
    bandeira_id SERIAL      PRIMARY KEY,
    nome        VARCHAR(50) NOT NULL UNIQUE,
    descricao   TEXT
);

-- ============================================================
-- BIN
-- ============================================================
CREATE TABLE bin (
    bin_id      SERIAL       PRIMARY KEY,
    codigo      VARCHAR(6)   NOT NULL UNIQUE CHECK (codigo ~ '^[0-9]{6}$'),
    bandeira_id INT          NOT NULL REFERENCES bandeira(bandeira_id),
    banco       VARCHAR(100) NOT NULL,
    created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- CARTAO
-- ============================================================
CREATE TABLE cartao (
    card_id        SERIAL             PRIMARY KEY,
    client_id      INT                NOT NULL REFERENCES cliente(client_id),
    bin_id         INT                NOT NULL REFERENCES bin(bin_id),
    variante_id    INT                NOT NULL REFERENCES variante(variante_id),
    limite_tipo_id INT                NOT NULL REFERENCES limite_tipo(limite_tipo_id),
    limite_valor   NUMERIC(10,2)      NOT NULL CHECK (limite_valor > 0),
    limite_usado   NUMERIC(10,2)      NOT NULL DEFAULT 0 CHECK (limite_usado >= 0),
    valor_fatura   NUMERIC(10,2)      NOT NULL DEFAULT 0 CHECK (valor_fatura >= 0),
    fatura_paga    BOOLEAN            NOT NULL DEFAULT FALSE,
    validade       DATE               NOT NULL,
    last4          VARCHAR(4)         NOT NULL CHECK (last4 ~ '^[0-9]{4}$'),
    status         enum_status_cartao NOT NULL DEFAULT 'ATIVO',
    created_at     TIMESTAMP          NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- MCC
-- ============================================================
CREATE OR REPLACE FUNCTION fn_mcc_categoria(codigo VARCHAR)
RETURNS enum_estabelecimento
IMMUTABLE
LANGUAGE SQL
AS $$
    SELECT CASE
        WHEN codigo::INT BETWEEN 0    AND 1499 THEN 'AGRICOLA'::enum_estabelecimento
        WHEN codigo::INT BETWEEN 1500 AND 2999 THEN 'CONSTRUCAO'::enum_estabelecimento
        WHEN codigo::INT BETWEEN 3000 AND 3999 THEN 'VIAGEM'::enum_estabelecimento
        WHEN codigo::INT BETWEEN 4000 AND 4799 THEN 'TRANSPORTE'::enum_estabelecimento
        WHEN codigo::INT BETWEEN 4800 AND 4999 THEN 'UTILIDADE'::enum_estabelecimento
        WHEN codigo::INT BETWEEN 5000 AND 5699 THEN 'COMERCIO'::enum_estabelecimento
        WHEN codigo::INT BETWEEN 5700 AND 7299 THEN 'RESTAURANTE'::enum_estabelecimento
        WHEN codigo::INT BETWEEN 7300 AND 7999 THEN 'COMERCIO'::enum_estabelecimento
        WHEN codigo::INT BETWEEN 8000 AND 8999 THEN 'SAUDE'::enum_estabelecimento
        ELSE 'GOVERNO'::enum_estabelecimento
    END;
$$;

CREATE TABLE mcc (
    mcc_id    SERIAL                 PRIMARY KEY,
    codigo    VARCHAR(4)             NOT NULL UNIQUE CHECK (codigo ~ '^[0-9]{4}$'),
    categoria enum_estabelecimento  NOT NULL GENERATED ALWAYS AS (fn_mcc_categoria(codigo)) STORED,
    descricao VARCHAR(100)           NOT NULL
);

-- ============================================================
-- ESTABELECIMENTO
-- ============================================================
CREATE TABLE estabelecimento (
    estabelecimento_id SERIAL             PRIMARY KEY,
    nome               VARCHAR(150)       NOT NULL,
    mcc_id             INT                NOT NULL REFERENCES mcc(mcc_id),
    endereco_id        INT                NOT NULL REFERENCES endereco(endereco_id),
    tamanho            enum_tamanho       NOT NULL,
    status             enum_status_estab  NOT NULL DEFAULT 'ATIVO',
    created_at         TIMESTAMP          NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- CAMPANHA_CASHBACK
-- ============================================================
CREATE TABLE campanha_cashback (
    campanha_id  SERIAL               PRIMARY KEY,
    nome         VARCHAR(150)         NOT NULL,
    cashback_pct NUMERIC(5,2)         NOT NULL CHECK (cashback_pct >= 0),
    bonus_limite NUMERIC(10,2)        NOT NULL DEFAULT 0 CHECK (bonus_limite >= 0),
    data_inicio  DATE                 NOT NULL,
    data_fim     DATE                 NOT NULL,
    status       enum_status_campanha NOT NULL DEFAULT 'ATIVA',
    created_at   TIMESTAMP            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_datas CHECK (data_fim > data_inicio)
);

-- ============================================================
-- CAMPANHA_MCC
-- ============================================================
CREATE TABLE campanha_mcc (
    campanha_id INT NOT NULL REFERENCES campanha_cashback(campanha_id),
    mcc_id      INT NOT NULL REFERENCES mcc(mcc_id),
    PRIMARY KEY (campanha_id, mcc_id)
);

-- ============================================================
-- TRANSACAO
-- ============================================================
CREATE TABLE transacao (
    transacao_id       SERIAL                PRIMARY KEY,
    card_id            INT                   NOT NULL REFERENCES cartao(card_id),
    estabelecimento_id INT                   NOT NULL REFERENCES estabelecimento(estabelecimento_id),
    campanha_id        INT                   REFERENCES campanha_cashback(campanha_id),
    tipo               enum_tipo_transacao   NOT NULL,
    valor              NUMERIC(10,2)         NOT NULL CHECK (valor > 0),
    installments       INT                   NOT NULL DEFAULT 1 CHECK (installments >= 1),
    status             enum_status_transacao NOT NULL DEFAULT 'PENDENTE',
    created_at         TIMESTAMP             NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- CASHBACK
-- ============================================================
CREATE TABLE cashback (
    cashback_id    SERIAL               PRIMARY KEY,
    transacao_id   INT                  NOT NULL REFERENCES transacao(transacao_id),
    valor          NUMERIC(10,2)        NOT NULL CHECK (valor >= 0),
    pct_aplicada   NUMERIC(5,2)         NOT NULL CHECK (pct_aplicada >= 0),
    status         enum_status_cashback NOT NULL DEFAULT 'PENDENTE',
    data_liberacao TIMESTAMP,
    created_at     TIMESTAMP            NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- LOG_TRANSACAO
-- ============================================================
CREATE TABLE log_transacao (
    log_id        SERIAL                PRIMARY KEY,
    transacao_id  INT                   NOT NULL REFERENCES transacao(transacao_id),
    status_antes  enum_status_transacao NOT NULL,
    status_depois enum_status_transacao NOT NULL,
    alterado_por  TEXT                  NOT NULL DEFAULT CURRENT_USER,
    created_at    TIMESTAMP             NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- LOG_CASHBACK
-- ============================================================
CREATE TABLE log_cashback (
    log_id        SERIAL               PRIMARY KEY,
    cashback_id   INT                  NOT NULL REFERENCES cashback(cashback_id),
    status_antes  enum_status_cashback NOT NULL,
    status_depois enum_status_cashback NOT NULL,
    alterado_por  TEXT                 NOT NULL DEFAULT CURRENT_USER,
    created_at    TIMESTAMP            NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- LOG_GLOBAL
-- ============================================================
CREATE TABLE log_global (
    log_id       SERIAL            PRIMARY KEY,
    tabela       TEXT              NOT NULL,
    operacao     enum_operacao_log NOT NULL,
    dado_antigo  JSONB,
    dado_novo    JSONB,
    alterado_por TEXT              NOT NULL DEFAULT CURRENT_USER,
    created_at   TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP
);



-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX idx_cliente_status
ON cliente(status);

CREATE INDEX idx_cartao_cliente
ON cartao(client_id);

CREATE INDEX idx_cartao_status
ON cartao(status);

CREATE INDEX idx_transacao_card
ON transacao(card_id);

CREATE INDEX idx_transacao_status
ON transacao(status);

CREATE INDEX idx_cashback_status
ON cashback(status);

CREATE INDEX idx_campanha_periodo
ON campanha_cashback(data_inicio, data_fim);

CREATE INDEX idx_estabelecimento_mcc
ON estabelecimento(mcc_id);
