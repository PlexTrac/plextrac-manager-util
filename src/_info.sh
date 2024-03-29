# Provides information about the running PlexTrac instance
#
# Usage:
#  plextrac info
#  plextrac info --summary # print just the summary

function mod_info() {
  title "PlexTrac Instance Summary"
  info "Public URL: ${UNDERLINE}https://${CLIENT_DOMAIN_NAME}${RESET}"
  echo >&2 ""
  info "TLS Certificate:"
  msg "    %b\n" "`info_TLSCertificateDetails`"
  echo >&2 ""
  info "Services:"
  msg "    %s\n" "`releaseDetails`"
  echo >&2 ""
  info "Upgrade Strategy: ${UPGRADE_STRATEGY:-stable}"

  title "Docker Compose"

  info "Active Container Images"
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    images=$(container_client images)
  else
    images=$(compose_client images)
  fi
  msg "    %s\n" "$images"
  echo >&2 ""

  info "Active Services"
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    active=$(container_client ps)
  else
    active=$(compose_client ps)
  fi
  msg "    %s\n" "$active"
  echo >&2 ""

  #Check for Maintenance Mode
  check_for_maintenance_mode

  title "Host Details"
  info "Disk Statistics"
  msg "$(check_disk_capacity)"
  msg "$(info_backupDiskUsage)"

}

function info_TLSCertificateDetails() {
  local certInfo opensslOutput
  local issuer expires subject
  if opensslOutput="`echo | openssl s_client -servername localhost -connect 127.0.0.1:443 2>/dev/null || true`"; then
    certInfo="`echo "$opensslOutput" | openssl x509 -noout -dates -checkend 6048000 -subject -issuer || true`"
    debug "$certInfo"
    echo "Issuer: \t`awk -F'=' '/issuer/ { $1=""; $2=""; print }' <<<"$certInfo" | sed 's/ //g'`"
    echo "Expires: \t`awk -F'=' '/notAfter/ { print $2}' <<<"$certInfo"`"
  else
    error "Certificate Information Unavailable" 2>&1
  fi
}

function releaseDetails() {
  summary=("Name Image Version")
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    local cmd='podman ps --format "{{.Names}}"'
  else
    local cmd='compose_client ps --services'
  fi
  for service in `$cmd | xargs -n1 echo`; do
    image=`_getServiceContainerImageRepo $service || echo "unknown"`
    version=`_getServiceContainerVersion $service || echo "unknown"`
    summary+=("$service $image $version")
  done

  printf "%s\n" "${summary[@]}" | column -t

  #for line in "${summary[@]}"; do echo "$line" | awk '{ printf "%-%ss  %25-s %s\n", $1, $4, $2, $3 }'; done
}

function _getImageForService() {
  service=$1
  if [ "$CONTAINER_RUNTIME" == "podman" ]; then
    imageId=$(container_client container inspect $service --format '{{.Image}}' 2>/dev/null)
  else
    imageId=$(compose_client images -q $service 2>/dev/null)
  fi
  if [ "$imageId" == "" ]; then echo "unknown"; else echo "$imageId"; fi
}

function _getServiceContainerImageRepo() {
  service=$1
  imageId=`_getImageForService $service`
  imageRepo=$(docker image inspect $imageId --format='{{ index .RepoTags 0 }}' 2>/dev/null | awk -F ':' '{print $1}' 2>/dev/null || echo '')
  echo $imageRepo
}

function _getServiceContainerVersion() {
  service=$1
  imageId=`_getImageForService $service`
  version=`docker image inspect $imageId --format='{{ index .Config.Labels "org.opencontainers.image.version" }}' 2>/dev/null || echo ''`
  if [ "$version" == "20.04" ]; then
    version="7.2.0"
  fi
  if [ "$version" == "" ]; then
    if [ "$CONTAINER_RUNTIME" == "podman" ]; then
      local cmd='docker exec'
    else
      local cmd='compose_client exec -T'
    fi
    case $service in
      "$coreBackendComposeService")
        version=`$cmd $coreBackendComposeService cat package.json | jq -r '.version'`
        ;;
      "$couchbaseComposeService")
        version=`$cmd $couchbaseComposeService couchbase-cli --version`
        ;;
      "$postgresComposeService")
        if [ "$CONTAINER_RUNTIME" == "podman" ]; then
          version=$(docker image inspect $imageId --format '{{ index .Annotations "org.opencontainers.image.version" }}' 2>/dev/null || echo '')
        else
          version=$(docker image inspect postgres:14-alpine --format '{{range $index, $value := .Config.Env}}{{$value}}{{"\n"}}{{end}}' | grep PG_VERSION | cut -d '=' -f2 || echo '')
        fi
        ;;
      "redis")
        if [ "$CONTAINER_RUNTIME" == "podman" ]; then
          version=$(docker image inspect $imageId --format '{{ index .Annotations "org.opencontainers.image.version" }}')
        else
          version=$(docker image inspect $imageId --format '{{range $index, $value := .Config.Env}}{{$value}}{{"\n"}}{{end}}' | grep REDIS_VERSION | cut -d '=' -f2 || echo '')
        fi
        ;;
      *)
        version=$(docker images $imageId | awk 'NR != 1 {print $3}')
        ;;
    esac
  fi
  echo "$version"
}
