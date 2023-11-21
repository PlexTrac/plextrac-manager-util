function systemPackageManager() {
  if command -v apt-get >/dev/null 2>&1; then echo "apt"; return; fi
  if command -v yum >/dev/null 2>&1; then echo "yum"; return; fi
}

function system_packages__refresh_package_lists() {
  debug "Refreshing OS package lists"
  case `systemPackageManager` in
    "apt")
      _system_cmd_with_debug_and_fail "apt-get update 2>&1"
      ;;
    "yum")
      _system_cmd_with_debug_and_fail "yum check-update 2>&1 || true" # hide exit code for successful check and pending upgrades"
      ;;
  esac
}

function system_packages__do_system_upgrade() {
  info "Updating OS packages, this make take some time!"
  nobest="--nobest"
  if [ "$(grep '^NAME' /etc/os-release | cut -d '=' -f2 | grep CentOS)" ]; then
    nobest=""
  elif [ "$(grep '^NAME' /etc/os-release | cut -d '=' -f2 | grep RHEL)" ]; then
    info "RHEL"

  elif [ "$(grep '^NAME' /etc/os-release | cut -d '=' -f2 | grep RockyLinux)" ]; then
    info "RockyLinux"
  fi
  debug "$(grep '^NAME' /etc/os-release | cut -d '=' -f2 | tr -d '"')"
  system_packages__refresh_package_lists
  debug "Running system upgrade"
  case `systemPackageManager` in
    "apt")
      out=`export DEBIAN_FRONTEND=noninteractive ; apt-get upgrade -y -o DPkg::Options::=--force-confold -o DPkg::Options::=--force-confdef  2>&1 && apt-get autoremove -y 2>&1` || { error "Failed to upgrade system packages"; debug "$out"; return 1; }
      debug "$out"
      ;;
    "yum")
      out=`yum upgrade -q -y $nobest 2>&1` || { error "Failed to upgrade system packages"; debug "$out"; return 1; }
      debug "$out"
      ;;
    *)  
      error "unsupported"
      exit 1
      ;;
  esac
  log "Done."
}

function system_packages__install_system_dependencies() {
  info "Installing/updating required packages..."
  system_packages__refresh_package_lists
  debug "Installing system dependencies"
  case `systemPackageManager` in
    "apt")
      out=`apt-get install -y \
        apt-transport-https \
        ca-certificates \
        wget \
        gnupg-agent \
        software-properties-common \
        jq \
        unzip \
        bc \
        2>&1` || { error "Failed to install system dependencies"; debug "$out"; return 1; }
      debug "$out"
      ;;
    "yum")
      out=`yum install -q -y \
        ca-certificates \
        wget \
        jq \
        unzip \
        bc \
        2>&1` || { error "Failed to install system dependencies"; debug "$out"; return 1; }
      debug "$out"
      ;;
    *)
      error "unsupported"
      exit 1
      ;;
  esac
  log "Done."
}

function install_docker() {
  if ! command -v docker &> /dev/null || [ "${1:-}" == "force" ]; then
    case `systemPackageManager` in
      "apt")
        info "installing docker, this might take some time..."
        _system_cmd_with_debug_and_fail "mkdir -p /etc/apt/keyrings; \
          wget -O - -q https://download.docker.com/linux/ubuntu/gpg | \
          sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
        _system_cmd_with_debug_and_fail 'echo "deb [arch=$(dpkg --print-architecture)
          signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu
          $(cat /etc/os-release | grep VERSION_CODENAME | cut -d '=' -f2) stable" | sudo tee /etc/apt/sources.list.d/docker.list'
        system_packages__refresh_package_lists
        _system_cmd_with_debug_and_fail "apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin 2>&1"
        _system_cmd_with_debug_and_fail "systemctl enable docker 2>&1"
        event__log_activity "install:docker" `docker --version`
        debug `docker --version`
        ;;
      "yum")
        info "installing docker, this might take some time..."
        _system_cmd_with_debug_and_fail "yum install -q -y yum-utils"
        # RHEL Docker repo has been deprecated, so only CentOS repo is used
          _system_cmd_with_debug_and_fail "yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo"
        system_packages__refresh_package_lists
        _system_cmd_with_debug_and_fail "yum install -q -y docker-ce docker-ce-cli containerd.io docker-compose-plugin 2>&1"
        _system_cmd_with_debug_and_fail "systemctl enable docker 2>&1"
        debug "restarting docker service"
        _system_cmd_with_debug_and_fail "/bin/systemctl restart docker.service"
        event__log_activity "install:docker" `docker --version`
        debug `docker --version`
        ;;
      *)
        error "unsupported"
        exit 1
        ;;
    esac
    log "Done."
  else
    info "docker already installed, version: `docker --version`"
  fi
}

function install_docker_compose() {
  if ! command -v docker compose &> /dev/null || [ "${1:-}" == "force" ]; then
    case `systemPackageManager` in
      "apt")
        info "Installing docker compose..."
        system_packages__refresh_package_lists
              _system_cmd_with_debug_and_fail "apt install -y docker-compose-plugin 2>&1"
        docker_compose_version=$(docker compose version)
        event__log_activity "install:docker-compose" `docker compose version`
        info "docker compose installed, version: `docker compose version`"
        ;;
      "yum")
        info "Installing docker compose..."
        system_packages__refresh_package_lists
        _system_cmd_with_debug_and_fail "yum install -q -y docker-ce docker-ce-cli containerd.io docker-compose-plugin 2>&1"
        event__log_activity "install:docker-compose" `docker compose version`
        info "docker compose installed, version: `docker compose version`"
        ;;
      *)
        error "unsupported"
        exit 1
        ;;
    esac
    log "Done."
  else
    info "docker compose already installed, version: `docker compose version`"
  fi
}

function _system_cmd_with_debug_and_fail() {
  cmd=$1
  fail_msg=${2:-"Command failed: '$cmd'"}
  out=`eval $cmd` || { error "$fail_msg"; debug "$out"; return 1; }
  debug "$out"
}
