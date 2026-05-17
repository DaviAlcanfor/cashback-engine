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
