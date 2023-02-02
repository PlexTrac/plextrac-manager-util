function setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
    BLUE=$(tput setaf 4)
    BOLD=`tput bold` DIM=`tput dim` UNDERLINE=`tput smul` BLINK=`tput blink` STANDOUT=`tput smso`
    RESET=`tput sgr0; tput cnorm` NOCURSOR=`tput civis` CLEARLINE=`tput el1`

  else
    RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
    BLUE=''
    BOLD='' DIM='' UNDERLINE='' BLINK='' STANDOUT=''
    RESET='' NOCURSOR='' CLEARLINE=''
  fi
}

PRINT_MAX_WIDTH=80
PRINT_FILL_CHAR="-"
PRINT_FILL=$(head -c ${PRINT_MAX_WIDTH} /dev/zero | tr '\0' "${PRINT_FILL_CHAR}")

msg() {
  if [ $# -ge 2 ]; then
    fmt="${1}"
    shift
    in="$@"
  else
    in="${1:-}"
    fmt="%b\n"
  fi
  _printf "${fmt}" "${in}"
}

_printf() {
  local line msg format=$1
  #while IFS=$'\n' read -ra line || echo "failed to read $2"; do
  IFS=$'\n' readarray -c1 -t msg <<< "${2}"
    for line in "${msg[@]}"; do
      printf >&2 "${format}" "${line}"
    done
  #done <<< "$2\n"
}

die() {
  local message=$1
  local code=${2:-1} # default exit status 1
  error "$message"
  exit "$code"
}

log_func_header() {
  title "${FUNCNAME[1]}"
}

title() {
  TITLE="${1:-${FUNCNAME[1]}}"
  fill=$(echo "$PRINT_MAX_WIDTH-${#TITLE}-4" | bc)
  printf >&2 "\n-- %s %.${fill}s\n\n" "${BOLD}${TITLE}${RESET}" "${PRINT_FILL}"
}

debug() {
  if [ ${VERBOSE:-false} == true ]; then
    msg "${DIM}    %b${RESET}\n" "${@}"
  fi
}

log() {
  msg "    %b${RESET}\n" "$1"
}

info() {
  msg "${GREEN}[+]${RESET} %b\n" "${@}"
}

error() {
  msg "${RED}${BOLD}!!! ${RESET}${BOLD}%b${RESET}\n" "$@"
}
