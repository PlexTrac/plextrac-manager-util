# Set a few vars that will be useful elsewhere.
couchbaseComposeService="plextracdb"
coreFrontendComposeService="plextracnginx"
coreBackendComposeService="plextracapi"
postgresComposeService="postgres"

function compose_client() {
  flags=($@)
  compose_files=$(for i in `ls -r ${PLEXTRAC_HOME}/docker-compose*.yml`; do printf " -f %s" "$i"; done )
  if [ "$CONTAINER_RUNTIME" == "podman-compose" ] || [ "$CONTAINER_RUNTIME" == "podman" ]; then
    debug "podman-compose flags: ${flags[@]}"
    debug "podman-compose configs: ${compose_files}"
    podman-compose $(echo $compose_files) ${flags[@]}
  elif [ "$CONTAINER_RUNTIME" == "docker" ]; then
    debug "docker compose flags: ${flags[@]}"
    debug "docker compose configs: ${compose_files}"
    docker compose $(echo $compose_files) ${flags[@]}
  fi
}

function container_client() {
  flags=($@)
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    debug "podman flags: ${flags[@]}"
    podman ${flags[@]}
  elif [ "$CONTAINER_RUNTIME" == "docker" ]; then
    debug "docker flags: ${flags[@]}"
    docker ${flags[@]}
  fi
}

function image_version_check() {
  die "Deprecated: image_version_check"
  if [ $IMAGE_PRECHECK == true ]
    then
      IMAGE_CHANGED=true
      IMAGE_PRECHECK=false
      expected_services=""
      current_services=""
      current_image_digests=""
      # Get list of expected services from the `docker compose config`
      if [ "$CONTAINER_RUNTIME" == "podman" ]; then
        expected_services="docker.io/plextrac/plextracdb:7.2.0
docker.io/plextrac/plextracpostgres:stable
docker.io/plextrac/plextracapi:${UPGRADE_STRATEGY:-stable}
docker.io/redis:6.2-alpine
docker.io/plextrac/plextracnginx:${UPGRADE_STRATEGY:-stable}"
      else
        expected_services=$(compose_client config --format json | jq -r .services[].image | sort -u)
      fi
      debug "Expected Services "`echo $expected_services | wc -l`""
      debug "$expected_services"
      current_services=$(for i in `docker image ls -q`; do docker image inspect "$i" --format json | jq -r '(.[].RepoTags[])'; done | sort -u)
      current_image_digests=$(for i in `grep -F -x -f <(echo "$expected_services") <(echo "$current_services")`; do docker image inspect $i --format json | jq -r '.[].Id'; done | sort -u)
      debug "Current Services"
      debug "$current_services"
      debug "Current Images Matching `echo "$current_image_digests" | wc -l`"
      debug "$current_image_digests"
      if [ "$(echo "$current_image_digests" | wc -l)" -ne "$(echo "$expected_services" | wc -l)" ]
        then
          debug "Number of desired service images does NOT match!"
          debug "The Image or number of running images has changed. Scaling"
          IMAGE_CHANGED=true
        else
          IMAGE_CHANGED=false
      fi
    else
      if [ $IMAGE_CHANGED == false ]
        then
          if [ "$CONTAINER_RUNTIME" == "podman" ]; then
            local new_services=$(for i in ${expected_services[2]}; do podman image inspect $i --format json | jq -r '(.[].RepoTags[])'; done | sort -u)
          else
            local new_services=$(for i in `compose_client images -q`; do docker image inspect $i --format json | jq -r '(.[].RepoTags[])'; done | sort -u)
          fi
          local new_image_digests=$(for i in `grep -F -x -f <(echo "$expected_services") <(echo "$new_services")`; do docker image inspect $i --format json | jq -r '.[].Id'; done | sort)
          debug "New Images Matching `echo "$new_image_digests" | wc -l`"
          debug "$new_image_digests"
          if [ "$new_image_digests" = "$current_image_digests" ]
            then
              IMAGE_CHANGED=false
            else
              IMAGE_CHANGED=true
          fi
      fi
  fi
}

function pull_docker_images() {
  info "Pulling updated docker images"
  IMAGE_PRECHECK=true
  if tty -s; then
    ARGS=''
  else
    ARGS='-q'
  fi
  compose_client pull ${ARGS:-}
  log "Done."
}

function composeConfigNeedsUpdated() {
  info "Checking for pending changes to docker-compose.yml"
  #decodedComposeFile=$(base64 -d <<<$DOCKER_COMPOSE_ENCODED)
  targetComposeFile="${PLEXTRAC_HOME}/docker-compose.yml"
  if [ $(echo "$decodedComposeFile" | md5sum | awk '{print $1}') == $(md5sum $targetComposeFile | awk '{print $1}') ]; then
    debug "docker-compose.yml content matches"; return 1;
  fi
  os_check
  diff -N --unified=2 $color_always --label existing --label "updated" $targetComposeFile <(echo "$decodedComposeFile") || return 0
  return 1
}

function docker_createInitialComposeOverrideFile() {
  local targetOverrideFile="${PLEXTRAC_HOME}/docker-compose.override.yml"

  info "Checking for existing $targetOverrideFile"
  if ! test -f "$targetOverrideFile"; then
    info "Creating initial $targetOverrideFile"
    echo "$DOCKER_COMPOSE_OVERRIDE_ENCODED" | base64 -d > "$targetOverrideFile"
  fi
  log "Done."
}
