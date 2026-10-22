#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
umask 077

for tool in curl jq openssl; do
  command -v "$tool" >/dev/null || { printf 'Install %s first.\n' "$tool" >&2; exit 1; }
done

action=${1:-bootstrap}
case "$action" in
  bootstrap)
    : "${KONNECT_TOKEN:?Export a Konnect personal access token}"
    : "${KONNECT_CONTROL_PLANE_ID:?Export the ID of a dedicated hybrid control plane}"
    : "${OPENAI_API_KEY:?Export the OpenAI API key to store in Kong}"
    printf '%s' "$KONNECT_CONTROL_PLANE_ID" | jq -Re 'test("^[0-9a-fA-F-]{36}$")' >/dev/null || {
      echo 'KONNECT_CONTROL_PLANE_ID must be a UUID.' >&2
      exit 1
    }
    case "${OPENAI_CHAT_MODEL:-gpt-4o-mini}" in
      *[!A-Za-z0-9._:-]*) echo 'Invalid OpenAI model name.' >&2; exit 1 ;;
    esac
    ;;
  ingest) ;;
  *) echo 'Use bootstrap or ingest.' >&2; exit 1 ;;
esac

# Keep the target explicit: credentials must never be forwarded to arbitrary hosts.
region=${KONNECT_REGION:-us}
case "$region" in us|eu|au|in|me|sg) ;; *) echo 'Unsupported Konnect region.' >&2; exit 1 ;; esac
base="https://$region.api.konghq.com"
work=$(mktemp -d)
trap 'rm -f "$work/request.json" "$work/response.json" "$work/auth" "$work/control-plane.json"; rmdir "$work"' EXIT
trap 'exit 1' HUP INT TERM

. scripts/konnect-api.sh

if [ "$action" = bootstrap ]; then
  # A curl config keeps the PAT out of command arguments and process listings.
  case "$KONNECT_TOKEN" in *'
'*|*'"'*|*'\'*) echo 'Invalid token characters.' >&2; exit 1 ;; esac
  printf 'header = "Authorization: Bearer %s"\n' "$KONNECT_TOKEN" > "$work/auth"
  prefix="/v2/control-planes/$KONNECT_CONTROL_PLANE_ID"
  api GET "$prefix" > "$work/control-plane.json"
  jq -e '.config.cluster_type == "CLUSTER_TYPE_CONTROL_PLANE"' "$work/control-plane.json" >/dev/null || {
    echo 'Select a dedicated hybrid control plane, not a control-plane group.' >&2
    exit 1
  }
  mkdir -p secrets
  if [ ! -s secrets/konnect-cluster.crt ] && [ ! -s secrets/konnect-cluster.key ]; then
    openssl req -new -x509 -nodes -newkey rsa:2048 -days 365 \
      -subj '/CN=kong-chatbot-local' \
      -keyout secrets/konnect-cluster.key -out secrets/konnect-cluster.crt 2>/dev/null
  fi
  [ -s secrets/konnect-cluster.crt ] && [ -s secrets/konnect-cluster.key ] || {
    echo 'Both certificate and private key must exist; refusing to replace either.' >&2
    exit 1
  }
  openssl x509 -in secrets/konnect-cluster.crt -noout -checkend 0 >/dev/null
  cert_key=$(openssl x509 -in secrets/konnect-cluster.crt -pubkey -noout)
  private_key=$(openssl pkey -in secrets/konnect-cluster.key -pubout)
  [ "$cert_key" = "$private_key" ] || { echo 'Certificate/private key mismatch.' >&2; exit 1; }
  sh scripts/configure-konnect.sh "$work" "$base" "$prefix"
else
  sh scripts/ingest-konnect.sh
fi
