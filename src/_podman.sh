function podman_setup() {
  info "Configuring up PlexTrac with podman"
  debug "Podman Network Configuration"
  if container_client network exists plextrac; then
    debug "Network plextrac already exists"
  else
    debug "Creating network plextrac"
    container_client network create plextrac 1>/dev/null
  fi
  create_volume_directories
  declare -A pt_volumes
  pt_volumes["postgres-initdb"]="${PLEXTRAC_HOME:-.}/volumes/postgres-initdb"
  pt_volumes["redis"]="${PLEXTRAC_HOME:-.}/volumes/redis"
  pt_volumes["couchbase-backups"]="${PLEXTRAC_BACKUP_PATH}/couchbase"
  pt_volumes["postgres-backups"]="${PLEXTRAC_BACKUP_PATH}/postgres"
  pt_volumes["nginx_ssl_certs"]="${PLEXTRAC_HOME:-.}/volumes/nginx_ssl_certs"
  pt_volumes["nginx_logos"]="${PLEXTRAC_HOME:-.}/volumes/nginx_logos"
  pt_volumes["minio-data"]="${PLEXTRAC_HOME:-.}/volumes/minio"
  for volume in "${!pt_volumes[@]}"; do
    if container_client volume exists "$volume"; then
      debug "-- Volume $volume already exists"
    else
      debug "-- Creating volume $volume"
      container_client volume create "$volume" --driver=local --opt device="${pt_volumes[$volume]}" --opt type=none --opt o="bind" 1>/dev/null
    fi
  done
}

function plextrac_install_podman() {
  var=$(declare -p "$1")
  eval "declare -A serviceValues="${var#*=}
  PODMAN_CB_IMAGE="${PODMAN_CB_IMAGE:-docker.io/plextrac/plextracdb:7.2.0}"
  PODMAN_PG_IMAGE="${PODMAN_PG_IMAGE:-docker.io/plextrac/plextracpostgres:stable}"
  PODMAN_REDIS_IMAGE="${PODMAN_REDIS_IMAGE:-docker.io/redis:6.2-alpine}"
  PODMAN_API_IMAGE="${PODMAN_API_IMAGE:-docker.io/plextrac/plextracapi:${UPGRADE_STRATEGY:-stable}}"
  PODMAN_NGINX_IMAGE="${PODMAN_NGINX_IMAGE:-docker.io/plextrac/plextracnginx:${UPGRADE_STRATEGY:-stable}}"
  PODMAN_CKE_IMAGE="${PODMAN_CKE_IMAGE:-docker.cke-cs.com/cs:4.17.1}"
  PODMAN_MINIO_IMAGE="${PODMAN_MINIO_IMAGE:-docker.io/chainguard/minio@sha256:92b5ea1641d52262d6f65c95cffff4668663e00d6b2033875774ba1c2212cfa7}"
  PODMAN_MINIO_BOOTSTRAP_IMAGE="${PODMAN_MINIO_BOOTSTRAP_IMAGE:-docker.io/plextrac/plextrac-minio-bootstrap:stable}"

  serviceValues[ckeditor-backend-image]="${PODMAN_CKE_IMAGE}"
  serviceValues[cb-image]="${PODMAN_CB_IMAGE}"
  serviceValues[pg-image]="${PODMAN_PG_IMAGE}"
  serviceValues[redis-image]="${PODMAN_REDIS_IMAGE}"
  serviceValues[api-image]="${PODMAN_API_IMAGE}"
  serviceValues[plextracnginx-image]="${PODMAN_NGINX_IMAGE}"
  serviceValues[env-file]="--env-file ${PLEXTRAC_HOME:-}/.env"

  serviceValues[env-file]="--env-file ${PLEXTRAC_HOME:-}/.env"
  serviceValues[redis-entrypoint]=$(printf '%s' "--entrypoint=" "[" "\"redis-server\"" "," "\"--requirepass\"" "," "\"${REDIS_PASSWORD}\"" "]")
  serviceValues[cb-healthcheck]='--health-cmd=["wget","--user='$CB_ADMIN_USER'","--password='$CB_ADMIN_PASS'","-qO-","http://plextracdb:8091/pools/default/buckets/reportMe"]'
  if [ "$LETS_ENCRYPT_EMAIL" != '' ] && [ "$USE_CUSTOM_CERT" == 'false' ]; then
    serviceValues[plextracnginx-ports]="-p 0.0.0.0:443:443 -p 0.0.0.0:80:80"
  else
    serviceValues[plextracnginx-ports]="-p 0.0.0.0:443:443"
  fi
  serviceValues[migrations-env_vars]="-e COUCHBASE_URL=${COUCHBASE_URL:-http://plextracdb} -e CB_API_PASS=${CB_API_PASS} -e CB_API_USER=${CB_API_USER} -e REDIS_CONNECTION_STRING=${REDIS_CONNECTION_STRING:-redis} -e REDIS_PASSWORD=${REDIS_PASSWORD:?err} -e PG_HOST=${PG_HOST:-postgres} -e PG_MIGRATE_PATH=/usr/src/plextrac-api -e PG_SUPER_USER=${POSTGRES_USER:?err} -e PG_SUPER_PASSWORD=${POSTGRES_PASSWORD:?err} -e PG_CORE_ADMIN_PASSWORD=${PG_CORE_ADMIN_PASSWORD:?err} -e PG_CORE_ADMIN_USER=${PG_CORE_ADMIN_USER:?err} -e PG_CORE_DB=${PG_CORE_DB:?err} -e PG_RUNBOOKS_ADMIN_PASSWORD=${PG_RUNBOOKS_ADMIN_PASSWORD:?err} -e PG_RUNBOOKS_ADMIN_USER=${PG_RUNBOOKS_ADMIN_USER:?err} -e PG_RUNBOOKS_RW_PASSWORD=${PG_RUNBOOKS_RW_PASSWORD:?err} -e PG_RUNBOOKS_RW_USER=${PG_RUNBOOKS_RW_USER:?err} -e PG_RUNBOOKS_DB=${PG_RUNBOOKS_DB:?err} -e PG_CKEDITOR_ADMIN_PASSWORD=${PG_CKEDITOR_ADMIN_PASSWORD:?err} -e PG_CKEDITOR_ADMIN_USER=${PG_CKEDITOR_ADMIN_USER:?err} -e PG_CKEDITOR_DB=${PG_CKEDITOR_DB:?err} -e PG_CKEDITOR_RO_PASSWORD=${PG_CKEDITOR_RO_PASSWORD:?err} -e PG_CKEDITOR_RO_USER=${PG_CKEDITOR_RO_USER:?err} -e PG_CKEDITOR_RW_PASSWORD=${PG_CKEDITOR_RW_PASSWORD:?err} -e PG_CKEDITOR_RW_USER=${PG_CKEDITOR_RW_USER:?err} -e PG_TENANTS_WRITE_MODE=${PG_TENANTS_WRITE_MODE:-couchbase_only} -e PG_TENANTS_READ_MODE=${PG_TENANTS_READ_MODE:-couchbase_only} -e PG_CORE_RO_PASSWORD=${PG_CORE_RO_PASSWORD:?err} -e PG_CORE_RO_USER=${PG_CORE_RO_USER:?err} -e PG_CORE_RW_PASSWORD=${PG_CORE_RW_PASSWORD:?err} -e PG_CORE_RW_USER=${PG_CORE_RW_USER:?err} -e CKEDITOR_MIGRATE=${CKEDITOR_MIGRATE:-} -e CKEDITOR_SERVER_CONFIG=${CKEDITOR_SERVER_CONFIG:-}"
  serviceValues[ckeditor-backend-env_vars]="-e DATABASE_DATABASE=${PG_CKEDITOR_DB:?err} -e DATABASE_DRIVER=postgres -e DATABASE_HOST=postgres -e DATABASE_PASSWORD=${PG_CKEDITOR_ADMIN_PASSWORD:?err} -e DATABASE_POOL_CONNECTION_LIMIT=10 -e DATABASE_PORT=5432 -e DATABASE_SCHEMA=public -e DATABASE_USER=${PG_CKEDITOR_ADMIN_USER:?err} -e ENABLE_METRIC_LOGS=${CKEDITOR_ENABLE_METRIC_LOGS:-false} -e ENVIRONMENTS_MANAGEMENT_SECRET_KEY=${CKEDITOR_ENVIRONMENT_SECRET_KEY:-} -e LICENSE_KEY=${CKEDITOR_SERVER_LICENSE_KEY:-} -e LOG_LEVEL=${CKEDITOR_LOG_LEVEL:-60} -e REDIS_CONNECTION_STRING=redis://redis:6379 -e REDIS_HOST=redis -e REDIS_PASSWORD=${REDIS_PASSWORD:?err}"
  serviceValues[minio-entrypoint]="$(printf '%s' "--entrypoint=" "[" "\"/usr/bin/minio\"" "," "\"server\"" "," "\"/data\"" "]")"
  serviceValues[minio-env_vars]="-e MINIO_ROOT_USER=${MINIO_ROOT_USER:-admin} -e MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD:?err} -e MINIO_LOCAL_USER=${MINIO_LOCAL_USER:-localadmin} -e MINIO_LOCAL_PASSWORD=${MINIO_LOCAL_PASSWORD:?err} -e CLOUD_STORAGE_ENDPOINT=${CLOUD_STORAGE_ENDPOINT:-127.0.0.1} -e CLOUD_STORAGE_PORT=${CLOUD_STORAGE_PORT:-9000} -e CLOUD_STORAGE_SSL=${CLOUD_STORAGE_SSL:-false} -e CLOUD_STORAGE_ACCESS_KEY=${CLOUD_STORAGE_ACCESS_KEY:?err} -e CLOUD_STORAGE_SECRET_KEY=${CLOUD_STORAGE_SECRET_KEY:?err}"
  serviceValues[minio-bootstrap-env_vars]="-e MINIO_ROOT_USER=${MINIO_ROOT_USER:-admin} -e MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD:?err} -e MINIO_LOCAL_USER=${MINIO_LOCAL_USER:-localadmin} -e MINIO_LOCAL_PASSWORD=${MINIO_LOCAL_PASSWORD:?err} -e CLOUD_STORAGE_ACCESS_KEY=${CLOUD_STORAGE_ACCESS_KEY:?err} -e CLOUD_STORAGE_SECRET_KEY=${CLOUD_STORAGE_SECRET_KEY:?err} -e MINIO_ENABLED=${MINIO_ENABLED:-true} -e UPSTREAM_CLOUD_BUCKET=${UPSTREAM_CLOUD_BUCKET:-cloud}"


  title "Installing PlexTrac Instance"
  requires_user_plextrac
  mod_configure
  info "Starting Databases before other services"
  # Check if DB running first, then start it.
  debug "Handling Databases..."
  for database in "${databaseNames[@]}"; do
    info "Checking $database"
    if container_client container exists "$database"; then
      debug "$database already exists"
      # if database exists but isn't running
      if [ "$(container_client container inspect --format '{{.State.Status}}' "$database")" != "running" ]; then
        info "Starting $database"
        container_client start "$database" 1>/dev/null
      else
        info "$database is already running"
      fi
    else
      info "Container doesn't exist. Creating $database"
      if [ "$database" == "plextracdb" ]; then
        local volumes=${serviceValues[cb-volumes]}
        local ports="${serviceValues[cb-ports]}"
        local healthcheck="${serviceValues[cb-healthcheck]}"
        local image="${serviceValues[cb-image]}"
        local env_vars=""
      elif [ "$database" == "postgres" ]; then
        local volumes="${serviceValues[pg-volumes]}"
        local ports="${serviceValues[pg-ports]}"
        local healthcheck="${serviceValues[pg-healthcheck]}"
        local image="${serviceValues[pg-image]}"
        local env_vars="${serviceValues[pg-env-vars]}"
      fi
      container_client run "${serviceValues[env-file]}" "$env_vars" --restart=always "$healthcheck" \
        "$volumes" --name="${database}" "${serviceValues[network]}" "$ports" -d "$image" 1>/dev/null
      info "Sleeping to give $database a chance to start up"
      local progressBar
      for i in `seq 1 10`; do
        progressBar=`printf ".%.0s%s"  {1..$i} "${progressBar:-}"`
        msg "\r%b" "${GREEN}[+]${RESET} ${NOCURSOR}${progressBar}"
        sleep 2
      done
      >&2 echo -n "${RESET}"
      log "Done"
    fi
  done
  mod_autofix
  if [ ${RESTOREONINSTALL:-0} -eq 1 ]; then
    info "Restoring from backups"
    log "Restoring databases first"
    RESTORETARGET="couchbase" mod_restore
    if [ -n "$(ls -A -- ${PLEXTRAC_BACKUP_PATH}/postgres/)" ]; then
      RESTORETARGET="postgres" mod_restore
    else
      debug "No postgres backups to restore"
    fi
    debug "Checking for uploads to restore"
    if [ -n "$(ls -A -- ${PLEXTRAC_BACKUP_PATH}/uploads/)" ]; then
      log "Starting API to prepare for uploads restore"
      if container_client container exists plextracapi; then
        if [ "$(container_client container inspect --format '{{.State.Status}}' plextracapi)" != "running" ]; then
          container_client start plextracapi 1>/dev/null
        else
          log "plextracapi is already running"
        fi
      else
        debug "Creating plextracapi"
        container_client run "${serviceValues[env-file]}" --restart=always "$healthcheck" \
        "$volumes" --name="plextracapi" "${serviceValues[network]}" -d "${serviceValues[api-image]}" 1>/dev/null
      fi
      log "Restoring uploads"
      RESTORETARGET="uploads" mod_restore
    else
      debug "No uploads to restore"
    fi
  fi

  mod_start # allow up to 10 or specified minutes for startup on install, due to migrations
  run_cb_migrations 600
  if [ "${CKEDITOR_MIGRATE:-false}" == "true" ]; then
    ckeditorNginxConf
    getCKEditorRTCConfig
    podman rm -f plextracapi
    mod_start # this doesn't re-run migrations
    run_cb_migrations
  fi

  mod_info
  info "Post installation note:"
  log "If you wish to have access to historical logs, you can configure docker to send logs to journald."
  log "Please see the config steps at"
  log "https://docs.plextrac.com/plextrac-documentation/product-documentation-1/on-premise-management/setting-up-historical-logs"
}

function plextrac_start_podman() {
  var=$(declare -p "$1")
  eval "declare -A serviceValues="${var#*=}
  serviceValues[redis-entrypoint]=$(printf '%s' "--entrypoint=" "[" "\"redis-server\"" "," "\"--requirepass\"" "," "\"${REDIS_PASSWORD}\"" "]")
  serviceValues[cb-healthcheck]='--health-cmd=["wget","--user='$CB_ADMIN_USER'","--password='$CB_ADMIN_PASS'","-qO-","http://plextracdb:8091/pools/default/buckets/reportMe"]'
  PODMAN_CB_IMAGE="${PODMAN_CB_IMAGE:-docker.io/plextrac/plextracdb:7.2.0}"
  PODMAN_PG_IMAGE="${PODMAN_PG_IMAGE:-docker.io/plextrac/plextracpostgres:stable}"
  PODMAN_REDIS_IMAGE="${PODMAN_REDIS_IMAGE:-docker.io/redis:6.2-alpine}"
  PODMAN_API_IMAGE="${PODMAN_API_IMAGE:-docker.io/plextrac/plextracapi:${UPGRADE_STRATEGY:-stable}}"
  PODMAN_NGINX_IMAGE="${PODMAN_NGINX_IMAGE:-docker.io/plextrac/plextracnginx:${UPGRADE_STRATEGY:-stable}}"
  PODMAN_CKE_IMAGE="${PODMAN_CKE_IMAGE:-docker.cke-cs.com/cs:4.17.1}"
  PODMAN_MINIO_IMAGE="${PODMAN_MINIO_IMAGE:-docker.io/chainguard/minio@sha256:92b5ea1641d52262d6f65c95cffff4668663e00d6b2033875774ba1c2212cfa7}"
  PODMAN_MINIO_BOOTSTRAP_IMAGE="${PODMAN_MINIO_BOOTSTRAP_IMAGE:-docker.io/plextrac/plextrac-minio-bootstrap:stable}"

  serviceValues[ckeditor-backend-image]="${PODMAN_CKE_IMAGE}"
  serviceValues[minio-image]="${PODMAN_MINIO_IMAGE}"
  serviceValues[minio-bootstrap-image]="${PODMAN_MINIO_BOOTSTRAP_IMAGE}"
  serviceValues[cb-image]="${PODMAN_CB_IMAGE}"
  serviceValues[pg-image]="${PODMAN_PG_IMAGE}"
  serviceValues[redis-image]="${PODMAN_REDIS_IMAGE}"
  serviceValues[api-image]="${PODMAN_API_IMAGE}"
  serviceValues[plextracnginx-image]="${PODMAN_NGINX_IMAGE}"
  serviceValues[env-file]="--env-file ${PLEXTRAC_HOME:-}/.env"
  if [ "$LETS_ENCRYPT_EMAIL" != '' ] && [ "$USE_CUSTOM_CERT" == 'false' ]; then
    serviceValues[plextracnginx-ports]="-p 0.0.0.0:443:443 -p 0.0.0.0:80:80"
  else
    serviceValues[plextracnginx-ports]="-p 0.0.0.0:443:443"
  fi
  serviceValues[migrations-env_vars]="-e COUCHBASE_URL=${COUCHBASE_URL:-http://plextracdb} -e CB_API_PASS=${CB_API_PASS} -e CB_API_USER=${CB_API_USER} -e REDIS_CONNECTION_STRING=${REDIS_CONNECTION_STRING:-redis} -e REDIS_PASSWORD=${REDIS_PASSWORD:?err} -e PG_HOST=${PG_HOST:-postgres} -e PG_MIGRATE_PATH=/usr/src/plextrac-api -e PG_SUPER_USER=${POSTGRES_USER:?err} -e PG_SUPER_PASSWORD=${POSTGRES_PASSWORD:?err} -e PG_CORE_ADMIN_PASSWORD=${PG_CORE_ADMIN_PASSWORD:?err} -e PG_CORE_ADMIN_USER=${PG_CORE_ADMIN_USER:?err} -e PG_CORE_DB=${PG_CORE_DB:?err} -e PG_RUNBOOKS_ADMIN_PASSWORD=${PG_RUNBOOKS_ADMIN_PASSWORD:?err} -e PG_RUNBOOKS_ADMIN_USER=${PG_RUNBOOKS_ADMIN_USER:?err} -e PG_RUNBOOKS_RW_PASSWORD=${PG_RUNBOOKS_RW_PASSWORD:?err} -e PG_RUNBOOKS_RW_USER=${PG_RUNBOOKS_RW_USER:?err} -e PG_RUNBOOKS_DB=${PG_RUNBOOKS_DB:?err} -e PG_CKEDITOR_ADMIN_PASSWORD=${PG_CKEDITOR_ADMIN_PASSWORD:?err} -e PG_CKEDITOR_ADMIN_USER=${PG_CKEDITOR_ADMIN_USER:?err} -e PG_CKEDITOR_DB=${PG_CKEDITOR_DB:?err} -e PG_CKEDITOR_RO_PASSWORD=${PG_CKEDITOR_RO_PASSWORD:?err} -e PG_CKEDITOR_RO_USER=${PG_CKEDITOR_RO_USER:?err} -e PG_CKEDITOR_RW_PASSWORD=${PG_CKEDITOR_RW_PASSWORD:?err} -e PG_CKEDITOR_RW_USER=${PG_CKEDITOR_RW_USER:?err} -e PG_TENANTS_WRITE_MODE=${PG_TENANTS_WRITE_MODE:-couchbase_only} -e PG_TENANTS_READ_MODE=${PG_TENANTS_READ_MODE:-couchbase_only} -e PG_CORE_RO_PASSWORD=${PG_CORE_RO_PASSWORD:?err} -e PG_CORE_RO_USER=${PG_CORE_RO_USER:?err} -e PG_CORE_RW_PASSWORD=${PG_CORE_RW_PASSWORD:?err} -e PG_CORE_RW_USER=${PG_CORE_RW_USER:?err} -e CKEDITOR_MIGRATE=${CKEDITOR_MIGRATE:-} -e CKEDITOR_SERVER_CONFIG=${CKEDITOR_SERVER_CONFIG:-}"
  serviceValues[ckeditor-backend-env_vars]="-e DATABASE_DATABASE=${PG_CKEDITOR_DB:?err} -e DATABASE_DRIVER=postgres -e DATABASE_HOST=postgres -e DATABASE_PASSWORD=${PG_CKEDITOR_ADMIN_PASSWORD:?err} -e DATABASE_POOL_CONNECTION_LIMIT=10 -e DATABASE_PORT=5432 -e DATABASE_SCHEMA=public -e DATABASE_USER=${PG_CKEDITOR_ADMIN_USER:?err} -e ENABLE_METRIC_LOGS=${CKEDITOR_ENABLE_METRIC_LOGS:-false} -e ENVIRONMENTS_MANAGEMENT_SECRET_KEY=${CKEDITOR_ENVIRONMENT_SECRET_KEY:-} -e LICENSE_KEY=${CKEDITOR_SERVER_LICENSE_KEY:-} -e LOG_LEVEL=${CKEDITOR_LOG_LEVEL:-} -e REDIS_CONNECTION_STRING=redis://redis:6379 -e REDIS_HOST=redis -e REDIS_PASSWORD=${REDIS_PASSWORD:?err}"
  serviceValues[minio-entrypoint]="$(printf '%s' "--entrypoint=" "[" "\"/usr/bin/minio\"" "," "\"server\"" "," "\"/data\"" "]")"
  serviceValues[minio-env_vars]="-e MINIO_ROOT_USER=${MINIO_ROOT_USER:-admin} -e MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD:?err} -e MINIO_LOCAL_USER=${MINIO_LOCAL_USER:-localadmin} -e MINIO_LOCAL_PASSWORD=${MINIO_LOCAL_PASSWORD:?err} -e CLOUD_STORAGE_ENDPOINT=${CLOUD_STORAGE_ENDPOINT:-127.0.0.1} -e CLOUD_STORAGE_PORT=${CLOUD_STORAGE_PORT:-9000} -e CLOUD_STORAGE_SSL=${CLOUD_STORAGE_SSL:-false} -e CLOUD_STORAGE_ACCESS_KEY=${CLOUD_STORAGE_ACCESS_KEY:?err} -e CLOUD_STORAGE_SECRET_KEY=${CLOUD_STORAGE_SECRET_KEY:?err}"
  serviceValues[minio-bootstrap-env_vars]="-e MINIO_ROOT_USER=${MINIO_ROOT_USER:-admin} -e MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD:?err} -e MINIO_LOCAL_USER=${MINIO_LOCAL_USER:-localadmin} -e MINIO_LOCAL_PASSWORD=${MINIO_LOCAL_PASSWORD:?err} -e CLOUD_STORAGE_ACCESS_KEY=${CLOUD_STORAGE_ACCESS_KEY:?err} -e CLOUD_STORAGE_SECRET_KEY=${CLOUD_STORAGE_SECRET_KEY:?err} -e MINIO_ENABLED=${MINIO_ENABLED:-true} -e UPSTREAM_CLOUD_BUCKET=${UPSTREAM_CLOUD_BUCKET:-cloud}"

  if [ "${CKEDITOR_MIGRATE:-false}" == "true" ]; then
    serviceNames=("plextracdb" "postgres" "redis" "ckeditor-backend" "plextracapi" "notification-engine" "notification-sender" "contextual-scoring-service" "migrations" "plextracnginx" "minio" "minio-bootstrap")
  fi
  serviceValues[notification-env_vars]="-e API_INTEGRATION_AUTH_CONFIG_NOTIFICATION_SERVICE=${API_INTEGRATION_AUTH_CONFIG_NOTIFICATION_SERVICE:?err}"
  serviceValues[notification-env_vars]="-e INTERNAL_API_KEY_SHARED=${INTERNAL_API_KEY_SHARED:?err}"

  title "Starting PlexTrac..."
  requires_user_plextrac

  for service in "${serviceNames[@]}"; do
    if [ "$service" == "migrations" ]; then
        # Skip the migration service, as it will be started separately
        continue
    fi
    debug "Checking $service"
    local volumes=""
    local ports=""
    local healthcheck=""
    local image="${serviceValues[api-image]}"
    local restart_policy="--restart=always"
    local entrypoint=""
    local deploy=""
    local env_vars=""
    local alias=""
    local init=""
    if container_client container exists "$service"; then
      if [ "$(container_client container inspect --format '{{.State.Status}}' "$service")" != "running" ]; then
        info "Starting $service"
        container_client start "$service" 1>/dev/null
      else
        info "$service is already running"
      fi
    else
      if [ "$service" == "plextracdb" ]; then
        local volumes="${serviceValues[cb-volumes]}"
        local ports="${serviceValues[cb-ports]}"
        local healthcheck="${serviceValues[cb-healthcheck]}"
        local image="${serviceValues[cb-image]}"
      elif [ "$service" == "postgres" ]; then
        local volumes="${serviceValues[pg-volumes]}"
        local ports="${serviceValues[pg-ports]}"
        local healthcheck="${serviceValues[pg-healthcheck]}"
        local image="${serviceValues[pg-image]}"
        local env_vars="${serviceValues[pg-env-vars]}"
      elif [ "$service" == "plextracapi" ]; then
        local volumes="${serviceValues[api-volumes]}"
        local healthcheck="${serviceValues[api-healthcheck]}"
        local image="${serviceValues[api-image]}"
      elif [ "$service" == "redis" ]; then
        local volumes="${serviceValues[redis-volumes]}"
        local image="${serviceValues[redis-image]}"
        local entrypoint="${serviceValues[redis-entrypoint]}"
        local healthcheck="${serviceValues[redis-healthcheck]}"
      elif [ "$service" == "notification-engine" ]; then
        local entrypoint="${serviceValues[notification-engine-entrypoint]}"
        local healthcheck="${serviceValues[notification-engine-healthcheck]}"
        local env_vars="${serviceValues[notification-env_vars]}"
        local init="--init"
      elif [ "$service" == "notification-sender" ]; then
        local entrypoint="${serviceValues[notification-sender-entrypoint]}"
        local healthcheck="${serviceValues[notification-sender-healthcheck]}"
        local env_vars="${serviceValues[notification-env_vars]}"
        local init="--init"
      elif [ "$service" == "contextual-scoring-service" ]; then
        local entrypoint="${serviceValues[contextual-scoring-service-entrypoint]}"
        local healthcheck="${serviceValues[contextual-scoring-service-healthcheck]}"
        local deploy="" # update this
      elif [ "$service" == "migrations" ]; then
        local volumes="${serviceValues[migrations-volumes]}"
        local env_vars="${serviceValues[migrations-env_vars]}"
      elif [ "$service" == "plextracnginx" ]; then
        local volumes="${serviceValues[plextracnginx-volumes]}"
        local ports="${serviceValues[plextracnginx-ports]}"
        local image="${serviceValues[plextracnginx-image]}"
        local healthcheck="${serviceValues[plextracnginx-healthcheck]}"
        local alias="${serviceValues[plextracnginx-alias]}"
      elif [ "$service" == "ckeditor-backend" ]; then
        local image="${serviceValues[ckeditor-backend-image]}"
        local env_vars="${serviceValues[ckeditor-backend-env_vars]}"
      elif [ "$service" == "minio" ]; then
        local image="${serviceValues[minio-image]}"
        local entrypoint="${serviceValues[minio-entrypoint]}"
        local env_vars="${serviceValues[minio-env_vars]}"
        local volumes="${serviceValues[minio-volumes]}"
      elif [ "$service" == "minio-bootstrap" ]; then
        local image="${serviceValues[minio-bootstrap-image]}"
        local env_vars="${serviceValues[minio-bootstrap-env_vars]}"
      fi
      info "Creating $service"
      # This specific if loop is because Bash escaping and the specific need for the podman flag --entrypoint were being a massive pain in figuring out. After hours of effort, simply making an if statement here and calling podman directly fixes the escaping issues
      container_client run ${serviceValues[env-file]} $env_vars $init $alias $entrypoint $restart_policy $healthcheck \
        $volumes --name=${service} $deploy ${serviceValues[network]} $ports -d $image 1>/dev/null
    fi
  done
}

function podman_run_cb_migrations() {
  var=$(declare -p "$1")
  eval "declare -A serviceValues="${var#*=}
  serviceValues[env-file]="--env-file ${PLEXTRAC_HOME:-}/.env"
  serviceValues[migrations-env_vars]="-e COUCHBASE_URL=${COUCHBASE_URL:-http://plextracdb} -e CB_API_PASS=${CB_API_PASS} -e CB_API_USER=${CB_API_USER} -e REDIS_CONNECTION_STRING=${REDIS_CONNECTION_STRING:-redis} -e REDIS_PASSWORD=${REDIS_PASSWORD:?err} -e PG_HOST=${PG_HOST:-postgres} -e PG_MIGRATE_PATH=/usr/src/plextrac-api -e PG_SUPER_USER=${POSTGRES_USER:?err} -e PG_SUPER_PASSWORD=${POSTGRES_PASSWORD:?err} -e PG_CORE_ADMIN_PASSWORD=${PG_CORE_ADMIN_PASSWORD:?err} -e PG_CORE_ADMIN_USER=${PG_CORE_ADMIN_USER:?err} -e PG_CORE_DB=${PG_CORE_DB:?err} -e PG_RUNBOOKS_ADMIN_PASSWORD=${PG_RUNBOOKS_ADMIN_PASSWORD:?err} -e PG_RUNBOOKS_ADMIN_USER=${PG_RUNBOOKS_ADMIN_USER:?err} -e PG_RUNBOOKS_RW_PASSWORD=${PG_RUNBOOKS_RW_PASSWORD:?err} -e PG_RUNBOOKS_RW_USER=${PG_RUNBOOKS_RW_USER:?err} -e PG_RUNBOOKS_DB=${PG_RUNBOOKS_DB:?err} -e PG_CKEDITOR_ADMIN_PASSWORD=${PG_CKEDITOR_ADMIN_PASSWORD:?err} -e PG_CKEDITOR_ADMIN_USER=${PG_CKEDITOR_ADMIN_USER:?err} -e PG_CKEDITOR_DB=${PG_CKEDITOR_DB:?err} -e PG_CKEDITOR_RO_PASSWORD=${PG_CKEDITOR_RO_PASSWORD:?err} -e PG_CKEDITOR_RO_USER=${PG_CKEDITOR_RO_USER:?err} -e PG_CKEDITOR_RW_PASSWORD=${PG_CKEDITOR_RW_PASSWORD:?err} -e PG_CKEDITOR_RW_USER=${PG_CKEDITOR_RW_USER:?err} -e PG_TENANTS_WRITE_MODE=${PG_TENANTS_WRITE_MODE:-couchbase_only} -e PG_TENANTS_READ_MODE=${PG_TENANTS_READ_MODE:-couchbase_only} -e PG_CORE_RO_PASSWORD=${PG_CORE_RO_PASSWORD:?err} -e PG_CORE_RO_USER=${PG_CORE_RO_USER:?err} -e PG_CORE_RW_PASSWORD=${PG_CORE_RW_PASSWORD:?err} -e PG_CORE_RW_USER=${PG_CORE_RW_USER:?err} -e CKEDITOR_MIGRATE=${CKEDITOR_MIGRATE:-} -e CKEDITOR_SERVER_CONFIG=${CKEDITOR_SERVER_CONFIG:-}"
  PODMAN_API_IMAGE="${PODMAN_API_IMAGE:-docker.io/plextrac/plextracapi:${UPGRADE_STRATEGY:-stable}}"
  serviceValues[api-image]="${PODMAN_API_IMAGE}"
  local env_vars="${serviceValues[migrations-env_vars]}"
  local volumes="${serviceValues[migrations-volumes]}"
  local image="${serviceValues[api-image]}"

  debug "Running migrations"
  podman run ${serviceValues[env-file]} $env_vars --entrypoint='["/bin/sh","-c","npm run maintenance:enable && npm run pg:superuser:bootstrap --if-present && npm run pg:migrate && npm run db:migrate && npm run pg:etl up all && npm run maintenance:disable"]' --restart=no \
  $volumes:z --replace --name="migrations" ${serviceValues[network]} -d $image 1>/dev/null
}

function podman_pull_images() {

  declare -A service_images
  PODMAN_CB_IMAGE="${PODMAN_CB_IMAGE:-docker.io/plextrac/plextracdb:7.2.0}"
  PODMAN_PG_IMAGE="${PODMAN_PG_IMAGE:-docker.io/plextrac/plextracpostgres:stable}"
  PODMAN_REDIS_IMAGE="${PODMAN_REDIS_IMAGE:-docker.io/redis:6.2-alpine}"
  PODMAN_API_IMAGE="${PODMAN_API_IMAGE:-docker.io/plextrac/plextracapi:${UPGRADE_STRATEGY:-stable}}"
  PODMAN_NGINX_IMAGE="${PODMAN_NGINX_IMAGE:-docker.io/plextrac/plextracnginx:${UPGRADE_STRATEGY:-stable}}"

  service_images[cb-image]="${PODMAN_CB_IMAGE}"
  service_images[pg-image]="${PODMAN_PG_IMAGE}"
  service_images[redis-image]="${PODMAN_REDIS_IMAGE}"
  service_images[api-image]="${PODMAN_API_IMAGE}"
  service_images[plextracnginx-image]="${PODMAN_NGINX_IMAGE}"

  info "Pulling updated container images"
  for image in "${service_images[@]}"; do
    debug "Pulling $image"
    podman pull $image 1>/dev/null
  done
  log "Done."
}

function podman_remove() {
  for service in "${serviceNames[@]}"; do
    if [ "$service" != "plextracdb" ] && [ "$service" != "postgres" ]; then
      if podman container exists "$service"; then
        podman stop "$service" 1>/dev/null
        podman rm -f "$service" 1>/dev/null
        podman image prune -f 1>/dev/null
      fi
    fi
  done
}
