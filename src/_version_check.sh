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
  get_user_approval
}

# Stable contiguous path: 2.x — unchanged (every minor in order). v3.0+ line (major >= 3) — one hop to the
# maximum 3.x Hub tag (UMF); do not step 3.0 then 3.1. e.g. 2.27 2.28 3.0 3.1 -> 2.27 2.28 3.1
function _collapse_upgrade_path_v3_umf() {
  local -a tags_below_v3_major=() tags_v3_major_and_above=() collapsed_path=()
  local hub_tag tag_major
  for hub_tag in "$@"; do
    [ -z "$hub_tag" ] && continue
    tag_major=$(echo "$hub_tag" | cut -d. -f1)
    if [[ "$tag_major" =~ ^[0-9]+$ ]] && [ "$tag_major" -ge 3 ]; then
      tags_v3_major_and_above+=("$hub_tag")
    else
      tags_below_v3_major+=("$hub_tag")
    fi
  done
  collapsed_path=("${tags_below_v3_major[@]}")
  if [ ${#tags_v3_major_and_above[@]} -gt 0 ]; then
    collapsed_path+=("$(printf '%s\n' "${tags_v3_major_and_above[@]}" | sort -V | tail -n1)")
  fi
  upgrade_path=("${collapsed_path[@]}")
}

function version_check() {
  #######################
  ### -- Running Version
  #######################
  ## LOGIC: RunVer
  debug "Running Version"
  # Get running version of Backend
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    running_backend_version="$(for i in $(podman ps -a -q --filter name=plextracapi); do podman inspect "$i" --format json | jq -r '(.[].Config.Labels | ."org.opencontainers.image.version")'; done | sort -u)"
  else
    running_backend_version="$(for i in $(compose_client ps plextracapi -q); do docker container inspect "$i" --format json | jq -r '(.[].Config.Labels | ."org.opencontainers.image.version")'; done | sort -u)"
  fi

  # CONDITION: plextracapi IS/NOT RUNNING
  # Validate that the app is running and returning a version
  if [[ $running_backend_version != "" ]]; then
    debug "RunVer: plextracapi is running and is version $running_backend_version"
    # Get the major and minor version from the running containers
    maj_ver=$(echo "$running_backend_version" | cut -d '.' -f1)
    min_ver=$(echo "$running_backend_version" | cut -d '.' -f2)
    running_ver=$(echo $running_backend_version | awk -F. '{print $1"."$2}')
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
          debug "Latest_Stable Version: ${latest_ver[0]}"
          if [ -n "$latest_ver" ]; then break; fi
        done
        # Set latest_ver to first index item which should be the "latest"
        latest_ver="${latest_ver[0]}"

        ## LOGIC: LATEST_STABLE
        # IF LATEST_STABLE <= 2.0
        #if (( $(echo "$latest_ver <= $breaking_ver" | bc -l) ))
        if [ $(printf "%03d%03d%03d%03d" $(echo "${latest_ver}" | tr '.' ' ')) -le $(printf "%03d%03d%03d%03d" $(echo "${breaking_ver}" | tr '.' ' ')) ]
          then
            debug "Updating normally to $latest_ver without warning"
            contiguous_update=false

          # IF LATEST_STABLE > 2.0
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
        get_user_approval
    fi

    upstream_tags=()
    page=1
    if [ "$contiguous_update" = true ]
      then
        # Get upstream tag list
        debug "Looking for Running version $running_ver or Breaking version $breaking_ver"
        while [ $page -lt 600 ]
          do
            upstream_tags+=(`wget --header="Authorization: JWT "${JWT_TOKEN} -O - "https://hub.docker.com/v2/repositories/plextrac/plextracapi/tags/?page=$page&page_size=1000" -q | jq -r .results[].name | grep -E '(^[0-9]\.[0-9]*$)' || true`)
            # Get the available versions from DockerHub and save to array
            if [[ $(echo "${upstream_tags[@]}" | grep "$running_ver" || true) ]]
              then
                  debug "Found running version $running_backend_version"; break;
            elif [[ $(echo "${upstream_tags[@]}" | grep "$breaking_ver" || true) ]]
              then
                  debug "Found breaking version $breaking_ver"; break;
            fi
            page=$[$page+1]
        done

        # Remove the running version from the Upgrade path
        for i in "${!upstream_tags[@]}"
          do
            #if (( $(echo "${upstream_tags[i]} <= $running_ver" | bc -l) ))
            if [ $(printf "%03d%03d%03d%03d" $(echo "${upstream_tags[i]}" | tr '.' ' ')) -le $(printf "%03d%03d%03d%03d" $(echo "${running_ver}" | tr '.' ' ')) ]
              then
                debug "correcting upstream_tags to remove running version and versions prior"
                unset 'upstream_tags[i]'
            fi
        done
        new_array=("")
        for i in "${!upstream_tags[@]}"; do
            new_array+=( "${upstream_tags[i]}" )
        done
        if [ "${#new_array[@]}" -gt 0 ]; then
                upstream_tags=("${new_array[@]}")
                unset new_array
        else
                upstream_tags=("")
        fi
        # This grabs the first element in the version sorted list which should always be the highest version available on DockerHub; this should match stable's version"
        if [[ -n "${upstream_tags[*]}" ]]; then
          debug "Setting latest upstream version var to array first index"
          # Sorting the tags to ensure we grab the latest and remove empty objects from the previous unset commands
          sorted_upstream_tags=($(sort -V <<<"${upstream_tags[*]}"))
          latest_ver="${sorted_upstream_tags[0]}"
        else
          debug "Setting latest to running version"
          latest_ver=$running_ver
          # Set Contiguous updates to false here to ensure that since the app is on latest version, it still attempts to pull patch version updates
          contiguous_update=false
        fi
        if [[ "${upstream_tags[@]}" != "" ]]; then
                # Sort the upstream tags weve chosen as the upgrade path
                IFS=$'\n' upgrade_path=($(sort -V <<<"${upstream_tags[*]}"))
                # Reset IFS to default value
                IFS=$' \t\n'
                _collapse_upgrade_path_v3_umf "${upgrade_path[@]}"
                if [ ${#upgrade_path[@]} -gt 0 ]; then
                  local upgrade_path_last_index
                  upgrade_path_last_index=$((${#upgrade_path[@]} - 1))
                  latest_ver="${upgrade_path[$upgrade_path_last_index]}"
                fi
        else
                upgrade_path=("")
        fi

        # Manager util major < 3: no multi-hop jumps while app is on 2.x (one Hub tag per update).
        # Manager util 3.0+ keeps the full sorted upgrade_path (DVU-style jumps when tags exist).
        # Once app is 3.x+ but util is still < 3, collapse to a single hop to newest tag in range.
        local util_major="${VERSION%%.*}"
        if [[ "${util_major}" =~ ^[0-9]+$ ]] && [ "${util_major}" -lt 3 ] && [ "${contiguous_update}" = true ]; then
          local upgrade_path_sorted=() sorted_hub_tag sorted_path_last_index
          while IFS= read -r sorted_hub_tag; do
            [ -z "$sorted_hub_tag" ] && continue
            upgrade_path_sorted+=("$sorted_hub_tag")
          done < <(printf '%s\n' "${upgrade_path[@]}" | sort -V)
          if [ ${#upgrade_path_sorted[@]} -ge 1 ]; then
            if [[ "${maj_ver}" =~ ^[0-9]+$ ]] && [ "${maj_ver}" -lt 3 ]; then
              upgrade_path=( "${upgrade_path_sorted[0]}" )
              latest_ver="${upgrade_path_sorted[0]}"
              info "Manager util v${VERSION} (< v3.0): stepping one release at a time on app 2.x — next target ${upgrade_path[*]}. Install manager util v3.0+ for multi-hop stable updates in one run."
            else
              sorted_path_last_index=$((${#upgrade_path_sorted[@]} - 1))
              upgrade_path=( "${upgrade_path_sorted[$sorted_path_last_index]}" )
              latest_ver="${upgrade_path_sorted[$sorted_path_last_index]}"
              info "Manager util v${VERSION} (< v3.0): app already on 3.x — updating to latest in range (${latest_ver})."
            fi
          fi
        fi

        debug "------------"
        debug "Listing version information"
        debug "------------"
        debug "Upgrade Strategy: $UPGRADE_STRATEGY"
        debug "Running Version: $running_ver"
        debug "Breaking Version: $breaking_ver"
        debug "Upstream Versions: [${upstream_tags[*]}]"
        debug "Latest Version: $latest_ver"
        debug "Upgrade path: [${upgrade_path[*]}]"
        debug "Number of upgrades: ${#upgrade_path[@]}"
    fi
  ## IF NOT STABLE
  else
    # Running Pinned Version; Normal update with warning
    debug "PinVer: Running as a non-stable, pinned version -- proceed with warning and update"
    contiguous_update=false
    local util_major="${VERSION%%.*}" pinned_strategy_major
    if [[ "${util_major}" =~ ^[0-9]+$ ]] && [ "${util_major}" -lt 3 ]; then
      pinned_strategy_major=$(echo "${UPGRADE_STRATEGY}" | cut -d. -f1)
      if [[ "${pinned_strategy_major}" =~ ^[0-9]+$ ]] && [[ "${maj_ver}" =~ ^[0-9]+$ ]] && [ "${maj_ver}" -lt 3 ] && [ "${pinned_strategy_major}" -ge 3 ]; then
        die "Manager util v${VERSION} cannot jump from app 2.x (${running_backend_version}) to a 3.x pin (${UPGRADE_STRATEGY}). Pin UPGRADE_STRATEGY to the next 2.x release and update repeatedly, or install manager util v3.0+ for direct 2.x → 3.x upgrades."
      fi
    fi
    upgrade_warning
  fi
}
