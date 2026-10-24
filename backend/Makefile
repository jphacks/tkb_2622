BACKEND_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
COMPOSE := docker compose --project-directory "$(BACKEND_DIR)" -f "$(BACKEND_DIR)compose.local.yaml"

.DEFAULT_GOAL := up
.PHONY: up down logs build migrate-up migrate-status seed seed-group-profile generate

up:
	$(COMPOSE) up --build -d

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f

build:
	$(COMPOSE) build

migrate-up:
	$(COMPOSE) run --rm --build migrate /app/migrate up

migrate-status:
	$(COMPOSE) run --rm --build migrate /app/migrate status

# Seeds only the local Compose database for a registered Supabase development user.
seed:
	@test -n "$${SEED_AUTH_SUBJECT:-}" || { echo "Set SEED_AUTH_SUBJECT to the Supabase user UUID for a registered iOS development account."; exit 2; }
	@$(COMPOSE) up -d postgres
	@$(COMPOSE) run --rm --build migrate /app/migrate up
	@$(COMPOSE) exec -T postgres psql -U postgres -d tkb -v ON_ERROR_STOP=1 -v seed_auth_subject="$${SEED_AUTH_SUBJECT}" -f /dev/stdin < "$(BACKEND_DIR)dev/postgres/seed.sql"

# Adds only a local two-person group fixture without replacing account, focus, or restriction state.
seed-group-profile:
	@test -n "$${SEED_AUTH_SUBJECT:-}" || { echo "Set SEED_AUTH_SUBJECT to the Supabase user UUID for a registered iOS development account."; exit 2; }
	@$(COMPOSE) up -d postgres
	@$(COMPOSE) run --rm --build migrate /app/migrate up
	@$(COMPOSE) exec -T postgres psql -U postgres -d tkb -v ON_ERROR_STOP=1 -v seed_auth_subject="$${SEED_AUTH_SUBJECT}" -f /dev/stdin < "$(BACKEND_DIR)dev/postgres/seed_group_profile.sql"

# Regenerates Go code and internal/docs/openapi.yaml from proto. Plugins are installed into bin/.
generate:
	cd "$(BACKEND_DIR)" && PATH="$(BACKEND_DIR)bin:$$PATH" bin/buf generate
