# Handle cleaning up PlexTrac instance backups
# Usage
#  plextrac clean
#
# Keeps at least 1 backup, removes any older than RETAIN_BACKUP_DAYS

RETAIN_BACKUP_DAYS=${RETAIN_BACKUP_DAYS:-3}

function mod_clean() {
  info_backupDiskUsage
  title "Running PlexTrac Cleanup"
  debug "Rotating old archives first to avoid excessive disk utilization"
  clean_rotateCompressedArchives
  clean_compressCouchbaseBackups
  clean_pruneDockerResources
  clean_sweepUploadsCache
}

function info_backupDiskUsage() {
  info "Getting disk utilization metrics for backups"
  debug "Set to retain up to ${RETAIN_BACKUP_DAYS} days of archives in ${PLEXTRAC_BACKUP_PATH}"
  log "`du -sh ${PLEXTRAC_BACKUP_PATH}/*`"
}

function clean_rotateCompressedArchives() {
  info "Rotating ${RETAIN_BACKUP_DAYS} days of compressed archives from ${PLEXTRAC_BACKUP_PATH}"

  findString="find ${PLEXTRAC_BACKUP_PATH} -daystart -type f -name '*.tar.gz'"

  totalArchives=`eval $findString -printf '.' | wc -c`
  debug "Total archives in ${PLEXTRAC_BACKUP_PATH}: $totalArchives"

  rotationCandidates=`eval $findString -mtime +${RETAIN_BACKUP_DAYS}`
  debug "Removing `wc -w <<< "$rotationCandidates"` archives"

  for i in $rotationCandidates; do
    debug "\tRemoving" "$i" 
    debug "`rm -f $i`"
  done
  log "Done."
}

function clean_compressCouchbaseBackups() {
  info "$couchbaseComposeService: Archiving Couchbase Backups"
  # Run from within a container due to permissions issues (Couchbase runs as root)
  debug "`compose_client run --rm -T --entrypoint= --workdir /backups plextracdb \
    find . -daystart -maxdepth 1 -mtime +1 -type d \
    -exec tar --remove-files -czvf /backups/{}.tar.gz {} \;
    2>&1`"
  debug "Fixing permissions on backups"
  debug "`compose_client run --rm -T --entrypoint= --workdir /backups plextracdb \
    find . -maxdepth 1 -type f -name '*.tar.gz' \
    -exec chown 1337:1337 {} \;
    2>&1`"
  log "Done."
}

function clean_pruneDockerResources() {
  info "Docker: Cleaning stopped containers & images"
  debug "`docker container prune -f`"
  debug "`docker image prune -f`"
  log "Done."
}

function clean_sweepUploadsCache() {
  info "core-backend: Cleaning uploads/exports caches"
  # Leaving the cleanup fairly light, this should help a ton without getting aggressive
  debug "`compose_client exec -T -w /usr/src/plextrac-api/uploads plextracapi \
    find . -maxdepth 1 -type f -regextype posix-extended -regex '^.*\.(json|xml|ptrac|csv|nessus)$' -delete`"
}
