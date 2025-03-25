# Provides a method using our utility to safely stop the PlexTrac Application
#
# Usage:
#  plextrac stop

function mod_stop() {
  title "Attempting to gracefully stop PlexTrac..."
  debug "Stopping API Services..."

  # Before stopping, check if the current image tag matches the image defined by compose files.
  # Does not work with podman, so skipping that check if this is a podman environment.

  if [ "$CONTAINER_RUNTIME" == "docker" ]; then

    debug "Validating the expected version against current running version"
    running_backend_version="$(for i in $(compose_client ps plextracapi -q); do docker container inspect "$i" --format json | jq -r '(.[].Config.Labels | ."org.opencontainers.image.version")'; done | sort -u)"
    running_frontend_version="$(for i in $(compose_client ps plextracnginx -q); do  docker container inspect "$i" --format json | jq -r '(.[].Config.Labels | ."org.opencontainers.image.version")'; done | sort -u)"
    expected_backend_tag="$(compose_client config | grep image | grep plextracapi | head -n 1 | awk '{print $2}')"
    expected_frontend_tag="$(compose_client config | grep image | grep plextracnginx | head -n 1 | awk '{print $2}')"
    expected_backend_version="$(docker image inspect $expected_backend_tag --format json | jq -r '(.[].Config.Labels | ."org.opencontainers.image.version")')"
    expected_frontend_version="$(docker image inspect $expected_frontend_tag --format json | jq -r '(.[].Config.Labels | ."org.opencontainers.image.version")')"


    if [[ "$running_backend_version" != "$expected_backend_version" ]]; then
      error "The running backend version ${running_backend_version} does not match the expected version (${expected_backend_version})"
      error "During a system reboot or shutdown, the docker engine normally handles this gracefully and automatically, so using 'plextrac stop' may be unnecessary"
      die "Since 'plextrac stop' runs a docker compose down, we cannot guarantee a 'plextrac start' will bring up the correct version. Please change UPGRADE_STRATEGY to the current running version ${running_backend_version} or run an update first"
    fi
    if [[ "$running_frontend_version" != "$expected_frontend_version" ]]; then
      error "The running frontend version (${running_frontend_version}) does not match the expected version (${expected_frontend_version})"
      error "During a system reboot or shutdown, the docker engine normally handles this gracefully and automatically, so using 'plextrac stop' may be unnecessary"
      die "Since 'plextrac stop' runs a docker compose down, we cannot guarantee a 'plextrac start' will bring up the correct version. Please change UPGRADE_STRATEGY to the current running version ${running_frontend_version} or run an update first"
    fi
    debug "Validating the expected version against current running version"
    running_backend_version="$(for i in $(compose_client ps plextracapi -q); do docker container inspect "$i" --format json | jq -r '(.[].Config.Labels | ."org.opencontainers.image.version")'; done | sort -u)"
    running_frontend_version="$(for i in $(compose_client ps plextracnginx -q); do  docker container inspect "$i" --format json | jq -r '(.[].Config.Labels | ."org.opencontainers.image.version")'; done | sort -u)"
    expected_backend_tag="$(compose_client config | grep image | grep plextracapi | head -n 1 | awk '{print $2}')"
    expected_frontend_tag="$(compose_client config | grep image | grep plextracnginx | head -n 1 | awk '{print $2}')"
    expected_backend_version="$(docker image inspect $expected_backend_tag --format json | jq -r '(.[].Config.Labels | ."org.opencontainers.image.version")')"
    expected_frontend_version="$(docker image inspect $expected_frontend_tag --format json | jq -r '(.[].Config.Labels | ."org.opencontainers.image.version")')"

    if [[ "$running_backend_version" != "$expected_backend_version" ]]; then
      error "The running backend version ${running_backend_version} does not match the expected version (${expected_backend_version})"
      error "During a system reboot or shutdown, the docker engine normally handles this gracefully and automatically, so using 'plextrac stop' may be unnecessary"
      die "Since 'plextrac stop' runs a docker compose down, we cannot guarantee a 'plextrac start' will bring up the correct version. Please change UPGRADE_STRATEGY to the current running version ${running_backend_version} or run an update first"
    fi
    if [[ "$running_frontend_version" != "$expected_frontend_version" ]]; then
      error "The running frontend version (${running_frontend_version}) does not match the expected version (${expected_frontend_version})"
      error "During a system reboot or shutdown, the docker engine normally handles this gracefully and automatically, so using 'plextrac stop' may be unnecessary"
      die "Since 'plextrac stop' runs a docker compose down, we cannot guarantee a 'plextrac start' will bring up the correct version. Please change UPGRADE_STRATEGY to the current running version ${running_frontend_version} or run an update first"
    fi

  fi

  for service in $(container_client ps --format '{{.Names}}' | grep -Eo 'plextracapi|plextracnginx|notification-engine|notification-sender|contextual-scoring-service'); do
    if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      container_client stop $service
    else
      compose_client stop $service
    fi
  done
  sleep 2
  debug "Done."
  debug "Stopping Couchbase, Postres, and Redis"
  for service in $(docker ps --format '{{.Names}}' | grep -Eo 'couchbase|postgres|redis'); do
    if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      container_client stop $service
    else
      compose_client stop $service
    fi
  done
  sleep 2
  debug "Ensuring all services are stopped"
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    container_client stop -a
  else
    compose_client stop
  fi
  info "-----"
  info "PlexTrac stopped. It's now safe to update the OS and restart"
}
