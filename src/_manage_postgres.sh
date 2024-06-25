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
CREATE USER $PG_PLACEHOLDER_ADMIN_USER WITH PASSWORD '$PG_PLACEHOLDER_ADMIN_PASSWORD';
-- Service Read-Only User
CREATE USER $PG_PLACEHOLDER_RO_USER WITH PASSWORD '$PG_PLACEHOLDER_RO_PASSWORD';
-- Service Read-Write User
CREATE USER $PG_PLACEHOLDER_RW_USER WITH PASSWORD '$PG_PLACEHOLDER_RW_PASSWORD';

-- Role memberships
-- Each role inherits from the role below
GRANT $PG_PLACEHOLDER_RO_USER TO $PG_PLACEHOLDER_RW_USER;
GRANT $PG_PLACEHOLDER_RW_USER TO $PG_PLACEHOLDER_ADMIN_USER;

-- Create Service Database $PG_PLACEHOLDER_DB
CREATE DATABASE $PG_PLACEHOLDER_DB;
REVOKE ALL ON DATABASE $PG_PLACEHOLDER_DB FROM public;
GRANT CONNECT ON DATABASE $PG_PLACEHOLDER_DB TO $PG_PLACEHOLDER_RO_USER;

-- switch to the new database.
\connect $PG_PLACEHOLDER_DB;

-- Schema level grants within $PG_PLACEHOLDER_DB db
--
-- Service Read-Only user needs basic access
GRANT USAGE ON SCHEMA public TO $PG_PLACEHOLDER_RO_USER;

-- Only the admin account should ever create new resources
-- This also marks Service Admin account as owner of new resources
GRANT CREATE ON SCHEMA public TO $PG_PLACEHOLDER_ADMIN_USER;

-- Enable read access to all new tables for Service Read-Only
ALTER DEFAULT PRIVILEGES FOR ROLE $PG_PLACEHOLDER_ADMIN_USER
    GRANT SELECT ON TABLES TO $PG_PLACEHOLDER_RO_USER;

-- Enable read-write access to all new tables for Service Read-Write
ALTER DEFAULT PRIVILEGES FOR ROLE $PG_PLACEHOLDER_ADMIN_USER
    GRANT INSERT,DELETE,TRUNCATE,UPDATE ON TABLES TO $PG_PLACEHOLDER_RW_USER;

-- Need to enable usage on sequences for Service Read-Write
-- to enable auto-incrementing ids
ALTER DEFAULT PRIVILEGES FOR ROLE $PG_PLACEHOLDER_ADMIN_USER
    GRANT USAGE ON SEQUENCES TO $PG_PLACEHOLDER_RW_USER;
EOBOOTSTRAPTEMPLATE
  cat > "$targetDir/initdb.sh" <<- "EOINITDBSCRIPT"
#!/bin/bash

PGPASSWORD="$POSTGRES_PASSWORD"
PGDATABASES=('core' 'runbooks' 'ckeditor')

tmpl=`cat /docker-entrypoint-initdb.d/bootstrap-template.sql.txt`

for db in ${PGDATABASES[@]}; do
  # Ugh this is ugly. Thanks Bash
  eval "echo "'"'"`echo "$tmpl" | sed "s/PLACEHOLDER/${db^^}/g" -`"'"'"" |
    psql -a -v ON_ERROR_STOP=1 --username $POSTGRES_USER -d $POSTGRES_USER
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
  while [ "$migration_exited" == "running" ]; do
    # Check if the migration container has exited, e.g., migrations have completed or failed
    if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      local migration_exited=$(podman container inspect --format '{{.State.Status}}' "migrations" || migration_exited="exited")
    else
      local migration_exited=$(docker inspect --format '{{.State.Status}}' `docker ps -a | grep migrations 2>/dev/null | awk '{print $1}'` || migration_exited="exited")
    fi
    if [ $(date +%s) -gt $endTime ]; then
      die "Migration container has been running for over 5 minutes or is still running. Exiting..."
    fi
    if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      for s in / - \\ \|; do printf "\r\033[K$s $(podman inspect --format '{{.State.Status}}' migrations) -- $(podman logs migrations 2> /dev/null | tail -n 1 -q)"; sleep .1; done
    else
      for s in / - \\ \|; do printf "\r\033[K$s $(docker inspect --format '{{.State.Status}}' `docker ps -a | grep migrations 2>/dev/null | awk '{print $1}'`) -- $(docker logs `docker ps -a | grep migrations 2>/dev/null | awk '{print $1}'` 2> /dev/null | tail -n 1 -q)"; sleep .1; done
    fi
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
