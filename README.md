# Maktub Barbell Club

App de entrenamiento para clubes de levantamiento de pesas y gimnasio: el coach planifica y
los atletas ejecutan el día juntos, desde varios dispositivos sincronizados. PWA en Flutter,
backend en Dart Frog y MongoDB.

El diseño (modelo del dominio, decisiones y features) está en [docs/diseno.md](docs/diseno.md).

| Carpeta | Qué es |
|---|---|
| `apps/frontend` | PWA en Flutter (Riverpod, go_router, clean architecture por feature) |
| `apps/backend` | API en Dart Frog con MongoDB (slices verticales) |
| `packages/maktub_core` | Modelos y reglas de entrenamiento compartidas |

El monorepo usa **pub workspaces** de Dart: un solo `flutter pub get` en la raíz resuelve todo.

## Levantarlo en local

```bash
flutter pub get
docker compose up -d                                   # MongoDB
dart pub global activate dart_frog_cli                 # una vez
(cd apps/backend && dart_frog dev)                     # API en http://localhost:8080
(cd apps/frontend && flutter run -d chrome)            # PWA
```
