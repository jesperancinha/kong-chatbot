#!/bin/sh
set -eu
: "${OLLAMA_CONTAINER:?Set OLLAMA_CONTAINER}"
: "${CHAT_MODEL:?Set CHAT_MODEL}"
: "${EMBEDDING_MODEL:?Set EMBEDDING_MODEL}"
attempt=0
until docker exec "$OLLAMA_CONTAINER" ollama list >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 60 ] || { echo 'Ollama startup timed out.' >&2; exit 1; }
  sleep 2
done
docker exec "$OLLAMA_CONTAINER" ollama pull "$CHAT_MODEL"
docker exec "$OLLAMA_CONTAINER" ollama pull "$EMBEDDING_MODEL"
