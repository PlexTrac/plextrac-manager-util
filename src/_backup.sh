# Handle backing up PlexTrac instance
# Usage
#  plextrac backup

function mod_backup() {
  title "Running PlexTrac Backups"
  backup_ensureBackupDirectory
  backup_fullPostgresBackup
  backup_fullCouchbaseBackup
  backup_fullUploadsBackup "svcValues"
}

function backup_ensureBackupDirectory() {
  if ! test -d "${PLEXTRAC_BACKUP_PATH}"; then
    info "Ensuring backup directory exists at $PLEXTRAC_BACKUP_PATH"
    debug "`mkdir -vp "${PLEXTRAC_BACKUP_PATH}"`"
    log "Done"
  fi
}

function backup_fullUploadsBackup() {
  var=$(declare -p "$1")
  eval "declare -A serviceValues="${var#*=}
  # Yoink uploads out to a compressed tarball
  info "$coreBackendComposeService: Performing backup of uploads directory"
  uploadsBackupDir="${PLEXTRAC_BACKUP_PATH}/uploads"
  mkdir -p $uploadsBackupDir
 if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    local current_date=$(date -u "+%Y-%m-%dT%H%M%Sz")
    podman exec --workdir="/usr/src/plextrac-api" plextracapi tar -czf "uploads/$current_date.tar.gz" uploads
    debug "Archiving uploads succeeded"
    podman cp plextracapi:/usr/src/plextrac-api/uploads/$current_date.tar.gz $uploadsBackupDir
    debug "Copying to host succeeded"
    podman exec --workdir="/usr/src/plextrac-api/uploads" plextracapi rm $current_date.tar.gz
    debug "Cleaned Archive from container"
  else
    debug "`compose_client run --user 1337 -v ${uploadsBackupDir}:/backups \
      --workdir /usr/src/plextrac-api --rm --entrypoint='' -T  $coreBackendComposeService \
      tar -czf /backups/$(date -u "+%Y-%m-%dT%H%M%Sz").tar.gz uploads`"
  fi
  log "Done."
}

function backup_fullCouchbaseBackup() {
  info "$couchbaseComposeService: Performing backup of couchbase database"
  local cmd='compose_client exec -T --user 1337'
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    cmd='docker exec'
  fi
  if [ "$CONTAINER_RUNTIME" != "podman" ]; then
    debug "`$cmd $couchbaseComposeService \
      chown -R 1337:1337 /backups 2>&1`"
  fi
  debug "`$cmd $couchbaseComposeService \
    cbbackup -m full "http://127.0.0.1:8091" /backups -u ${CB_BACKUP_USER} -p ${CB_BACKUP_PASS} 2>&1`"
  latestBackup=`ls -dc1 ${PLEXTRAC_BACKUP_PATH}/couchbase/* | head -n1`
  backupDir=`basename $latestBackup`
  debug "Compressing Couchbase backup"
  debug "`tar -C $(dirname $latestBackup) --remove-files -czvf $latestBackup.tar.gz $backupDir 2>&1`"
  log "Done."
}

function backup_fullPostgresBackup() {
  info "$postgresComposeService: Performing backup of postgres database"
  local cmd='compose_client exec -T --user 1337'
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    cmd='docker exec'
  fi
  if [ "$CONTAINER_RUNTIME" != "podman" ]; then
    debug "`compose_client exec -T $postgresComposeService chown -R 1337:1337 /backups 2>&1`"
  fi
  backupTimestamp=$(date -u "+%Y-%m-%dT%H%M%Sz")
  targetPath=/backups/$backupTimestamp
  debug "`$cmd $postgresComposeService mkdir -p $targetPath`"
  pgBackupFlags='--format=custom --compress=1 --verbose'
  for db in ${postgresDatabases[@],,}; do
    log "Backing up $db to $targetPath"
    debug "`$cmd -e PGPASSWORD=$POSTGRES_PASSWORD $postgresComposeService \
      pg_dump -U $POSTGRES_USER $db $pgBackupFlags --file=$targetPath/$db.psql 2>&1`"
  done
  debug "Compressing Postgres backup"
  tar -C ${PLEXTRAC_BACKUP_PATH}/postgres/$backupTimestamp --remove-files -czvf ${PLEXTRAC_BACKUP_PATH}/postgres/$backupTimestamp.tar.gz .
  log "Done"
}

# function validate_backups() {
#   # We should have a backup within the last 24h
#
# }
