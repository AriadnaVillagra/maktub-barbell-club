# Day-to-day commands, run from the repo root: `make <target>`.
# `make dev` runs everything in one terminal; `make api` and `make app` run one side each.

DART_FROG := $(HOME)/.pub-cache/bin/dart_frog

.PHONY: help dev mongo api app app-chrome alta semilla deps test analyze

help:
	@echo "make dev         Todo: Mongo + API (:8080) + app (:5000). Ctrl+C corta las dos"
	@echo "make api         Solo backend: Mongo + API en http://localhost:8080"
	@echo "make app         Solo frontend: app en http://localhost:5000, abrila en tu Chrome"
	@echo "make mongo       MongoDB local (docker compose)"
	@echo "make app-chrome  App en un Chrome aparte (sin tu sesión de Google)"
	@echo "make alta        Script de alta: ALTA_USUARIOS=\"email:Nombre,...\" make alta"
	@echo "make semilla     Carga el catálogo base aprobado en plataforma (idempotente, no pisa lo existente)"
	@echo "make deps        flutter pub get en todo el workspace"
	@echo "make test        Tests de core, backend, ui y app"
	@echo "make analyze     Análisis de core, backend, ui y app"

dev:
	scripts/dev.sh

mongo:
	docker compose up -d

api: mongo
	cd apps/backend && $(DART_FROG) dev

# The OAuth client allows only http://localhost and http://localhost:5000.
app:
	cd apps/frontend && flutter run -d web-server --web-port 5000

app-chrome:
	cd apps/frontend && flutter run -d chrome --web-port 5000

# ALTA_USUARIOS (or tool/alta.local.json) comes from the environment.
alta: mongo
	cd apps/backend && dart run tool/alta.dart

# Base catalog seed (E2.7): reads tool/semilla/catalogo_base.json, writes to MONGO_URL.
semilla: mongo
	cd apps/backend && dart run tool/semilla.dart

deps:
	flutter pub get

test:
	cd packages/maktub_core && dart test
	cd apps/backend && dart test
	cd packages/maktub_ui && flutter test
	cd apps/frontend && flutter test

analyze:
	cd packages/maktub_core && dart analyze
	cd apps/backend && dart analyze
	cd packages/maktub_ui && flutter analyze
	cd apps/frontend && flutter analyze
