# Maktub Barbell Club

App para seguir y diseñar planes de powerlifting. Es el port a Dart del proyecto de Apps Script
que está en `reference/`, ahora con base de datos, backend y frontend propios.

| Carpeta | Qué es |
|---|---|
| `apps/frontend` | App Flutter (Riverpod, clean architecture por feature) |
| `apps/backend` | API en Dart Frog con MongoDB (slices verticales) |
| `packages/maktub_core` | Modelos y reglas de entrenamiento compartidas |

El monorepo usa **pub workspaces** de Dart: un solo `flutter pub get` en la raíz resuelve todo.

## Levantarlo en local

```bash
flutter pub get
docker compose up -d                                   # MongoDB
dart pub global activate dart_frog_cli                 # una vez
(cd apps/backend && dart run bin/sembrar.dart)         # catálogo, atletas, RMs y plan de ejemplo
(cd apps/backend && dart_frog dev)                     # API en http://localhost:8080
(cd apps/frontend && flutter run)                      # en emulador Android: --dart-define=API_URL=http://10.0.2.2:8080
```

Las reglas del modelo de entrenamiento están en [reference/DISENO.md](reference/DISENO.md).
