
# Update ENV configuration
# Reads in `config.txt`, `.env` (if they exist) and merges with an auto-generated defaults
# configuration.
# Behavior:
#   Non-empty values from .env & config.txt are read into a local variable, preference given to .env
#   The existing, non-empty vars are imported to ensure secrets, etc remain stable
#   Default configuration is generated, using imported vars where applicable
#   The new base configuration (including any values set with imported vars) is merged with existing vars
#   This final result is diffed against the current .env for review
#   User is prompted to accept or deny the modifications
function generate_default_config() {
  info "Generating env config"

  # Read vars from .env & config.txt, skipping empty values
  # Output unique vars with preference given to .env
  local existingEnv=`cat ${PLEXTRAC_HOME}/.env 2>/dev/null || echo ""`
  local configTxt=`cat ${PLEXTRAC_HOME}/config.txt 2>/dev/null || echo ""`
  existingCfg=$(sort -u -t '=' -k 1,1 \
    <(echo "$existingEnv" | awk -F= 'length($2)') \
    <(echo "$configTxt" | awk -F= 'length($2)') \
    | awk 'NF' -)
  set -o allexport
  debug "Loading vars from existing config..."
  source <(echo "${existingCfg}")
  set +o allexport


  # Generate base env, using imported vars from above where applicable
  generatedEnv="
JWT_KEY=${JWT_KEY:-`generateSecret`}
MFA_KEY=${MFA_KEY:-`generateSecret`}
COOKIE_KEY=${COOKIE_KEY:-`generateSecret`}
PROVIDER_CODE_KEY=${PROVIDER_CODE_KEY:-`generateSecret`}
PLEXTRAC_HOME=$PLEXTRAC_HOME
CLIENT_DOMAIN_NAME=${CLIENT_DOMAIN_NAME:-$(hostname -f)}
DOCKER_HUB_USER=${DOCKER_HUB_USER:-plextracusers}
DOCKER_HUB_KEY=${DOCKER_HUB_KEY:-}
ADMIN_EMAIL=${ADMIN_EMAIL:-}
LETS_ENCRYPT_EMAIL=${LETS_ENCRYPT_EMAIL:-}
USE_CUSTOM_CERT=${USE_CUSTOM_CERT:-false}
USE_CUSTOM_MAILER_CERT=${USE_CUSTOM_MAILER_CERT:-false}
USE_MAILER_SSL=${USE_MAILER_SSL:-false}
COUCHBASE_URL=${couchbaseComposeService}
REDIS_PASSWORD=${REDIS_PASSWORD:-`generateSecret`}
REDIS_CONNECTION_STRING=redis
RUNAS_APPUSER=True
PLEXTRAC_PARSER_URL=https://plextracparser:4443
UPGRADE_STRATEGY=${UPGRADE_STRATEGY:-"stable"}
PLEXTRAC_BACKUP_PATH="${PLEXTRAC_BACKUP_PATH:-$PLEXTRAC_HOME/backups}"

`generate_default_couchbase_env | setDefaultSecrets`
`generate_default_postgres_env | setDefaultSecrets`
"

  # Merge the generated env with the local vars
  # Preference is given to the generated data so we can force new
  # values as needed (eg, rotating SENTRY_DSN)
  mergedEnv=$(echo "${generatedEnv}" | sort -u -t '=' -k 1,1 - <(echo "$existingCfg") | awk 'NF' -)

  if test -f "${PLEXTRAC_HOME}/.env"; then
    if [ $(echo "$mergedEnv" | md5sum | awk '{print $1}') = $(md5sum "${PLEXTRAC_HOME}/.env" | awk '{print $1}') ]; then
      log "No change required";
    else
      envDiff="`diff -Nurb --color=always "${PLEXTRAC_HOME}/.env" <(echo "$mergedEnv") || true`"
      info "Detected pending changes to ${PLEXTRAC_HOME}/.env:"
      log "${envDiff}"
      if get_user_approval; then
        event__log_activity "config:update-env" "$envDiff"
        echo "$mergedEnv" > "${PLEXTRAC_HOME}/.env"
      else
        die "Unable to continue without updating .env"
      fi
    fi
  else
    info "Writing initial .env"
    echo "$mergedEnv" > "${PLEXTRAC_HOME}/.env"
  fi

  mv "${PLEXTRAC_HOME}/config.txt" "${PLEXTRAC_HOME}/config.txt.old" 2>/dev/null || true
  _load_env
  log "Done."
}

function generateSecret() {
  # replace any non-alphanumeric characters so postgres doesn't choke
  echo `head -c 64 /dev/urandom | base64 | tr -cd '[:alnum:]._-' | head -c 32`
}

function setDefaultSecrets() {
  OLDIFS=$IFS
  export IFS==
  while read var val; do
    if [ $val == "<secret>" ]; then
      val='`generateSecret`'
    fi
    eval "echo `printf '%s=${%s:-%s}\n' $var $var $val`"
    #echo "$var=${var:-$val}"
  done < "${1:-/dev/stdin}"
  export IFS=$OLDIFS
}

function login_dockerhub() {
  local output
  info "Logging into DockerHub to pull images"
  if [ -z ${DOCKER_HUB_KEY} ]; then
    die "ERROR: Docker Hub key not found, please set DOCKER_HUB_KEY in the .env and re-run configuration"
  fi

  output="`docker login -u ${DOCKER_HUB_USER:-plextracusers} --password-stdin 2>&1 <<< "${DOCKER_HUB_KEY}"`" || die "${output}"
  debug "$output"
  log "Done."
}

function updateComposeConfig() {
  title "Updating Docker Compose Configuration"
  docker_createInitialComposeOverrideFile
  targetComposeFile="${PLEXTRAC_HOME}/docker-compose.yml"

  info "Checking $targetComposeFile for changes"
  decodedComposeFile=$(base64 -d <<<$DOCKER_COMPOSE_ENCODED)
  if ! test -f "$targetComposeFile"; then
    debug "Creating initial file"
    echo "$decodedComposeFile" > $targetComposeFile
  fi

  composeConfigDiff="`composeConfigNeedsUpdated 2>/dev/null || true`"
  if composeConfigNeedsUpdated >/dev/null; then
    log "$composeConfigDiff"
    if get_user_approval; then
      echo "$decodedComposeFile" > $targetComposeFile
      event__log_activity "config:update-dockercompose" "$composeConfigDiff"
    else
      error "Unable to continue without updating docker-compose.yml"
      return 1
    fi
  fi
  info "Done."
}

function create_volume_directories() {
  title "Create directories for bind mounts"
  debug "Ensuring directories exist for Docker Volumes..."
  info "`compose_client config --format=json | jq '.volumes[] | .driver_opts.device | select(.)' | xargs -r mkdir -vp`"
  info "Done"
}

