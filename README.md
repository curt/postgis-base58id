# postgis-base58id

A PostgreSQL extension providing a native **base58id** data type: a 64-bit unsigned integer stored compactly (8 bytes, pass-by-value) with automatic Base58 encoding for text I/O. All values are zero-padded to 11 characters for consistent formatting. Designed for time-based distributed IDs (Snowflake, Sonyflake, etc.) that display as short, URL-safe strings without requiring wide character columns.

## Features

- **Compact storage**: 8 bytes, pass-by-value (same as `bigint`)
- **Base58 encoding**: Bitcoin alphabet (no `0OIl` ambiguity), zero-padded to 11 characters
- **Full operator support**: Comparison operators (`<`, `<=`, `=`, `>=`, `>`, `<>`)
- **Indexable**: B-tree and hash operator classes included
- **Cast support**: Bidirectional casts with `bigint` and `text`
- **Binary I/O**: Efficient `COPY` and client protocol support
- **Uniform hash distribution**: Uses PostgreSQL's `hash_any()` for optimal hash index performance

## Project Structure

```
.
├── extension/
│   ├── base58id.c              # C implementation (encoding, I/O, operators)
│   ├── base58id--1.0.sql       # SQL type/function definitions
│   ├── base58id.control        # Extension metadata
│   └── Makefile                # PGXS build (for "make install")
├── docker/
│   └── initdb/
│       └── 01-enable-base58id.sql  # Auto-enable extension on container init
├── Dockerfile.ext              # Final runtime image (FROM PostGIS base + extension)
├── Makefile                    # Orchestrates multi-stage build
└── dist/                       # Staged extension files (created by "make dist")
```

## Build Process Overview

The build is a **multi-stage pipeline** designed for ARM64 Alpine Linux, orchestrated by the root [Makefile](Makefile):

1. **`make base`**: Builds a PostGIS-enabled PostgreSQL base image from upstream sources
   (no official ARM64 Alpine PostGIS images exist, so we compile from `docker-postgis` repo)

2. **`make dev-image`**: Creates a cached builder image with PostgreSQL headers, `clang`, `llvm`, and build tools

3. **`make dist`**: Compiles the `base58id` extension inside the dev container and stages installed files to `./dist/`

4. **`make ext`**: Builds the final runtime image by copying `dist/usr/` into the PostGIS base

5. **`make all`**: Runs the full pipeline (`base` → `dev-image` → `dist` → `ext`)

## Usage

### Quick Start

```bash
# Build everything (takes ~10-15 min on first run due to PostGIS compilation)
make all

# Run a test container
make run

# Connect to the database
docker exec -it pg-test psql -U postgres
```

### Using the Extension

```sql
-- Enable the extension
CREATE EXTENSION base58id;

-- Create a table with base58id primary key
CREATE TABLE events (
    id base58id PRIMARY KEY,
    payload jsonb
);

-- Insert a Snowflake-style ID (e.g., from application)
-- Note: All base58id values are zero-padded to 11 characters
INSERT INTO events VALUES ('1111MKNMDHF', '{"event": "user.login"}');

-- Query by ID (displays as 11-char base58, compares as uint64)
SELECT * FROM events WHERE id = '1111MKNMDHF';

-- Cast to/from bigint (output is always 11 characters)
SELECT '1111MKNMDHF'::base58id::bigint;       -- 987654321
SELECT 987654321::bigint::base58id;            -- '1111MKNMDHF'
SELECT 0::bigint::base58id;                    -- '11111111111'

-- Range queries work naturally (IDs are time-ordered if using Snowflake)
SELECT id, payload FROM events WHERE id > '1111MKNMDHF' ORDER BY id LIMIT 10;
```

## Makefile Targets

| Target       | Description                                                                 |
|--------------|-----------------------------------------------------------------------------|
| `base`       | Build PostGIS base image from upstream (ARM64 only)                        |
| `dev-image`  | Build cached builder image with PostgreSQL dev headers + clang/llvm       |
| `dist`       | Compile extension and stage to `./dist/`                                   |
| `ext`        | Build final runtime image (PostGIS + base58id extension)                  |
| `all`        | Full pipeline (default)                                                    |
| `run`        | Start test container with extension pre-installed                         |
| `clean`      | Remove `./dist/` directory                                                 |

## Configuration

Edit variables at the top of [Makefile](Makefile):

```makefile
PG_MAJOR        ?= 17                          # PostgreSQL version
POSTGIS_REF     ?= 17-3.4-alpine               # PostGIS upstream tag
PLATFORMS       ?= linux/arm64                 # Target architecture
REGISTRY        ?= local                       # Image registry prefix
```

For **multi-platform builds** (e.g., AMD64 + ARM64), change `PLATFORMS` and ensure Docker Buildx is configured.

## Development Workflow

### Local Extension Development

```bash
# Edit extension/base58id.c or extension/base58id--1.0.sql
vim extension/base58id.c

# Rebuild and test
make dist ext run
docker exec -it pg-test psql -U postgres -c "DROP EXTENSION base58id; CREATE EXTENSION base58id;"
```

### Testing Changes

```bash
# Run container with auto-loaded extension
make run

# Connect and test
docker exec -it pg-test psql -U postgres <<SQL
  CREATE EXTENSION base58id;
  SELECT 0::bigint::base58id;                    -- '11111111111'
  SELECT 1::bigint::base58id;                    -- '11111111112'
  SELECT '11111111112'::base58id::bigint;        -- 1
SQL
```

## Notes for Time-Based Flake IDs

If using Snowflake/Sonyflake-style IDs (timestamp in MSBs):

- ✅ **B-tree indexes**: Excellent clustering and range query performance
- ✅ **Hash indexes**: Use `hash_any()` for uniform distribution (see [base58id.c:217](extension/base58id.c#L217))
- ⚠️ **Hot spot contention**: Monotonic IDs cause right-edge B-tree growth; tune `fillfactor` if needed

## Author

**Curt Gilman**

## License

MIT License - see [LICENSE](LICENSE) for details
