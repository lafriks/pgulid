EXTENSION = pgulid
DATA = pgulid--1.0.sql
PGFILEDESC = "pgULID - An ULID generation extension for PostgreSQL"

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
