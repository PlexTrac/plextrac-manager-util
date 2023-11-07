# Instance & Utility Update Management
#
# Usage: plextrac update

# Need this as a global variable

upgrade_path=()
function mod_ver_check() {
  debug "------"
  debug "-- Beginning version comparison"
  # Get running version of Backend
  running_backend_version="$(for i in `docker compose ps plextracapi -q`; do docker container inspect "$i" --format json | jq -r '(.[].Config.Labels | ."org.opencontainers.image.version")'; done | sort -u)"
  # Set the needed JWT Token to interact with the DockerHUB API
  JWT_TOKEN=$(wget --header="Content-Type: application/json" --post-data='{"username": "'$DOCKER_HUB_USER'", "password": "'$DOCKER_HUB_KEY'"}' -O - https://hub.docker.com/v2/users/login/ -q | jq -r .token)
  if [ -z $JWT_TOKEN ]
    then
      error "Unable to retrieve JWT Token for wget, variable empty"
    else
      # Validate that the app is running and returning a version
      if [[ $running_backend_version != "" ]]
        then
          # Get the major and minor version from the running containers
          maj_ver=$(echo "$running_backend_version" | cut -d '.' -f1)
          min_ver=$(echo "$running_backend_version" | cut -d '.' -f2)
          # Statically set the version we're expecting breaking changes to begin
          breaking_ver="1.62"
          # Set the running version format as x.x
          running_ver="$maj_ver.$min_ver"
          # Default values for variables
          page=1
          upstream_tags=()
          latest_ver=""
          debug "Looking for version $running_ver"
          while [ $page -lt 600 ]
            do
              # Get the available versions from DockerHub and save to array
              upstream_tags+=(`wget --header="Authorization: JWT "${JWT_TOKEN} -O - "https://hub.docker.com/v2/repositories/plextrac/plextracapi/tags/?page=$page&page_size=1000" -q | jq -r .results[].name | grep -E '(^[0-9]\.[0-9]*$)' || true`)
              if [ -z $latest_ver ]; then if [[ "${upstream_tags[@]}" != "" ]]; then latest_ver="${upstream_tags[0]}"; else debug "unable to fetch upstream tags"; break; fi; fi
              if (( $(echo "$latest_ver <= $breaking_ver" | bc -l) )); then debug $breaking_ver not publically available; break; fi
              if [[ $(echo "${upstream_tags[@]}" | grep "$breaking_ver" || true) ]]
                then 
                  debug "Found breaking version $breaking_ver"; break; 
              elif [[ $(echo "${upstream_tags[@]}" | grep "$running_ver" || true) ]]
                then
                  debug "Found running version $running_backend_version"; break; 
              fi
              debug "Page of results: $page"
              page=$[$page+1]
          done
          debug "-----"
          debug "-- Listing version information"
          debug "Upstream Versions: [${upstream_tags[@]} ]"
          # This grabs the first element in the version sorted list which should always be the highest version available on DockerHub"
          latest_ver="${upstream_tags[0]}"
          debug "Breaking Version: $breaking_ver"
          debug "Running Version: $running_ver"
          debug "Latest Version: $latest_ver"
          debug "Upgrade Strategy: $UPGRADE_STRATEGY"

          # Check if 1.62 is avaiable to the public yet
          if (( $(echo "$latest_ver >= $breaking_ver" | bc -l) ))
            then
              debug "$breaking_ver and above now available to public"
              debug "Proceeding with contiguous update"
              # Determine an upgrade path to follow
              IFS=$'\n' upgrade_path=($(sort -V <<<"${upstream_tags[*]}"))
              unset IFS
              debug "Upgrade path: [${upgrade_path[@]}]"
              # Variable to indicate how to handle updating
              contiguous_update=true
          else
              # if breaking version isn't available, do nothing and update like normal
              debug "Breaking version $breaking_ver not publically avaialble yet"
              contiguous_update=false
          fi
        else
          # BACKEND not running or returning version
          debug "plextracapi not running or returning version"
      fi
  fi
}

# subcommand function, this is the entrypoint eg `plextrac update`
function mod_update() {
  title "Updating PlexTrac"
  # I'm comparing an int :shrug:
  # shellcheck disable=SC2086
  if [ ${SKIP_SELF_UPGRADE:-0} -eq 0 ]; then
    info "Checking for updates to the PlexTrac Management Utility"
    if selfupdate_checkForNewRelease; then
      event__log_activity "update:upgrade-utility" "${releaseInfo}"
      selfupdate_doUpgrade
      die "Failed to upgrade PlexTrac Management Util! Please reach out to support if problem persists"
      exit 1 # just in case, previous line should already exit
    fi
  else
    info "Skipping self upgrade"
    error "PlexTrac began/will begin doing contiguous updates to the PlexTrac application starting with the v1.62 releas. From that point forward, all releases will need to be updated with minor version increments. Skipping updating the PlexTrac Manager Util can have adverse affects on the application if a minor version update is skipped. Are you sure you want to continue skipping updates to this utility?"
    get_user_approval
  fi
  info "Updating PlexTrac instance to latest release..."
  # -------- START OF NEW
  mod_ver_check
  debug "Contiguous update: $contiguous_update"
  contiguous_update=true
  debug "Number of upgrades: $(echo "${#upgrade_path[@]} - 1" | bc -l || 1)"
  # If $contiguous_update is true
  if $contiguous_update
    then
      if [ $UPGRADE_STRATEGY == "stable" ]; then info "stable is the chosen"; fi
      info "Running Ver is $running_ver"
      debug "Proceeding with contiguous update"
      for i in ${upgrade_path[@]}
         do
            if [ "$i" != "$running_ver" ]
              then
                info "Upgrading to $i"
                UPGRADE_STRATEGY="$i"
                info "UPGRADE_STRATEGY is now $UPGRADE_STRATEGY"
            fi
      done
    else
      debug "Proceeding with normal update"
      mod_configure
      title "Pulling latest container images"
      pull_docker_images
      if [ "$IMAGE_CHANGED" == true ]
        then
          title "Executing Rolling Deployment"
          mod_rollout
      fi

      # Sometimes containers won't start correctly at first, but will upon a retry
      maxRetries=2
      for i in $( seq 1 $maxRetries ); do
        mod_start || sleep 5 # Wait before going on to health checks, they should handle triggering retries if mod_start errors
        unhealthy_services=$(compose_client ps -a --format json | \
          jq -r '. | select(.Health == "unhealthy" or (.State != "running" and .ExitCode != 0) or .State == "created" ) | .Service' | \
          xargs -r printf "%s;")
        if [[ "${unhealthy_services}" == "" ]]; then break; fi
        info "Detected unhealthy services: ${unhealthy_services}"
        if [[ $i -ge $maxRetries ]]; then
          error "One or more containers are in a failed state, please contact support!"
          exit 1
        fi
        info "An error occurred with one or more containers, attempting to start again"
        sleep 5
      done
      mod_check
      title "Update complete"
  fi
  # -------- END OF NEW
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

  eval "SKIP_SELF_UPGRADE=1 $ProgName $_INITIAL_CMD_ARGS"
  exit $?
}
