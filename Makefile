# =========================
# Config
# =========================
PG_MAJOR        ?= 17
POSTGIS_VERSION ?= 17-3.5# PostgreSQL major - PostGIS major version
POSTGIS_VARIANT ?= alpine
PLATFORMS       ?= linux/arm64

# Upstream PostGIS base (we BUILD this from source for arm64) and local image names
REGISTRY        ?= local
BASE_IMAGE      ?= $(REGISTRY)/postgis:$(POSTGIS_VERSION)-$(POSTGIS_VARIANT)-arm64
EXT_IMAGE       ?= $(REGISTRY)/postgis-base58id:$(POSTGIS_VERSION)-$(POSTGIS_VARIANT)-arm64

# Upstream PG Alpine base we use for the dev toolchain image
BASE_PG_IMAGE   ?= postgres:$(PG_MAJOR)-alpine
DEV_IMAGE       ?= postgres-dev:$(PG_MAJOR)-alpine   # local, cached toolchain

# Where "make install DESTDIR=" stages files
DIST_DIR        ?= dist

SHELL := bash
.ONESHELL:
.SILENT:

# =========================
# Helpers
# =========================
builder:
	docker buildx inspect alpine-builder >/dev/null 2>&1 || \
	  docker buildx create --name alpine-builder --use
	docker buildx use alpine-builder
	echo "→ buildx ready for $(PLATFORMS)"

# =========================
# Targets
# =========================

## Build the PostGIS Alpine image for ARM64 from upstream sources (no prebuilt available)
base: builder
	echo "→ Building PostGIS base $(BASE_IMAGE) (VERSION=$(POSTGIS_VERSION) VARIANT=$(POSTGIS_VARIANT)) for $(PLATFORMS)"
	rm -rf .tmp-postgis
	git clone --depth=1 https://github.com/postgis/docker-postgis.git .tmp-postgis
	cd .tmp-postgis && \
	  VERSION=$(POSTGIS_VERSION) VARIANT=$(POSTGIS_VARIANT) make build && \
	  docker tag postgis/postgis:$(POSTGIS_VERSION)-$(POSTGIS_VARIANT) $(BASE_IMAGE)
	rm -rf .tmp-postgis
	echo "→ Built $(BASE_IMAGE)"

## Build a cached dev image with all build deps (clang/llvm included) so we don't apk add each time
dev-image: builder
	echo "→ Building $(DEV_IMAGE) (FROM $(BASE_PG_IMAGE)) for $(PLATFORMS)"
	{ \
	  echo 'ARG PG_MAJOR=$(PG_MAJOR)'; \
	  echo 'ARG BASE_PG_IMAGE=$(BASE_PG_IMAGE)'; \
	  echo 'FROM $${BASE_PG_IMAGE}'; \
	  echo ''; \
	  echo 'RUN set -euo pipefail && \'; \
	  echo '    apk add --no-cache \'; \
	  echo '      build-base \'; \
	  echo '      make \'; \
	  echo '      ca-certificates \'; \
	  echo '      postgresql$${PG_MAJOR}-dev \'; \
	  echo '      clang19 \'; \
	  echo '      llvm19'; \
	} | docker buildx build \
	  --platform=$(PLATFORMS) \
	  --pull \
	  -t $(DEV_IMAGE) \
	  -f- \
	  --build-arg PG_MAJOR=$(PG_MAJOR) \
	  --build-arg BASE_PG_IMAGE=$(BASE_PG_IMAGE) \
	  --load \
	  .
	echo "→ Built $(DEV_IMAGE)"

## Compile the extension using the dev image and stage to ./dist
dist: dev-image
	echo "→ Compiling extension with $(DEV_IMAGE) for $(PLATFORMS)"
	rm -rf "$(DIST_DIR)"; mkdir -p "$(DIST_DIR)"
	docker run --rm --platform=$(PLATFORMS) --user root \
	  -v "$$(pwd)/extension:/src/extension" \
	  -v "$$(pwd)/$(DIST_DIR):/out" \
	  -e PG_MAJOR=$(PG_MAJOR) \
	  $(DEV_IMAGE) \
	  sh -lc '\
	    set -euo pipefail; \
	    make -C /src/extension clean; \
	    make -C /src/extension; \
	    make -C /src/extension install DESTDIR=/out; \
	    chown -R 1000:1000 /out \
	  '
	echo "→ Staged files under $(DIST_DIR)/usr/ ..."

## Build the final runtime image: FROM PostGIS base, then COPY the staged extension files
ext: base dist
	test -f Dockerfile.ext || { echo "Missing Dockerfile.ext (needs to COPY dist/usr/ /)"; exit 1; }
	echo "→ Building runtime image $(EXT_IMAGE) FROM $(BASE_IMAGE)"
	docker build \
	  --platform=$(PLATFORMS) \
	  -t $(EXT_IMAGE) \
	  --build-arg BASE_IMAGE=$(BASE_IMAGE) \
	  -f Dockerfile.ext \
	  .
	echo "→ Built $(EXT_IMAGE)"

## Convenience: build everything
all: ext

## Smoke test the final image locally
run:
	docker rm -f pg-test >/dev/null 2>&1 || true
	docker run -d --name pg-test --rm -e POSTGRES_PASSWORD=dev -p 5432:5432 $(EXT_IMAGE)
	echo "→ Waiting for server..." ; sleep 6
	docker exec -u postgres pg-test psql -U postgres -c "\dx"
	echo "→ Try: docker exec -it pg-test psql -U postgres"

## Clean staged outputs
clean:
	rm -rf "$(DIST_DIR)"

.PHONY: builder base dev-image dist ext all run clean