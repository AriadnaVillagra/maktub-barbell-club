#!/usr/bin/env bash
# Creates or updates the daily Mongo backup (issue E0.4): a Cloud Run job that runs mongodump
# into the backups bucket, plus a Cloud Scheduler trigger. Idempotent; run scripts/gcp-preparar.sh
# first (bucket, maktub-backup account, mongo-url secret).
#
#   scripts/programar-backup.sh
#
# Overridable: PROYECTO, REGION, REGION_PLANIFICADOR, BUCKET_BACKUPS, HORARIO (cron), ZONA_HORARIA.
# Cloud Scheduler is not offered in europe-north1, so the schedule lives in europe-west1;
# it only sends an HTTP call to the job, which still runs in REGION.
# Default schedule: every day at 04:00 Europe/Madrid (quiet hour for the club).
# MONGO_URL comes from the `mongo-url` secret, never from the repo.
set -euo pipefail

PROYECTO="${PROYECTO:-maktub-514012}"
REGION="${REGION:-europe-north1}"
REGION_PLANIFICADOR="${REGION_PLANIFICADOR:-europe-west1}"
BUCKET_BACKUPS="${BUCKET_BACKUPS:-${PROYECTO}-backups}"
TRABAJO="${TRABAJO:-maktub-backup}"
PLANIFICADOR="${PLANIFICADOR:-maktub-backup-diario}"
HORARIO="${HORARIO:-0 4 * * *}"
ZONA_HORARIA="${ZONA_HORARIA:-Europe/Madrid}"
CUENTA_BACKUP_EMAIL="maktub-backup@${PROYECTO}.iam.gserviceaccount.com"
CUENTA_DISPARO="maktub-backup-disparo"
CUENTA_DISPARO_EMAIL="${CUENTA_DISPARO}@${PROYECTO}.iam.gserviceaccount.com"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"

echo "▸ Habilitando APIs en ${PROYECTO}…"
gcloud services enable run.googleapis.com cloudscheduler.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com --project "$PROYECTO"

echo "▸ Desplegando el job ${TRABAJO} en ${REGION}…"
# deploy creates the job or updates it in place.
gcloud run jobs deploy "$TRABAJO" \
  --project "$PROYECTO" \
  --region "$REGION" \
  --source "$RAIZ/infra/backup" \
  --service-account "$CUENTA_BACKUP_EMAIL" \
  --tasks 1 \
  --max-retries 1 \
  --task-timeout 15m \
  --cpu 1 \
  --memory 512Mi \
  --set-secrets "MONGO_URL=mongo-url:latest" \
  --set-env-vars "BUCKET=${BUCKET_BACKUPS}" \
  --quiet

echo "▸ Cuenta que dispara el job (solo run.invoker sobre ese job)…"
if ! gcloud iam service-accounts describe "$CUENTA_DISPARO_EMAIL" --project "$PROYECTO" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$CUENTA_DISPARO" --project "$PROYECTO" \
    --display-name "Dispara el backup de Mongo (Cloud Scheduler)"
fi
for intento in 1 2 3 4 5 6; do
  if gcloud run jobs add-iam-policy-binding "$TRABAJO" --project "$PROYECTO" --region "$REGION" \
    --member "serviceAccount:${CUENTA_DISPARO_EMAIL}" --role roles/run.invoker >/dev/null 2>&1; then
    break
  fi
  [ "$intento" = 6 ] && { echo "✗ No se pudo dar run.invoker a ${CUENTA_DISPARO}"; exit 1; }
  echo "  esperando a que la cuenta esté disponible (${intento}/6)…"
  sleep 10
done

echo "▸ Programación diaria (${HORARIO} ${ZONA_HORARIA})…"
URI="https://run.googleapis.com/v2/projects/${PROYECTO}/locations/${REGION}/jobs/${TRABAJO}:run"
if gcloud scheduler jobs describe "$PLANIFICADOR" --project "$PROYECTO" --location "$REGION_PLANIFICADOR" >/dev/null 2>&1; then
  ACCION=update
else
  ACCION=create
fi
gcloud scheduler jobs "$ACCION" http "$PLANIFICADOR" \
  --project "$PROYECTO" --location "$REGION_PLANIFICADOR" \
  --schedule "$HORARIO" --time-zone "$ZONA_HORARIA" \
  --uri "$URI" --http-method POST \
  --oauth-service-account-email "$CUENTA_DISPARO_EMAIL" \
  --attempt-deadline 60s \
  --quiet
# Make sure it is enabled even if someone paused it.
gcloud scheduler jobs resume "$PLANIFICADOR" --project "$PROYECTO" --location "$REGION_PLANIFICADOR" >/dev/null

echo "✓ Backup programado: job ${TRABAJO}, planificador ${PLANIFICADOR}"
echo "  Ejecutar ahora:  gcloud run jobs execute ${TRABAJO} --project ${PROYECTO} --region ${REGION} --wait"
echo "  Ver el dump:     gcloud storage ls -l gs://${BUCKET_BACKUPS}/   (necesita permiso de listado, p. ej. tu usuario)"
