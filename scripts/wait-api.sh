#!/bin/sh
set -eu
url=${1:?Provide the API base URL}
limit=${STARTUP_TIMEOUT:-1200}
elapsed=0
until curl --fail --silent --max-time 5 "$url/health" >/dev/null; do
  if [ "$elapsed" -ge "$limit" ]; then
    echo 'API readiness timed out. Inspect the chatbot and Kong container logs.' >&2
    exit 1
  fi
  sleep 5
  elapsed=$((elapsed + 5))
done
printf 'Ready: %s/api/rag/chat\n' "$url"
