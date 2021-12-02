# Simple restore of backups
#
# Usage:
#   plextrac restore

function mod_restore() {
  title "Restoring Couchbase from backup"
  error "This is a potentiall destructive process, are you sure?"
  info "Please confirm before continuing the restore"
  if get_user_approval; then
    compose_client exec $couchbaseComposeService cbrestore /backups http://localhost:8091 -u ${CB_BACKUP_USER} -p "${CB_BACKUP_PASS}" -x conflict_resolve=0,data_only=1
  fi
}
