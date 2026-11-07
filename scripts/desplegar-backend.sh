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
(cd "$RAIZ/apps/backend" && dart_frog build)

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
