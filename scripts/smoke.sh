#!/bin/sh
set -eu
base=${CHATBOT_URL:-http://127.0.0.1:${CHATBOT_PORT:-8080}}
command -v jq >/dev/null || { echo 'Install jq to run the smoke check.' >&2; exit 1; }
curl --fail-with-body --silent --show-error "$base/health" | jq -e '.status == "UP"' >/dev/null
for route in rag/chat support/chat chat; do
  answer=$(curl --fail-with-body --silent --show-error --max-time 240 "$base/api/$route" \
    -H 'Content-Type: application/json' \
    -d '{"message":"What is the project release smoke-answer?"}')
  printf '%s\n' "$answer" | jq -e '.response | type == "string" and length > 0' >/dev/null
  printf '%s\n' "$answer" | jq -e '.response | test("BLUE ORBIT READY"; "i")' >/dev/null || {
    printf '%s did not return the fact from the sample knowledge: %s\n' "$route" "$answer" >&2
    exit 1
  }
  printf '%s: %s\n' "$route" "$answer"
done
status=$(curl --silent --show-error -o /dev/null -w '%{http_code}' "$base/api/rag/chat" \
  -H 'Content-Type: application/json' -d '{"message":""}')
[ "$status" = 400 ] || { printf 'Expected invalid input to return 400, got %s\n' "$status" >&2; exit 1; }
