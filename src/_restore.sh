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
  error "This is a potentially destructive process, are you sure?"
  info "Please confirm before continuing the restore"
  if get_user_approval; then
    local latestBackup="${PLEXTRAC_BACKUP_PATH}/uploads/`ls -c1 ${PLEXTRAC_BACKUP_PATH}/uploads | head -n1`"
    log "Restoring from $latestBackup"
    debug "`cat $latestBackup | compose_client run --workdir /usr/src/plextrac-api --rm --entrypoint='' -T \
      $coreBackendComposeService tar -xzf -`"
  fi
}

function restore_doCouchbaseRestore() {
  title "Restoring Couchbase from backup"
  error "This is a potentially destructive process, are you sure?"
  info "Please confirm before continuing the restore"
  if get_user_approval; then
    compose_client exec $couchbaseComposeService cbrestore /backups http://localhost:8091 -u ${CB_BACKUP_USER} -p "${CB_BACKUP_PASS}" -x conflict_resolve=0,data_only=1
  fi
}

function restore_doPostgresRestore() {
  title "Restoring Postgres from backup"
  error "This is a potentially destructive process, are you sure?"
  info "Please confirm before continuing the restore"
  if get_user_approval; then
    latestBackup=`ls -dc1 ${PLEXTRAC_BACKUP_PATH}/postgres/* | head -n1`
    backupFile=`basename $latestBackup`
    databaseBackups=$(basename -s .psql `tar -tf $latestBackup | awk '/.psql/{print $1}'`)
    log "Restoring from $latestBackup"
    log "Databases to restore:\n$databaseBackups"
      debug "`compose_client exec -T --user 1337 $postgresComposeService\
        tar -tf /backups/$backupFile 2>&1`"
    for db in $databaseBackups; do
      log "Extracting backup for $db"
      debug "`compose_client exec -T $postgresComposeService\
        tar -xvzf /backups/$backupFile ./$db.psql 2>&1`"
      log "Restoring $db"
      debug "`compose_client exec -T -e PGPASSWORD=$POSTGRES_PASSWORD $postgresComposeService\
        psql -U $POSTGRES_USER -d $db -f $db.psql 2>&1`"
      debug "`compose_client exec -T $postgresComposeService \
        rm $db.psql 2>&1`"
    done
  fi



}
