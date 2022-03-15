function create_user() {
  # create "plextrac" user with UID/GID 1337 to match the UID/GID of the container user
  # this is required for anything in the uploads directory to
  if ! id -u "plextrac" >/dev/null 2>&1
  then
    info "Adding plextrac user..."
    useradd --uid 1337 \
            --groups docker \
            --shell /bin/bash \
            --create-home --home "${PLEXTRAC_HOME}" \
            plextrac
    log "Done."
  fi
}

function configure_user_environment() {
  info "Configuring plextrac user environment..."
    test -f "${PLEXTRAC_HOME}/.profile" || test -f /etc/skel/.profile && cp /etc/skel/.profile "${PLEXTRAC_HOME}/.profile" || log "/etc/skel/.profile does not exist, skipping"
    test -f "${PLEXTRAC_HOME}/.bashrc" || cp /etc/skel/.bashrc "${PLEXTRAC_HOME}/.bashrc"
    mkdir -p "${PLEXTRAC_HOME}/.local/bin"
    sed -i 's/#force_color_prompt=yes/force_color_prompt=yes/' "${PLEXTRAC_HOME}/.bashrc"
    egrep 'PATH=${HOME}/.local/bin:$PATH' "${PLEXTRAC_HOME}/.bashrc" || echo 'PATH=${HOME}/.local/bin:$PATH' >> "${PLEXTRAC_HOME}/.bashrc"
}

function copy_scripts() {
  info "Copying plextrac CLI to user PATH..."
  tmp=`mktemp -p /tmp plextrac-XXX`
  debug "tmp script location: $tmp"
  debug "`$(dirname $0)/plextrac dist 2>/dev/null > $tmp && cp -uv $tmp "${PLEXTRAC_HOME}/.local/bin/plextrac"`"
  chmod +x "${PLEXTRAC_HOME}/.local/bin/plextrac"
  log "Done."
}

function fix_file_ownership() {
  info "Fixing file ownership in ${PLEXTRAC_HOME} for plextrac"
  chown -R plextrac:plextrac "${PLEXTRAC_HOME}"
  log "Done."
}
