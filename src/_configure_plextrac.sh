
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
CB_BUCKET=reportMe
CB_API_USER=${CB_API_USER:-"ptapiuser"}
CB_ADMIN_USER=${CB_ADMIN_USER:-"ptadminuser"}
CB_BACKUP_USER=${CB_BACKUP_USER:-"ptbackupuser"}
CB_API_PASS=${CB_API_PASS:-`generateSecret`}
CB_ADMIN_PASS=${CB_ADMIN_PASS:-`generateSecret`}
CB_BACKUP_PASS=${CB_BACKUP_PASS:-`generateSecret`}
RUNAS_APPUSER=True
BACKUP_DIR=/opt/couchbase/backups
PLEXTRAC_PARSER_URL=https://plextracparser:4443
UPGRADE_STRATEGY=${UPGRADE_STRATEGY:-"stable"}
"


  # Merge the generated env with the local vars
  # Preference is given to the generated data so we can force new
  # values as needed (eg, rotating SENTRY_DSN)
  mergedEnv=$(echo "${generatedEnv}" | sort -u -t '=' -k 1,1 - <(echo "$existingCfg") | awk 'NF' -)

  diff -Nurb --color=always <(sort "${PLEXTRAC_HOME}/.env") <(echo "$mergedEnv") || true

  if test -f "${PLEXTRAC_HOME}/.env"; then
    if [ $(echo "$mergedEnv" | md5sum | awk '{print $1}') = $(md5sum "${PLEXTRAC_HOME}/.env" | awk '{print $1}') ]; then
      log "No change required";
    else
      if get_user_approval; then
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
  echo `head -c 64 /dev/urandom | base64 | head -c 32`
}

function login_dockerhub() {
  info "Logging into DockerHub to pull images"
  if [ -z ${DOCKER_HUB_KEY} ]; then
    die "ERROR: Docker Hub key not found, please set DOCKER_HUB_KEY in the .env and re-run configuration"
  fi

  docker login -u ${DOCKER_HUB_USER:-plextracusers} -p ${DOCKER_HUB_KEY}  > /dev/null 2>&1
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

  if composeConfigNeedsUpdated; then
    if get_user_approval; then
      echo "$decodedComposeFile" > $targetComposeFile
    else
      die "Unable to continue without updating docker-compose.yml";
    fi
  fi
  info "Done."
}

function create_volume_directories() {
  log_func_header
  debug "Ensuring directories exist for Docker Volumes..."
  info "`compose_client config --format=json | jq '.volumes[] | .driver_opts.device | select(.)' | xargs -r mkdir -vp`"
  info "Done"
}

