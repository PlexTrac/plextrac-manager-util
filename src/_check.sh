# Handle running checks on the PlexTrac instance
# Usage
#   plextrac check        # run checks against the active installation
#   plextrac check --pre  # run pre-install checks

function mod_check() {
  if [ ${DO_PREINSTALL_CHECKS:-0} -eq 1 ]; then
    title "Running pre-installation checks"
    _check_no_existing_installation
    _check_system_meets_minimum_requirements
  else
    title "Running checks on installation at '${PLEXTRAC_HOME}'"
    requires_user_plextrac
    info "Checking Docker Compose Config"
    compose_client config -q && info "Config check passed"
    pending=`composeConfigNeedsUpdated || true`
    if [ "$pending" != "" ]; then
        error "Pending Changes:"
        msg "    %s\n" "$pending"
    fi
    VALIDATION_ONLY=1 configure_couchbase_users
  fi
}

###

# Check for an existing installation
function _check_no_existing_installation() {
  info "Checking for pre-existing installation at '${PLEXTRAC_HOME}'"
  if test -d "${PLEXTRAC_HOME}"; then
    debug "Found directory '${PLEXTRAC_HOME}'"
    if test -f "${PLEXTRAC_HOME}/docker-compose.yml"; then
      debug "Found existing docker-compose.yml"
    fi
    if test -f "${PLEXTRAC_HOME}/docker-compose.override.yml"; then
      debug "Found existing docker-compose.override.yml"
    fi
  fi
}

function _check_system_meets_minimum_requirements() {
  info "Checking system meets minimum requirements"
  _check_os_supported_flavor_and_release
}

# Check common files to get the os flavor/release version
function _check_os_supported_flavor_and_release() {
  debug "Supported Operation Systems:"
  debug "`jq -r '(["NAME", "VERSIONS"] | (., map(length*"-"))), (.operating_systems[] | [.name, .versions[]]) | @tsv' <<<"$SYSTEM_REQUIREMENTS"`"
  debug ""

  name=`lsb_release -si | tr '[:upper:]' '[:lower:]'`
  debug "Detected OS name: '${name}'"
  release=`lsb_release -sr`
  debug "Detected OS release/version: '${release}'"

  query=".operating_systems[] | select((.name==\"$name\" and .versions[]==\"$release\")) | .name"

  output=`jq --exit-status -r "${query}" <<<"${SYSTEM_REQUIREMENTS}"` || \
    { error "Detected OS $name:$release does not meet system requirements"; debug "json query filter: '${query}'" ; exit 1 ; }
  log "Detected OS '$name:$release' matched supported OS '$output'"
}
