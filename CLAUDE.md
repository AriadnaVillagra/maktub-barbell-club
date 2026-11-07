# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A powerlifting training app for two athletes, being ported from a Google Apps Script + Sheets app (`reference/`, a separate git repo kept as the spec) to a Dart monorepo with its own backend and database. Code, identifiers, and docs are in Spanish; keep new code in Spanish too.

**Read `reference/DISENO.md` before touching the training model or weight calculations.** It explains decisions and data quirks the code doesn't show.

## Monorepo layout (Dart pub workspaces, not npm/yarn)

```
pubspec.yaml            workspace root: one resolution and one pubspec.lock for everything
packages/maktub_core/   pure Dart, no deps: models (JSON contracts) + training rules
apps/backend/           Dart Frog API + MongoDB (mongo_dart), vertical slices
apps/frontend/          Flutter app, Riverpod, clean architecture per feature
docker-compose.yml      local MongoDB
reference/              original Apps Script app (read-only spec)
```

Members depend on `maktub_core` by path. Run `flutter pub get` (or `dart pub get`) from the root after changing any pubspec.

## Commands

```bash
docker compose up -d                                  # MongoDB on localhost:27017
cd apps/backend && dart run bin/sembrar.dart          # seed catalog, athletes, RMs, sample plan (idempotent)
cd apps/backend && dart_frog dev                      # API on :8080 (CLI: dart pub global activate dart_frog_cli)
cd apps/frontend && flutter run                       # add --dart-define=API_URL=http://10.0.2.2:8080 on Android emulator

dart test                                             # in packages/maktub_core or apps/backend
flutter test                                          # in apps/frontend
flutter test test/features/temporizador/crono_test.dart          # one file
flutter test --plain-name "guardar envía el día completo"         # one test by name
dart analyze / flutter analyze                        # per package
```

`MONGO_URL` overrides the default `mongodb://localhost:27017/maktub` (backend and seed script).

## Architecture

### `maktub_core` (shared)
- `src/modelos/`: the JSON contract between backend and frontend (`Plan`, `SesionRegistrada`, `SeguimientoSnapshot`...). Enums carry their wire name in `.cable`; note `Bloque.cierre` is `"final"` on the wire.
- `src/reglas/`: pure rules both sides rely on: nearest loadable weight (`Equipo`), `%` normalization and daily adjustment, cycle/week from date (`UbicacionEnCiclo`, `varianteDeSemana`), timer phases (`fasesDe`). Put any rule that matters on both sides here, with tests.
- Dates are calendar dates as `DateTime.utc(y,m,d)` and travel as `yyyy-MM-dd` strings (in Mongo too).

### Backend: vertical slices
- One folder per use case: `lib/features/<feature>/<slice>/` holds `<slice>.dart` (endpoint function + use-case class) and `<slice>_store.dart` (an interface with only the reads/writes that slice needs + its Mongo implementation). Slices don't share repositories. Tests use a fake store.
- `routes/` files only dispatch by HTTP method to the slice endpoint. `main.dart` opens Mongo once in `init` and provides `Db` to every request.
- Only cross-cutting code goes in `lib/infraestructura/`: Mongo connection, `_id`↔`id` mapping, collection names, error middleware (`ErrorDeSolicitud` → 4xx JSON `{error}`), CORS.
- Mongo model: `planes` embeds days → variants → prescriptions → sets. `sesiones` is one doc per day with `_id = SesionRegistrada.clave` (`atleta|plan|ciclo|semana|dia`), so saving again replaces it. `rms` keeps history; the current one is the latest by date. Accessory weights are embedded in `atletas.pesosAccesorios`.

### Frontend: clean architecture per feature
- `lib/features/<feature>/{data,domain,presentation}`; `lib/core/` holds cross-cutting code (HTTP `ClienteApi`, `API_URL`).
- `domain/` is pure: entities, repository interface, use cases. Session logic lives in the `SesionDelDia` entity (immutable, methods return a new instance) and the `ConstruirSesion` / `ArmarRegistro` use cases.
- `presentation/providers.dart` is the feature's DI. Tests override `seguimientoRepositoryProvider` and `hoyProvider`. Controllers are Riverpod `AsyncNotifier`/`Notifier` (no codegen).
- Features: `seguimiento` (today's training: tracking, adjustments, saving) and `temporizador` (`Crono` engine measured against the wall clock + `CronoController` with a 200 ms tick).

## Domain rules that are easy to break

- A plan is a 4-week template repeated from `inicio`. Weeks 1 and 4 use `descarga`, week 2 `carga`, week 3 `carga2` only if any day defines it (otherwise `carga`). `ciclo` counts the repetitions.
- Weight: an exercise with `referencia` (sentadilla / peso_muerto / bench) loads `RM × pct` snapped to the nearest loadable weight (20 kg bar plus pairs of 20/15/10/5/2.5/1.5/1.25, with ties going to the lighter). An exercise without one uses the athlete's fixed `pesosAccesorios` weight, unsnapped. No field says "accessory".
- Each set has its own reps and % (warm-up ramps). Plans store sets one by one.
- Daily adjustment: a session % plus a per-exercise override (null = inherit), clamped to 50–150. **Never modifies stored RMs.** A set edited by hand (`tocada`) keeps its weight when the adjustment changes.
- Logged sessions are complete and denormalized (kg + RM + % at the time). Invariant **`rmVigente × pct ≈ pesoKg`**: if kg was typed by hand, the % is derived from it (`SerieVista.pctARegistrar`).

## Pending (from reference/README.md plus the port)

History charts; plan configurator (`reference/Plan.html`) as a new feature + backend slices; editing the catalog, RMs and accessory weights in-app; a fixed per-athlete training-max factor (see DISENO); equipment stored in the DB (now `Equipo.estandar`); remembering the last athlete; offline cache for the gym; timer sound and wake lock; importing the old spreadsheet history (`reference/importar.py`, `generar.py`) into Mongo.
