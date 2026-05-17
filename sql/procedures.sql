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
