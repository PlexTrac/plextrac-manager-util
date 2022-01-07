function system_packages__refresh_package_lists() {
  debug "Refreshing OS package lists"
  output=`apt-get update 2>&1`
  if [ $? -gt 0 ]; then
    error "Failed to get updates"
    log "$output"
  else
    debug "$output"
  fi
}

function system_packages__do_system_upgrade() {
  title "Updating OS packages, this make take some time!"
  system_packages__refresh_package_lists
  apt-get upgrade -y -o Dpkg::Options::="--force-confold" > /dev/null 2>&1 \
    && apt-get autoremove -y > /dev/null 2>&1
  log "Done."
}

function install_os_dependencies() {
  title "Installing/updating required packages..."
  system_packages__refresh_package_lists
  apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common \
    jq \
    unzip \
    > /dev/null 2>&1
  log "Done."
}

function install_docker() {
  if ! command -v docker &> /dev/null || [ "${1:-}" == "force" ]; then
    title "installing docker, this might take some time..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - > /dev/null 2>&1
    debug "docker fingerprint: "
    debug `apt-key fingerprint 0EBFCD88 2>&1`
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /dev/null 2>&1
    apt update > /dev/null 2>&1
    apt install -y docker-ce docker-ce-cli containerd.io > /dev/null 2>&1
    systemctl enable docker > /dev/null 2>&1
    event__log_activity "install-docker" `docker --version`
    debug `docker --version`
    log "Done."
  else
    DVER=$(docker --version)
    info "docker already installed, version: ${DVER}"
  fi
}

function install_docker_compose() {
  if ! command -v docker-compose &> /dev/null || [ "${1:-}" == "force" ]; then
    title "installing docker-compose..."
    curl -sL $(curl -sL \
      https://api.github.com/repos/docker/compose/releases/latest | jq -r \
      ".assets[] | select(.name | test(\"^docker-compose-$(uname -s)-$(uname -m)$\"; \"i\")) | .browser_download_url" | grep -v .sha256) -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    DCVER=$(docker-compose --version)
    event__log_activity "install-docker" "$DCVER"
    info "docker compose installed, version: $DCVER"
  else
    DCVER=$(docker-compose --version)
    info "docker-compose already installed, version: ${DCVER}"
  fi
  log "Done."
}
