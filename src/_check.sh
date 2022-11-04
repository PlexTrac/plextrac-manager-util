# Handle running checks on the PlexTrac instance
# Usage
#   plextrac check        # run checks against the active installation
#   plextrac check --pre  # run pre-install checks

function mod_check() {
  if [ ${DO_PREINSTALL_CHECKS:-0} -eq 1 ]; then
    title "Running pre-installation checks"
    _check_system_meets_minimum_requirements
    _check_no_existing_installation
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
    postgres_metrics_validation


    # echo >&2 ""

    # title "Notifications"
    # info "Summary"
    # msg "`compose_client exec plextracapi npm run status:notifications | fgrep -v '> '`"
  fi
}

###

# Check for an existing installation
function _check_no_existing_installation() {
  if [ ${IGNORE_EXISTING_INSTALLATION:-0} -eq 1 ]; then
    info "SKIPPING existing installation checks (check command arguments)"
    return 0
  fi
  info "Checking for pre-existing installation at '${PLEXTRAC_HOME}'"
  status=0
  if test -d "${PLEXTRAC_HOME}"; then
    debug "Found directory '${PLEXTRAC_HOME}'"
    if test -f "${PLEXTRAC_HOME}/docker-compose.yml"; then
      error "Found existing docker-compose.yml"
      status=1
    fi
    if test -f "${PLEXTRAC_HOME}/docker-compose.override.yml"; then
      error "Found existing docker-compose.override.yml"
      status=1
    fi
  fi
  return $status
}

function _check_system_meets_minimum_requirements() {
  info "Checking for initial packages"
  _check_base_required_packages
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

  query=".operating_systems[] | select((.name==\"$name\" and .versions[]==\"$release\")) | .family"

  output=`jq --exit-status -r "${query}" <<<"${SYSTEM_REQUIREMENTS}"` || \
    { error "Detected OS $name:$release does not meet system requirements"
      debug "json query filter: '${query}'"; debug "$output" ; exit 1 ; }
  log "Detected supported OS '$name:$release' from family '$output'"
}

# Check for some base required packages to even validate the system
function _check_base_required_packages() {
  requiredCommands=('jq' 'lsb_release' 'curl')
  missingCommands=()
  status=0
  for cmd in ${requiredCommands[@]}; do
    debug "--"
    debug "Checking if '$cmd' is available"
    output="`command -V "$cmd" 2>&1`" || { debug "Missing required command '$cmd'"; debug "$output";
                                         missingCommands+=("$cmd"); status=1 ; continue; }
    log "$cmd is available"
  done
  if [ $status -ne 0 ]; then
    error "Missing required commands: ${missingCommands[*]}"
    # special handling for centos/rhel, which need epel enabled
    if command -v yum >/dev/null 2>&1; then
      installCmd="${BOLD}\$${RESET} ${CYAN}"
      yum repolist -q | grep epel || installCmd+='yum install --assumeyes epel-release && '

      declare -A cmdToPkg=([jq]=jq [lsb_release]=redhat-lsb-core [curl]=curl)
      installCmd="$installCmd""yum install --assumeyes`for cmd in ${missingCommands[@]}; do echo -n " ${cmdToPkg[$cmd]}"; done`"

      log "${BOLD}Please enable the EPEL repo and install required packages:"
      log "$installCmd"
    fi
    # debian based systems should all be roughly similar
    if command -v apt-get >/dev/null 2>&1; then
      declare -A cmdToPkg=([jq]=jq [lsb_release]=lsb-release [curl]=curl)
      installCandidates=`for cmd in ${missingCommands[@]}; do echo -n " ${cmdToPkg[$cmd]}"; done`
      log "${BOLD}Please install required packages:"
      log "${BOLD}\$${RESET} ${CYAN}apt-get install -y ${installCandidates}"
    fi
  fi
  return $status
}
