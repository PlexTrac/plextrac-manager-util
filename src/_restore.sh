# Simple restore of backups
#
# Usage:
#   plextrac restore

function mod_restore() {
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
