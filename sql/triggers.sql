-- ============================================================
-- DROP TRIGGERS
-- ============================================================

DROP TRIGGER IF EXISTS trg_validar_transacao       ON transacao;
DROP TRIGGER IF EXISTS trg_processar_transacao     ON transacao;
DROP TRIGGER IF EXISTS trg_liberar_cashback        ON transacao;
DROP TRIGGER IF EXISTS trg_log_transacao           ON transacao;
DROP TRIGGER IF EXISTS trg_log_cashback            ON cashback;
DROP TRIGGER IF EXISTS trg_log_global_transacao    ON transacao;
DROP TRIGGER IF EXISTS trg_log_global_cashback     ON cashback;

-- ============================================================
-- DROP TRIGGER FUNCTIONS
-- ============================================================

DROP FUNCTION IF EXISTS tr_validar_transacao() CASCADE;
DROP FUNCTION IF EXISTS tr_processar_transacao() CASCADE;
DROP FUNCTION IF EXISTS tr_liberar_cashback() CASCADE;
DROP FUNCTION IF EXISTS tr_log_transacao() CASCADE;
DROP FUNCTION IF EXISTS tr_log_cashback() CASCADE;
DROP FUNCTION IF EXISTS tr_log_global() CASCADE;

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
