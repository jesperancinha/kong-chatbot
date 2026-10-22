#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

mode=${1:-local}
action=${2:-up}
case "$mode" in
  local) compose_file=compose.local.yaml; default_env=.env ;;
  konnect) compose_file=compose.yaml; default_env=.env.konnect ;;
  *) printf 'Unknown mode: %s (use local or konnect)\n' "$mode" >&2; exit 1 ;;
esac
ENV_FILE=${ENV_FILE:-$default_env}

command -v docker >/dev/null || { echo 'Docker is required.' >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo 'Start the Docker daemon first.' >&2; exit 1; }

compose() {
  docker compose --env-file "$ENV_FILE" -f "$compose_file" "$@"
}

if [ ! -f "$ENV_FILE" ]; then
  if [ "$mode" = konnect ]; then
    echo 'Missing Konnect environment file; run make konnect-bootstrap first.' >&2
    exit 1
  fi
  (umask 077; cp .env.example "$ENV_FILE")
fi

if [ "$mode" = konnect ] && { [ "$action" = up ] || [ "$action" = check ]; }; then
  for file in secrets/konnect-cluster.crt secrets/konnect-cluster.key; do
    [ -s "$file" ] || { printf 'Missing %s; run make konnect-bootstrap first.\n' "$file" >&2; exit 1; }
  done
fi

case "$action" in
  check) compose config --quiet ;;
  up)
    compose up --build -d --remove-orphans
    address=$(compose port chatbot 8080)
    echo 'Waiting for document indexing and API readiness (first model download can take several minutes)...'
    if ! sh scripts/wait-api.sh "http://$address"; then
      compose logs --tail 80
      exit 1
    fi
    ;;
  down) compose down ;;
  logs) compose logs --follow ;;
  ps) compose ps -a ;;
  config) compose config --quiet ;;
  *) printf 'Unknown action: %s\n' "$action" >&2; exit 1 ;;
esac
