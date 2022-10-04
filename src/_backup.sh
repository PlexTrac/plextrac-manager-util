# Handle backing up PlexTrac instance
# Usage
#  plextrac backup

function mod_backup() {
  title "Running PlexTrac Backups"
  backup_ensureBackupDirectory
  backup_fullPostgresBackup
  backup_fullCouchbaseBackup
  backup_fullUploadsBackup
}

function backup_ensureBackupDirectory() {
  if ! test -d "${PLEXTRAC_BACKUP_PATH}"; then
    info "Ensuring backup directory exists at $PLEXTRAC_BACKUP_PATH"
    debug "`mkdir -vp "${PLEXTRAC_BACKUP_PATH}"`"
    log "Done"
  fi
}

function backup_fullUploadsBackup() {
  # Yoink uploads out to a compressed tarball
  info "$coreBackendComposeService: Performing backup of uploads directory"
  uploadsBackupDir="${PLEXTRAC_BACKUP_PATH}/uploads"
  mkdir -p $uploadsBackupDir
  debug "`compose_client run --workdir /usr/src/plextrac-api --rm --entrypoint='' -T \
    $coreBackendComposeService tar -czf - uploads > \
    ${uploadsBackupDir}/$(date -u "+%Y-%m-%dT%H%M%Sz").tar.gz`"
  log "Done."
}

function backup_fullCouchbaseBackup() {
  info "$couchbaseComposeService: Performing backup of couchbase database"
  debug "`compose_client exec -T $couchbaseComposeService \
    chown -R 1337:1337 /backups 2>&1`"
  debug "`compose_client exec -T --user 1337 $couchbaseComposeService \
    cbbackup -m full "http://localhost:8091" /backups -u ${CB_BACKUP_USER} -p ${CB_BACKUP_PASS} 2>&1`"
  latestBackup=`ls -dc1 ${PLEXTRAC_BACKUP_PATH}/couchbase/* | head -n1`
  backupDir=`basename $latestBackup`
  debug "Compressing Couchbase backup"
  debug "`tar -C $(dirname $latestBackup) --remove-files -czvf $latestBackup.tar.gz $backupDir 2>&1`"
  log "Done."
}

function backup_fullPostgresBackup() {
  info "$postgresComposeService: Performing backup of postgres database"
  debug "`compose_client exec -T $postgresComposeService \
    chown -R 1337:1337 /backups 2>&1`"
  backupTimestamp=$(date -u "+%Y-%m-%dT%H%M%Sz")
  targetPath=/backups/$backupTimestamp
  debug "`compose_client exec -T --user 1337 $postgresComposeService mkdir -p $targetPath`"
  pgBackupFlags='--format=custom --compress=1 --verbose'
  for db in ${postgresDatabases[@],,}; do
    log "Backing up $db to $targetPath"
    debug "`compose_client exec -T --user 1337 -e PGPASSWORD=$POSTGRES_PASSWORD $postgresComposeService \
      pg_dump -U $POSTGRES_USER $db $pgBackupFlags --file=$targetPath/$db.psql 2>&1`"
  done
  debug "Compressing Postgres backup"
  debug "`tar -C ${PLEXTRAC_BACKUP_PATH}/postgres/$backupTimestamp --remove-files -czvf \
    ${PLEXTRAC_BACKUP_PATH}/postgres/$backupTimestamp.tar.gz .`"
  log "Done"
}

# function validate_backups() {
#   # We should have a backup within the last 24h
#
# }
