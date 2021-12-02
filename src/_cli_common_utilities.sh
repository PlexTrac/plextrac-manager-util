
function get_user_approval() {
  # If interactive, prompt for user approval & return 0
  # If non-interactive, log failure and return 1
  # If -y/--assume-yes/ASSUME_YES flags/envvars are set, return 0
  if [ ${ASSUME_YES:-false} == "true" ]; then return 0; fi
  tty -s || die "Unable to request user approval in non-interactive shell, try passing the -y or --assume-yes CLI flag"
  PS3='Please select an option: '
  select opt in "Yes" "No" "Exit"; do
    case "${REPLY,,}" in
      "yes" | "y")
        return 0
        ;;
      "no" | "n")
        return 1
        ;;
      "q" | "quit" | "exit")
        die "User cancelled selection";;
      *)
        error "Invalid selection: $REPLY was not one of the provided options"
        ;;
    esac
  done
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
