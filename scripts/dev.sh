#!/usr/bin/env bash
# Starts everything for local development from one terminal: MongoDB, the API on :8080
# (in the background) and the app on :5000. Ctrl+C (or `q` in flutter) stops both.
# Open http://localhost:5000 in your own Chrome: the OAuth client allows only that origin.
set -euo pipefail
cd "$(dirname "$0")/.."

for port in 8080 5000; do
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "El puerto $port ya está en uso (¿otra API o app corriendo, por ejemplo desde VS Code?). Cortala y probá de nuevo." >&2
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >&2
    exit 1
  fi
done

docker compose up -d

# stdin is an empty pipe: `dart_frog dev` grabs the terminal for its `R` shortcut whenever it thinks it
# has one (it even takes /dev/null for one), and a background job touching the terminal breaks.
(cd apps/backend && exec "$HOME/.pub-cache/bin/dart_frog" dev < <(true)) &
api=$!

stop_api() {
  kill -INT "$api" 2>/dev/null || true
  wait "$api" 2>/dev/null || true
}
trap stop_api EXIT

echo "Esperando la API en http://localhost:8080 ..."
for _ in $(seq 1 60); do
  if curl -s -o /dev/null http://localhost:8080/; then break; fi
  if ! kill -0 "$api" 2>/dev/null; then echo "La API no arrancó." >&2; exit 1; fi
  sleep 1
done

cd apps/frontend
flutter run -d web-server --web-port 5000
