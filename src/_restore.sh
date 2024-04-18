# Simple restore of backups
#
# Usage:
#   plextrac restore

function mod_restore() {
  restoreTargets=(restore_doPostgresRestore restore_doCouchbaseRestore restore_doUploadsRestore)
  currentTarget=`tr [:upper:] [:lower:] <<< "${RESTORETARGET:-ALL}"`
  for target in "${restoreTargets[@]}"; do
    debug "Checking if $target matches $currentTarget"
    if [[ $currentTarget == "all" || ${target,,} =~ "restore_do${currentTarget}restore" ]]; then
      $target
    fi
  done
}

function restore_doUploadsRestore() {
  title "Restoring uploads from backup"
  latestBackup="`ls -dc1 ${PLEXTRAC_BACKUP_PATH}/uploads/* | head -n1`"
  info "Latest backup: $latestBackup"

  error "This is a potentially destructive process, are you sure?"
  info "Please confirm before continuing the restore"

  if get_user_approval; then
    log "Restoring from $latestBackup"
    if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      cat $latestBackup | podman cp - plextracapi:/usr/src/plextrac-api
    else
      debug "`cat $latestBackup | compose_client run -T --workdir /usr/src/plextrac-api --rm --entrypoint='' \
      $coreBackendComposeService tar -xzf -`"
    fi
    log "Done"
  fi
}

function restore_doCouchbaseRestore() {
  title "Restoring Couchbase from backup"
  debug "Fixing permissions"
  local user_id=$(id -u plextrac)
  if [ "$CONTAINER_RUNTIME" == "docker" ]; then
    debug "`compose_client exec -T $couchbaseComposeService \
      chown -R $user_id:$user_id /backups 2>&1`"
  fi
  latestBackup="`ls -dc1 ${PLEXTRAC_BACKUP_PATH}/couchbase/* | head -n1`"
  backupFile=`basename $latestBackup`
  info "Latest backup: $latestBackup"

  error "This is a potentially destructive process, are you sure?"
  info "Please confirm before continuing the restore"

  if get_user_approval; then
    log "Restoring from $backupFile"
    log "Extracting backup files"
    if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      podman exec --workdir /backups $couchbaseComposeService tar -xzvf /backups/$backupFile
    else
      debug "`compose_client exec -T --user 1337 --workdir /backups $couchbaseComposeService \
        tar -xzvf /backups/$backupFile 2>&1`"
    fi

    log "Running database restore"
    if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      podman exec $couchbaseComposeService cbrestore /backups http://127.0.0.1:8091 \
        -u ${CB_BACKUP_USER} -p "${CB_BACKUP_PASS}" --from-date 2022-01-01 -x conflict_resolve=0,data_only=1
    else
      # We have the TTY enabled by default so the output from cbrestore is intelligible
      tty -s || { debug "Disabling TTY allocation for Couchbase restore due to non-interactive invocation"; ttyFlag="-T"; }
      compose_client exec ${ttyFlag:-} $couchbaseComposeService cbrestore /backups http://127.0.0.1:8091 \
        -u ${CB_BACKUP_USER} -p "${CB_BACKUP_PASS}" --from-date 2022-01-01 -x conflict_resolve=0,data_only=1
    fi

    log "Cleaning up extracted backup files"
    dirName=`basename -s .tar.gz $backupFile`
    if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      podman exec --workdir /backups $couchbaseComposeService rm -rf /backups/$dirName
    else
      debug "`compose_client exec -T --user 1337 --workdir /backups $couchbaseComposeService \
        rm -rf /backups/$dirName 2>&1`"
    fi
    log "Done"
  fi
}

function restore_doPostgresRestore() {
  title "Restoring Postgres from backup"
  latestBackup="`ls -dc1 ${PLEXTRAC_BACKUP_PATH}/postgres/* | head -n1`"
  backupFile=`basename $latestBackup`
  info "Latest backup: $latestBackup"

  error "This is a potentially destructive process, are you sure?"
  info "Please confirm before continuing the restore"

  if get_user_approval; then
    databaseBackups=$(basename -s .psql `tar -tf $latestBackup | awk '/.psql/{print $1}'`)
    log "Restoring from $backupFile"
    log "Databases to restore:\n$databaseBackups"
    local cmd='compose_client exec -T --user 1337'
    if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      local cmd='podman exec'
    fi
      debug "`$cmd $postgresComposeService \
        tar -tf /backups/$backupFile 2>&1`"
    local cmd='compose_client exec -T'
    if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      local cmd='podman exec'
    fi
    for db in $databaseBackups; do
      log "Extracting backup for $db"
      debug "`$cmd $postgresComposeService\
        tar -xvzf /backups/$backupFile ./$db.psql 2>&1`"
      dbAdminEnvvar="PG_${db^^}_ADMIN_USER"
      dbAdminRole=$(eval echo "\$$dbAdminEnvvar")
      log "Restoring $db with role:${dbAdminRole}"
      dbRestoreFlags="-d $db --clean --if-exists --no-privileges --no-owner --role=$dbAdminRole  --disable-triggers --verbose"
      debug "`$cmd -e PGPASSWORD=$POSTGRES_PASSWORD $postgresComposeService \
        pg_restore -U $POSTGRES_USER $dbRestoreFlags ./$db.psql 2>&1`"
      debug "`$cmd $postgresComposeService \
        rm ./$db.psql 2>&1`"
    done
  fi
}
