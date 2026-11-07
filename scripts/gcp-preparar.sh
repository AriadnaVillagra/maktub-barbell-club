#!/usr/bin/env bash
# Prepara el proyecto de Google Cloud para la API. Se corre una sola vez; es idempotente.
# Requiere `gcloud auth login` hecho y el secreto `mongo-url` creado en Secret Manager.
#
#   scripts/gcp-preparar.sh
set -euo pipefail

PROYECTO="${PROYECTO:-maktub-514012}"
REGION="${REGION:-europe-north1}"
CUENTA="maktub-api"
CUENTA_EMAIL="${CUENTA}@${PROYECTO}.iam.gserviceaccount.com"

echo "▸ Habilitando APIs en ${PROYECTO}…"
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  secretmanager.googleapis.com --project "$PROYECTO"

echo "▸ Cuenta de servicio de la API (solo puede leer su secreto)…"
if ! gcloud iam service-accounts describe "$CUENTA_EMAIL" --project "$PROYECTO" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$CUENTA" --project "$PROYECTO" --display-name "API de Maktub (Cloud Run)"
fi
# Una cuenta recién creada tarda unos segundos en ser visible para IAM: se reintenta.
for intento in 1 2 3 4 5 6; do
  if gcloud secrets add-iam-policy-binding mongo-url --project "$PROYECTO" \
    --member "serviceAccount:${CUENTA_EMAIL}" --role roles/secretmanager.secretAccessor >/dev/null 2>&1; then
    break
  fi
  [ "$intento" = 6 ] && { echo "✗ No se pudo dar acceso al secreto mongo-url"; exit 1; }
  echo "  esperando a que la cuenta esté disponible (${intento}/6)…"
  sleep 10
done

echo "▸ Permisos para construir desde el código (Cloud Build usa la cuenta de Compute por defecto)…"
NUMERO=$(gcloud projects describe "$PROYECTO" --format 'value(projectNumber)')
gcloud projects add-iam-policy-binding "$PROYECTO" \
  --member "serviceAccount:${NUMERO}-compute@developer.gserviceaccount.com" --role roles/run.builder \
  --condition None >/dev/null

gcloud config set project "$PROYECTO" >/dev/null
gcloud config set run/region "$REGION" >/dev/null
echo "✓ Listo. Ahora: scripts/desplegar-backend.sh"
