# Sourced by the bootstrap scripts; work, base and the private auth config exist.
api() {
  method=$1
  path=$2
  if [ "$method" = GET ]; then
    curl --fail-with-body --silent --show-error --connect-timeout 10 --max-time 60 \
      --config "$work/auth" "$base$path"
  else
    curl --fail-with-body --silent --show-error --connect-timeout 10 --max-time 60 --config "$work/auth" \
      -X "$method" -H 'Content-Type: application/json' \
      --data-binary "@$work/request.json" "$base$path"
  fi
}
