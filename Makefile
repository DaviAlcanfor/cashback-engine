include .env
export

.PHONY: install schema seed run reseed

install:
	pip install -r dataload/requirements.txt

schema:
	psql $(DB_URI) -f sql/schema.sql

seed:
	python dataload/dataload.py

run: install schema seed

reseed: schema seed