DROP FUNCTION IF EXISTS fn_buscar_pct_vigente(INT, INT, TIMESTAMP) CASCADE;
DROP FUNCTION IF EXISTS fn_validar_cartao(INT, NUMERIC) CASCADE;
DROP FUNCTION IF EXISTS fn_buscar_campanha(INT, TIMESTAMP) CASCADE;
DROP FUNCTION IF EXISTS fn_calcular_cashback(INT, INT, NUMERIC) CASCADE;


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
    v_validade          DATE;
BEGIN

    SELECT
        c.status,
        cl.status,
        (c.limite_valor - c.limite_usado),
        c.validade
    INTO
        v_status_cartao,
        v_status_cliente,
        v_limite_disponivel,
        v_validade
    FROM cartao c
    JOIN cliente cl
        ON cl.client_id = c.client_id
    WHERE c.card_id = p_card_id;

    -- cartão inexistente
    IF NOT FOUND THEN

        RETURN QUERY
        SELECT
            FALSE,
            'CARTAO_NAO_ENCONTRADO'::enum_motivo_recusa;
        RETURN;
    END IF;

    -- cartão inválido
    IF v_status_cartao <> 'ATIVO' THEN

        RETURN QUERY
        SELECT
            FALSE,
            'CARTAO_BLOQUEADO_OU_CANCELADO'::enum_motivo_recusa;
        RETURN;
    END IF;

    -- cliente inválido
    IF v_status_cliente <> 'ATIVO' THEN

        RETURN QUERY
        SELECT
            FALSE,
            'CLIENTE_INATIVO_OU_BLOQUEADO'::enum_motivo_recusa;
        RETURN;
    END IF;

    -- validade
    IF v_validade < CURRENT_DATE THEN

        RETURN QUERY
        SELECT
            FALSE,
            'CARTAO_EXPIRADO'::enum_motivo_recusa;

        RETURN;
    END IF;

    -- limite
    IF p_valor > v_limite_disponivel THEN

        RETURN QUERY
        SELECT
            FALSE,
            'LIMITE_INSUFICIENTE'::enum_motivo_recusa;
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        TRUE,
        NULL::enum_motivo_recusa;
END;
$$;
	


CREATE OR REPLACE FUNCTION fn_buscar_campanha(
    p_mcc_id INT,
    p_data TIMESTAMP
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
    JOIN campanha_mcc cm
        ON cm.campanha_id = c.campanha_id
    WHERE
        cm.mcc_id = p_mcc_id
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
    cashback_pct NUMERIC,
    campanha_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_mcc_id INT;
    v_variante_pct NUMERIC(5,2);
    v_campanha_pct NUMERIC(5,2);
    v_pct_final NUMERIC(5,2);
    v_campanha_id INT;
BEGIN

    -- busca MCC do estabelecimento
    SELECT e.mcc_id
    INTO v_mcc_id
    FROM estabelecimento e
    WHERE e.estabelecimento_id = p_estabelecimento_id;

    -- busca cashback base da variante
    SELECT v.cashback_pct
    INTO v_variante_pct
    FROM cartao c
    JOIN variante v
        ON v.variante_id = c.variante_id
    WHERE c.card_id = p_card_id;

    -- busca campanha
    v_campanha_id := fn_buscar_campanha(v_mcc_id, CURRENT_TIMESTAMP);

    -- cashback campanha
    IF v_campanha_id IS NOT NULL THEN

        SELECT cashback_pct
        INTO v_campanha_pct
        FROM campanha_cashback
        WHERE campanha_id = v_campanha_id;

    ELSE
        v_campanha_pct := 0;
    END IF;

    -- regra final
    v_pct_final := v_variante_pct + v_campanha_pct;

    RETURN QUERY
    SELECT
        ROUND((p_valor * v_pct_final / 100), 2),
        v_pct_final,
        v_campanha_id;

END;
$$;


