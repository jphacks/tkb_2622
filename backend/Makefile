BACKEND_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
COMPOSE := docker compose --project-directory "$(BACKEND_DIR)" -f "$(BACKEND_DIR)compose.local.yaml"

.DEFAULT_GOAL := up
.PHONY: up down logs build migrate-up migrate-status generate

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

# Regenerates Go code and internal/docs/openapi.yaml from proto. Plugins are installed into bin/.
generate:
	cd "$(BACKEND_DIR)" && PATH="$(BACKEND_DIR)bin:$$PATH" bin/buf generate
