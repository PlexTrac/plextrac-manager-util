# Handle backing up PlexTrac instance
# Usage
#  plextrac backup

function mod_backup() {
  title "Running PlexTrac Backups"
  local backupFailed=0
  PLEXTRAC_VERSION=$(get_plextrac_version)
  debug "PLEXTRAC_VERSION is ${PLEXTRAC_VERSION}"
  backup_ensureBackupDirectory
  backup_fullPostgresBackup
  backup_fullCouchbaseBackup || backupFailed=1
  backup_fullUploadsBackup "svcValues" || backupFailed=1
  if [ "$backupFailed" -ne 0 ]; then
    error "Backup completed with errors - see the failure(s) above"
    exit 1
  fi
}

# Gets the running plextracapi image version, for labeling backup archive
# filenames so it's possible to tell what application version a given
# backup was taken from. Same technique as _version_check.sh's running
# version detection (org.opencontainers.image.version label), which is more
# robust than parsing the image tag string.
function get_plextrac_version() {
  local version
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    version="$(for i in $(podman ps -a -q --filter name=plextracapi); do podman inspect "$i" --format json | jq -r '(.[].Config.Labels | ."org.opencontainers.image.version")'; done | sort -u | head -n1)"
  else
    version="$(for i in $(compose_client ps plextracapi -q); do docker container inspect "$i" --format json | jq -r '(.[].Config.Labels | ."org.opencontainers.image.version")'; done | sort -u | head -n1)"
  fi
  echo "${version:-unknown}"
}

function backup_ensureBackupDirectory() {
  if ! test -d "${PLEXTRAC_BACKUP_PATH}"; then
    info "Ensuring backup directory exists at $PLEXTRAC_BACKUP_PATH"
    debug "`mkdir -vp "${PLEXTRAC_BACKUP_PATH}"`"
    log "Done"
  fi
}

function backup_fullUploadsBackup() {
  var=$(declare -p "$1")
  eval "declare -A serviceValues="${var#*=}
  # Yoink uploads out to a compressed tarball
  info "$coreBackendComposeService: Performing backup of uploads directory"
  uploadsBackupDir="${PLEXTRAC_BACKUP_PATH}/uploads"
  mkdir -p $uploadsBackupDir

  local current_date=$(date -u "+%Y-%m-%dT%H%M%Sz")
  local versionedFileName="${current_date}-uploads-v${PLEXTRAC_VERSION}.tar.gz"
  local archivePath="${uploadsBackupDir}/${versionedFileName}"
  local tarExit=0

  # NEVER write the archive inside `uploads` - that is the tree being archived.
  # An in-tree target makes tar read its own output (GNU tar on amd64 embeds it,
  # doubling the archive) and tar always exits 1 because the directory mtime
  # changes when the archive is created. Under `set -e` that exit 1 aborted this
  # function before the copy-out and cleanup ran, so no backup reached the host
  # and the archive was orphaned in the live volume for the next run to archive
  # again, compounding on every run. Stream to stdout and let the host write it.
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    # No -t on exec: a TTY would corrupt the binary stream.
    podman exec --workdir="/usr/src/plextrac-api" plextracapi \
      tar -czf - uploads > "$archivePath" || tarExit=$?
  else
    # $uploadsBackupDir is bind-mounted at /backups, so this target is already
    # outside the archived tree. Do not wrap this in `debug "`...`"` - command
    # substitution inside an argument hides the exit code and silently swallows
    # a failed backup.
    compose_client run --user $(id -u) --no-deps -v ${uploadsBackupDir}:/backups \
      --workdir /usr/src/plextrac-api --rm --entrypoint='' -T $coreBackendComposeService \
      tar -czf /backups/$versionedFileName uploads || tarExit=$?
  fi

  backup_verifyUploadsArchive "$tarExit" "$archivePath" || return 1
  log "Done."
}

# Validates the uploads tar. tar exits 1 when a file it is reading changes
# underneath it, which is expected here: six services mount the uploads volume
# read-write and the app keeps writing to it for the whole backup. The archive
# is still complete and valid in that case, so only 2+ is a real failure.
# Confirms the gzip stream too, so a truncated archive is never left behind
# looking like a good backup.
function backup_verifyUploadsArchive() {
  local tarExit="$1"
  local archivePath="$2"

  if [ "$tarExit" -ge 2 ]; then
    error "tar failed with status $tarExit while archiving uploads"
    rm -f "$archivePath"
    return 1
  fi

  if [ "$tarExit" -eq 1 ]; then
    log "Some files changed while being read - expected on a running instance, archive is still valid"
  fi

  if ! gzip -t "$archivePath" 2>/dev/null; then
    error "Uploads archive failed its integrity check and was discarded: $archivePath"
    rm -f "$archivePath"
    return 1
  fi

  debug "Uploads archive verified: `du -h "$archivePath" 2>/dev/null | cut -f1`"
}

function backup_fullCouchbaseBackup() {
  info "$couchbaseComposeService: Performing backup of couchbase database"
  local user_id=$(id -u ${PLEXTRAC_USER_NAME:-plextrac})
  local cmd="compose_client exec -T"
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    cmd='podman exec'
  fi
  if [ "$CONTAINER_RUNTIME" != "podman" ]; then
    debug "`$cmd $couchbaseComposeService \
      chown -R $user_id:$user_id /backups 2>&1`"
  fi
  local cmd="compose_client exec -T --user $user_id"
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    cmd='podman exec'
  fi

  if [ "${LEGACY_BACKUP:-false}" == "true" ]; then
    backup_fullCouchbaseBackup_legacy "$cmd"
  else
    backup_fullCouchbaseBackup_cbbackupmgr "$cmd"
  fi
}

# Legacy path using the deprecated cbbackup tool.
# NOTE: cbbackup silently abandons DCP streams that go quiet for 30s and
# still exits 0, so exit code alone can't be trusted - validate its own
# transfer accounting (transferred vs. estimated msg count) before treating
# this as a good backup. See internal incident notes on the July 2026 k3s
# migration data-loss investigation for the underlying cbbackup/pump_dcp.py
# behavior.
function backup_fullCouchbaseBackup_legacy() {
  local cmd="$1"

  local cbbackupExit=0
  local cbbackupOutput
  cbbackupOutput="$($cmd $couchbaseComposeService \
    cbbackup -m full "http://127.0.0.1:8091" /backups -u ${CB_BACKUP_USER} -p ${CB_BACKUP_PASS} 2>&1)" || cbbackupExit=$?
  debug "$cbbackupOutput"

  if [ "$cbbackupExit" -ne 0 ]; then
    error "cbbackup exited with status $cbbackupExit"
    echo "$cbbackupOutput"
    return 1
  fi

  if echo "$cbbackupOutput" | grep -q "no response for"; then
    error "Couchbase backup incomplete: DCP stream(s) stalled and were abandoned mid-backup."
    echo "$cbbackupOutput" | grep "no response for"
    return 1
  fi

  local transferLine
  transferLine=$(echo "$cbbackupOutput" | grep -Eo '\([0-9]+/estimated [0-9]+ msgs\)' | tail -n1)
  if [ -z "$transferLine" ]; then
    error "Couchbase backup validation failed: no transfer summary found in cbbackup output."
    echo "$cbbackupOutput"
    return 1
  fi

  local transferNumbers
  transferNumbers=($(echo "$transferLine" | grep -Eo '[0-9]+'))
  local transferred="${transferNumbers[0]}"
  local estimated="${transferNumbers[1]}"

  if [ "$transferred" != "$estimated" ]; then
    error "Couchbase backup incomplete: transferred $transferred of estimated $estimated messages."
    return 1
  fi

  info "Couchbase backup verified complete: $transferred/$estimated messages transferred"

  # pipefail disabled: if this directory ever accumulates enough files to
  # exceed a single pipe buffer, `ls`'s later write()s can hit SIGPIPE once
  # `head -n1` closes the pipe early, which pipefail would otherwise report
  # as a real failure and abort the script via set -e (confirmed against a
  # near-identical `tar -tzf | head -n1` lookup in _restore.sh).
  set +o pipefail
  latestBackup=`ls -dt1 ${PLEXTRAC_BACKUP_PATH}/couchbase/* | head -n1`
  set -o pipefail
  backupDir=`basename $latestBackup`
  debug "Compressing Couchbase backup"
  debug "`tar -C $(dirname $latestBackup) --remove-files -czvf ${latestBackup}-couchbase-v${PLEXTRAC_VERSION}.tar.gz $backupDir 2>&1`"
  log "Done."
}

# Default path using cbbackupmgr, the actively-maintained replacement for
# cbbackup. Available on Community Edition for basic backup/restore (only
# `merge`/`examine` are Enterprise-gated). Each run gets its own fresh
# archive+repo under /backups. Since /backups inside the couchbase container
# is host-mounted to ${PLEXTRAC_BACKUP_PATH}/couchbase, the archive shows up
# there directly - no copy-out step needed (unlike the k3s scripts).
function backup_fullCouchbaseBackup_cbbackupmgr() {
  local cmd="$1"
  local repoName="plextrac"
  local archiveName="cbbackupmgr-archive-$(date -u "+%Y%m%dT%H%M%Sz")"
  local archivePath="/backups/$archiveName"

  debug "Configuring cbbackupmgr archive at $archivePath..."
  if ! $cmd $couchbaseComposeService cbbackupmgr config -a "$archivePath" -r "$repoName" 2>&1; then
    error "Failed to configure cbbackupmgr archive"
    return 1
  fi

  local cbbackupmgrExit=0
  local cbbackupmgrOutput
  cbbackupmgrOutput="$($cmd $couchbaseComposeService \
    cbbackupmgr backup -a "$archivePath" -r "$repoName" -c "http://127.0.0.1:8091" \
    -u ${CB_BACKUP_USER} -p ${CB_BACKUP_PASS} --full-backup --no-progress-bar 2>&1)" || cbbackupmgrExit=$?
  debug "$cbbackupmgrOutput"

  if [ "$cbbackupmgrExit" -ne 0 ]; then
    error "cbbackupmgr backup exited with status $cbbackupmgrExit"
    echo "$cbbackupmgrOutput"
    if echo "$cbbackupmgrOutput" | grep -q "insufficient_credentials"; then
      error "This looks like a missing role on ${CB_BACKUP_USER} - cbbackupmgr requires the admin role on Community Edition. Run 'plextrac autofix' to fix this automatically."
    fi
    return 1
  fi

  if ! echo "$cbbackupmgrOutput" | grep -q "Backup completed successfully"; then
    error "cbbackupmgr backup did not report successful completion"
    echo "$cbbackupmgrOutput"
    return 1
  fi

  if echo "$cbbackupmgrOutput" | grep -qi "Failed"; then
    error "cbbackupmgr backup reported a failure"
    echo "$cbbackupmgrOutput"
    return 1
  fi

  info "Couchbase backup completed via cbbackupmgr"

  debug "Compressing Couchbase backup"
  debug "`tar -C ${PLEXTRAC_BACKUP_PATH}/couchbase --remove-files -czvf ${PLEXTRAC_BACKUP_PATH}/couchbase/${archiveName}-couchbase-v${PLEXTRAC_VERSION}.tar.gz ${archiveName} 2>&1`"
  log "Done."
}

function backup_fullPostgresBackup() {
  info "$postgresComposeService: Performing backup of postgres database"
  local user_id=$(id -u ${PLEXTRAC_USER_NAME:-plextrac})
  local cmd="compose_client exec -T --user $user_id"
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    cmd='podman exec'
  fi
  if [ "$CONTAINER_RUNTIME" != "podman" ]; then
    debug "`compose_client exec -T $postgresComposeService chown -R $user_id:$user_id /backups 2>&1`"
  fi
  backupTimestamp=$(date -u "+%Y-%m-%dT%H%M%Sz")
  targetPath=/backups/$backupTimestamp
  debug "`$cmd $postgresComposeService mkdir -p $targetPath`"
  pgBackupFlags='--format=custom --compress=1 --verbose'
  for db in ${postgresDatabases[@],,}; do
    log "Backing up $db to $targetPath"
    debug "`$cmd -e PGPASSWORD=$POSTGRES_PASSWORD $postgresComposeService \
      pg_dump -U $POSTGRES_USER $db $pgBackupFlags --file=$targetPath/$db.psql 2>&1`"
  done
  debug "Compressing Postgres backup"
  tar -C ${PLEXTRAC_BACKUP_PATH}/postgres/$backupTimestamp --remove-files -czvf ${PLEXTRAC_BACKUP_PATH}/postgres/${backupTimestamp}-postgres-v${PLEXTRAC_VERSION}.tar.gz .
  log "Done"
}

# function validate_backups() {
#   # We should have a backup within the last 24h
#
# }
