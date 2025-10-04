EXTENSION = base58id
MODULES   = base58id
DATA      = base58id--1.0.sql

PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Optional: harden
CCFLAGS += -O2 -Wall -Wextra -Werror
