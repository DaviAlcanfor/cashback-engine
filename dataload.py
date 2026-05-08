import random
import psycopg2
from psycopg2.extras import execute_values
from loguru import logger
from faker import Faker
from datetime import date, timedelta
import os
from dotenv import load_dotenv

load_dotenv()

fake = Faker("pt_BR")

DB_URI = os.getenv("DB_URI")

NUM_ENDERECOS = 120
NUM_CLIENTES = 50
NUM_BINS = 10
NUM_CARTOES = 60
NUM_ESTABELECIMENTOS = 50
NUM_CAMPANHAS = 10
NUM_CAMPANHA_MCC = 20
NUM_TRANSACOES = 500
NUM_CASHBACKS = 300

ESTADOS = ["SP", "RJ", "MG", "RS", "BA", "PR", "PE", "CE", "SC", "GO"]
PROFILES = ["BAIXO", "MEDIO", "ALTO", "PREMIUM"]
STATUS_CLIENTE = ["ATIVO", "ATIVO", "ATIVO", "INATIVO", "BLOQUEADO"]
STATUS_CARTAO = ["ATIVO", "ATIVO", "ATIVO", "BLOQUEADO", "CANCELADO"]
STATUS_ESTAB = ["ATIVO", "ATIVO", "ATIVO", "INATIVO"]
STATUS_TRANSACAO = ["APROVADA", "APROVADA", "APROVADA", "RECUSADA", "CANCELADA", "PENDENTE"]
STATUS_CASHBACK = ["PENDENTE", "LIBERADO", "LIBERADO", "EXPIRADO"]
TIPOS_TRANSACAO = ["DEBITO", "CREDITO"]
TAMANHOS = ["MICRO", "PEQUENO", "MEDIO", "GRANDE"]
INSTALLMENTS = [1, 1, 1, 2, 3, 6, 12]

VARIANTES = [
    ("GOLD", 1.00, "Cartao Gold com 1% de cashback"),
    ("PLATINUM", 1.50, "Cartao Platinum com 1.5% de cashback"),
    ("BLACK", 2.00, "Cartao Black com 2% de cashback"),
]

LIMITES = [
    ("L1", "Limite Basico", 2000.00),
    ("L2", "Limite Padrao", 5000.00),
    ("L3", "Limite Plus", 10000.00),
    ("L4", "Limite Premium", 20000.00),
    ("L5", "Limite Black", 50000.00),
]

BANDEIRAS = [
    ("Visa", "Bandeira Visa"),
    ("Mastercard", "Bandeira Mastercard"),
    ("Elo", "Bandeira Elo"),
    ("Amex", "Bandeira American Express"),
]

BANCOS = ["Itau", "Bradesco", "Nubank", "C6 Bank", "Inter", "Santander", "BTG", "XP", "PicPay", "Neon"]

MCCS = [
    ("0001", "Fazenda e Agricultura"),
    ("0750", "Veterinario"),
    ("1520", "Construtora Geral"),
    ("1740", "Instalacoes Hidraulicas"),
    ("3001", "Companhia Aerea"),
    ("3500", "Locadora de Veiculos"),
    ("4111", "Transporte Local"),
    ("4411", "Transporte Maritimo"),
    ("4812", "Telefonia"),
    ("4900", "Energia Eletrica"),
    ("5045", "Computadores e Perifericos"),
    ("5200", "Material de Construcao"),
    ("5411", "Supermercado"),
    ("5812", "Restaurante"),
    ("6010", "Banco e Financeiras"),
    ("7011", "Hotel e Hospedagem"),
    ("7299", "Servicos Pessoais"),
    ("8011", "Medico"),
    ("8050", "Clinica e Hospital"),
    ("9311", "Governo Federal"),
]


def rand_date(start: date, end: date) -> date:
    return start + timedelta(days=random.randint(0, (end - start).days))


def rand_cpf() -> str:
    return "".join([str(random.randint(0, 9)) for _ in range(11)])


def rand_telefone() -> str:
    return f"119{''.join([str(random.randint(0, 9)) for _ in range(8)])}"


def rand_complemento() -> str | None:
    return random.choice([
        f"Apto {random.randint(1, 200)}",
        f"Casa {random.randint(1, 20)}",
        None,
        None,
    ])


def batch_insert(cur, tabela: str, colunas: list[str], rows: list[tuple]) -> list[int]:
    cols = ", ".join(colunas)
    result = execute_values(
        cur,
        f"INSERT INTO {tabela} ({cols}) VALUES %s RETURNING *",
        rows,
        fetch=True,
    )
    return [row[0] for row in result]


def get_pct_cashback(cur, card_id: int, campanha_id: int | None) -> float:
    if campanha_id:
        cur.execute(
            "SELECT cashback_pct FROM campanha_cashback WHERE campanha_id = %s",
            (campanha_id,)
        )
        row = cur.fetchone()
        if row:
            return float(row[0])
    cur.execute(
        """
        SELECT v.cashback_pct
        FROM cartao c
        JOIN variante v ON v.variante_id = c.variante_id
        WHERE c.card_id = %s
        """,
        (card_id,)
    )
    return float(cur.fetchone()[0])


def seed_enderecos(cur) -> list[int]:
    rows = [
        (
            "Brasil",
            random.choice(ESTADOS),
            fake.city(),
            fake.bairro(),
            fake.street_name(),
            str(random.randint(1, 9999)),
            rand_complemento(),
        )
        for _ in range(NUM_ENDERECOS)
    ]
    ids = batch_insert(cur, "endereco", ["pais", "estado", "cidade", "bairro", "rua", "numero", "complemento"], rows)
    logger.info(f"enderecos inseridos: {len(ids)}")
    return ids


def seed_clientes(cur, endereco_ids: list[int]) -> list[int]:
    cpfs_usados: set[str] = set()
    emails_usados: set[str] = set()
    rows = []

    for _ in range(NUM_CLIENTES):
        while True:
            cpf = rand_cpf()
            if cpf not in cpfs_usados:
                cpfs_usados.add(cpf)
                break
        while True:
            email = fake.email()
            if email not in emails_usados:
                emails_usados.add(email)
                break

        rows.append((
            fake.name(),
            cpf,
            email,
            rand_telefone(),
            rand_date(date(1960, 1, 1), date(2000, 12, 31)),
            random.choice(PROFILES),
            round(random.uniform(1500, 25000), 2),
            random.choice(STATUS_CLIENTE),
            random.choice(endereco_ids[:60]),
        ))

    ids = batch_insert(cur, "cliente", [
        "nome", "cpf", "email", "telefone", "data_nascimento",
        "profile", "renda_mensal", "status", "endereco_id"
    ], rows)
    logger.info(f"clientes inseridos: {len(ids)}")
    return ids


def seed_variantes(cur) -> list[int]:
    rows = [(nome, pct, desc) for nome, pct, desc in VARIANTES]
    ids = batch_insert(cur, "variante", ["nome", "cashback_pct", "descricao"], rows)
    logger.info(f"variantes inseridas: {len(ids)}")
    return ids


def seed_limite_tipos(cur) -> list[int]:
    rows = [(cod, desc, teto) for cod, desc, teto in LIMITES]
    ids = batch_insert(cur, "limite_tipo", ["codigo", "descricao", "valor_teto"], rows)
    logger.info(f"limite_tipos inseridos: {len(ids)}")
    return ids


def seed_bandeiras(cur) -> list[int]:
    rows = [(nome, desc) for nome, desc in BANDEIRAS]
    ids = batch_insert(cur, "bandeira", ["nome", "descricao"], rows)
    logger.info(f"bandeiras inseridas: {len(ids)}")
    return ids


def seed_bins(cur, bandeira_ids: list[int]) -> list[int]:
    bins_usados: set[str] = set()
    rows = []

    for i in range(NUM_BINS):
        while True:
            cod = str(random.randint(400000, 499999))
            if cod not in bins_usados:
                bins_usados.add(cod)
                break
        rows.append((cod, random.choice(bandeira_ids), BANCOS[i]))

    ids = batch_insert(cur, "bin", ["codigo", "bandeira_id", "banco"], rows)
    logger.info(f"bins inseridos: {len(ids)}")
    return ids


def seed_cartoes(cur, client_ids: list[int], bin_ids: list[int], variante_ids: list[int], limite_tipo_ids: list[int]) -> list[int]:
    cur.execute("SELECT limite_tipo_id, valor_teto FROM limite_tipo")
    tetos = {row[0]: float(row[1]) for row in cur.fetchall()}
    rows = []

    for _ in range(NUM_CARTOES):
        limite_tipo_id = random.choice(limite_tipo_ids)
        valor_teto = tetos[limite_tipo_id]
        limite_valor = round(random.uniform(valor_teto * 0.5, valor_teto), 2)
        limite_usado = round(random.uniform(0, limite_valor), 2)

        rows.append((
            random.choice(client_ids),
            random.choice(bin_ids),
            random.choice(variante_ids),
            limite_tipo_id,
            limite_valor,
            limite_usado,
            round(limite_usado * random.uniform(0.5, 1.0), 2),
            random.choice([True, False]),
            str(random.randint(1000, 9999)),
            random.choice(STATUS_CARTAO),
        ))

    ids = batch_insert(cur, "cartao", [
        "client_id", "bin_id", "variante_id", "limite_tipo_id",
        "limite_valor", "limite_usado", "valor_fatura", "fatura_paga", "last4", "status"
    ], rows)
    logger.info(f"cartoes inseridos: {len(ids)}")
    return ids


def seed_mccs(cur) -> list[int]:
    rows = [(cod, desc) for cod, desc in MCCS]
    ids = batch_insert(cur, "mcc", ["codigo", "descricao"], rows)
    logger.info(f"mccs inseridos: {len(ids)}")
    return ids


def seed_estabelecimentos(cur, mcc_ids: list[int], endereco_ids: list[int]) -> list[int]:
    rows = [
        (
            fake.company(),
            random.choice(mcc_ids),
            random.choice(endereco_ids[60:]),
            random.choice(TAMANHOS),
            random.choice(STATUS_ESTAB),
        )
        for _ in range(NUM_ESTABELECIMENTOS)
    ]
    ids = batch_insert(cur, "estabelecimento", ["nome", "mcc_id", "endereco_id", "tamanho", "status"], rows)
    logger.info(f"estabelecimentos inseridos: {len(ids)}")
    return ids


def seed_campanhas(cur) -> list[int]:
    hoje = date.today()
    rows = []

    for i in range(NUM_CAMPANHAS):
        inicio = rand_date(date(2024, 1, 1), hoje)
        fim = inicio + timedelta(days=random.randint(30, 180))
        rows.append((
            f"Campanha {fake.word().capitalize()} {i+1}",
            round(random.uniform(0.5, 5.0), 2),
            round(random.uniform(50, 500), 2),
            inicio,
            fim,
            "ATIVA" if fim >= hoje else "ENCERRADA",
        ))

    ids = batch_insert(cur, "campanha_cashback", [
        "nome", "cashback_pct", "bonus_limite", "data_inicio", "data_fim", "status"
    ], rows)
    logger.info(f"campanhas inseridas: {len(ids)}")
    return ids


def seed_campanha_mcc(cur, campanha_ids: list[int], mcc_ids: list[int]) -> None:
    pares_usados: set[tuple[int, int]] = set()
    rows = []

    for _ in range(NUM_CAMPANHA_MCC):
        for _ in range(10):
            par = (random.choice(campanha_ids), random.choice(mcc_ids))
            if par not in pares_usados:
                pares_usados.add(par)
                rows.append(par)
                break

    execute_values(cur, "INSERT INTO campanha_mcc (campanha_id, mcc_id) VALUES %s", rows)
    logger.info(f"campanha_mcc inseridos: {len(rows)}")


def seed_transacoes(cur, card_ids: list[int], estab_ids: list[int], campanha_ids: list[int]) -> list[int]:
    campanha_ids_com_none = campanha_ids + [None, None, None]
    rows = [
        (
            random.choice(card_ids),
            random.choice(estab_ids),
            random.choice(campanha_ids_com_none),
            random.choice(TIPOS_TRANSACAO),
            round(random.uniform(10, 3000), 2),
            random.choice(INSTALLMENTS),
            random.choice(STATUS_TRANSACAO),
        )
        for _ in range(NUM_TRANSACOES)
    ]
    ids = batch_insert(cur, "transacao", [
        "card_id", "estabelecimento_id", "campanha_id",
        "tipo", "valor", "installments", "status"
    ], rows)
    logger.info(f"transacoes inseridas: {len(ids)}")
    return ids


def seed_cashbacks(cur) -> None:
    cur.execute(
        "SELECT transacao_id, card_id, campanha_id, valor FROM transacao WHERE status = 'APROVADA'"
    )
    transacoes_aprovadas = cur.fetchall()
    amostra = random.sample(transacoes_aprovadas, min(NUM_CASHBACKS, len(transacoes_aprovadas)))

    cur.execute("SELECT card_id, cashback_pct FROM cartao JOIN variante USING (variante_id)")
    pct_por_cartao = {row[0]: float(row[1]) for row in cur.fetchall()}

    cur.execute("SELECT campanha_id, cashback_pct FROM campanha_cashback")
    pct_por_campanha = {row[0]: float(row[1]) for row in cur.fetchall()}

    rows = []
    for t_id, card_id, campanha_id, valor_transacao in amostra:
        pct = pct_por_campanha.get(campanha_id) or pct_por_cartao.get(card_id, 1.0)
        valor_cb = round(float(valor_transacao) * (pct / 100), 2)
        status_cb = random.choice(STATUS_CASHBACK)
        rows.append((
            t_id,
            valor_cb,
            pct,
            status_cb,
            fake.date_time_this_year() if status_cb == "LIBERADO" else None,
        ))

    execute_values(cur, "INSERT INTO cashback (transacao_id, valor, pct_aplicada, status, data_liberacao) VALUES %s", rows)
    logger.info(f"cashbacks inseridos: {len(rows)}")


def main():
    logger.info("Iniciando dataload...")
    conn = psycopg2.connect(DB_URI)
    cur = conn.cursor()

    try:
        endereco_ids = seed_enderecos(cur)
        client_ids = seed_clientes(cur, endereco_ids)
        variante_ids = seed_variantes(cur)
        limite_tipo_ids = seed_limite_tipos(cur)
        bandeira_ids = seed_bandeiras(cur)
        bin_ids = seed_bins(cur, bandeira_ids)
        card_ids = seed_cartoes(cur, client_ids, bin_ids, variante_ids, limite_tipo_ids)
        mcc_ids = seed_mccs(cur)
        estab_ids = seed_estabelecimentos(cur, mcc_ids, endereco_ids)
        campanha_ids = seed_campanhas(cur)
        seed_campanha_mcc(cur, campanha_ids, mcc_ids)
        seed_transacoes(cur, card_ids, estab_ids, campanha_ids)
        seed_cashbacks(cur)

        conn.commit()
        logger.success("Dataload concluido com sucesso!")
    except Exception as e:
        conn.rollback()
        logger.error(f"Erro durante o dataload: {e}")
        raise
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    main()