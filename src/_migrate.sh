# Manage migrating existing instances
#
# Simply outputs the difference between the upstream docker-compose.yml
# and the local docker-compose.yml/docker-database.yml configs. Optionally
# create the docker-compose.override.yml and prompt user to make necessary edits
#
# Calls `plextrac configure` and `plextrac check`, enabling the admin
# to validate the migration prior to calling `plextrac update` (a manual step)
#
# Archives the existing docker-compose.yml & docker-database.yml (and env)
# files into the backups directory.
#
# Usage:
#   plextrac migrate [-y] [--plextrac-home ...]

function mod_migrate() {
  title "Migrating Existing Instance"
  docker_createInitialComposeOverrideFile

  local legacyScriptPackVersion
  if test -f "${PLEXTRAC_HOME}/docker-compose.yml"; then
    legacyScriptPackVersion=1
    info "Found existing installation in ${PLEXTRAC_HOME}, assuming v1 legacy script pack"
  elif test -f "${PLEXTRAC_HOME}/compose-files/docker-compose.yml"; then
    legacyScriptPackVersion=2
    info "Found existing installation in ${PLEXTRAC_HOME}/compose-files, assuming v2 legacy script pack"
  else
    die "Could not find existing installation in ${PLEXTRAC_HOME}"
  fi

  if checkExistingConfigForOverrides $legacyScriptPackVersion; then
    error "You have existing customizations to your Docker Compose configuration."
    log "\n\tThe diff shows what will be REMOVED from your configuration\n"
    error "Please review the above changes and add any required configuration to ${PLEXTRAC_HOME}/docker-compose.override.yml\n"
    info "Do you wish to continue anyway?"
    if ! get_user_approval; then
      die "Migration cannot continue without resolving local customizations"
    fi
    else
      info "No local customizations detected"
  fi

  info "Continuing..."

  debug "couchbase credentials"
  migrate_getCouchbaseCredentials >> "${PLEXTRAC_HOME}/.env"
  migrate_getDockerHubCredentials >> "${PLEXTRAC_HOME}/.env"

  debug "legacy files"
  migrate_archiveLegacyComposeFiles
  migrate_archiveLegacyScripts

  info "Finished archiving legacy files"
  mod_configure

  title "Migration complete"
  info "Please run 'plextrac install' to complete your installation"
}

function migrate_getCouchbaseCredentials() {
  info "Retrieving Couchbase Credentials"
  local activeCouchbaseContainer="`docker ps | grep plextracdb 2>/dev/null | awk '{print $1}' || echo ""`"
  if [ "$activeCouchbaseContainer" == "" ]; then
    die "Unable to retrieve couchbase credentials from running container, please set them in .env manually"
  fi
  local cbEnv="`docker exec -it $activeCouchbaseContainer env | grep CB_ADMIN`"
  echo "CB_ADMIN_PASS=`echo "$cbEnv" | awk -F= '/PASS/ {print $2}' | grep . || echo "Plextrac"`"
  echo "CB_ADMIN_USER=`echo "$cbEnv" | awk -F= '/USER/ {print $2}' | grep . || echo "Administrator"`"
}

function migrate_getDockerHubCredentials() {
  info "Checking for existing DockerHub credentials"
  local credentials="`jq '.auths."https://index.docker.io/v1/".auth' ~/.docker/config.json -r 2>/dev/null | base64 -d | awk -F':' '{printf "DOCKER_HUB_USER=%s\nDOCKER_HUB_KEY=%s\n", $1, $2}'`"
  if [ "$credentials" == "" ]; then
    error "Please add your DOCKER_HUB_USER & DOCKER_HUB_KEY credentials to ${PLEXTRAC_HOME}/.env"
  fi
  echo "$credentials"
}

function migrate_archiveLegacyScripts() {
  info "Archiving Legacy Scripts"
  backup_ensureBackupDirectory
  debug "`tar --remove-files -cvf ${PLEXTRAC_HOME}/backups/legacy_scripts.tar ${PLEXTRAC_HOME}/{**/,}*.sh 2>/dev/null || true`"
}

function migrate_archiveLegacyComposeFiles() {
  info "Archiving Legacy Compose Files"
  backup_ensureBackupDirectory
  debug "`tar --remove-files -cvf ${PLEXTRAC_HOME}/backups/legacy_composefiles.tar ${PLEXTRAC_HOME}/{**/,}docker-{compose,database}.yml 2>/dev/null || true`"
}

function checkExistingConfigForOverrides() {
  info "Checking for overrides to the legacy docker-compose configuration"
  local composeOverrideFile="${PLEXTRAC_HOME}/docker-compose.override.yml"
  local legacyComposeFile legacyDatabaseFile
  case ${1:-1} in
    1)
      local legacyComposeFile="${PLEXTRAC_HOME}/docker-compose.yml"
      local legacyDatabaseFile="${PLEXTRAC_HOME}/docker-database.yml"
      ;;
    2)
      local legacyComposeFile="${PLEXTRAC_HOME}/compose-files/docker-compose.yml"
      local legacyDatabaseFile="${PLEXTRAC_HOME}/compose-files/docker-database.yml"
      ;;
    *)
      die "Invalid script pack version";;
  esac

  info "Checking legacy configuration"
  local dcCMD="docker-compose -f $legacyComposeFile -f $legacyDatabaseFile"
  ${dcCMD} config -q || die "Invalid legacy configuration - please contact support"

  local decodedComposeFile=$(base64 -d <<<$DOCKER_COMPOSE_ENCODED)
  #diff -N --unified=2 --color=always --label existing --label "updated" $targetComposeFile <(echo "$decodedComposeFile") || return 0
  diff --unified --color=always --show-function-line='^\s\{2\}\w\+' \
    <($dcCMD config --no-interpolate) \
    <(docker-compose -f - <<< "${decodedComposeFile}" -f $composeOverrideFile config --no-interpolate) || return 0
  return 1
  #diff --color=always -y --left-column <($dcCMD config --format=json | jq -S . -r) <(docker-compose -f - <<< "$decodedComposeFile" -f $composeOverrideFile config --format=json | jq -S . -r) | grep -v '^\+'
}
