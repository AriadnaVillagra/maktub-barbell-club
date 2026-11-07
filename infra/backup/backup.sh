#!/usr/bin/env bash
# Dumps the whole database into one gzip archive and uploads it to the backups bucket.
# Env: MONGO_URL (from Secret Manager), BUCKET (bucket name, no gs://).
set -euo pipefail

: "${MONGO_URL:?MONGO_URL is required}"
: "${BUCKET:?BUCKET is required}"

NAME="maktub-$(date -u +%Y-%m-%dT%H%M%SZ).archive.gz"
FILE="/tmp/${NAME}"

echo "Dumping to ${FILE}..."
# The URI goes via env/config, never on the command line, so it does not show in process lists.
CONFIG="$(mktemp)"
printf 'uri: "%s"\n' "$MONGO_URL" >"$CONFIG"
mongodump --config "$CONFIG" --archive="$FILE" --gzip
rm -f "$CONFIG"

SIZE=$(wc -c <"$FILE")
[ "$SIZE" -gt 0 ] || { echo "Empty dump, aborting" >&2; exit 1; }

echo "Uploading ${SIZE} bytes to gs://${BUCKET}/${NAME}..."
TOKEN=$(curl -fsS -H 'Metadata-Flavor: Google' \
  'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token' | jq -r .access_token)
# Only the object is created: objectCreator is enough (no get/list/delete).
curl -fsS -X POST \
  -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/gzip' \
  --data-binary "@${FILE}" \
  "https://storage.googleapis.com/upload/storage/v1/b/${BUCKET}/o?uploadType=media&name=${NAME}" >/dev/null

echo "Done: gs://${BUCKET}/${NAME}"
