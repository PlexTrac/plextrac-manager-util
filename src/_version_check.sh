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

# Hub tag (x.y) strictly after running major.minor (same numeric padding as existing compares).
function _hub_xy_tag_gt_running_ver() {
  local hub_tag="$1" run="$2"
  [ $(printf "%03d%03d%03d%03d" $(echo "${hub_tag}" | tr '.' ' ')) -gt $(printf "%03d%03d%03d%03d" $(echo "${run}" | tr '.' ' ')) ]
}

# True if hub_tag sorts at or before pin (sort -V); used to cap pinned contiguous path at UPGRADE_STRATEGY.
function _hub_tag_sort_lte_pin() {
  local hub_tag="$1" pin="$2"
  local low
  low=$(printf '%s\n' "${hub_tag}" "${pin}" | sort -V | head -n1)
  [ "${low}" = "${hub_tag}" ]
}

# Hub page progress: log on page 1 and every 10th page (10, 20, …) to limit noise during long scans.
function _version_check_log_hub_page_tick() {
  local page="${1:?}"
  [ "${page}" -eq 1 ] || [ $((page % 10)) -eq 0 ]
}

# Manager util major < 3: only when the app is already on 3.x, collapse to a single hop (newest tag in range). 2.x apps use the full upgrade_path in one update (same as util v3+).
function _version_check_apply_util_lt3_upgrade_throttle() {
  local util_major="${VERSION%%.*}"
  if [[ "${util_major}" =~ ^[0-9]+$ ]] && [ "${util_major}" -lt 3 ] && [ "${contiguous_update}" = true ]; then
    local upgrade_path_sorted=() sorted_hub_tag sorted_path_last_index
    while IFS= read -r sorted_hub_tag; do
      [ -z "${sorted_hub_tag}" ] && continue
      upgrade_path_sorted+=("${sorted_hub_tag}")
    done < <(printf '%s\n' "${upgrade_path[@]}" | sort -V)
    if [ ${#upgrade_path_sorted[@]} -ge 1 ]; then
      if [[ "${maj_ver}" =~ ^[0-9]+$ ]] && [ "${maj_ver}" -ge 3 ]; then
        sorted_path_last_index=$((${#upgrade_path_sorted[@]} - 1))
        upgrade_path=( "${upgrade_path_sorted[$sorted_path_last_index]}" )
        latest_ver="${upgrade_path_sorted[$sorted_path_last_index]}"
        info "Manager util v${VERSION} (< v3.0): app already on 3.x — updating to latest in range (${latest_ver})."
      fi
    fi
  fi
}

function _version_check_debug_path_summary() {
  debug "------------"
  debug "Listing version information"
  debug "------------"
  debug "Upgrade Strategy: $UPGRADE_STRATEGY"
  debug "Running Version: $running_ver"
  debug "Breaking Version: ${breaking_ver:-}"
  debug "Upstream Versions: [${upstream_tags[*]}]"
  debug "Latest Version: $latest_ver"
  debug "Upgrade path: [${upgrade_path[*]}]"
  debug "Number of upgrades: ${#upgrade_path[@]}"
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
    running_ver="$maj_ver.$min_ver"
  else
    debug "RunVer: plextracapi is NOT running"
    die "plextracapi service isn't running. Please run 'plextrac start' and re-run the update"
  fi

  local hub_docker_tags_qs="page_size=1000&ordering=last_updated"

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
    info "Authenticating with Docker Hub…"
    JWT_TOKEN=$(wget --header="Content-Type: application/json" --post-data='{"username": "'$DOCKER_HUB_USER'", "password": "'$DOCKER_HUB_KEY'"}' -O - https://hub.docker.com/v2/users/login/ -q | jq -r .token)
    if [[ -n "$JWT_TOKEN" ]]; then
        # Latest x.y: for app already on 3.x, newest tags tend to appear on page 1 — one page is enough for max semver there.
        # Otherwise paginate until we find a page with at least one x.y tag (legacy behavior).
        local stable_p1_json cand_latest
        if [[ "${maj_ver}" =~ ^[0-9]+$ ]] && [ "${maj_ver}" -ge 3 ]; then
          info "Looking up latest stable x.y tag (single Hub page; app already on 3.x)…"
          if stable_p1_json=$(wget --header="Authorization: JWT "${JWT_TOKEN} -O - "https://hub.docker.com/v2/repositories/plextrac/plextracapi/tags/?page=1&${hub_docker_tags_qs}" -q 2>/dev/null); then
            cand_latest=$(echo "${stable_p1_json}" | jq -r .results[].name 2>/dev/null | grep -E '(^[0-9]\.[0-9]*$)' | sort -V | tail -n1 || true)
            if [ -n "${cand_latest}" ]; then
              latest_ver="${cand_latest}"
              debug "Stable: latest x.y from Hub page 1 (max semver on page): ${latest_ver}"
            fi
          fi
        fi
        if [ -z "${latest_ver}" ]; then
          info "Looking up the latest stable plextracapi tag on Docker Hub (paginated API; each page fetch may take a moment)…"
          page=1
          while [ $page -lt 600 ]; do
            if _version_check_log_hub_page_tick "${page}"; then
              log "Docker Hub: fetching tags page ${page} (latest stable lookup)…"
            fi
            latest_ver=($(wget --header="Authorization: JWT "${JWT_TOKEN} -O - "https://hub.docker.com/v2/repositories/plextrac/plextracapi/tags/?page=$page&${hub_docker_tags_qs}" -q | jq -r .results[].name | grep -E '(^[0-9]\.[0-9]*$)' || true))
            page=$(($page + 1))
            debug "Latest_Stable Version: ${latest_ver[0]}"
            if [ -n "$latest_ver" ]; then break; fi
          done
          latest_ver="${latest_ver[0]}"
        fi

        ## LOGIC: LATEST_STABLE
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
    if [ "$contiguous_update" = true ]; then
      local stable_latest_maj
      stable_latest_maj=$(echo "${latest_ver}" | cut -d. -f1)
      # Running and latest stable both 3.x: UMF collapses 3.x to one hop — no upstream tag walk.
      if [[ "${maj_ver}" =~ ^[0-9]+$ ]] && [ "${maj_ver}" -ge 3 ] \
         && [[ "${stable_latest_maj}" =~ ^[0-9]+$ ]] && [ "${stable_latest_maj}" -ge 3 ]; then
        debug "Stable: skipping upstream Hub pagination (running and latest stable x.y are 3.x)."
        if [ $(printf "%03d%03d%03d%03d" $(echo "${latest_ver}" | tr '.' ' ')) -gt $(printf "%03d%03d%03d%03d" $(echo "${running_ver}" | tr '.' ' ')) ]; then
          _collapse_upgrade_path_v3_umf "${latest_ver}"
          if [ ${#upgrade_path[@]} -gt 0 ]; then
            local upgrade_path_last_index
            upgrade_path_last_index=$((${#upgrade_path[@]} - 1))
            latest_ver="${upgrade_path[$upgrade_path_last_index]}"
          fi
          upstream_tags=("${latest_ver}")
        else
          debug "Stable: running version is at or past latest stable x.y."
          contiguous_update=false
          upgrade_path=("")
          latest_ver="${running_ver}"
          upstream_tags=("${running_ver}")
        fi
        _version_check_apply_util_lt3_upgrade_throttle
        _version_check_debug_path_summary
      else
        # Get upstream tag list (2.x paths or if latest stable is still 2.x)
        debug "Looking for Running version $running_ver or Breaking version $breaking_ver"
        info "Scanning Docker Hub tag pages for the contiguous upgrade path (stops once your running or breaking version appears in a page; may take several minutes if Hub is slow)…"
        while [ $page -lt 600 ]
          do
            if _version_check_log_hub_page_tick "${page}"; then
              log "Docker Hub: fetching tags page ${page} (upgrade path scan)…"
            fi
            upstream_tags+=(`wget --header="Authorization: JWT "${JWT_TOKEN} -O - "https://hub.docker.com/v2/repositories/plextrac/plextracapi/tags/?page=$page&${hub_docker_tags_qs}" -q | jq -r .results[].name | grep -E '(^[0-9]\.[0-9]*$)' || true`)
            # Get the available versions from DockerHub and save to array
            if [[ $(echo "${upstream_tags[@]}" | grep "$running_ver" || true) ]]
              then
                  debug "Found running version $running_backend_version"; break;
            elif [[ $(echo "${upstream_tags[@]}" | grep "$breaking_ver" || true) ]]
              then
                  debug "Found breaking version $breaking_ver"; break;
            fi
            page=$((page + 1))
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
        # Max x.y seen in the scanned tag set (sort -V ascending → tail is highest). Final target still comes from upgrade_path after UMF collapse below.
        if [[ -n "${upstream_tags[*]}" ]]; then
          debug "Setting latest_ver to max x.y among collected upstream tags (intermediate; path collapse may adjust)"
          latest_ver=$(printf '%s\n' "${upstream_tags[@]}" | sort -V | tail -n1)
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

        _version_check_apply_util_lt3_upgrade_throttle
        _version_check_debug_path_summary
      fi
    fi
  ## IF NOT STABLE (pinned): same Hub contiguous rules as stable, capped at UPGRADE_STRATEGY
  else
    debug "PinVer: Pinned UPGRADE_STRATEGY=${UPGRADE_STRATEGY}"
    breaking_ver="2.0"
    upstream_tags=()
    # Fast path: skip Hub tag enumeration when it cannot change the answer.
    # - Running x.y already equals the pin (any major): no path to discover.
    # - Pure 3.x → higher 3.x pin: UMF collapses to one hop; no need to list every repo tag page.
    local pinned_pin_major pinned_skip_hub_scan=false
    pinned_pin_major=$(echo "${UPGRADE_STRATEGY}" | cut -d. -f1)
    # Running x.y strictly past pin (sort -V): no forward contiguous path to enumerate on Hub.
    local pinned_ord_hi pinned_ord_lo
    pinned_ord_hi=$(printf '%s\n' "${running_ver}" "${UPGRADE_STRATEGY}" | sort -V | tail -n1)
    pinned_ord_lo=$(printf '%s\n' "${running_ver}" "${UPGRADE_STRATEGY}" | sort -V | head -n1)
    if [ "${pinned_ord_hi}" = "${running_ver}" ] && [ "${pinned_ord_lo}" = "${UPGRADE_STRATEGY}" ] && [ "${running_ver}" != "${UPGRADE_STRATEGY}" ]; then
      pinned_skip_hub_scan=true
      contiguous_update=false
      upgrade_path=("")
      latest_ver="${running_ver}"
      upstream_tags=("${running_ver}")
      debug "Pinned: running x.y is past UPGRADE_STRATEGY — no forward contiguous path; skipping Hub tag scan."
    elif [ "${running_ver}" = "${UPGRADE_STRATEGY}" ]; then
      pinned_skip_hub_scan=true
      contiguous_update=false
      upgrade_path=("")
      latest_ver="${running_ver}"
      upstream_tags=("${running_ver}")
      debug "Pinned: running x.y matches UPGRADE_STRATEGY — skipping Hub tag scan."
    elif [[ "${maj_ver}" =~ ^[0-9]+$ ]] && [ "${maj_ver}" -ge 3 ] \
         && [[ "${pinned_pin_major}" =~ ^[0-9]+$ ]] && [ "${pinned_pin_major}" -ge 3 ]; then
      local pinned_hi pinned_lo
      pinned_hi=$(printf '%s\n' "${running_ver}" "${UPGRADE_STRATEGY}" | sort -V | tail -n1)
      pinned_lo=$(printf '%s\n' "${running_ver}" "${UPGRADE_STRATEGY}" | sort -V | head -n1)
      if [ "${pinned_hi}" = "${UPGRADE_STRATEGY}" ] && [ "${pinned_lo}" = "${running_ver}" ]; then
        pinned_skip_hub_scan=true
        contiguous_update=true
        _collapse_upgrade_path_v3_umf "${UPGRADE_STRATEGY}"
        latest_ver="${UPGRADE_STRATEGY}"
        upstream_tags=("${UPGRADE_STRATEGY}")
        info "Skipping Docker Hub tag scan — 3.x → 3.x pin (${running_ver} → ${UPGRADE_STRATEGY}), single collapsed hop."
      fi
    fi

    if [ "${pinned_skip_hub_scan}" = true ]; then
      _version_check_apply_util_lt3_upgrade_throttle
      if [ "${contiguous_update}" != true ]; then
        upgrade_warning
      fi
      _version_check_debug_path_summary
    else
      info "Authenticating with Docker Hub…"
      JWT_TOKEN=$(wget --header="Content-Type: application/json" --post-data='{"username": "'$DOCKER_HUB_USER'", "password": "'$DOCKER_HUB_KEY'"}' -O - https://hub.docker.com/v2/users/login/ -q | jq -r .token)
      if [[ -z "$JWT_TOKEN" ]]; then
        contiguous_update=false
        upgrade_path=("")
        local util_major="${VERSION%%.*}" pinned_strategy_major min_2x_before_3_pin higher_of_running_and_floor
        min_2x_before_3_pin="${MIN_2X_BEFORE_3_PIN:-2.28}"
        if [[ "${util_major}" =~ ^[0-9]+$ ]] && [ "${util_major}" -lt 3 ]; then
          pinned_strategy_major=$(echo "${UPGRADE_STRATEGY}" | cut -d. -f1)
          if [[ "${pinned_strategy_major}" =~ ^[0-9]+$ ]] && [[ "${maj_ver}" =~ ^[0-9]+$ ]] && [ "${maj_ver}" -lt 3 ] && [ "${pinned_strategy_major}" -ge 3 ]; then
            higher_of_running_and_floor=$(printf '%s\n' "${running_ver}" "${min_2x_before_3_pin}" | sort -V | tail -n1)
            if [ "${higher_of_running_and_floor}" != "${running_ver}" ]; then
              die "Manager util v${VERSION} cannot jump from app 2.x (${running_backend_version}) to a 3.x pin (${UPGRADE_STRATEGY}) without Docker Hub (no JWT). Reach at least ${min_2x_before_3_pin} on 2.x first, set Docker Hub credentials for contiguous pins, or install manager util v3.0+."
            fi
          fi
        fi
        upgrade_warning
      else
        local page=1 hub_page_json hub_result_count
        local -a pinned_hub_xy_for_bailout=()
        local -a page_xy_tags
        local xy_element
        info "Scanning Docker Hub tag pages for tags between ${running_ver} and ${UPGRADE_STRATEGY} (stops once running or breaking x.y appears in fetched pages, like stable; may take a moment if Hub is slow)…"
        while [ $page -lt 600 ]; do
          if _version_check_log_hub_page_tick "${page}"; then
            log "Docker Hub: fetching tags page ${page} (pinned path)…"
          fi
          # Do not assign via bare $(wget …) under set -e: a timeout, rate limit, or network blip aborts the whole update.
          if ! hub_page_json=$(wget --header="Authorization: JWT "${JWT_TOKEN} -O - "https://hub.docker.com/v2/repositories/plextrac/plextracapi/tags/?page=$page&${hub_docker_tags_qs}" -q); then
            debug "Docker Hub: no response for tags page ${page} (fetch failed or empty). Stopping scan; continuing with ${#upstream_tags[@]} tag(s) collected so far."
            break
          fi
          if [ -z "${hub_page_json}" ]; then
            debug "Docker Hub: empty response body for tags page ${page}. Stopping scan; continuing with ${#upstream_tags[@]} tag(s) collected so far."
            break
          fi
          hub_result_count=$(echo "${hub_page_json}" | jq -r '.results | length // 0' 2>/dev/null) || hub_result_count=0
          if _version_check_log_hub_page_tick "${page}"; then
            log "Docker Hub: page ${page} received (${hub_result_count} tag entries in response)."
          fi
          if ! [[ "${hub_result_count}" =~ ^[0-9]+$ ]] || [ "${hub_result_count}" -eq 0 ]; then
            debug "Docker Hub tags: stopping tag scan at page ${page} (empty or invalid response)"
            break
          fi
          # One parse per page: accumulate all x.y for bailout; add range-filtered tags to upstream_tags.
          page_xy_tags=()
          while IFS= read -r xyname; do
            [ -n "${xyname}" ] && page_xy_tags+=("${xyname}")
          done < <(echo "${hub_page_json}" | jq -r .results[].name 2>/dev/null | grep -E '(^[0-9]\.[0-9]*$)' || true)
          for xy_element in "${page_xy_tags[@]}"; do
            pinned_hub_xy_for_bailout+=("${xy_element}")
            _hub_xy_tag_gt_running_ver "${xy_element}" "${running_ver}" || continue
            _hub_tag_sort_lte_pin "${xy_element}" "${UPGRADE_STRATEGY}" || continue
            upstream_tags+=("${xy_element}")
          done
          if [[ $(printf '%s\n' "${pinned_hub_xy_for_bailout[@]}" | grep -Fx "${running_ver}" || true) ]]; then
            debug "Pinned: found running x.y ${running_ver} in accumulated Hub tags — stopping pagination (same bailout as stable upstream scan)."
            break
          elif [[ $(printf '%s\n' "${pinned_hub_xy_for_bailout[@]}" | grep -Fx "${breaking_ver}" || true) ]]; then
            debug "Pinned: found breaking x.y ${breaking_ver} in accumulated Hub tags — stopping pagination."
            break
          fi
          page=$((page + 1))
        done
        local -a deduped_hub_tags=()
        while IFS= read -r hub_tag_name; do
          [ -z "${hub_tag_name}" ] && continue
          deduped_hub_tags+=("${hub_tag_name}")
        done < <(printf '%s\n' "${upstream_tags[@]}" | sort -u | sort -V)
        upstream_tags=("${deduped_hub_tags[@]}")
        if [ ${#upstream_tags[@]} -eq 0 ] || [[ -z "${upstream_tags[0]:-}" ]]; then
          local pin_wins
          pin_wins=$(printf '%s\n' "${running_ver}" "${UPGRADE_STRATEGY}" | sort -V | tail -n1)
          if [ "${pin_wins}" = "${UPGRADE_STRATEGY}" ] && [ "${UPGRADE_STRATEGY}" != "${running_ver}" ]; then
            contiguous_update=true
            _collapse_upgrade_path_v3_umf "${UPGRADE_STRATEGY}"
            latest_ver="${UPGRADE_STRATEGY}"
          else
            contiguous_update=false
            upgrade_path=("")
            latest_ver="${running_ver}"
          fi
        else
          contiguous_update=true
          IFS=$'\n' upgrade_path=($(printf '%s\n' "${upstream_tags[@]}" | sort -V))
          IFS=$' \t\n'
          _collapse_upgrade_path_v3_umf "${upgrade_path[@]}"
          if [ ${#upgrade_path[@]} -gt 0 ]; then
            local upgrade_path_last_index last_step last_major pin_major
            upgrade_path_last_index=$((${#upgrade_path[@]} - 1))
            last_step="${upgrade_path[$upgrade_path_last_index]}"
            last_major=$(echo "${last_step}" | cut -d. -f1)
            pin_major=$(echo "${UPGRADE_STRATEGY}" | cut -d. -f1)
            # Pin newer than last Hub step: refine v3→v3 in place; crossing 2.x→3.x must append so we do not drop the last 2.x hop (e.g. [2.28] + pin 3.0.0-rc.3 → [2.28, 3.0.0-rc.3] not [3.0.0-rc.3]).
            if [ "$(printf '%s\n' "${last_step}" "${UPGRADE_STRATEGY}" | sort -V | tail -n1)" = "${UPGRADE_STRATEGY}" ] && [ "${UPGRADE_STRATEGY}" != "${last_step}" ]; then
              if [[ "${last_major}" =~ ^[0-9]+$ ]] && [ "${last_major}" -lt 3 ] \
                 && [[ "${pin_major}" =~ ^[0-9]+$ ]] && [ "${pin_major}" -ge 3 ]; then
                upgrade_path+=("${UPGRADE_STRATEGY}")
              else
                upgrade_path[$upgrade_path_last_index]="${UPGRADE_STRATEGY}"
              fi
            fi
            upgrade_path_last_index=$((${#upgrade_path[@]} - 1))
            latest_ver="${upgrade_path[$upgrade_path_last_index]}"
          fi
        fi
        _version_check_apply_util_lt3_upgrade_throttle
        if [ "${contiguous_update}" != true ]; then
          upgrade_warning
        fi
        _version_check_debug_path_summary
      fi
    fi
  fi
}
