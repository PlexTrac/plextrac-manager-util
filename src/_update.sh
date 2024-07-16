# Instance & Utility Update Management
#
# Usage: plextrac update

# subcommand function, this is the entrypoint eg `plextrac update`
function mod_update() {
  if [ "${LOCK_UPDATES:-false}" == "true" ]; then
    die "Updates are locked due to a failed data migration. Continuing to attempt to update may result in data loss!!! Please contact PlexTrac Support"
  fi
  title "Updating PlexTrac"
  # I'm comparing an int :shrug:
  # shellcheck disable=SC2086
  if [ "${AIRGAPPED:-false}" == "false" ]; then
    if [ ${SKIP_SELF_UPGRADE:-0} -eq 0 ]; then
      if [ ${UTIL_UPDATED:-0} -eq 0 ]; then
        info "Checking for updates to the PlexTrac Management Utility"
        if selfupdate_checkForNewRelease; then
          event__log_activity "update:upgrade-utility" "${releaseInfo}"
          selfupdate_doUpgrade
          die "Failed to upgrade PlexTrac Management Util! Please reach out to support if problem persists"
          exit 1 # just in case, previous line should already exit
        fi
      fi
    else
      info "Skipping self upgrade"
      error "PlexTrac began/will begin doing contiguous updates to the PlexTrac application starting with the v2.0 release. From that point forward, all releases will need to be updated with minor version increments. Skipping updating the PlexTrac Manager Util can have adverse affects on the application if a minor version update is skipped. Are you sure you want to continue skipping updates to this utility?"
      get_user_approval
    fi
  else
    info "AIRGAPPED mode enabled, skipping utility update"
  fi
  info "Updating PlexTrac instance to latest release..."
  # Check upstream tags avaialble to download
  mod_configure
  if [ "${AIRGAPPED:-false}" == "false" ]; then
    version_check
  else
    info "AIRGAPPED mode enabled, skipping version check and using pinned version."
    contiguous_update=false
  fi
  if [ "${MIGRATE_CKE:-false}" == "true" ]; then
    debug "Enabling Environment and RTC Migration"
    ckeditorNginxConf
  fi
  if $contiguous_update
    then
      debug "Proceeding with contiguous update"
      upgrade_time_estimate
      for i in ${upgrade_path[@]}
        do
          if [ "$i" != "$running_ver" ]; then
            debug "Upgrading to $i"
            getCKEditorRTCConfig
            mod_configure
            UPGRADE_STRATEGY="$i"
            debug "Upgrade Strategy is $UPGRADE_STRATEGY"
            # ETL Check before an update
            ETL_OUTPUT=false
            mod_check_etl_status "${ETL_OUTPUT-}"
            if [ "$CONTAINER_RUNTIME" == "podman" ]; then
              title "Pulling latest container images"
              podman_remove
              podman_pull_images
            else
              title "Pulling latest container images"
              pull_docker_images
            fi
              
            mod_start || sleep 20
            run_cb_migrations
            if [ "$CONTAINER_RUNTIME" == "podman" ]; then
              unhealthy_services=$(for service in $(podman ps -a --format json | jq -r .[].Names | grep '"' | cut -d '"' -f2); do podman inspect $service --format json | jq -r '.[] | select(.State.Health.Status == "unhealthy" or (.State.Status != "running" and .State.ExitCode != 0) or .State.Status == "created") | .Name' | xargs -r printf "%s;"; done)
            else
              unhealthy_services=$(compose_client ps -a --format json | jq -r '. | select(.Health == "unhealthy" or (.State != "running" and .ExitCode != 0) or .State == "created" ) | .Service' | xargs -r printf "%s;")
            fi
            if [[ "${unhealthy_services}" != "" ]]; then
              info "Detected unhealthy services: ${unhealthy_services}"
              error "One or more containers are in a failed state, please contact support!"
            fi
          fi
      done
      mod_check
      # ETL check AFTER an update
      ETL_OUTPUT=false
      mod_check_etl_status "${ETL_OUTPUT-}"
      title "Update complete"
  else
      debug "Proceeding with normal update"
      getCKEditorRTCConfig
      mod_configure
      # ETL Check before an update
      ETL_OUTPUT=false
      mod_check_etl_status "${ETL_OUTPUT-}"
      if [ "${AIRGAPPED:-false}" == "false" ]; then
        if [ "$CONTAINER_RUNTIME" == "podman" ]; then
          title "Pulling latest container images"
          podman_remove
          podman_pull_images
        else
          title "Pulling latest container images"
          pull_docker_images
        fi
      else
        info "AIRGAPPED mode enabled, skipping image pull"
      fi

      if [ "$CONTAINER_RUNTIME" == "podman" ]; then
        title "Pulling latest container images"
        podman_remove
        podman_pull_images
      fi
      mod_start || sleep 20
      run_cb_migrations
      if [ "$CONTAINER_RUNTIME" == "podman" ]; then
        unhealthy_services=$(for service in $(podman ps -a --format json | jq -r .[].Names | grep '"' | cut -d '"' -f2); do podman inspect $service --format json | jq -r '.[] | select(.State.Health.Status == "unhealthy" or (.State.Status != "running" and .State.ExitCode != 0) or .State.Status == "created") | .Name' | xargs -r printf "%s;"; done)
      else
        unhealthy_services=$(compose_client ps -a --format json | jq -r '. | select(.Health == "unhealthy" or (.State != "running" and .ExitCode != 0) or .State == "created" ) | .Service' | xargs -r printf "%s;")
      fi
      if [[ "${unhealthy_services}" != "" ]]; then
        info "Detected unhealthy services: ${unhealthy_services}"
        error "One or more containers are in a failed state, please contact support!"
      fi
      mod_check
      ETL_OUTPUT=false
      mod_check_etl_status "${ETL_OUTPUT-}"
      title "Update complete"
  fi
}

function _selfupdate_refreshReleaseInfo() {
  releaseApiUrl='https://api.github.com/repos/PlexTrac/plextrac-manager-util/releases'
  targetRelease="${PLEXTRAC_UTILITY_VERSION:-latest}"
  if [ "${targetRelease}" == "latest" ]; then
    releaseApiUrl="${releaseApiUrl}/${targetRelease}"
  else
    releaseApiUrl="${releaseApiUrl}/tags/${targetRelease}"
  fi

  if test -z ${releaseInfo+x}; then
    _check_base_required_packages
    export releaseInfo="`wget -O - -q $releaseApiUrl`"
    info "$releaseApiUrl"
    if [ $? -gt 0 ] || [ "$releaseInfo" == "" ]; then die "Failed to get updated release from GitHub"; fi
    debug "`jq . <<< "$releaseInfo"`"
  fi
}

function selfupdate_checkForNewRelease() {
  #if test -z ${DIST+x}; then
  #  log "Running in local mode, skipping release check"
  #  return 1
  #fi
  _selfupdate_refreshReleaseInfo
  releaseTag="`jq '.tag_name' -r <<<"$releaseInfo"`"
  releaseVersion="`_parseVersion "$releaseTag"`"
  if [ "$releaseVersion" == "" ]; then die "Unable to parse release version, cannot continue"; fi
  localVersion="`_parseVersion "$VERSION"`"
  debug "Current Version: $localVersion"
  debug "Latest Version: $releaseVersion"
  if [ "$localVersion" == "$releaseVersion" ]; then
    info "$localVersion is already up to date"
    return 1
  fi
  info "Updating from $localVersion to $releaseVersion"

  return 0
}

function _parseVersion() {
  rawVersion=$1
  sed -E 's/^v?(.*)$/\1/' <<< $rawVersion
}

function info_getReleaseDetails() {
  changeLog=$(jq '.body' <<<$releaseInfo)
  debug "$changeLog"
}

function selfupdate_doUpgrade() {
  info "Starting Self Update"
  releaseVersion=$(jq '.tag_name' -r <<<$releaseInfo)
  scriptAsset="`jq '.assets[] | select(.name=="plextrac") | .' <<<"$releaseInfo"`"
  scriptAssetSHA256SUM="`jq '.assets[] | select(.name=="sha256sum-plextrac.txt") | .' <<<"$releaseInfo"`"
  if [ "$scriptAsset" == "" ]; then die "Failed to find release asset for ${releaseVersion}"; fi

  debug "Downloading updated script from $scriptAsset"
  tempDir=`mktemp -d -t plextrac-$releaseVersion-XXX`
  debug "Tempdir: $tempDir"
  target="${PLEXTRAC_HOME}/.local/bin/plextrac"

  debug "`wget $releaseApiUrl -O $tempDir/$(jq -r '.name, " ", .browser_download_url' <<<$scriptAsset) 2>&1 || error "Release download failed"`"
  debug "`wget -O $tempDir/$(jq -r '.name, " ", .browser_download_url' <<<$scriptAsset) 2>&1 || error "Release download failed"`"
  debug "`wget -O $tempDir/$(jq -r '.name, " ", .browser_download_url' <<<$scriptAssetSHA256SUM) 2>&1 || error "Checksum download failed"`"
  checksumoutput=`pushd $tempDir >/dev/null && sha256sum -c sha256sum-plextrac.txt 2>&1` || die "checksum failed: $checksumoutput"
  debug "$checksumoutput"
  tempScript="$tempDir/plextrac"
  chmod a+x $tempScript && debug "`$tempScript help 2>&1 | grep -i "plextrac management utility" 2>&1`" || die "Invalid script $tempScript"

  info "Successfully downloaded & tested update"
  log "Backing up previous release & installing $releaseVersion"
  debug "Moving $tempScript to $target"
  debug "`cp -vb --suffix=.bak $tempScript "$target" 2>&1`"
  debug `chmod -v a-x "${target}.bak" || true`
  debug `chmod -v a+x $target`
  info "Upgrade complete"

  debug "Initially called '$ProgName' w/ args '$_INITIAL_CMD_ARGS'"
  debug "Script Backup: `sha256sum ${target}.bak`"
  debug "Script Update: `sha256sum $target`"

  if [ "${SKIP_APP_UPDATE:-false}" == "true" ]; then
    exit 0
  fi
  eval "UTIL_UPDATED=1 $ProgName $_INITIAL_CMD_ARGS"
  exit $?
}


function mod_util-update() {
  if [ "${AIRGAPPED:-false}" == "true" ]; then
    info "AIRGAPPED mode enabled, skipping utility update"
    return 0
  fi
  info "Checking for updates to the PlexTrac Management Utility"
  SKIP_APP_UPDATE=true
  if selfupdate_checkForNewRelease; then
    event__log_activity "update:upgrade-utility" "${releaseInfo}"
    selfupdate_doUpgrade
    die "Failed to upgrade PlexTrac Management Util! Please reach out to support if problem persists"
    exit 1 # just in case, previous line should already exit
  fi
}
