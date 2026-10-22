#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
command -v docker >/dev/null || { echo 'Docker is required.' >&2; exit 1; }
# The Docker provider does not automatically honor the CLI's active context.
if [ -z "${DOCKER_HOST:-}" ] || [ -n "${DOCKER_CONTEXT:-}" ]; then
  DOCKER_HOST=$(docker context inspect --format '{{.Endpoints.docker.Host}}')
  export DOCKER_HOST
fi
if [ -z "${TF_VAR_docker_builder:-}" ]; then
  builder_info=$(docker buildx inspect)
  TF_VAR_docker_builder=$(printf '%s\n' "$builder_info" | sed -n 's/^Name:[[:space:]]*//p' | head -1)
  [ -n "$TF_VAR_docker_builder" ] || { echo 'Cannot determine the active Buildx builder.' >&2; exit 1; }
  export TF_VAR_docker_builder
fi
exec "${TERRAFORM:-terraform}" -chdir=terraform "$@"
