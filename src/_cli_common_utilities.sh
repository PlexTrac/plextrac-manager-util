
function get_user_approval() {
  # If interactive, prompt for user approval & return 0
  # If non-interactive, log failure and return 1
  # If -y/--assume-yes/ASSUME_YES flags/envvars are set, return 0
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
  if [ "$EUID" -ne 1337 ]; then
    die "${RED}Please run as plextrac user${RESET}"
  fi
}

function event__log_activity() {
  local event_log_filepath="${PLEXTRAC_HOME}/event.log"
  if ! test -d `dirname "${event_log_filepath}"`; then { debug "missing parent directory to create event log"; return 0; }; fi
  local activity_timestamp=`date -u +%s`
  local activity_name="${1:-func:${FUNCNAME[1]}}"
  local activity_data="${2:--}"

  debug `printf "Logged event '%s' at %s\n" $activity_name $activity_timestamp | tee -a "${event_log_filepath}"`

  if [ "$activity_data" != "-" ]; then activity_data="`printf "|\n>>>\n%s\n<<<\n" "$activity_data"`"; fi
  debug "`{
    echo "Event Details:"
    echo "  activity: $activity_name"
    echo "  timestamp: \`date -d @$activity_timestamp +%c\`"
    echo "  user: ${USER:-$EUID}"
    echo "  data: $activity_data"
    echo ""
  } |& tee -a "$event_log_filepath"`"
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
  fi
}
