-- ============================================================
-- RESET
-- ============================================================

DROP VIEW IF EXISTS vw_painel_cliente  CASCADE;

DROP TRIGGER   IF EXISTS trg_validar_transacao        ON transacao;
DROP TRIGGER   IF EXISTS trg_processar_transacao      ON transacao;
DROP TRIGGER   IF EXISTS trg_liberar_cashback         ON transacao;
DROP TRIGGER   IF EXISTS trg_log_transacao            ON transacao;
DROP TRIGGER   IF EXISTS trg_log_cashback             ON cashback;
DROP TRIGGER   IF EXISTS trg_log_global_transacao     ON transacao;
DROP TRIGGER   IF EXISTS trg_log_global_cashback      ON cashback;

DROP PROCEDURE IF EXISTS pr_registrar_transacao(INT,INT,enum_tipo_transacao,NUMERIC,INT) CASCADE;
DROP PROCEDURE IF EXISTS pr_expirar_cashbacks()                                          CASCADE;

DROP FUNCTION  IF EXISTS tr_validar_transacao()                     CASCADE;
DROP FUNCTION  IF EXISTS tr_processar_transacao()                   CASCADE;
DROP FUNCTION  IF EXISTS tr_liberar_cashback()                      CASCADE;
DROP FUNCTION  IF EXISTS tr_log_transacao()                         CASCADE;
DROP FUNCTION  IF EXISTS tr_log_cashback()                          CASCADE;
DROP FUNCTION  IF EXISTS tr_log_global()                            CASCADE;
DROP FUNCTION  IF EXISTS fn_buscar_pct_vigente(INT, INT, TIMESTAMP) CASCADE;
DROP FUNCTION  IF EXISTS fn_validar_cartao(INT, NUMERIC)            CASCADE;
DROP FUNCTION  IF EXISTS fn_buscar_campanha(INT, TIMESTAMPTZ)       CASCADE;
DROP FUNCTION  IF EXISTS fn_calcular_cashback(INT, INT, NUMERIC)    CASCADE;
DROP FUNCTION  IF EXISTS fn_mcc_categoria(VARCHAR)                  CASCADE;
DROP FUNCTION  IF EXISTS fn_age_group(DATE)                         CASCADE;

DROP TABLE     IF EXISTS log_global        CASCADE;
DROP TABLE     IF EXISTS log_cashback      CASCADE;
DROP TABLE     IF EXISTS log_transacao     CASCADE;
DROP TABLE     IF EXISTS cashback          CASCADE;
DROP TABLE     IF EXISTS transacao         CASCADE;
DROP TABLE     IF EXISTS campanha_mcc      CASCADE;
DROP TABLE     IF EXISTS campanha_cashback CASCADE;
DROP TABLE     IF EXISTS estabelecimento   CASCADE;
DROP TABLE     IF EXISTS mcc               CASCADE;
DROP TABLE     IF EXISTS cartao            CASCADE;
DROP TABLE     IF EXISTS bin               CASCADE;
DROP TABLE     IF EXISTS bandeira          CASCADE;
DROP TABLE     IF EXISTS limite_tipo       CASCADE;
DROP TABLE     IF EXISTS variante          CASCADE;
DROP TABLE     IF EXISTS cliente           CASCADE;
DROP TABLE     IF EXISTS endereco          CASCADE;

DROP TYPE      IF EXISTS enum_estabelecimento   CASCADE;
DROP TYPE      IF EXISTS enum_operacao_log      CASCADE;
DROP TYPE      IF EXISTS enum_status_cashback   CASCADE;
DROP TYPE      IF EXISTS enum_status_campanha   CASCADE;
DROP TYPE      IF EXISTS enum_status_transacao  CASCADE;
DROP TYPE      IF EXISTS enum_tipo_transacao    CASCADE;
DROP TYPE      IF EXISTS enum_status_cartao     CASCADE;
DROP TYPE      IF EXISTS enum_status_estab      CASCADE;
DROP TYPE      IF EXISTS enum_tamanho           CASCADE;
DROP TYPE      IF EXISTS enum_variante          CASCADE;
DROP TYPE      IF EXISTS enum_status_cliente    CASCADE;
DROP TYPE      IF EXISTS enum_profile           CASCADE;
DROP TYPE      IF EXISTS enum_motivo_recusa     CASCADE;

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
CREATE TYPE enum_motivo_recusa AS ENUM ('CARTAO_NAO_ENCONTRADO','CARTAO_BLOQUEADO_OU_CANCELADO','CLIENTE_INATIVO_OU_BLOQUEADO','LIMITE_INSUFICIENTE');

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
    created_at         TIMESTAMP             NOT NULL DEFAULT CURRENT_TIMESTAMP,
    motivo_recusa      enum_motivo_recusa
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

-- ============================================================
-- FUNCTIONS
-- ============================================================

CREATE OR REPLACE FUNCTION fn_buscar_pct_vigente(
    p_card_id      INT,
    p_estab_id     INT,
    p_data_compra  TIMESTAMP
)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    v_mcc_id       INT;
    v_pct_campanha NUMERIC(5,2);
    v_pct_variante NUMERIC(5,2);
BEGIN
    -- pega o mcc do estabelecimento
    SELECT mcc_id INTO v_mcc_id
    FROM estabelecimento
    WHERE estabelecimento_id = p_estab_id;

    -- busca campanha vigente na data da compra para esse mcc
    SELECT c.cashback_pct INTO v_pct_campanha
    FROM campanha_cashback c
    JOIN campanha_mcc cm ON cm.campanha_id = c.campanha_id
    WHERE 1=1
	  AND cm.mcc_id = v_mcc_id
      AND c.status = 'ATIVA'
      AND p_data_compra::DATE BETWEEN c.data_inicio AND c.data_fim
    ORDER BY c.cashback_pct DESC
    LIMIT 1;

    -- se encontrou campanha retorna ela
    IF v_pct_campanha IS NOT NULL THEN
        RETURN v_pct_campanha;
    END IF;

    -- senao retorna o padrao da variante do cartao
    SELECT v.cashback_pct INTO v_pct_variante
    FROM cartao c
    JOIN variante v ON v.variante_id = c.variante_id
    WHERE c.card_id = p_card_id;

    RETURN v_pct_variante;
END;
$$;


CREATE OR REPLACE FUNCTION fn_validar_cartao(
    p_card_id INT,
    p_valor NUMERIC
)
RETURNS TABLE (
    valido BOOLEAN,
    motivo enum_motivo_recusa
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status_cartao     enum_status_cartao;
    v_status_cliente    enum_status_cliente;
    v_limite_disponivel NUMERIC(10,2);
BEGIN

    SELECT
        c.status,
        cl.status,
        (c.limite_valor - c.limite_usado)
    INTO
        v_status_cartao,
        v_status_cliente,
        v_limite_disponivel
    FROM cartao c
    JOIN cliente cl ON cl.client_id = c.client_id
    WHERE c.card_id = p_card_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'CARTAO_NAO_ENCONTRADO'::enum_motivo_recusa;
        RETURN;
    END IF;

    IF v_status_cartao <> 'ATIVO' THEN
        RETURN QUERY SELECT FALSE, 'CARTAO_BLOQUEADO_OU_CANCELADO'::enum_motivo_recusa;
        RETURN;
    END IF;

    IF v_status_cliente <> 'ATIVO' THEN
        RETURN QUERY SELECT FALSE, 'CLIENTE_INATIVO_OU_BLOQUEADO'::enum_motivo_recusa;
        RETURN;
    END IF;

    IF p_valor > v_limite_disponivel THEN
        RETURN QUERY SELECT FALSE, 'LIMITE_INSUFICIENTE'::enum_motivo_recusa;
        RETURN;
    END IF;

    RETURN QUERY SELECT TRUE, NULL::enum_motivo_recusa;
END;
$$;


CREATE OR REPLACE FUNCTION fn_buscar_campanha(
    p_mcc_id INT,
    p_data TIMESTAMPTZ
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_campanha_id INT;
BEGIN
    SELECT c.campanha_id
    INTO v_campanha_id
    FROM campanha_cashback c
    JOIN campanha_mcc cm ON cm.campanha_id = c.campanha_id
    WHERE 1=1
      AND cm.mcc_id = p_mcc_id
      AND c.status = 'ATIVA'
      AND p_data::DATE BETWEEN c.data_inicio AND c.data_fim
    ORDER BY c.cashback_pct DESC
    LIMIT 1;

    RETURN v_campanha_id;
END;
$$;


CREATE OR REPLACE FUNCTION fn_calcular_cashback(
    p_card_id INT,
    p_estabelecimento_id INT,
    p_valor NUMERIC
)
RETURNS TABLE (
    cashback_valor NUMERIC,
    cashback_pct   NUMERIC,
    campanha_id    INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_mcc_id       INT;
    v_variante_pct NUMERIC(5,2);
    v_campanha_pct NUMERIC(5,2);
    v_pct_final    NUMERIC(5,2);
    v_campanha_id  INT;
BEGIN

    SELECT e.mcc_id
    INTO v_mcc_id
    FROM estabelecimento e
    WHERE e.estabelecimento_id = p_estabelecimento_id;

    SELECT v.cashback_pct
    INTO v_variante_pct
    FROM cartao c
    JOIN variante v ON v.variante_id = c.variante_id
    WHERE c.card_id = p_card_id;

    v_campanha_id := fn_buscar_campanha(v_mcc_id, CURRENT_TIMESTAMP);

    IF v_campanha_id IS NOT NULL THEN
        SELECT cc.cashback_pct
        INTO v_campanha_pct
        FROM campanha_cashback cc
        WHERE cc.campanha_id = v_campanha_id;
    ELSE
        v_campanha_pct := 0;
    END IF;

    v_pct_final := v_variante_pct + v_campanha_pct;

    RETURN QUERY
    SELECT
        ROUND((p_valor * v_pct_final / 100), 2),
        v_pct_final::NUMERIC,
        v_campanha_id;

END;
$$;




-- ============================================================
-- TRIGGER VALIDAR TRANSAÇÃO
-- ============================================================

CREATE OR REPLACE FUNCTION tr_validar_transacao()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_valido BOOLEAN;
    v_motivo enum_motivo_recusa;
BEGIN

    SELECT
        valido,
        motivo
    INTO
        v_valido,
        v_motivo
    FROM fn_validar_cartao(
        NEW.card_id,
        NEW.valor
    );

    -- aprovada
	IF v_valido THEN
	    NEW.status := 'APROVADA';
	ELSE
	    NEW.status        := 'RECUSADA';
	    NEW.motivo_recusa := v_motivo;
	
	    RAISE NOTICE
	        'TRANSACAO RECUSADA | CARD_ID: % | MOTIVO: %',
	        NEW.card_id,
	        v_motivo;
	END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_transacao
BEFORE INSERT
ON transacao
FOR EACH ROW
EXECUTE FUNCTION tr_validar_transacao();

-- ============================================================
-- TRIGGER PROCESSAR TRANSAÇÃO
-- ============================================================

CREATE OR REPLACE FUNCTION tr_processar_transacao()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_cashback_valor NUMERIC(10,2);
    v_cashback_pct   NUMERIC(5,2);
    v_campanha_id    INT;
BEGIN

    -- processa apenas aprovadas
    IF NEW.status <> 'APROVADA' THEN
        RETURN NEW;
    END IF;

    -- calcula cashback
    SELECT
        cashback_valor,
        cashback_pct,
        campanha_id
    INTO
        v_cashback_valor,
        v_cashback_pct,
        v_campanha_id
    FROM fn_calcular_cashback(
        NEW.card_id,
        NEW.estabelecimento_id,
        NEW.valor
    );

    -- atualiza campanha
    UPDATE transacao
    SET campanha_id = v_campanha_id
    WHERE transacao_id = NEW.transacao_id;

    -- atualiza cartão
    UPDATE cartao
    SET
        limite_usado = limite_usado + NEW.valor,
        valor_fatura = valor_fatura + NEW.valor
    WHERE card_id = NEW.card_id;

    -- cria cashback
    IF v_cashback_valor > 0 THEN
        INSERT INTO cashback (transacao_id,valor,pct_aplicada, status)
        VALUES ( NEW.transacao_id, v_cashback_valor,  v_cashback_pct,  'PENDENTE');
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_processar_transacao
AFTER INSERT
ON transacao
FOR EACH ROW
EXECUTE FUNCTION tr_processar_transacao();

-- ============================================================
-- TRIGGER LIBERAR CASHBACK
-- ============================================================

CREATE OR REPLACE FUNCTION tr_liberar_cashback()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.status <> 'APROVADA'
       AND NEW.status = 'APROVADA'
    THEN
        UPDATE cashback
        SET status = 'LIBERADO',
            data_liberacao = CURRENT_TIMESTAMP
        WHERE transacao_id = NEW.transacao_id;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_liberar_cashback
AFTER UPDATE
ON transacao
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION tr_liberar_cashback();

-- ============================================================
-- TRIGGER LOG TRANSAÇÃO
-- ============================================================

CREATE OR REPLACE FUNCTION tr_log_transacao()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    INSERT INTO log_transacao (transacao_id, status_antes, status_depois)
	VALUES (NEW.transacao_id, OLD.status,NEW.status);

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_log_transacao
AFTER UPDATE
ON transacao
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION tr_log_transacao();

-- ============================================================
-- TRIGGER LOG CASHBACK
-- ============================================================

CREATE OR REPLACE FUNCTION tr_log_cashback()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    INSERT INTO log_cashback (cashback_id, status_antes, status_depois)
    VALUES ( NEW.cashback_id,  OLD.status, NEW.status);

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_log_cashback
AFTER UPDATE
ON cashback
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION tr_log_cashback();

-- ============================================================
-- TRIGGER LOG GLOBAL
-- ============================================================

CREATE OR REPLACE FUNCTION tr_log_global()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    -- INSERT
    IF TG_OP = 'INSERT' THEN

        INSERT INTO log_global ( tabela,operacao,dado_novo)
        VALUES ( TG_TABLE_NAME,'INSERT',to_jsonb(NEW));

        RETURN NEW;
    END IF;

    -- UPDATE
    IF TG_OP = 'UPDATE' THEN

        INSERT INTO log_global (tabela, operacao,dado_antigo, dado_novo)
        VALUES ( TG_TABLE_NAME,'UPDATE', to_jsonb(OLD),to_jsonb(NEW));

        RETURN NEW;
    END IF;

    -- DELETE
    IF TG_OP = 'DELETE' THEN

        INSERT INTO log_global (tabela,operacao, dado_antigo)
        VALUES (TG_TABLE_NAME, 'DELETE', to_jsonb(OLD));

        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_log_global_transacao
AFTER INSERT OR UPDATE OR DELETE
ON transacao
FOR EACH ROW
EXECUTE FUNCTION tr_log_global();

CREATE TRIGGER trg_log_global_cashback
AFTER INSERT OR UPDATE OR DELETE
ON cashback
FOR EACH ROW
EXECUTE FUNCTION tr_log_global();
-- ============================================================
-- PROCEDURE REGISTRAR TRANSAÇÃO
-- ============================================================

CREATE OR REPLACE PROCEDURE pr_registrar_transacao(
    IN p_card_id            INT,
    IN p_estabelecimento_id INT,
    IN p_tipo               enum_tipo_transacao,
    IN p_valor              NUMERIC,
    IN p_installments       INT DEFAULT 1
)
LANGUAGE plpgsql
AS $$
BEGIN

    INSERT INTO transacao (
        card_id,
        estabelecimento_id,
        tipo,
        valor,
        installments
    )
    VALUES (
        p_card_id,
        p_estabelecimento_id,
        p_tipo,
        p_valor,
        p_installments
    );

END;
$$;


CREATE OR REPLACE PROCEDURE pr_expirar_cashbacks()
LANGUAGE plpgsql
AS $$
DECLARE
    v_total INT := 0;
BEGIN
    -- expira cashbacks pendentes de clientes inativos por mais de 1 ano
    UPDATE cashback cb
    SET status = 'EXPIRADO'
    FROM transacao t
    JOIN cartao ca ON ca.card_id = t.card_id
    JOIN cliente cl ON cl.client_id = ca.client_id
    WHERE cb.transacao_id = t.transacao_id
      AND cb.status = 'PENDENTE'
      AND cl.status != 'ATIVO'
      AND cb.created_at < CURRENT_TIMESTAMP - INTERVAL '1 year';

    GET DIAGNOSTICS v_total = ROW_COUNT;

    RAISE NOTICE 'Cashbacks expirados: %', v_total;
END;
$$;

create or replace VIEW vw_painel_cliente AS
SELECT
    c.client_id,
    c.nome,
    c.cpf,
    c.profile,
    c.age_group,
    ca.card_id,
    ca.last4,
    v.nome          AS variante,
    lt.codigo       AS limite_tipo,
    ca.limite_valor,
    ca.limite_usado,
    (ca.limite_valor - ca.limite_usado) AS limite_disponivel,
    ca.valor_fatura,
    ca.fatura_paga,
    ca.status 		AS status_cartao,
    b.nome 			AS bandeira,
    bn.banco 		AS emissor,
    COALESCE(SUM(cb.valor) FILTER (WHERE cb.status = 'LIBERADO'), 0)  AS cashback_disponivel,
    COALESCE(SUM(cb.valor) FILTER (WHERE cb.status = 'PENDENTE'), 0)  AS cashback_pendente,
    COALESCE(SUM(cb.valor) FILTER (WHERE cb.status = 'EXPIRADO'), 0)  AS cashback_expirado
FROM cliente c
	JOIN cartao ca       
		ON ca.client_id = c.client_id
	JOIN variante v      
		ON v.variante_id = ca.variante_id
	JOIN limite_tipo lt 
		ON lt.limite_tipo_id = ca.limite_tipo_id
	JOIN bin bn         
		ON bn.bin_id = ca.bin_id
	JOIN bandeira b    
		ON b.bandeira_id = bn.bandeira_id
	LEFT JOIN transacao t  
		ON t.card_id     = ca.card_id AND t.status = 'APROVADA'
	LEFT JOIN cashback cb  
		ON cb.transacao_id = t.transacao_id
GROUP BY
    c.client_id, c.nome, c.cpf, c.profile, c.age_group,
    ca.card_id, ca.last4, v.nome, lt.codigo,
    ca.limite_valor, ca.limite_usado, ca.valor_fatura,
    ca.fatura_paga, ca.status, b.nome, bn.banco; 
-- group by all resolveria se tivesse
