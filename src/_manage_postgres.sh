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
-- this file is used in the migration that creates the DB for CKEditor. Be sure to test the CKE DB is functional with the
-- CKE service if this is altered

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

PGPASSWORD="$POSTGRES_PASSWORD"
PGDATABASES=('core' 'runbooks' 'ckeditor')

tmpl=`cat /docker-entrypoint-initdb.d/bootstrap-template.sql.txt`

for db_name in ${PGDATABASES[@]}; do
  # Convert database name to uppercase for variable name construction
  db_name_uppercase=${db_name^^}
  
  # Build environment variable names
  admin_user="PG_${db_name_uppercase}_ADMIN_USER"
  admin_password="PG_${db_name_uppercase}_ADMIN_PASSWORD"
  ro_user="PG_${db_name_uppercase}_RO_USER"
  ro_password="PG_${db_name_uppercase}_RO_PASSWORD"
  rw_user="PG_${db_name_uppercase}_RW_USER"
  rw_password="PG_${db_name_uppercase}_RW_PASSWORD"
  ai_user="PG_CORE_AI_SQL_USER"
  ai_password="PG_CORE_AI_SQL_PASSWORD"
  
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
      -v pg_core_ai_sql_user="${!ai_user}" \
      -v pg_core_ai_sql_password="${!ai_password}" \
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

function mod_check_etl_status() {
  local migration_exited="running"
  title "Checking Data Migration Status"
  info "Checking Migration Status"
  secs=300
  endTime=$(( $(date +%s) + secs ))
  if [[ $(container_client ps -a | grep migrations 2>/dev/null | awk '{print $1}') != "" ]]; then
    migration_exited="running"
  else
    migration_exited="exited"
    debug "Migration container not found"
  fi
  while [ "$migration_exited" == "running" ]; do
    # Check if the migration container has exited, e.g., migrations have completed or failed
    local migration_exited=$(container_client inspect --format '{{.State.Status}}' `container_client ps -a | grep migrations 2>/dev/null | awk '{print $1}'` || migration_exited="exited")
    if [ $(date +%s) -gt $endTime ]; then
      error "Migration container has been running for over 5 minutes or is still running. Please ensure they complete or fail before taking further action with the PlexTrac Manager Utility. You can check on the logs by running 'docker compose logs -f couchbase-migrations'"
      die "Exiting PlexTrac Manager Utility."
    fi
    for s in / - \\ \|; do printf "\r\033[K$s $(container_client inspect --format '{{.State.Status}}' `container_client ps -a | grep migrations 2>/dev/null | awk '{print $1}'`) -- $(container_client logs `container_client ps -a | grep migrations 2>/dev/null | awk '{print $1}'` 2> /dev/null | tail -n 1 -q)"; sleep .1; done
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
    if (( $(echo "$etl_breaking_ver <= $etl_running_ver" | bc -l) )); then
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
            etl_failure
        fi
      else
        info "PlexTrac API container not running, skipping ETL status check"
      fi
    else
      info "Skipping ETL Check; Version prior to 2.0 detected: $running_ver"
    fi
  else
    error "Skipping ETL status check"
  fi
}

function etl_failure() {
  error "One or more ETLs are in an unhealthy status."
  LOCK_UPDATES=true
  LOCK_VERSION=${running_ver:-"failed"}
  sed -i "/^LOCK_VERSION/s/=.*$/=${LOCK_VERSION}/" "${PLEXTRAC_HOME}/.env"
  sed -i '/^LOCK_UPDATES/s/=.*$/=true/' "${PLEXTRAC_HOME}/.env"
  sed -i '/^UPGRADE_STRATEGY/s/=.*$/=NULL/' "${PLEXTRAC_HOME}/.env"
  
  die "Updates are locked due to a failed data migration. Version Lock: $LOCK_VERSION. Continuing to attempt to update may result in data loss!!! Please contact PlexTrac Support"
}
