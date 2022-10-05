# Simple restore of backups
#
# Usage:
#   plextrac restore

function mod_restore() {
  restore_doPostgresRestore
  restore_doCouchbaseRestore
  restore_doUploadsRestore
}

function restore_doUploadsRestore() {
  title "Restoring uploads from backup"
  latestBackup="`ls -dc1 ${PLEXTRAC_BACKUP_PATH}/uploads/* | head -n1`"
  info "Latest backup: $latestBackup"

  error "This is a potentially destructive process, are you sure?"
  info "Please confirm before continuing the restore"

  if get_user_approval; then
    log "Restoring from $latestBackup"
    debug "`cat $latestBackup | compose_client run --workdir /usr/src/plextrac-api --rm --entrypoint='' -T \
      $coreBackendComposeService tar -xzf -`"
    log "Done"
  fi
}

function restore_doCouchbaseRestore() {
  title "Restoring Couchbase from backup"
  latestBackup="`ls -dc1 ${PLEXTRAC_BACKUP_PATH}/couchbase/* | head -n1`"
  backupFile=`basename $latestBackup`
  info "Latest backup: $latestBackup"

  error "This is a potentially destructive process, are you sure?"
  info "Please confirm before continuing the restore"

  if get_user_approval; then
    log "Restoring from $backupFile"
    log "Extracting backup files"
    debug "`compose_client exec -T --user 1337 --workdir /backups $couchbaseComposeService \
      tar -xzvf /backups/$backupFile 2>&1`"

    log "Running database restore"
    compose_client exec $couchbaseComposeService cbrestore /backups http://localhost:8091 \
      -u ${CB_BACKUP_USER} -p "${CB_BACKUP_PASS}" -x conflict_resolve=0,data_only=1

    log "Cleaning up extracted backup files"
    dirName=`basename -s .tar.gz $backupFile`
    debug "`compose_client exec -T --user 1337 --workdir /backups $couchbaseComposeService \
      rm -rf /backups/$dirName 2>&1`"
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
      debug "`compose_client exec -T --user 1337 $postgresComposeService\
        tar -tf /backups/$backupFile 2>&1`"
    for db in $databaseBackups; do
      log "Extracting backup for $db"
      debug "`compose_client exec -T $postgresComposeService\
        tar -xvzf /backups/$backupFile ./$db.psql 2>&1`"
      log "Restoring $db"
      dbRestoreFlags="-d $db --clean --if-exists --no-owner --disable-triggers --verbose"
      debug "`compose_client exec -T -e PGPASSWORD=$POSTGRES_PASSWORD $postgresComposeService \
        pg_restore -U $POSTGRES_USER $dbRestoreFlags ./$db.psql 2>&1`"
      debug "`compose_client exec -T $postgresComposeService \
        rm ./$db.psql 2>&1`"
    done
  fi
}
