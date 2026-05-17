include .env
export

.PHONY: install schema seed run reseed simulate

install:
	pip install -r dataload/requirements.txt

schema:
	psql $(DB_URI) -f sql/schema.sql
	psql $(DB_URI) -f sql/functions.sql
	psql $(DB_URI) -f sql/triggers.sql
	psql $(DB_URI) -f sql/procedures.sql
	psql $(DB_URI) -f sql/views.sql

seed:
	python dataload/dataload.py

simulate:
	python scripts/simulator.py

run: install schema seed

reseed: schema seed