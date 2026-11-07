#!/usr/bin/env bash
# Construye el backend con Dart Frog y lo despliega en Cloud Run.
#
#   scripts/desplegar-backend.sh
#   ORIGENES_PERMITIDOS=https://usuario.github.io scripts/desplegar-backend.sh
#
# Configuración del servicio (ver CLAUDE.md, "Hosting"):
# - una sola instancia (--max-instances 1): la difusión en vivo es en memoria;
# - escala a cero (--min-instances 0): gratis cuando nadie lo usa;
# - timeout de 60 min: tope de una conexión WebSocket; el cliente reconecta y resincroniza;
# - MONGO_URL sale del secreto `mongo-url` y TOKEN_SECRET de `token-secret`, nunca del repo
#   (los dos los crea o habilita scripts/gcp-preparar.sh).
set -euo pipefail

PROYECTO="${PROYECTO:-maktub-514012}"
REGION="${REGION:-europe-north1}"
SERVICIO="${SERVICIO:-maktub-api}"
CUENTA_EMAIL="maktub-api@${PROYECTO}.iam.gserviceaccount.com"
ORIGENES="${ORIGENES_PERMITIDOS:-}"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"

export PATH="$PATH:$HOME/.pub-cache/bin"

echo "▸ Build de producción (Dart Frog)…"
SALIDA_BUILD="$(cd "$RAIZ/apps/backend" && dart_frog build 2>&1)" || { echo "$SALIDA_BUILD"; exit 1; }
echo "$SALIDA_BUILD"
# Dart Frog only warns about a rogue route (x.dart next to an x/ folder) and then drops it from the server.
if grep -q "Rogue route" <<<"$SALIDA_BUILD"; then
  echo "✗ Hay rutas que Dart Frog descarta (ver arriba). Movelas a <carpeta>/index.dart." >&2
  exit 1
fi

# Compile here what Cloud Build compiles: route handlers with the wrong parameters (e.g. missing
# clubId under routes/clubes/[clubId]/) only fail at this step, never in tests or the analyzer.
echo "▸ Compilando el servidor como en Cloud Build…"
(cd "$RAIZ/apps/backend/build" && dart pub get >/dev/null && dart compile exe bin/server.dart -o "$(mktemp -d)/server" >/dev/null)

echo "▸ Desplegando ${SERVICIO} en ${REGION}…"
gcloud run deploy "$SERVICIO" \
  --project "$PROYECTO" \
  --region "$REGION" \
  --source "$RAIZ/apps/backend/build" \
  --service-account "$CUENTA_EMAIL" \
  --allow-unauthenticated \
  --min-instances 0 \
  --max-instances 1 \
  --cpu 1 \
  --memory 256Mi \
  --concurrency 80 \
  --timeout 3600 \
  --set-secrets "MONGO_URL=mongo-url:latest,TOKEN_SECRET=token-secret:latest" \
  --set-env-vars "^|^ORIGENES_PERMITIDOS=${ORIGENES}" \
  --quiet

# Que las imágenes viejas no se acumulen fuera de la cuota gratis de Artifact Registry.
POLITICA="$(mktemp)"
cat >"$POLITICA" <<'JSON'
[
  {"name": "conservar-3", "action": {"type": "Keep"}, "mostRecentVersions": {"keepCount": 3}},
  {"name": "borrar-resto", "action": {"type": "Delete"}, "condition": {"tagState": "any"}}
]
JSON
gcloud artifacts repositories set-cleanup-policies cloud-run-source-deploy \
  --project "$PROYECTO" --location "$REGION" --policy "$POLITICA" --no-dry-run --quiet >/dev/null || true
rm -f "$POLITICA"

URL=$(gcloud run services describe "$SERVICIO" --project "$PROYECTO" --region "$REGION" --format 'value(status.url)')
echo "✓ Desplegado: ${URL}"
echo "  Prueba: curl ${URL}/health"
