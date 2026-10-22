#!/bin/sh
set -eu
umask 077
admin=$1
plugin_id=$2
shift 2
work=$(mktemp -d)
trap 'rm -f "$work/chunks.jsonl" "$work/response.json"; rmdir "$work"' EXIT
trap 'exit 1' HUP INT TERM
for file do
  [ "$(wc -c < "$file")" -le 1048576 ] || { printf 'Document too large: %s\n' "$file" >&2; exit 1; }
  jq -Rsc --arg source "$file" '
    . as $text | range(0; length; 1000) as $offset |
    {content:("Source: "+$source+"\n"+$text[$offset:$offset+1200])}
  ' "$file" > "$work/chunks.jsonl"
  while IFS= read -r chunk; do
    printf '%s' "$chunk" | curl --fail-with-body --silent --show-error \
      --connect-timeout 10 --max-time 120 \
      -H 'Content-Type: application/json' --data-binary @- \
      "$admin/ai-rag-injector/$plugin_id/ingest_chunk" > "$work/response.json"
    jq -e '.metadata.chunk_id | type == "string" and length > 0' "$work/response.json" >/dev/null
  done < "$work/chunks.jsonl"
  printf 'Indexed %s\n' "$file"
done
