# Handle backing up PlexTrac instance
# Usage
#  plextrac backup

function mod_backup() {
  title "Running PlexTrac Backups"
  backup_ensureBackupDirectory
  backup_fullUploadsBackup
  backup_fullCouchbaseBackup
}

function backup_fullUploadsBackup() {
  # Yoink uploads out to a compressed tarball
  info "$coreBackendComposeService: Performing backup of uploads directory"
  local uploadsBackupDir="${PLEXTRAC_BACKUP_PATH}/uploads"
  mkdir -p $uploadsBackupDir
  debug "`compose_client run --workdir /usr/src/plextrac-api --rm --entrypoint='' -T \
    $coreBackendComposeService tar -czf - uploads > \
    ${uploadsBackupDir}/$(date "+%Y.%m.%d-%H.%M.%S").tar.gz`"
  debug "`ls -lah ${uploadsBackupDir}`"
  log "Done."
}

function backup_fullCouchbaseBackup() {
  info "$couchbaseComposeService: Performing backup of couchbase database"
  debug "`compose_client exec $couchbaseComposeService \
    chown 1337:1337 /backups 2>&1`"
  debug "`compose_client exec $couchbaseComposeService \
    cbbackup -m full "http://localhost:8091" /backups -u ${CB_BACKUP_USER} -p ${CB_BACKUP_PASS} 2>&1`"
  log "Done."
}

function backup_ensureBackupDirectory() {
  info "Ensuring backup directory exists at $PLEXTRAC_BACKUP_PATH"
  if ! test -d "${PLEXTRAC_BACKUP_PATH}"; then
    debug "`mkdir -vp "${PLEXTRAC_BACKUP_PATH}"`"
  fi
  log "Done"
}

# function validate_backups() {
#   # We should have a backup within the last 24h
#
# }
