# Access logs of a running instance
# Usage:
#   plextrac logs [-s|--service SERVICE]

function mod_logs() {
  tail_logs
}

function tail_logs() {
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    container_client logs -f --tail=200 ${LOG_SERVICE-''}
  else
    compose_client logs -f --tail=200 ${LOG_SERVICE-''}
  fi
}
