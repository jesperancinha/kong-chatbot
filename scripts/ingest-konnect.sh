#!/bin/sh
set -eu
umask 077
command -v docker >/dev/null || { echo 'Docker is required.' >&2; exit 1; }
[ -s secrets/konnect-rag-plugin.json ] && [ -s secrets/konnect-settings.json ] || {
  echo 'Run make konnect-bootstrap first.' >&2
  exit 1
}
if [ -n "${KONG_LICENSE_DATA:-}" ]; then
  printf '%s' "$KONG_LICENSE_DATA" > secrets/kong-license.json
fi
[ -s secrets/kong-license.json ] || {
  echo 'Export KONG_LICENSE_DATA for a standalone AI Gateway Enterprise ingestion worker.' >&2
  echo 'A Konnect subscription alone does not license a standalone node.' >&2
  exit 1
}
jq -e . secrets/kong-license.json >/dev/null
image=$(jq -er '.kong_gateway_image' secrets/konnect-settings.json)
plugin_id=$(jq -er '.id' secrets/konnect-rag-plugin.json)

# Discover the actual Redis network so this works for either deployment tool.
if docker container inspect kong-chatbot-vector-db >/dev/null 2>&1; then
  redis=kong-chatbot-vector-db
else
  redis=$(docker compose --env-file .env.konnect -f compose.yaml ps -q vector-db)
fi
[ -n "$redis" ] || { echo 'Start the Konnect stack before ingesting.' >&2; exit 1; }
network=$(docker inspect "$redis" --format '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{"\n"}}{{end}}' | head -1)
[ -n "$network" ] || { echo 'Redis has no Docker network.' >&2; exit 1; }

work=$(mktemp -d)
db_name="kong-chatbot-ingest-db-$$"
worker_name="kong-chatbot-ingest-$$"
db_started=false
worker_started=false
cleanup() {
  if [ "$worker_started" = true ]; then docker stop "$worker_name" >/dev/null; fi
  if [ "$db_started" = true ]; then docker stop "$db_name" >/dev/null; fi
  rm -f "$work/db.env" "$work/plugin.json"
  rmdir "$work"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
password=$(openssl rand -hex 24)
printf 'POSTGRES_USER=kong\nPOSTGRES_DB=kong\nPOSTGRES_PASSWORD=%s\n' "$password" > "$work/db.env"
docker run -d --rm --name "$db_name" --network "$network" \
  --env-file "$work/db.env" postgres:17-alpine >/dev/null
db_started=true
attempt=0
until docker exec "$db_name" pg_isready -U kong >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 60 ] || { echo 'Ingestion PostgreSQL startup timed out.' >&2; exit 1; }
  sleep 2
done
printf 'KONG_DATABASE=postgres\nKONG_PG_HOST=%s\nKONG_PG_USER=kong\nKONG_PG_PASSWORD=%s\nKONG_PG_DATABASE=kong\nKONG_PROXY_LISTEN=off\nKONG_ADMIN_LISTEN=0.0.0.0:8001\nKONG_LUA_SSL_TRUSTED_CERTIFICATE=system\n' \
  "$db_name" "$password" > "$work/db.env"
license_path="$(pwd)/secrets/kong-license.json"
docker run --rm --network "$network" --env-file "$work/db.env" \
  -v "$license_path:/etc/kong/license.json:ro" "$image" kong migrations bootstrap
docker run -d --rm --name "$worker_name" --network "$network" --env-file "$work/db.env" \
  -p "127.0.0.1::8001" -v "$license_path:/etc/kong/license.json:ro" "$image" >/dev/null
worker_started=true
address=$(docker port "$worker_name" 8001/tcp)
admin="http://$address"
attempt=0
until curl --fail --silent --max-time 5 "$admin/status" >/dev/null; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 90 ]; then
    docker logs --tail 80 "$worker_name"
    echo 'Licensed ingestion worker startup timed out.' >&2
    exit 1
  fi
  sleep 2
done
# Use the documented traditional-mode Admin API, never a guessed Konnect endpoint.
curl --fail-with-body --silent --show-error -X POST "$admin/plugins" \
  -H 'Content-Type: application/json' --data-binary @secrets/konnect-rag-plugin.json \
  > "$work/plugin.json"
[ -n "$(find knowledge -type f \( -iname '*.md' -o -iname '*.txt' \) -print -quit)" ] || {
  echo 'No knowledge documents found.' >&2
  exit 1
}
find knowledge -type f \( -iname '*.md' -o -iname '*.txt' \) \
  -exec sh scripts/ingest-file.sh "$admin" "$plugin_id" {} +
echo 'Knowledge ingested into the shared Redis namespace. The temporary Enterprise ingestion worker is being removed.'
echo 'Re-running ingestion adds chunks; see the README before re-indexing changed documents.'
