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
  info "Creating backup user ${CB_BACKUP_USER} with access to ${CB_BUCKET}"
  get_user_approval
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    local cruntime="container_client exec"
  else
    local cruntime="compose_client exec -T"
  fi
  $cruntime $couchbaseComposeService \
    couchbase-cli user-manage --set -c 127.0.0.1:8091 -u "${CB_ADMIN_USER}" -p "${CB_ADMIN_PASS}" \
      --rbac-username "${CB_BACKUP_USER}" --rbac-password "${CB_BACKUP_PASS}" --rbac-name='PlexTrac-Backup-User' \
      --roles bucket_full_access[${CB_BUCKET}] --auth-domain local
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

function configure_couchbase_users() {
  title "Checking Couchbase User Accounts"
  test_couchbase_access $CB_ADMIN_USER $CB_ADMIN_PASS || die "The admin user is broken or misconfigured - please contact support!"
  test_couchbase_access $CB_API_USER $CB_API_PASS "reportMe" || manage_api_user
  test_couchbase_access $CB_BACKUP_USER $CB_BACKUP_PASS "reportMe" || manage_backup_user
}
