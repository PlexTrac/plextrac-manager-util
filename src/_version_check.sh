# Need this as a global variable
upgrade_path=()

function upgrade_time_estimate() {
  debug "upgrade_time_estimate function running"
  if (( ${#upgrade_path[@]} >= 1 ))
    then
      time_estimate=$(echo "${#upgrade_path[@]} * 15" | bc -l)
      error "Detected ${#upgrade_path[@]} upgrade(s). Each upgrade can take up to 15 minutes to pull the new version, and update the running application. Given the number of upgrades, the projected upgade time is $time_estimate minutes. Are you sure you want to continue?"
      get_user_approval
  fi
}

function upgrade_warning() {
  debug "upgrade_warning function running"
  error "Its been detected that you're on a pinned version of PlexTrac other than stable. Beginning with version 2.0, PlexTrac is going to require contiguous updates to ensure code migrations are successful and enable us to continue to move forward with improving the platform. We recommend updating to the next minor version available compared to the running version $running_backend_version"
  error "Are you sure you want to update to $UPGRADE_STRATEGY?"
  get_user_approval hardcheck
}

function version_check() {
  #######################
  ### -- Running Version
  #######################
  ## LOGIC: RunVer
  debug "Running Version"
  # Get running version of Backend
  running_backend_version="$(for i in $(docker compose ps plextracapi -q); do docker container inspect "$i" --format json | jq -r '(.[].Config.Labels | ."org.opencontainers.image.version")'; done | sort -u)"

  # CONDITION: plextracapi IS/NOT RUNNING
  # Validate that the app is running and returning a version
  if [[ $running_backend_version != "" ]]; then
    debug "RunVer: plextracapi is running and is version $running_backend_version"
    # Get the major and minor version from the running containers
    maj_ver=$(echo "$running_backend_version" | cut -d '.' -f1)
    min_ver=$(echo "$running_backend_version" | cut -d '.' -f2)
    # Set the running version format as x.x
    running_ver="$maj_ver.$min_ver"
  else
    debug "RunVer: plextracapi is NOT running"
    die "plextracapi service isn't running. Please run 'plextrac start' and re-run the update"
  fi

  #######################
  ### -- Pinned Version
  #######################
  ## LOGIC: PinVer
  debug "Pinned Version"
  # Check what the pinned version (UPGRADE_STRATEGY) is and see if a contiguous update will apply
  ## IF STABLE
  if [[ "$UPGRADE_STRATEGY" == "stable" ]]; then
    debug "PinVer: Running Stable!"

    #######################
    ### -- Latest Stable Version
    #######################
    debug "Latest_Stable Version"
    # Set vars
    breaking_ver="2.0"
    latest_ver=""
    page=1

    # Set the needed JWT Token to interact with the DockerHUB API
    JWT_TOKEN=$(wget --header="Content-Type: application/json" --post-data='{"username": "'$DOCKER_HUB_USER'", "password": "'$DOCKER_HUB_KEY'"}' -O - https://hub.docker.com/v2/users/login/ -q | jq -r .token)
    if [[ -n "$JWT_TOKEN" ]]; then
        # Get latest from DockerHUB and assign to array
        while [ $page -lt 600 ]; do
          latest_ver=($(wget --header="Authorization: JWT "${JWT_TOKEN} -O - "https://hub.docker.com/v2/repositories/plextrac/plextracapi/tags/?page=$page&page_size=1000" -q | jq -r .results[].name | grep -E '(^[0-9]\.[0-9]*$)' || true))
          page=$(($page + 1))
          if [ -n $latest_ver ]; then break; fi
        done
        # Set latest_ver to first index item which should be the "latest"
        latest_ver="${latest_ver[0]}"

        ### Compare stable and latest
        # Get date stable was pushed
        stable_date=$(date -d $(wget --header="Authorization: JWT "${JWT_TOKEN} -O - "https://hub.docker.com/v2/repositories/plextrac/plextracapi/tags/stable" -q | jq -r .tag_last_pushed) +%s)
        # Get date for the latest version tag was pushed
        latest_date=$(date -d $(wget --header="Authorization: JWT "${JWT_TOKEN} -O - "https://hub.docker.com/v2/repositories/plextrac/plextracapi/tags/$latest_ver" -q | jq -r .tag_last_pushed) +%s)
        
        ## LOGIC: LATEST_STABLE
        # IF LATEST_STABLE <= 2.0
        if (( $(echo "$latest_ver <= $breaking_ver" | bc -l) ))
          then 
            debug "$breaking_ver not publically available. Updating normally without warning"
            contiguous_update=false
          
          # IF LATEST_STABLE >= 2.1
          else
            debug "Stable version is greater than $breaking_ver. Running contiguous update"
            contiguous_update=true
        fi
      # If the JWT token is empty for on-prem envs
      else
        contiguous_update=false
        error "Unable to validate versioned images from DockerHub. Likely On-prem or Air-gapped"
        msg "-------"
        error "Beginning with version 2.0, PlexTrac is going to require contiguous updates to ensure code migrations are successful and enable us to continue to move forward with improving the platform. We recommend updating to the next minor version available compared to the running version $running_backend_version"
        error "Are you sure you want to update to $UPGRADE_STRATEGY? (y/n)"
        get_user_approval hardcheck
    fi

    upstream_tags=()
    page=1
    if [ "$contiguous_update" = true ]
      then
        # Get upstream tag list
        debug "Looking for Running version $running_ver or Breaking version $breaking_ver"
        while [ $page -lt 600 ]
          do
            # Get the available versions from DockerHub and save to array
            if [[ $(echo "${upstream_tags[@]}" | grep "$breaking_ver" || true) ]]
              then
                debug "Found breaking version $breaking_ver"; break;
            elif [[ $(echo "${upstream_tags[@]}" | grep "$running_ver" || true) ]]
              then
                debug "Found running version $running_backend_version"; break;
            else
              upstream_tags+=(`wget --header="Authorization: JWT "${JWT_TOKEN} -O - "https://hub.docker.com/v2/repositories/plextrac/plextracapi/tags/?page=$page&page_size=1000" -q | jq -r .results[].name | grep -E '(^[0-9]\.[0-9]*$)' || true`)
            fi
            page=$[$page+1]
        done
        # Compare stable vs latest_tag and if stable is older than the newest tag, then remove the newest tag to ensure we don't update past stable
        if [ $stable_date -le $latest_date ]; then
          debug "Stable is older than latest version"
          # If stable is older, remove latest from upgrade path
          for i in ${!upstream_tags[@]}
            do
              if [[ ${upstream_tags[i]} = $latest_ver ]]
                then
                  debug "correcting upstream_tags to remove latest"
                  unset 'upstream_tags[i]'
              fi
          done
        else
          debug "Stable is pinned to the latest version $latest_ver"
        fi
        
        # Remove the running version from the Upgrade path
        for i in ${!upstream_tags[@]}
          do
            if [[ ${upstream_tags[i]} = $running_ver ]]
              then
                debug "correcting upstream_tags to remove running version"
                unset 'upstream_tags[i]'
            fi
        done
        for i in "${!upstream_tags[@]}"; do
            new_array+=( "${upstream_tags[i]}" )
        done
        upstream_tags=("${new_array[@]}")
        unset new_array
        # This grabs the first element in the version sorted list which should always be the highest version available on DockerHub; this should match stable's version"
        if [[ -n "${upstream_tags[@]}" ]]; then
          debug "Setting latest upstream version var to array first index"
          latest_ver="${upstream_tags[0]}"
        else
          debug "Setting latest to running version"
          latest_ver=$running_ver
          # Set Contiguous updates to false here to ensure that since the app is on latest version, it still attempts to pull patch version updates
          contiguous_update=false
        fi
        # Sort the upstream tags we've chosen as the upgrade path
        IFS=$'\n' upgrade_path=($(sort -V <<<"${upstream_tags[*]}"))
        # Reset IFS to default value
        IFS=$' \t\n'


        debug "------------"
        debug "Listing version information"
        debug "------------"
        debug "Upgrade Strategy: $UPGRADE_STRATEGY"
        debug "Running Version: $running_ver"
        debug "Breaking Version: $breaking_ver"
        debug "Upstream Versions: [${upstream_tags[@]}]"
        debug "Latest Version: $latest_ver"
        debug "Upgrade path: [${upgrade_path[@]}]"
        debug "Number of upgrades: ${#upgrade_path[@]}"
    fi
  ## IF NOT STABLE
  else
    # Running Pinned Version; Normal update with warning
    debug "PinVer: Running as a non-stable, pinned version -- proceed with warning and update"
    contiguous_update=false
    upgrade_warning
  fi
}
