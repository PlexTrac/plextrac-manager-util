# Provides a method using our utility to safely stop the PlexTrac Application
#
# Usage:
#  plextrac stop

function mod_stop() {
  title "Attempting to gracefully stop PlexTrac..."
  debug "Stopping API Services..."
  for service in $(docker ps --format '{{.Names}}' | grep -E 'plextracapi|plextracnginx|notification-engine|notification-sender|contextual-scoring-service'); do
    if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      container_client stop $service
    else
      compose_client stop $service
    fi
  done
  sleep 2
  debug "Done."
  debug "Stopping Couchbase, Postres, and Redis"
  for service in $(docker ps --format '{{.Names}}' | grep -E 'couchbase|postgres|redis'); do
    if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      container_client stop $service
    else
      compose_client stop $service
    fi
  done
  sleep 2
  debug "Ensuring all services are stopped"
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    docker stop -a
  else
    compose_client stop
  fi
  info "-----"
  info "PlexTrac stopped. It's now safe to update and restart"
}
