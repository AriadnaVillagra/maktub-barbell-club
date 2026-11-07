#!/usr/bin/env bash
# Prepara el proyecto de Google Cloud para la API. Se corre una sola vez; es idempotente.
# Requiere `gcloud auth login` hecho y el secreto `mongo-url` creado en Secret Manager.
#
#   scripts/gcp-preparar.sh
#
# Also prepares the Mongo backup storage (issue E0.3): a Cloud Storage bucket plus a dedicated
# service account that can only create objects in it and read the `mongo-url` secret.
# Overridable: BUCKET_BACKUPS (default <project>-backups), DIAS_BACKUP (retention, default 30).
set -euo pipefail

PROYECTO="${PROYECTO:-maktub-514012}"
REGION="${REGION:-europe-north1}"
CUENTA="maktub-api"
CUENTA_EMAIL="${CUENTA}@${PROYECTO}.iam.gserviceaccount.com"
CUENTA_BACKUP="maktub-backup"
CUENTA_BACKUP_EMAIL="${CUENTA_BACKUP}@${PROYECTO}.iam.gserviceaccount.com"
BUCKET_BACKUPS="${BUCKET_BACKUPS:-${PROYECTO}-backups}"
DIAS_BACKUP="${DIAS_BACKUP:-30}"

echo "▸ Habilitando APIs en ${PROYECTO}…"
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  secretmanager.googleapis.com storage.googleapis.com --project "$PROYECTO"

echo "▸ Secreto para firmar los tokens de acceso (token-secret)…"
# Generated once and never printed. Rotating it only forces every app to renew its access token.
if ! gcloud secrets describe token-secret --project "$PROYECTO" >/dev/null 2>&1; then
  openssl rand -base64 48 | tr -d '\n' |
    gcloud secrets create token-secret --project "$PROYECTO" --replication-policy automatic --data-file=- >/dev/null
fi

echo "▸ Cuenta de servicio de la API (solo puede leer sus secretos)…"
if ! gcloud iam service-accounts describe "$CUENTA_EMAIL" --project "$PROYECTO" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$CUENTA" --project "$PROYECTO" --display-name "API de Maktub (Cloud Run)"
fi
# Una cuenta recién creada tarda unos segundos en ser visible para IAM: se reintenta.
for secreto in mongo-url token-secret; do
  for intento in 1 2 3 4 5 6; do
    if gcloud secrets add-iam-policy-binding "$secreto" --project "$PROYECTO" \
      --member "serviceAccount:${CUENTA_EMAIL}" --role roles/secretmanager.secretAccessor >/dev/null 2>&1; then
      break
    fi
    [ "$intento" = 6 ] && { echo "✗ No se pudo dar acceso al secreto ${secreto}"; exit 1; }
    echo "  esperando a que la cuenta esté disponible (${intento}/6)…"
    sleep 10
  done
done

echo "▸ Bucket de backups de Mongo (gs://${BUCKET_BACKUPS}, se borran a los ${DIAS_BACKUP} días)…"
if ! gcloud storage buckets describe "gs://${BUCKET_BACKUPS}" --project "$PROYECTO" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${BUCKET_BACKUPS}" --project "$PROYECTO" --location "$REGION" \
    --uniform-bucket-level-access --public-access-prevention
fi
# Lifecycle is re-applied on every run: it replaces the whole config, so it stays idempotent.
LIFECYCLE="$(mktemp)"
cat >"$LIFECYCLE" <<JSON
{"rule": [{"action": {"type": "Delete"}, "condition": {"age": ${DIAS_BACKUP}}}]}
JSON
gcloud storage buckets update "gs://${BUCKET_BACKUPS}" --project "$PROYECTO" --lifecycle-file="$LIFECYCLE" >/dev/null
rm -f "$LIFECYCLE"

echo "▸ Cuenta de servicio del backup (crea objetos en el bucket y lee mongo-url, nada más)…"
if ! gcloud iam service-accounts describe "$CUENTA_BACKUP_EMAIL" --project "$PROYECTO" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$CUENTA_BACKUP" --project "$PROYECTO" --display-name "Backup de Mongo (Cloud Run job)"
fi
# No project-level roles: both bindings are on the bucket and on the secret only.
# Same retry as above: a new account takes a few seconds to be visible to IAM.
for intento in 1 2 3 4 5 6; do
  if gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_BACKUPS}" --project "$PROYECTO" \
    --member "serviceAccount:${CUENTA_BACKUP_EMAIL}" --role roles/storage.objectCreator >/dev/null 2>&1 &&
    gcloud secrets add-iam-policy-binding mongo-url --project "$PROYECTO" \
    --member "serviceAccount:${CUENTA_BACKUP_EMAIL}" --role roles/secretmanager.secretAccessor >/dev/null 2>&1; then
    break
  fi
  [ "$intento" = 6 ] && { echo "✗ No se pudieron dar los permisos a ${CUENTA_BACKUP}"; exit 1; }
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
