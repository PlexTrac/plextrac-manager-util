## Functions for managing the Couchbase database

couchbaseUsers=('API' 'ADMIN' 'BACKUP')

function generate_default_couchbase_env() {
  cat <<- ENDCOUCHBASE
`
  echo CB_BUCKET=reportMe
  echo POSTGRES_USER=internalonly
  echo "POSTGRES_PASSWORD=<secret>"
  echo BACKUP_DIR=/opt/couchbase/backups
  for user in ${couchbaseUsers[@]}; do
    echo "CB_${user}_USER=pt${user,,}user"
    echo "CB_${user}_PASS=<secret>"
  done
`
ENDCOUCHBASE
}

function manage_api_user() {
  info "Creating unprivileged user ${CB_API_USER} with access to ${CB_BUCKET}"
  get_user_approval
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    local cruntime="container_client exec"
  else
    local cruntime="compose_client exec -T"
  fi
  $cruntime $couchbaseComposeService \
    couchbase-cli user-manage --set -c 127.0.0.1:8091 -u "${CB_ADMIN_USER}" -p "${CB_ADMIN_PASS}" \
      --rbac-username "${CB_API_USER}" --rbac-password "${CB_API_PASS}" --rbac-name='PlexTrac-API-User' \
      --roles bucket_full_access[${CB_BUCKET}] --auth-domain local
}

function manage_backup_user() {
  # NOTE: cbbackupmgr requires the `data_backup` role to move bucket data,
  # and the cluster-metadata portion of the backup requires cluster-wide
  # permissions too. Neither `data_backup` nor `backup_admin` are assignable
  # roles on Couchbase Community Edition (confirmed against Couchbase's own
  # RBAC docs: cbbackupmgr itself is an Enterprise Edition feature, and CE's
  # RBAC is limited to admin/ro_admin/bucket_full_access) - `admin` is the
  # only role on CE that satisfies cbbackupmgr's permission checks. This is
  # a real privilege increase over the old bucket-scoped backup user; if
  # that's not acceptable, use --legacy (cbbackup/cbrestore) instead, which
  # only ever needed bucket_full_access.
  info "Creating backup user ${CB_BACKUP_USER} with admin access (required by cbbackupmgr on Community Edition)"
  get_user_approval
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    local cruntime="container_client exec"
  else
    local cruntime="compose_client exec -T"
  fi
  $cruntime $couchbaseComposeService \
    couchbase-cli user-manage --set -c 127.0.0.1:8091 -u "${CB_ADMIN_USER}" -p "${CB_ADMIN_PASS}" \
      --rbac-username "${CB_BACKUP_USER}" --rbac-password "${CB_BACKUP_PASS}" --rbac-name='PlexTrac-Backup-User' \
      --roles admin --auth-domain local
}

function test_couchbase_access() {
  user=$1
  pass=$2
  bucket=${3:-reportMe}
  info "Checking user $user can access couchbase"
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    local cruntime="container_client exec"
  else
    local cruntime="compose_client exec -T"
  fi
  bucketList=$($cruntime -- $couchbaseComposeService \
                 couchbase-cli bucket-list -c 127.0.0.1:8091 -u $user -p $pass -o json || echo "noaccess")
  if [ "$bucketList" != "noaccess" ]; then
    bucketList=$(jq '.[].name' <<<$bucketList -r 2>/dev/null)
    debug ".. $user found '$bucketList'"
    grep $bucket <<<"$bucketList" >/dev/null && debug ".. $user is configured correctly" && return
  fi
  error "$user not configured correctly"
  if [ ${VALIDATION_ONLY:-0} -eq 0 ]; then
    return 1
  fi
}

function test_couchbase_backup_role() {
  local user=$1
  info "Checking $user has the admin role required by cbbackupmgr"
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    local cruntime="container_client exec"
  else
    local cruntime="compose_client exec -T"
  fi
  local rolesJson
  rolesJson=$($cruntime -- $couchbaseComposeService \
                couchbase-cli user-manage --get -c 127.0.0.1:8091 -u "${CB_ADMIN_USER}" -p "${CB_ADMIN_PASS}" \
                --rbac-username "$user" -o json 2>/dev/null || echo "noaccess")
  if [ "$rolesJson" != "noaccess" ]; then
    if jq -e '.[0].roles[] | select(.role == "admin")' <<<"$rolesJson" >/dev/null 2>&1; then
      debug ".. $user has admin role"
      return 0
    fi
  fi
  debug ".. $user is missing the admin role"
  return 1
}

function configure_couchbase_users() {
  title "Checking Couchbase User Accounts"
  test_couchbase_access $CB_ADMIN_USER $CB_ADMIN_PASS || die "The admin user is broken or misconfigured - please contact support!"
  test_couchbase_access $CB_API_USER $CB_API_PASS "reportMe" || manage_api_user
  # `admin` is a superset of bucket_full_access, so requiring it here covers
  # both cbbackupmgr (default) and --legacy (cbbackup/cbrestore) usage. Kept
  # here (in addition to the same check on `plextrac update` below) so
  # `plextrac autofix`/`plextrac check` can still catch and fix this
  # manually if the role ever gets reset outside of an update.
  if test_couchbase_access $CB_BACKUP_USER $CB_BACKUP_PASS "reportMe" && test_couchbase_backup_role $CB_BACKUP_USER; then
    debug ".. $CB_BACKUP_USER is configured correctly"
  else
    manage_backup_user
  fi
}

# Same check as configure_couchbase_users' backup-user role check, called
# separately so it also runs automatically on `plextrac update` and doesn't
# require a manual `plextrac autofix`. Idempotent: once fixed, a no-op on
# every subsequent update.
function ensure_couchbase_backup_user_role() {
  if test_couchbase_backup_role $CB_BACKUP_USER; then
    debug ".. $CB_BACKUP_USER already has the role cbbackupmgr requires"
  else
    manage_backup_user
  fi
}
