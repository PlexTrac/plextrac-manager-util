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

  pendingChanges="`checkExistingConfigForOverrides $legacyScriptPackVersion`" || true
  if [ "$pendingChanges" != "" ]; then
    event__log_activity "migrate:pending-changes" "$pendingChanges"
    error "There are pending changes to your Docker-Compose configuration."
    log "Do you wish to review the changes?"
    if get_user_approval; then
      error "Any output in RED indicates configuration that will be REMOVED"
      log "If you have any customizations such as a custom log or TLS certificate,"
      log "please set those in the '${PLEXTRAC_HOME}/docker-compose.override.yml' file."
      echo "$pendingChanges" >&2
    fi
    info "Do you wish to continue?"
    if ! get_user_approval; then
      die "Migration cannot continue without resolving local customizations"
    fi
    else
      info "No local customizations detected"
  fi

  info "Continuing..."

  info "Migrating existing Couchbase credentials"
  migrate_getCouchbaseCredentials >> "${PLEXTRAC_HOME}/.env"

  info "Migrating existing DockerHub credentials"
  migrate_getDockerHubCredentials >> "${PLEXTRAC_HOME}/.env"

  info "Migrating backups"
  migrate_backupDir

  info "Cleaning up legacy files"
  migrate_archiveLegacyComposeFiles
  migrate_archiveLegacyScripts

  info "Finished archiving legacy files"
  mod_configure

  if [ $legacyScriptPackVersion -eq 2 ]; then
    title "Final Steps (MANUAL DATA MIGRATION)"
    error "Manual data migration required"
    log "The legacy 'v2 script pack' placed certain data volumes in custom directories"
    log "To ensure data is still available post-migration, we recommend manually"
    log "performing the following steps:"
    log ""
    info "  1. Stop all running Docker containers"
    info "  2. Create new services and associated data volumes without starting any containers"
    info "  3. Copy existing data to newly available volumes"
    info "  4. Finalize installation"
    log ""
    log ""
    info "Example Commands:"
    log ""
    log "  # docker stop"
    log "  # docker-compose create"
    log "  # cp -aR /var/lib/docker/volumes/compose-files_dbdata/_data/. /var/lib/docker/volumes/plextrac_dbdata/_data/"
    log "  # cp -aR ${PLEXTRAC_HOME}/uploads/. /var/lib/docker/volumes/plextrac_uploads/_data/"
    log "  # plextrac install"
  else
    title "Migration complete"
    info "Please run 'plextrac install --ignore-existing' to complete your installation"
  fi
}

function migrate_getCouchbaseCredentials() {
  info "Retrieving Couchbase Credentials"
  activeCouchbaseContainer="`docker ps | grep plextracdb 2>/dev/null | awk '{print $1}' || echo ""`"
  cbEnv="`docker exec -it $activeCouchbaseContainer env | grep CB_ADMIN`" || info "CB_ADMIN credentials unset, will assume defaults"
  echo "CB_ADMIN_PASS=`echo "$cbEnv" | awk -F= '/PASS/ {print $2}' | grep . || echo "Plextrac"`"
  echo "CB_ADMIN_USER=`echo "$cbEnv" | awk -F= '/USER/ {print $2}' | grep . || echo "Administrator"`"
}

function migrate_getDockerHubCredentials() {
  info "Checking for existing DockerHub credentials"
  legacyDockerLoginScript="${PLEXTRAC_HOME}/connection_setup.sh"
  if test -f "$legacyDockerLoginScript"; then
    debug "`bash ${legacyDockerLoginScript} || true`"
  fi
  local credentials="`jq '.auths."https://index.docker.io/v1/".auth' ~/.docker/config.json -r \
    2>/dev/null | base64 -d | \
    awk -F':' '{printf "DOCKER_HUB_USER=%s\nDOCKER_HUB_KEY=%s\n", $1, $2}'`"
  if [ "$credentials" == "" ]; then
    error "Please add your DOCKER_HUB_USER & DOCKER_HUB_KEY credentials to ${PLEXTRAC_HOME}/.env"
  fi
  echo "$credentials"
}

function migrate_backupDir() {
  export PLEXTRAC_BACKUP_PATH="${PLEXTRAC_BACKUP_PATH:-$PLEXTRAC_HOME/backups}"
  log "Using PLEXTRAC_BACKUP_PATH=$PLEXTRAC_BACKUP_PATH"
  backup_ensureBackupDirectory
}

function migrate_archiveLegacyScripts() {
  info "Archiving Legacy Scripts"
  debug "`tar --remove-files -cvf ${PLEXTRAC_BACKUP_PATH}/legacy_scripts.tar ${PLEXTRAC_HOME}/{**/,}*.sh 2>/dev/null || true`"
}

function migrate_archiveLegacyComposeFiles() {
  info "Archiving Legacy Compose Files"
  debug "`tar --remove-files -cvf ${PLEXTRAC_BACKUP_PATH}/legacy_composefiles.tar ${PLEXTRAC_HOME}/{**/,}docker-{compose,database}.yml 2>/dev/null || true`"
}

function checkExistingConfigForOverrides() {
  info "Checking for overrides to the legacy docker-compose configuration"
  composeOverrideFile="${PLEXTRAC_HOME}/docker-compose.override.yml"
  case ${1:-1} in
    1)
      legacyComposeFile="${PLEXTRAC_HOME}/docker-compose.yml"
      legacyDatabaseFile="${PLEXTRAC_HOME}/docker-database.yml"
      ;;
    2)
      legacyComposeFile="${PLEXTRAC_HOME}/compose-files/docker-compose.yml"
      legacyDatabaseFile="${PLEXTRAC_HOME}/compose-files/docker-database.yml"
      ;;
    *)
      die "Invalid script pack version";;
  esac

  info "Checking legacy configuration"
  dcCMD="docker-compose -f $legacyComposeFile -f $legacyDatabaseFile"
  ${dcCMD} config -q || die "Invalid legacy configuration - please contact support"

  decodedComposeFile=$(base64 -d <<<$DOCKER_COMPOSE_ENCODED)
  #diff -N --unified=2 --color=always --label existing --label "updated" $targetComposeFile <(echo "$decodedComposeFile") || return 0
  diff --unified --color=always --show-function-line='^\s\{2\}\w\+' \
    <($dcCMD config --no-interpolate) \
    <(docker-compose -f - <<< "${decodedComposeFile}" -f $composeOverrideFile config --no-interpolate) || return 0
  return 1
  #diff --color=always -y --left-column <($dcCMD config --format=json | jq -S . -r) <(docker-compose -f - <<< "$decodedComposeFile" -f $composeOverrideFile config --format=json | jq -S . -r) | grep -v '^\+'
}
