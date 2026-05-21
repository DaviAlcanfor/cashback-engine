include .env
export

.PHONY: install schema seed run reseed simulate script

install:
	pip install -r scripts/requirements.txt

schema:
	psql $(DB_URI) -f sql/schema.sql
	psql $(DB_URI) -f sql/functions.sql
	psql $(DB_URI) -f sql/triggers.sql
	psql $(DB_URI) -f sql/procedures.sql
	psql $(DB_URI) -f sql/views.sql

script:
	psql $(DB_URI) -f script.sql

seed:
	python scripts/dataload.py

simulate:
	python scripts/simulador.py

run: install schema seed

reseed: schema seed