## Functions for managing the Postgres Database

postgresDatabases=('CORE' 'RUNBOOKS' 'CKEDITOR')
postgresUsers=('ADMIN' 'RW' 'RO')

function generate_default_postgres_env() {
  cat <<- ENDPOSTGRES
`
  echo PG_HOST=postgres
  echo POSTGRES_USER=internalonly
  echo "POSTGRES_PASSWORD=<secret>"
  for db in ${postgresDatabases[@]}; do
    echo "PG_${db}_DB=${db,,}"
    for user in ${postgresUsers[@]}; do
      echo "PG_${db}_${user}_USER=${db,,}_${user,,}"
      echo "PG_${db}_${user}_PASSWORD=<secret>"
    done
  done
`
ENDPOSTGRES
}

function deploy_volume_contents_postgres() {
  debug "Adding postgres initdb scripts to volume mount"
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    targetDir="${PLEXTRAC_HOME}/volumes/postgres-initdb"
  else
    targetDir=`compose_client config --format=json | jq -r \
      '.volumes[] | select(.name | test("postgres-initdb")) |
        .driver_opts.device'`
  fi
  debug "Adding scripts to $targetDir"
  cat > "$targetDir/bootstrap-template.sql.txt" <<- "EOBOOTSTRAPTEMPLATE"
-- Add Service Roles
--
-- Service Admin
CREATE USER :"admin_user" WITH PASSWORD :'admin_password';
-- Service Read-Only User
CREATE USER :"ro_user" WITH PASSWORD :'ro_password';
-- Service Read-Write User
CREATE USER :"rw_user" WITH PASSWORD :'rw_password';

-- Role memberships
-- Each role inherits from the role below
GRANT :"ro_user" TO :"rw_user";
GRANT :"rw_user" TO :"admin_user";

-- Create Service Database
CREATE DATABASE :"db_name";
REVOKE ALL ON DATABASE :"db_name" FROM public;
GRANT CONNECT ON DATABASE :"db_name" TO :"ro_user";

-- switch to the new database.
\connect :"db_name";

-- Schema level grants within the database
--
-- Service Read-Only user needs basic access
GRANT USAGE ON SCHEMA public TO :"ro_user";
-- Only the admin account should ever create new resources
-- This also marks Service Admin account as owner of new resources
GRANT CREATE ON SCHEMA public TO :"admin_user";


-- Enable read access to all new tables for Service Read-Only
ALTER DEFAULT PRIVILEGES FOR ROLE :"admin_user"
    GRANT SELECT ON TABLES TO :"ro_user";
-- Enable read-write access to all new tables for Service Read-Write
ALTER DEFAULT PRIVILEGES FOR ROLE :"admin_user"
    GRANT INSERT,DELETE,TRUNCATE,UPDATE ON TABLES TO :"rw_user";
-- Need to enable usage on sequences for Service Read-Write
-- to enable auto-incrementing ids
ALTER DEFAULT PRIVILEGES FOR ROLE :"admin_user"
    GRANT USAGE ON SEQUENCES TO :"rw_user";
EOBOOTSTRAPTEMPLATE

  # Create a separate file for AI SQL user creation
  cat > "$targetDir/ai-sql-user.sql.txt" <<- "EOAISQLUSER"
-- AI SQL User creation for core database
CREATE USER :"pg_core_ai_sql_user" WITH PASSWORD :'pg_core_ai_sql_password';

-- Grant necessary permissions
GRANT CONNECT ON DATABASE :"db_name" TO :"pg_core_ai_sql_user";
GRANT USAGE ON SCHEMA public TO :"pg_core_ai_sql_user";
EOAISQLUSER

  cat > "$targetDir/initdb.sh" <<- "EOINITDBSCRIPT"
#!/bin/bash

for db_name in core runbooks ckeditor; do
  # Convert database name to uppercase for variable name construction
  db_name_uppercase=${db_name^^}

  # Build environment variable names
  admin_user="PG_${db_name_uppercase}_ADMIN_USER"
  admin_password="PG_${db_name_uppercase}_ADMIN_PASSWORD"
  ro_user="PG_${db_name_uppercase}_RO_USER"
  ro_password="PG_${db_name_uppercase}_RO_PASSWORD"
  rw_user="PG_${db_name_uppercase}_RW_USER"
  rw_password="PG_${db_name_uppercase}_RW_PASSWORD"

  # Execute bootstrap template for all databases
  psql -a -v ON_ERROR_STOP=1 \
    -v db_name="${db_name}" \
    -v admin_user="${!admin_user}" \
    -v admin_password="${!admin_password}" \
    -v ro_user="${!ro_user}" \
    -v ro_password="${!ro_password}" \
    -v rw_user="${!rw_user}" \
    -v rw_password="${!rw_password}" \
    --username $POSTGRES_USER \
    -d $POSTGRES_USER \
    < /docker-entrypoint-initdb.d/bootstrap-template.sql.txt

  # Execute AI SQL user creation only for core database
  if [ "${db_name}" = "core" ]; then
    psql -a -v ON_ERROR_STOP=1 \
      -v db_name="${db_name}" \
      -v pg_core_ai_sql_user="$PG_CORE_AI_SQL_USER" \
      -v pg_core_ai_sql_password="$PG_CORE_AI_SQL_PASSWORD" \
      --username $POSTGRES_USER \
      -d ${db_name} \
      < /docker-entrypoint-initdb.d/ai-sql-user.sql.txt
  fi
done
EOINITDBSCRIPT
  # postgres container does not have a uid 1337, most reliable way to bootstrap
  # without adding failure points is just allow other users to read the (not secret)
  # bootstrapping scripts
  debug "`chmod -Rc a+r $targetDir`"
  log "Done."
}

function postgres_metrics_validation() {
  if [ "${PG_METRICS_USER:-}" != "" ]; then
    info "Checking user $PG_METRICS_USER can access postgres metrics"
    if [ "$CONTAINER_RUNTIME" != "podman" ]; then
      local container_runtime="compose_client exec -T -u 1337"
    else
      local container_runtime="container_client exec"
    fi
    debug "`$container_runtime -e PGPASSWORD=$POSTGRES_PASSWORD $postgresComposeService \
        psql -a -v -U internalonly -d core 2>&1 <<- EOF
CREATE OR REPLACE FUNCTION __tmp_create_user() returns void as \\$\\$
BEGIN
  IF NOT EXISTS (
          SELECT                       -- SELECT list can stay empty for this
          FROM   pg_catalog.pg_user
          WHERE  usename = '$PG_METRICS_USER') THEN
    CREATE USER $PG_METRICS_USER;
  END IF;
END;
\\$\\$ language plpgsql;

SELECT __tmp_create_user();
DROP FUNCTION __tmp_create_user();

ALTER USER $PG_METRICS_USER WITH PASSWORD '$PG_METRICS_PASSWORD';
ALTER USER $PG_METRICS_USER SET SEARCH_PATH TO $PG_METRICS_USER,pg_catalog;

GRANT pg_monitor to $PG_METRICS_USER;
EOF
`"
fi

  # Stand up PlexTrac in Vagrant --
  # Query inside container with compose_client passing in user / pass and then query
  # Review _backup.sh for a postgres query / access example

  # This function should be run when? Run on update or arbitrarily -- _check.sh line 21
  # /vagrant/src/plextrac autofix

}

function mod_autofix() {
  title "Fixing Auto-Correctable Issues"
  configure_couchbase_users
  # Add postgres configuration monitor here
  postgres_metrics_validation
}

# One container id for migration polling. In normal operation only one of unified-migrations /
# couchbase-migrations is running at a time (the CLI never starts both for one update). docker ps -a
# can still show exited containers from the other path after prior upgrades, so naive "grep migrations"
# matched multiple IDs -> docker logs failed (single container only) under set -e.
# Optional arg: legacy | umf | any (default any). legacy = couchbase + Podman --name=migrations only;
# use on legacy wait loops so we do not follow a stale exited unified container.
function _plextrac_one_migration_container_id() {
  local mode="${1:-any}"
  local id cid n st
  local -a filters=()

  case "$mode" in
    legacy) filters=(couchbase-migrations) ;;
    umf)    filters=(unified-migrations) ;;
    *)      filters=(unified-migrations couchbase-migrations) ;;
  esac

  for n in "${filters[@]}"; do
    while read -r cid; do
      [ -z "$cid" ] && continue
      st=$(container_client inspect --format '{{.State.Status}}' "$cid" 2>/dev/null) || continue
      [ "$st" = "running" ] && printf '%s' "$cid" && return 0
    done < <(container_client ps -aq --filter "name=$n" 2>/dev/null)
  done

  for n in "${filters[@]}"; do
    id="$(container_client ps -aq --filter "name=$n" 2>/dev/null | head -n1)"
    if [ -n "$id" ]; then
      printf '%s' "$id"
      return 0
    fi
  done

  if [ "$mode" = "legacy" ] || [ "$mode" = "any" ]; then
    while read -r cid; do
      [ -z "$cid" ] && continue
      n=$(container_client inspect --format '{{.Name}}' "$cid" 2>/dev/null) || continue
      case "$n" in *unified-migrations*|*couchbase-migrations*) continue ;; esac
      case "$n" in */migrations|migrations) printf '%s' "$cid"; return 0 ;; esac
    done < <(container_client ps -aq 2>/dev/null)
  fi
  printf ''
}

# docker inspect/logs accept one id; if anything returns "id1 id2", use the first only.
function _plextrac_sanitize_container_id() {
  local raw="${1:-}"
  raw="${raw%% *}"
  raw="${raw//$'\n'/}"
  raw="${raw//$'\r'/}"
  printf '%s' "$raw"
}

function mod_check_etl_status() {
  local migration_exited="running"
  local mig_cid status_line logs_line
  title "Checking Data Migration Status"
  info "Checking Migration Status"
  secs=300
  endTime=$(( $(date +%s) + secs ))

  mig_cid="$(_plextrac_sanitize_container_id "$(_plextrac_one_migration_container_id)")"
  if [[ -n "$mig_cid" ]]; then
    migration_exited="running"
  else
    migration_exited="exited"
    debug "Migration container not found"
  fi
  while [ "$migration_exited" == "running" ]; do
    mig_cid="$(_plextrac_sanitize_container_id "$(_plextrac_one_migration_container_id)")"
    if [[ -z "$mig_cid" ]]; then
      migration_exited="exited"
      break
    fi
    if ! status_line=$(container_client inspect --format '{{.State.Status}}' "$mig_cid" 2>/dev/null); then
      migration_exited="exited"
      break
    fi
    migration_exited="$status_line"
    if [ "$migration_exited" != "running" ]; then
      break
    fi
    if [ "$(date +%s)" -gt "$endTime" ]; then
      error "Migration container has been running for over 5 minutes or is still running. Please ensure they complete or fail before taking further action with the PlexTrac Manager Utility. You can check on the logs by running 'docker compose logs -f couchbase-migrations' or 'docker compose logs -f unified-migrations'"
      die "Exiting PlexTrac Manager Utility."
    fi
    for s in / - \\ \|; do
      status_line=$(container_client inspect --format '{{.State.Status}}' "$mig_cid" 2>/dev/null || echo "?")
      logs_line=$(container_client logs "$mig_cid" 2>/dev/null | tail -n 1)
      printf "\r\033[K%s %s -- %s" "$s" "$status_line" "$logs_line"
      sleep .1
    done
    sleep 1
  done
  printf "\r\033[K"
  info "Migrations complete"

  if [ "${IGNORE_ETL_STATUS:-false}" == "false" ]; then
   if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      local etl_running_backend_version="$(for i in $(podman ps -a -q --filter name=plextracapi); do podman inspect "$i" --format json | jq -r '(.[].Config.Labels | ."org.opencontainers.image.version")'; done | sort -u)"
    else
      local etl_running_backend_version="$(for i in $(compose_client ps plextracapi -q); do docker container inspect "$i" --format json | jq -r '(.[].Config.Labels | ."org.opencontainers.image.version")'; done | sort -u)"
    fi
    if [[ $etl_running_backend_version != "" ]]; then
      debug "Running Version: $etl_running_backend_version"
      # Get the major and minor version from the running containers
      local etl_maj_ver=$(echo "$etl_running_backend_version" | cut -d '.' -f1)
      local etl_min_ver=$(echo "$etl_running_backend_version" | cut -d '.' -f2)
      local etl_running_ver=$(echo $etl_running_backend_version | awk -F. '{print $1"."$2}')
      local etl_running_ver="$etl_maj_ver.$etl_min_ver"
    else
      debug "ETL RunVer: plextracapi is NOT running"
      die "plextracapi service isn't running. Please run 'plextrac start' and re-run the update"
    fi
    local etl_breaking_ver=${etl_breaking_ver:-"2.0"}
    debug "Running Version: $etl_running_ver, Breaking Version: $etl_breaking_ver"
    # v3.0+ uses UMF (unified-migrations); legacy Couchbase→Postgres ETL gatekeeping is not applied here.
    if [[ "${etl_maj_ver}" =~ ^[0-9]+$ ]] && [ "${etl_maj_ver}" -ge 3 ]; then
      info "Skipping ETL status check for app v${etl_maj_ver}.x (UMF migration path; no separate pg:etl:status gate after update)."
    elif (( $(echo "$etl_breaking_ver <= $etl_running_ver" | bc -l) )); then
      title "Checking Data ETL Status"
      debug "Checking ETL health and status..."
      ETL_OUTPUT=${ETL_OUTPUT:-true}
      if [ "$CONTAINER_RUNTIME" == "podman" ]; then
        local api_running=$(podman container inspect --format '{{.State.Status}}' "plextracapi" | wc -l)
      else
        local api_running=$(compose_client ps -q plextracapi | wc -l)
      fi
      if [ $api_running -gt 0 ]; then
        if [ "$CONTAINER_RUNTIME" == "podman" ]; then
          RAW_OUTPUT=$(podman exec plextracapi npm run pg:etl:status --no-update-notifier --if-present)
        else
          RAW_OUTPUT=$(compose_client exec plextracapi npm run pg:etl:status --no-update-notifier --if-present)
        fi
        if [ "$RAW_OUTPUT" == "" ]; then
          debug "No ETL status output found or it failed to run."
          return
        fi
        # Find the json content by looking for the first line that starts
        # with an opening brace and the first line that starts with a closing brace.
        JSON_OUTPUT=$(echo "$RAW_OUTPUT" | sed '/^{/,/^}/!d')

        # Find the summary content by finding the first line that starts
        # with a closing brace and selecting all remaining lines after that one.
        SUMMARY_OUTPUT=$(echo "$RAW_OUTPUT" | sed '1,/^}/d')
        ETLS_COMBINED_STATUS=$(echo $JSON_OUTPUT | jq -r .etlsCombinedStatus)
        if [ "${ETL_OUTPUT:-true}" == "true" ]; then
          msg "$SUMMARY_OUTPUT\n"
          debug "$JSON_OUTPUT\n"
        fi

        if [[ "$ETLS_COMBINED_STATUS" == "HEALTHY" ]]; then
            info "All ETLs are in a healthy status."
          else
            etl_failure "${etl_running_ver}"
        fi
      else
        info "PlexTrac API container not running, skipping ETL status check"
      fi
    else
      info "Skipping ETL Check; Version prior to 2.0 detected: ${etl_running_ver:-unknown}"
    fi
  else
    error "Skipping ETL status check"
  fi
}

function etl_failure() {
  local app_ver="${1:-failed}"
  error "One or more ETLs are in an unhealthy status."
  LOCK_UPDATES=true
  LOCK_VERSION="$app_ver"
  sed -i "/^LOCK_VERSION/s/=.*$/=${LOCK_VERSION}/" "${PLEXTRAC_HOME}/.env"
  sed -i '/^LOCK_UPDATES/s/=.*$/=true/' "${PLEXTRAC_HOME}/.env"
  sed -i '/^UPGRADE_STRATEGY/s/=.*$/=NULL/' "${PLEXTRAC_HOME}/.env"

  die "Updates are locked due to a failed data migration. Version Lock: $LOCK_VERSION. Continuing to attempt to update may result in data loss!!! Please contact PlexTrac Support"
}
