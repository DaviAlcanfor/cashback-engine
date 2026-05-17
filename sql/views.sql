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
