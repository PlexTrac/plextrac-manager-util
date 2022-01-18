function system_packages__refresh_package_lists() {
  debug "Refreshing OS package lists"
  _system_cmd_with_debug_and_fail "apt-get update 2>&1"
}

function system_packages__do_system_upgrade() {
  info "Updating OS packages, this make take some time!"
  system_packages__refresh_package_lists
  debug "Running system upgrade"
  out=`apt-get upgrade -y -o DPkg::Options::=--force-confold -o DPkg::Options::=--force-confdef  2>&1 && apt-get autoremove -y 2>&1` || { error "Failed to upgrade system packages"; debug "$out"; return 1; }
  debug "$out"
  log "Done."
}

function system_packages__install_system_dependencies() {
  info "Installing/updating required packages..."
  system_packages__refresh_package_lists
  debug "Installing system dependencies"
  out=`apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common \
    jq \
    unzip \
    2>&1` || { error "Failed to install system dependencies"; debug "$out"; return 1; }
  debug "$out"
  log "Done."
}

function install_docker() {
  if ! command -v docker &> /dev/null || [ "${1:-}" == "force" ]; then
    info "installing docker, this might take some time..."
    _system_cmd_with_debug_and_fail "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - 2>&1"
    debug "docker fingerprint: \n`apt-key fingerprint 0EBFCD88 2>&1`"
    _system_cmd_with_debug_and_fail "add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" 2>&1"
    system_packages__refresh_package_lists
    _system_cmd_with_debug_and_fail "apt install -y docker-ce docker-ce-cli containerd.io 2>&1"
    _system_cmd_with_debug_and_fail "systemctl enable docker 2>&1"
    event__log_activity "install:docker" `docker --version`
    debug `docker --version`
    log "Done."
  else
    info "docker already installed, version: `docker --version`"
  fi
}

function install_docker_compose() {
  if ! command -v docker-compose &> /dev/null || [ "${1:-}" == "force" ]; then
    info "installing docker-compose..."
    curl -sL $(curl -sL \
      https://api.github.com/repos/docker/compose/releases/latest | jq -r \
      ".assets[] | select(.name | test(\"^docker-compose-$(uname -s)-$(uname -m)$\"; \"i\")) | .browser_download_url" | grep -v .sha256) -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    docker_compose_version=`docker-compose --version`
    event__log_activity "install:docker-compose" "$docker_compose_version"
    info "docker compose installed, version: $docker_compose_version"
  else
    info "docker-compose already installed, version: `docker-compose --version`"
  fi
  log "Done."
}

function _system_cmd_with_debug_and_fail() {
  cmd=$1
  fail_msg=${2:-"Command failed: '$cmd'"}
  out=`eval $cmd` || { error "$fail_msg"; debug "$out"; return 1; }
  debug "$out"
}
