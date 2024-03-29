function mod_autocomplete() {
  info "Configuring plextrac CLI autocomplete..."
  if [ ! -f "${PLEXTRAC_HOME}/.bash_completion.d" ]; then
    debug "Creating autocomplete directory"
    mkdir -p "${PLEXTRAC_HOME}/.bash_completion.d"
  fi
  if [ -f "${PLEXTRAC_HOME}/.local/bin/plextrac" ]; then
    command_list="$(grep -E "function mod" ${PLEXTRAC_HOME}/.local/bin/plextrac | cut -d ' ' -f2 | cut -d '_' -f2 | cut -d '(' -f1 | grep -v etl)"
    command_list=$(echo -n $command_list | tr '\n' ' ' | sed 's/ $//')
    plextrac_compgen="_plextrac()
{
  local cur=\${COMP_WORDS[COMP_CWORD]}
  COMPREPLY=( \$(compgen -W \"$command_list\" -- \$cur) )
}
complete -F _plextrac plextrac"

    bashrc_content='
if [ -d ~/.bash_completion.d ]; then
  for ac in ~/.bash_completion.d/*; do
    if [ -f "$ac" ]; then
      . "$ac"
    fi
  done
fi
unset ac'
    debug "`echo \"${plextrac_compgen}\" > ${PLEXTRAC_HOME}/.bash_completion.d/plextrac`"
    if grep -q ".bash_completion.d" "${PLEXTRAC_HOME}/.bashrc"; then
      debug "bash_completion.d already sourced in ${PLEXTRAC_HOME}/.bashrc"
    else
      debug "`echo "${bashrc_content}" >> "${PLEXTRAC_HOME}/.bashrc"`"
    fi
  else
    error "plextrac CLI not found in ${PLEXTRAC_HOME}/.local/bin/plextrac"
  fi
  info "Done. Logout and back in to use autocomplete."    
}
