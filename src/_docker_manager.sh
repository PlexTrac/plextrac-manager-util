# Set a few vars that will be useful elsewhere.
couchbaseComposeService="plextracdb"
coreFrontendComposeService="plextracnginx"
coreBackendComposeService="plextracapi"
postgresComposeService="postgres"

function compose_client() {
  flags=($@)
  compose_files=$(for i in `ls -r ${PLEXTRAC_HOME}/docker-compose*.yml`; do printf " -f %s" "$i"; done )
  debug "docker-compose flags: ${flags[@]}"
  debug "docker-compose configs: ${compose_files}"
  docker-compose $(echo $compose_files) ${flags[@]}
}

function pull_docker_images() {
  info "Pulling updated docker images"
  if tty -s; then
    ARGS=''
  else
    ARGS='-q'
  fi
  compose_client pull ${ARGS:-}
  info "Done."
}

function composeConfigNeedsUpdated() {
  info "Checking for pending changes to docker-compose.yml"
  decodedComposeFile=$(base64 -d <<<$DOCKER_COMPOSE_ENCODED)
  targetComposeFile="${PLEXTRAC_HOME}/docker-compose.yml"
  if [ $(echo "$decodedComposeFile" | md5sum | awk '{print $1}') == $(md5sum $targetComposeFile | awk '{print $1}') ]; then
    debug "docker-compose.yml content matches"; return 1;
  fi
  diff -N --unified=2 --color=always --label existing --label "updated" $targetComposeFile <(echo "$decodedComposeFile") || return 0
  return 1
}

function docker_createInitialComposeOverrideFile() {
  local targetOverrideFile="${PLEXTRAC_HOME}/docker-compose.override.yml"

  info "Checking for existing $targetOverrideFile"
  if ! test -f "$targetOverrideFile"; then
    info "Creating initial $targetOverrideFile"
    echo "$DOCKER_COMPOSE_OVERRIDE_ENCODED" | base64 -d > "$targetOverrideFile"
  fi
  log "Done"
}
