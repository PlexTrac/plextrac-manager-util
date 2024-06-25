
function get_user_approval() {
  # If interactive, prompt for user approval & return 0
  # If non-interactive, log failure and return 1
  # If -y/--assume-yes/ASSUME_YES flags/envvars are set, return 0
  # If -y/--assume-yes/ASSUME_YES flags/envvars are NOT allowed, skip returning 0
  if [ ${ASSUME_YES:-false} == "true" ]; then return 0; fi
  tty -s || die "Unable to request user approval in non-interactive shell, try passing the -y or --assume-yes CLI flag"
  PS3='Please select an option: '
  select opt in "Yes" "No" "Exit"; do
    case "${REPLY,,}" in
      "yes" | "y" | 1)
        return 0
        ;;
      "no" | "n" | 2)
        return 1
        ;;
      "q" | "quit" | "exit" | 3)
        die "User cancelled selection";;
      *)
        error "Invalid selection: $REPLY was not one of the provided options"
        ;;
    esac
  done
}

function requires_user_root() {
  if [ "$EUID" -ne 0 ]; then
    die "${RED}Please run as root user (eg, with sudo)${RESET}"
  fi
}

function requires_user_plextrac {
  if [ "$EUID" -ne $(id -u ${PLEXTRAC_USER_NAME:-plextrac}) ]; then
    die "${RED}Please run as ${PLEXTRAC_USER_NAME:-plextrac} user${RESET}"
  fi
}

function event__log_activity() {
  local event_log_filepath="${PLEXTRAC_HOME}/event.log"
  if ! test -d `dirname "${event_log_filepath}"`; then { debug "missing parent directory to create event log"; return 0; }; fi
  local activity_timestamp=`date -u +%s`
  local activity_name="${1:-func:${FUNCNAME[1]}}"
  local activity_data="${2:--}"

  # old versions of tee don't support -p flag, so check here first by grepping help
  if `tee --help | grep -q "diagnose errors writing to non pipes"`; then tee_options='-pa'; else tee_options='-a'; fi

  debug "`printf "Logged event '%s' at %s\n" $activity_name $activity_timestamp | tee $tee_options "${event_log_filepath}" 2>&1 || echo "Unable to write to event log"`"

  if [ "$activity_data" != "-" ]; then activity_data="`printf "|\n>>>\n%s\n<<<\n" "$activity_data"`"; fi
  debug "`{
    echo "Event Details:"
    echo "  activity: $activity_name"
    echo "  timestamp: \`date -d @$activity_timestamp +%c\`"
    echo "  user: ${USER:-$EUID}"
    echo "  data: $activity_data"
    echo ""
  } |& tee $tee_options "$event_log_filepath" 2>&1 || echo "Unable to write to event log"`"
}

function panic() {
  echo >&2 "$*"
  stacktrace
  exit 1
}

function stacktrace() {
  local frame=0 LINE SUB FILE
  while read LINE SUB FILE < <(caller "$frame"); do
    printf '  %s @ %s:%s' "${SUB}" "${FILE}" "${LINE}"
    ((frame++))
  done
}

function _load_static() {
  if ! grep -q -e "^DOCKER_COMPOSE_ENCODED=.*" $0; then
    local staticFilesDir="$(dirname $0)/../static"
    export DOCKER_COMPOSE_ENCODED=`base64 -w0 "$staticFilesDir/docker-compose.yml"`
    export DOCKER_COMPOSE_OVERRIDE_ENCODED=`base64 -w0 "$staticFilesDir/docker-compose.override.yml"`
    export SYSTEM_REQUIREMENTS=`cat "$staticFilesDir/system-requirements.json"`
  fi
}

function os_check() {
  OS_NAME=$(grep '^NAME' /etc/os-release | cut -d '=' -f2)
  OS_VERSION=$(grep '^VERSION_ID' /etc/os-release | cut -d '=' -f2)
  color_always="--color=always"
  if grep -q "Red" <(echo "$OS_NAME"); then
    if grep -q "7." <(echo "$OS_VERSION"); then
      color_always=""
      fi
  fi
}

function check_container_runtime() {
  if [ "$CONTAINER_RUNTIME" == "docker" ]; then debug "Using Docker and Docker Compose as the container runtime";
  elif [ "$CONTAINER_RUNTIME" == "podman" ]; then debug "Using Podman as the container runtime";
  elif [ "$CONTAINER_RUNTIME" == "podman-compose" ]; then die "Using Podman-Compose is still currently unsupported";
  else error "Unknown container runtime: $CONTAINER_RUNTIME"; die "Valid container runtimes are: docker, podman, podman-compose";
  fi
}
