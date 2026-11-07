# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A training app for weightlifting and gym clubs: coaches plan, athletes run the day together from several devices in sync. Flutter PWA + Dart Frog + MongoDB. Docs are in Spanish. Existing code is in Spanish; **new code is written in English** (decided 2026-11-07, without migrating what exists).

**`docs/diseno.md` is the source of truth for the domain model, the decisions log, and the feature list ("Features" section) with dependencies.** Its section numbers change as it grows, so refer to sections by name. Read the relevant section before building a feature. It is maintained from a separate session: don't edit it; raise conflicts with the user instead.

`reference/` is the previous Apps Script app, kept as its own git repo (ignored here). It is a reference for proven rules and the source of the history to migrate, **not a spec to port**. `reference/DISENO.md` explains the reasoning behind those rules.

## Layout (Dart pub workspaces, not npm/yarn)

```
pubspec.yaml            workspace root: one resolution and one pubspec.lock for all members
packages/maktub_core/   pure Dart, no deps: shared models (JSON contracts) + training rules
packages/maktub_ui/     design system (F17): tokens, light/dark themes, densities, components, gallery
apps/backend/           Dart Frog + MongoDB (mongo_dart), vertical slices
apps/frontend/          Flutter PWA, Riverpod + go_router, clean architecture per feature
docker-compose.yml      local MongoDB
```

Members depend on `maktub_core` by path. Run `flutter pub get` from the root after changing any pubspec. Pin new dependencies to an exact version at least two weeks old.

## Commands

```bash
docker compose up -d                                   # MongoDB on localhost:27017
cd apps/backend && dart_frog dev                       # API on :8080 (CLI: dart pub global activate dart_frog_cli)
cd apps/backend && dart_frog build                     # production build + Dockerfile in build/
cd apps/frontend && flutter run -d chrome              # API_URL via --dart-define (default http://localhost:8080)
cd apps/frontend && flutter build web                  # PWA in build/web

dart test                                              # in packages/maktub_core or apps/backend
flutter test                                           # in apps/frontend or packages/maktub_ui
flutter test test/app/navegacion_test.dart             # one file
flutter test --plain-name "usa un riel lateral"        # one test by name
dart analyze / flutter analyze                         # per member

scripts/gcp-preparar.sh                                # one-time GCP setup (idempotent)
scripts/desplegar-backend.sh                           # deploy API to Cloud Run (needs `gcloud auth login`)
ORIGENES_PERMITIDOS=https://<usuario>.github.io scripts/desplegar-backend.sh
```

Production API: `https://maktub-api-312703406459.europe-north1.run.app` (GCP project `maktub-514012`). `MONGO_URL` comes from the Secret Manager secret `mongo-url`, read by the `maktub-api` service account. Atlas allows `0.0.0.0/0` because Cloud Run has no static egress IP. The Atlas database user `contacto_db_user` has the built-in role "Read and write to any database" (not Atlas admin); that also covers index creation and `mongodump` for the backup. Budgets on the project: a $5 spend cap on Cloud Run plus a $5 alerts-only budget.

Backend env vars: `MONGO_URL` (default `mongodb://localhost:27017/maktub`), `TOKEN_SECRET` (HMAC key for access tokens, ≥ 32 chars, from the Secret Manager secret `token-secret`; without it a random one is used per process, fine for development), and `ORIGENES_PERMITIDOS`, a comma-separated CORS allowlist such as `https://<usuario>.github.io`. `http://localhost:<any port>` is always allowed for development.

Hosting (all free tier): the PWA goes on GitHub Pages, the API on Google Cloud Run in `europe-north1` as a plain Docker container, and MongoDB on Atlas M0. Keep the backend free of Google-specific APIs so the same image can move to any VM. The app and the API are on different sites, so auth travels in the `Authorization` header and never in cookies.

## Architecture

### `maktub_core`
- `src/reglas/`: pure rules shared by both sides: nearest loadable weight (`Equipo`), `%` normalization, daily adjustment and `%` derived from typed kg (`porcentajes.dart`), cycle/week from a start date (`UbicacionEnCiclo`), timer expansion into phases (`fasesDe`). Rules that matter on both sides go here, with tests.
- `src/modelos/`: wire contracts. Common base is `DelClub` (every document has `clubId`) and `Auditoria` (created/modified by user + UTC instant). Enums implement `ConCable` with a stable wire name. Each feature adds its models here as it is built, following the "Modelo del dominio" section of `docs/diseno.md`. Add every field the doc already defines for that model, even if the first screens don't use it, to avoid migrations later.
- Calendar dates are `DateTime.utc(y,m,d)` and travel as `yyyy-MM-dd`. Instants travel as ISO 8601 UTC.

### Backend: vertical slices
- One folder per use case: `lib/features/<feature>/<slice>/` with `<slice>.dart` (endpoint function + use-case class) and `<slice>_store.dart` (an interface with only what that slice reads and writes, plus its Mongo implementation). Slices don't share repositories, and tests use fake stores.
- `routes/` files only dispatch by HTTP method to the slice endpoint. `main.dart` opens Mongo once in `init` and provides `Db`. On Cloud Run the server scales to zero (1–2 s cold start) and runs as a **single instance** (`max-instances=1`), because realtime fan-out is in memory behind an interface. Clients must reconnect and resync by sequence number. See "Multi-dispositivo" in the design doc.
- `lib/infraestructura/` holds only cross-cutting code: Mongo connection and `_id`↔`id` mapping, collection names (`Colecciones`), `asegurarIndices`, error middleware (`ErrorDeSolicitud` → 4xx `{error}`, anything else → 500 without details), CORS.
- Every query filters by `clubId` (multi-club isolation).

### `maktub_ui` (design system, spec in `docs/features/F17-design-system.md`)
- Tokens come in three layers: primitives (`Paleta`, not exported; `Espacio`, `Radios`, `Borde`), then semantics (Material `ColorScheme` plus the `ColoresMaktub`, `NumerosMaktub` and `DensidadMaktub` theme extensions), then component themes inside `TemaMaktub`. Changing the visual identity means changing `tokens/primitivos.dart`. Palette and typography are approved (decisions DS6 and DS7). The brand colors are black, maroon `#830000`, dark red `#BC0202` (primary) and red `#FF0000` (accent; in light mode only for large or non-text elements). The other tones come from HCT scales; error is orange `#FB8C00`, warning yellow and success green. Fonts are Inter for UI text and Barlow Condensed for big numbers and `display` titles, bundled as assets of `maktub_ui` (never downloaded at runtime), always with tabular figures. Reference them through `Familias`. The primary button uses `context.colores.botonPrimario` (`#BC0202` with white text in both themes). `ColorScheme.primary` is a light red in dark mode because Material also uses it as a text color.
- **Screens never use literal colors, sizes, spacing or text styles.** Use `context.esquema`, `context.colores`, `context.textos`, `context.numeros`, `context.densidad`, `Espacio.*`, `Radios.*`, or a component from the package. If a component is missing, add it to the package along with its gallery section; don't build it inside a screen.
- Each mode has its own theme: `TemaDeModo` (used by the shell) makes training dark with 56 dp touch targets, while planning follows the system with 48 dp. A user preference (`preferenciaTemaProvider`) can override either.
- Tests: `contraste_test.dart` enforces WCAG AA on every text/background pair in both themes, and `tema_test.dart` enforces minimum touch sizes per density. Goldens (`--tags golden`) are macOS-specific; regenerate them with `flutter test --update-goldens --tags golden` after an intentional visual change. The gallery is at `/galeria` in debug builds.

### Frontend: clean architecture per feature
- `lib/features/<feature>/{data,domain,presentation}`. `domain/` is pure (entities, repository interfaces, use cases). Each feature's DI lives in `presentation/providers.dart`, so tests override the repository provider. Riverpod `Notifier`/`AsyncNotifier`, without codegen.
- `lib/app/`: `MaterialApp.router`, `router.dart` (`Rutas`: `/entrenamiento`, `/planificacion` as `StatefulShellRoute` branches; features add child routes under their mode), `shell.dart` (applies each mode's theme, a bottom `NavigationBar` on compact screens and a `NavigationRail` from medium width up, plus the running timer bar), `modos.dart` (mode landing pages, placeholders for now).
- `lib/core/red/cliente_api.dart`: HTTP client (`ErrorDeApi` carries the backend's `{error}`).
- `features/temporizador`: `Crono` (immutable, measured against the wall clock) + `CronoController` (200 ms tick, haptics). It is the base for F8.

## Status

F0 (foundations) is in progress: done are the monorepo, shared rules, the backend skeleton, the HTTP client, the navigation shell and the PWA manifest. The API is deployed on Cloud Run with Atlas. Still pending are publishing the PWA on GitHub Pages (the repo isn't created yet), the scheduled backup, CI deploys, and the app icon/logo. Next on the critical path is F1: clubs, users, login and roles. The first commit (`a28bee9`) holds an earlier prototype of the tracking screen built on the old reference model, for reference only.
