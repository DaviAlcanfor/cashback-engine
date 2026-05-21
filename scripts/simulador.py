import time
import random
import psycopg2
from rich.console import Console
from rich.panel import Panel
from rich.text import Text
from dotenv import load_dotenv
import os
import sys
sys.stdout.reconfigure(encoding='utf-8') # resolve bug do rich no terminal

load_dotenv()

DB_URI = os.getenv("DB_URI")
console = Console()


def get_connection():
    return psycopg2.connect(DB_URI)


def buscar_dados_aleatorios(cur):
    cur.execute("""
        SELECT c.card_id, cl.nome, c.last4, v.nome AS variante,
               (c.limite_valor - c.limite_usado) AS limite_disponivel
        FROM cartao c
        JOIN cliente cl ON cl.client_id = c.client_id
        JOIN variante v ON v.variante_id = c.variante_id
        WHERE c.status = 'ATIVO'
          AND cl.status = 'ATIVO'
          AND (c.limite_valor - c.limite_usado) > 10 
        ORDER BY RANDOM()
        LIMIT 1
    """)
    card = cur.fetchone()

    cur.execute("""
        SELECT estabelecimento_id
        FROM estabelecimento
        WHERE status = 'ATIVO'
        ORDER BY RANDOM()
        LIMIT 1
    """)
    estab = cur.fetchone()

    return card, estab


def registrar_transacao(cur, card_id, estab_id, valor):
    tipo = random.choice(['DEBITO', 'CREDITO'])
    cur.execute(
        "CALL pr_registrar_transacao(%s, %s, %s::enum_tipo_transacao, %s)",
        (card_id, estab_id, tipo, valor)
    )


def buscar_resultado(cur, card_id, valor):
    cur.execute("""
        SELECT t.transacao_id, t.status, t.valor, t.tipo,
               cb.valor AS cashback_valor,
               cb.pct_aplicada,
               c.nome AS campanha_nome
        FROM transacao t
        LEFT JOIN cashback cb ON cb.transacao_id = t.transacao_id
        LEFT JOIN campanha_cashback c ON c.campanha_id = t.campanha_id
        WHERE t.card_id = %s
          AND t.valor = %s
        ORDER BY t.created_at DESC
        LIMIT 1
    """, (card_id, valor))

    return cur.fetchone()


def exibir_aprovada(nome, last4, valor, cashback_valor, cashback_pct, tipo, variante, campanha_nome):
    text = Text()
    text.append("✅ APROVADA\n", style="bold green")
    text.append(f"CLIENTE : {nome}\n", style="white")
    text.append(f"CARTÃO  : **** {last4} ({tipo})\n", style="white")
    text.append(f"VARIANTE: {variante}\n", style="cyan")
    text.append(f"VALOR   : R$ {valor:,.2f}\n", style="white")

    if cashback_valor:
        base = cashback_pct
        texto_cb = f"CASHBACK: R$ {cashback_valor:,.2f} ({base:.2f}%)"

        if campanha_nome:
            texto_cb += f"\nCAMPANHA: {campanha_nome}"
            texto_cb += f"\nCÁLCULO : R$ {valor:,.2f} × {base:.2f}% = R$ {cashback_valor:,.2f}"

        text.append(texto_cb, style="bold yellow")
    else:
        text.append("CASHBACK: —", style="dim")

    console.print(Panel(text, border_style="green", width=50))


def exibir_recusada(nome, last4, valor, motivo):
    text = Text()
    text.append("❌ RECUSADA\n", style="bold red")
    text.append(f"CLIENTE : {nome}\n", style="white")
    text.append(f"CARTÃO  : **** {last4}\n", style="white")
    text.append(f"VALOR   : R$ {valor:,.2f}\n", style="white")
    text.append(f"MOTIVO  : {motivo}", style="bold red")

    console.print(Panel(text, border_style="red", width=45))


def simular():
    console.print("\n[bold cyan]⚡ SIMULADOR DE TRANSAÇÕES — CASHBACK ENGINE[/bold cyan]\n")

    conn = get_connection()
    cur = conn.cursor()

    try:
        while True:
            card, estab = buscar_dados_aleatorios(cur)

            if not card or not estab:
                console.print("[yellow]Sem cartões com limite disponível, aguardando...[/yellow]")
                time.sleep(1)
                continue

            card_id, nome, last4, variante, limite_disponivel = card
            estab_id = estab[0]
            if random.random() < 0.2:
                valor = round(random.uniform(float(limite_disponivel), float(limite_disponivel) * 1.5), 2)
            else:
                valor = round(random.uniform(10, min(500, float(limite_disponivel))), 2)

            registrar_transacao(cur, card_id, estab_id, valor)
            conn.commit()

            resultado = buscar_resultado(cur, card_id, valor)

            if not resultado:
                continue

            t_id, status, t_valor, tipo, cb_valor, cb_pct, campanha_nome = resultado
            if status == 'APROVADA':
                exibir_aprovada(nome, last4, t_valor, cb_valor, cb_pct, tipo, variante, campanha_nome)
            else:
                # busca motivo no log
                cur.execute("""
                    SELECT motivo_recusa
                    FROM transacao
                    WHERE transacao_id = %s
                """, (t_id,))
                row = cur.fetchone()
                motivo = row[0] if row else 'RECUSADA'
                exibir_recusada(nome, last4, t_valor, motivo)

            time.sleep(1)

    except KeyboardInterrupt:
        console.print("\n[yellow]Simulador encerrado.[/yellow]")
    except Exception as e:
        print(f"ERRO: {e}")
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    simular()