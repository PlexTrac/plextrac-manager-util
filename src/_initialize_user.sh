function create_user() {
  if ! id -u "${PLEXTRAC_USER_NAME:-plextrac}" >/dev/null 2>&1
  then
    info "Adding plextrac user..."
    local user_id="-u 1337"
    if [ "${PLEXTRAC_USER_ID:-}" ]; then
      local user_id="-u ${PLEXTRAC_USER_ID}"
    fi
    if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      useradd --shell /bin/bash $user_id \
              --create-home --home "${PLEXTRAC_HOME}" \
              ${PLEXTRAC_USER_NAME:-plextrac}
    else
      useradd $user_id --groups docker \
              --shell /bin/bash \
              --create-home --home "${PLEXTRAC_HOME}" \
              ${PLEXTRAC_USER_NAME:-plextrac}
    fi
    if ! id -g "plextrac" >/dev/null 2>&1
    then
      groupadd -g $(id -u ${PLEXTRAC_USER_NAME:-plextrac}) ${PLEXTRAC_USER_NAME:-plextrac} -f
    fi
    usermod -g ${PLEXTRAC_USER_NAME:-plextrac} ${PLEXTRAC_USER_NAME:-plextrac}
    log "Done."
  fi
}

function configure_user_environment() {
  info "Configuring plextrac user environment..."
    PROFILES=("/etc/skel/.profile" "/etc/skel/.bash_profile" "/etc/skel/.bashrc")
    for profile in "${PROFILES[@]}"; do
      if [ -f "${profile}" ]; then
        debug "Copying ${profile} to ${PLEXTRAC_HOME}"
        cp "${profile}" "${PLEXTRAC_HOME}"
      else
        debug "${profile} does not exist, skipping"
      fi
    done
    mkdir -p "${PLEXTRAC_HOME}/.local/bin"
    sed -i 's/#force_color_prompt=yes/force_color_prompt=yes/' "${PLEXTRAC_HOME}/.bashrc"
    grep -E 'PATH=${HOME}/.local/bin:$PATH' "${PLEXTRAC_HOME}/.bashrc" || echo 'PATH=${HOME}/.local/bin:$PATH' >> "${PLEXTRAC_HOME}/.bashrc"
    log "Done."
}

function copy_scripts() {
  info "Copying plextrac CLI to user PATH..."
  tmp=`mktemp -p ~/ plextrac-XXX`
  debug "tmp script location: $tmp"
  debug "`$0 dist 2>/dev/null > $tmp && cp -uv $tmp "${PLEXTRAC_HOME}/.local/bin/plextrac"`"
  chmod +x "${PLEXTRAC_HOME}/.local/bin/plextrac"
  log "Done."
}

function fix_file_ownership() {
  info "Fixing file ownership in ${PLEXTRAC_HOME} for plextrac"
  local user=$(id -u ${PLEXTRAC_USER_NAME:-plextrac})
  chown -R $user:$user "${PLEXTRAC_HOME}"
  log "Done."
}
