# Handle backing up PlexTrac instance
# Usage
#  plextrac backup

function mod_backup() {
  title "Running PlexTrac Backups"
  do_uploads_backup
  do_couchbase_backup
}

function do_uploads_backup() {
  # Yoink uploads out to a compressed tarball
  info "$coreBackendComposeService: Performing backup of uploads directory"
  mkdir -p ${PLEXTRAC_HOME}/backups/uploads
  compose_client run --rm --entrypoint='' -T \
    $coreBackendComposeService tar -czf - /usr/src/plextrac-api/uploads > ${PLEXTRAC_HOME}/backups/uploads/$(date "+%Y.%m.%d-%H.%M.%S").tar.gz 2>/dev/null
  debug "`ls -lah ${PLEXTRAC_HOME}/backups/uploads`"
  info "Done."
}

function do_couchbase_backup() {
  info "$couchbaseComposeService: Performing backup of couchbase database"
  # Yoink database backup out to a compressed tarball
  compose_client exec $couchbaseComposeService \
      cbbackup -m full "http://localhost:8091" /backups -u ${CB_BACKUP_USER} -p ${CB_BACKUP_PASS} -v
  info "Done."
}

function backup_ensureBackupDirectory() {
  local backupDir="${PLEXTRAC_HOME}/backups"
  info "Ensuring backup directory exists at $backupDir"
  if ! test -d "${backupDir}"; then
    debug "`mkdir -vp "${PLEXTRAC_HOME}/backups"`"
  fi
  log "Done"
}

# function validate_backups() {
#   # We should have a backup within the last 24h
#
# }
