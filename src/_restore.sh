# Simple restore of backups
#
# Usage:
#   plextrac restore

function mod_restore() {
  restoreTargets=(restore_doPostgresRestore restore_doCouchbaseRestore restore_doUploadsRestore)
  currentTarget=`tr [:upper:] [:lower:] <<< "${RESTORETARGET:-ALL}"`
  for target in "${restoreTargets[@]}"; do
    debug "Checking if $target matches $currentTarget"
    if [[ $currentTarget == "all" || ${target,,} =~ "restore_do${currentTarget}restore" ]]; then
      $target
    fi
  done

  log "Clearing the license cache in redis so it properly uses the one from the restore"
  compose_client exec -T --user $(id -u ${PLEXTRAC_USER_NAME:-plextrac}) redis redis-cli -a $REDIS_PASSWORD DEL "{\"cacheDomain\":\"License\",\"method\":\"getTenantLicense\",\"params\":0,\"tenantId\":0}"
}

function restore_doUploadsRestore() {
  title "Restoring uploads from backup"
  latestBackup="`ls -dc1 ${PLEXTRAC_BACKUP_PATH}/uploads/* | head -n1`"
  info "Latest backup: $latestBackup"

  error "This is a potentially destructive process, are you sure?"
  info "Please confirm before continuing the restore"

  if get_user_approval; then
    log "Restoring from $latestBackup"
    if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      cat $latestBackup | podman cp - plextracapi:/usr/src/plextrac-api
    else
      debug "`cat $latestBackup | compose_client run -T --workdir /usr/src/plextrac-api --rm --entrypoint='' \
      $coreBackendComposeService tar -xzf -`"
    fi
    log "Done"
  fi
}

function restore_doCouchbaseRestore() {
  title "Restoring Couchbase from backup"
  debug "Fixing permissions"
  local user_id=$(id -u ${PLEXTRAC_USER_NAME:-plextrac})
  if [ "$CONTAINER_RUNTIME" == "docker" ]; then
    debug "`compose_client exec -T $couchbaseComposeService \
      chown -R $user_id:$user_id /backups 2>&1`"
  fi
  latestBackup="`ls -dc1 ${PLEXTRAC_BACKUP_PATH}/couchbase/* | head -n1`"
  backupFile=`basename $latestBackup`
  info "Latest backup: $latestBackup"

  error "This is a potentially destructive process, are you sure?"
  info "Please confirm before continuing the restore"

  if get_user_approval; then
    log "Restoring from $backupFile"
    # Create a unique temp directory for extraction
    timestamp=$(date +%s)
    restoreTmp="/backups/restore_tmp_$timestamp"

    log "Extracting backup files"
    if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      podman exec $couchbaseComposeService mkdir -p $restoreTmp
      podman exec $couchbaseComposeService tar -C $restoreTmp -xzvf /backups/$backupFile
    else
      debug "`compose_client exec -T --user $(id -u ${PLEXTRAC_USER_NAME:-plextrac}) $couchbaseComposeService \
        mkdir -p $restoreTmp 2>&1`"
      debug "`compose_client exec -T --user $(id -u ${PLEXTRAC_USER_NAME:-plextrac}) $couchbaseComposeService \
        tar -C $restoreTmp -xzvf /backups/$backupFile 2>&1`"
    fi

    log "Running database restore"
    if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      podman exec $couchbaseComposeService cbrestore $restoreTmp http://127.0.0.1:8091 \
        -u ${CB_BACKUP_USER} -p "${CB_BACKUP_PASS}" --from-date 2022-01-01 -x conflict_resolve=0,data_only=1
    else
      # We have the TTY enabled by default so the output from cbrestore is intelligible
      tty -s || { debug "Disabling TTY allocation for Couchbase restore due to non-interactive invocation"; ttyFlag="-T"; }
      compose_client exec ${ttyFlag:-} $couchbaseComposeService cbrestore $restoreTmp http://127.0.0.1:8091 \
        -u ${CB_BACKUP_USER} -p "${CB_BACKUP_PASS}" --from-date 2022-01-01 -x conflict_resolve=0,data_only=1
    fi

    log "Cleaning up extracted backup files"
    if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      podman exec $couchbaseComposeService rm -rf $restoreTmp
    else
      debug "`compose_client exec -T --user $(id -u ${PLEXTRAC_USER_NAME:-plextrac}) $couchbaseComposeService \
        rm -rf $restoreTmp 2>&1`"
    fi
    log "Done"
  fi
}

function restore_doPostgresRestore() {
  title "Restoring Postgres from backup"

  local plextrac_user_id=$(id -u ${PLEXTRAC_USER_NAME:-plextrac})
  PODMAN_PG_IMAGE="${PODMAN_PG_IMAGE:-docker.io/plextrac/plextracpostgres:stable}"

  # If docker runtime, gather a list of compose files
  if [ "$CONTAINER_RUNTIME" == "docker" ]; then
    compose_files=$(for i in `ls -r ${PLEXTRAC_HOME}/docker-compose*.yml`; do printf " -f %s" "$i"; done )
  fi

  latestBackup="`ls -dc1 ${PLEXTRAC_BACKUP_PATH}/postgres/* | head -n1`"
  backupFile=`basename $latestBackup`
  info "Latest backup: $latestBackup"

  error "This is a potentially destructive process, are you sure?"
  info "Please confirm before continuing the restore"

  if get_user_approval; then
    # Tear down the existing postgres container to ensure a clean restore
    if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      # Tear down the existing postgres container, including the related volumes
      podman stop postgres
      podman rm postgres
      podman volume rm postgres-data

      # Stop the rest of the app
      mod_stop

      # recreate the postgres container
      # copied from the plextrac_install_podman function
      local volumes="${svcValues[pg-volumes]}"
      local ports="${svcValues[pg-ports]}"
      local healthcheck="${svcValues[pg-healthcheck]}"
      local image="${PODMAN_PG_IMAGE}"
      local env_vars="${svcValues[pg-env-vars]}"
      container_client run --env-file ${PLEXTRAC_HOME:-}/.env "$env_vars" --restart=always "$healthcheck" \
        "$volumes" --name="postgres" "${svcValues[network]}" "$ports" -d "$image" 1>/dev/null

      # wait for postgres to be ready
      sleep 10

    else
      # tear down the existing postgres container, including the related volumes
      compose_client down $postgresComposeService --volumes

      # stop the rest of the app to avoid issues with writes coming into the fresh database before a restore
      mod_stop

      # recreate the postgres container
      compose_client up -d $postgresComposeService

      # wait for postgres to be ready. Could probably do better than a sleep here eventually.
      sleep 10
    fi

    # now actually perform the db restore
    # Extract backup to a temp directory to handle varying tarball structures
    timestamp=$(date +%s)
    restoreTmp="/tmp/postgres_restore_$timestamp"
    mkdir -p $restoreTmp
    tar -xvzf $latestBackup -C $restoreTmp

    # Find all .psql files in the extracted backup, regardless of directory structure
    mapfile -t psql_files < <(find $restoreTmp -type f -name '*.psql')
    if [ ${#psql_files[@]} -eq 0 ]; then
      error "No .psql files found in backup archive."
      rm -rf $restoreTmp
      return 1
    fi

    log "Restoring from $backupFile"
    log "Databases to restore:\n${psql_files[*]}"
    local cmd='compose_client exec -T'
    if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      local cmd='podman exec'
    fi
    for psql_path in "${psql_files[@]}"; do
      db=$(basename "$psql_path" .psql)
      log "Restoring backup for $db"
      # only the core database gets timescaledb tables, so we need to do special things for this restore to work
      if [ $db = "core" ]; then
        log "restoring core db, running special timescaledb commands"
        if [ "$CONTAINER_RUNTIME" == "podman" ]; then
          # temporarily grant
          podman exec -e PGPASSWORD=$POSTGRES_PASSWORD --user $plextrac_user_id postgres /bin/sh -c 'psql -U $POSTGRES_USER -d $PG_CORE_DB -c "ALTER ROLE $PG_CORE_ADMIN_USER WITH SUPERUSER;"'

          # create the timescaledb extension
          podman exec -e PGPASSWORD=$POSTGRES_PASSWORD --user $plextrac_user_id postgres /bin/sh -c 'psql -U $POSTGRES_USER -d $PG_CORE_DB -c "CREATE EXTENSION timescaledb;"'

          # run the timescaledb pre_restore
          podman exec -e PGPASSWORD=$POSTGRES_PASSWORD --user $plextrac_user_id postgres /bin/sh -c 'psql -U $POSTGRES_USER -d $PG_CORE_DB -c "SELECT timescaledb_pre_restore();"'
        else
          # temporarily grant superuser priveleges to the core_admin user
          debug "`docker compose $(echo $compose_files) exec -e PGPASSWORD=$POSTGRES_PASSWORD -T --user $plextrac_user_id $postgresComposeService \
            psql -U $POSTGRES_USER -d $PG_CORE_DB -c "ALTER ROLE $PG_CORE_ADMIN_USER WITH SUPERUSER;" 2>&1`"

          # create the timescaledb extension for the core database
          debug "`docker compose $(echo $compose_files) exec -e PGPASSWORD=$POSTGRES_PASSWORD -T --user $plextrac_user_id $postgresComposeService \
            psql -U $POSTGRES_USER -d $PG_CORE_DB -c "CREATE EXTENSION timescaledb;" 2>&1`"

          # run the timescaledb pre_restore command
          debug "`docker compose $(echo $compose_files) exec -e PGPASSWORD=$POSTGRES_PASSWORD -T --user $plextrac_user_id $postgresComposeService \
            psql -U $POSTGRES_USER -d $PG_CORE_DB -c "SELECT timescaledb_pre_restore();" 2>&1`"
        fi
      fi

      dbAdminEnvvar="PG_${db^^}_ADMIN_USER"
      dbAdminRole=$(eval echo "\$$dbAdminEnvvar")

      # Note: Not using `--clean --if-exists` here because it is incompatible with timescaledb.
      # This is because --clean will drop the extension and recreate it during the restoration,
      # but that will fail because timescaledb requires that the CREATE EXTENSION command be
      # run as the first command in the session due to the way it modified the process's memory.
      dbRestoreFlags="-d $db --no-privileges --no-owner --role=$dbAdminRole  --disable-triggers --verbose"

      # Copy the backup file into the container for restore
      if [ "$CONTAINER_RUNTIME" == "podman" ]; then
        podman cp "$psql_path" $postgresComposeService:/tmp/$(basename "$psql_path")
      else
        docker cp "$psql_path" $(docker compose ps -q $postgresComposeService):/tmp/$(basename "$psql_path")
      fi

      log "Restoring $db with role:${dbAdminRole}"
      debug "`$cmd -e PGPASSWORD=$POSTGRES_PASSWORD $postgresComposeService \
        pg_restore -U $POSTGRES_USER $dbRestoreFlags /tmp/$db.psql 2>&1`"
      debug "`$cmd $postgresComposeService \
        rm /tmp/$db.psql 2>&1`"

      # Run through the post-restore steps for core db
      if [ $db = "core" ]; then
        if [ "$CONTAINER_RUNTIME" == "podman" ]; then
          podman exec -e PGPASSWORD=$POSTGRES_PASSWORD --user $plextrac_user_id postgres /bin/sh -c 'psql -U $POSTGRES_USER -d $PG_CORE_DB -c "SELECT timescaledb_post_restore();"'
          podman exec -e PGPASSWORD=$POSTGRES_PASSWORD --user $plextrac_user_id postgres /bin/sh -c 'psql -U $POSTGRES_USER -d $PG_CORE_DB -c "ALTER ROLE $PG_CORE_ADMIN_USER WITH NOSUPERUSER;"'
        else
          # run the timescaledb post_restore command
          debug "`docker compose $(echo $compose_files) exec -e PGPASSWORD=$POSTGRES_PASSWORD -T --user $plextrac_user_id $postgresComposeService \
            psql -U $POSTGRES_USER -d $PG_CORE_DB -c "SELECT timescaledb_post_restore();" 2>&1`"

          # revoke the temporarily granted superuser privileges from core_admin
          debug "`docker compose $(echo $compose_files) exec -e PGPASSWORD=$POSTGRES_PASSWORD -T --user $plextrac_user_id $postgresComposeService \
            psql -U $POSTGRES_USER -d $PG_CORE_DB -c "ALTER ROLE $PG_CORE_ADMIN_USER WITH NOSUPERUSER;" 2>&1`"

        fi
      fi
    done

    # Clean up the temp extraction directory
    rm -rf $restoreTmp

    log "now, start the rest of the app and sleep for 120s to give couchbase a chance"
    mod_start
    sleep 120

  fi
}
