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

  title "Docker-Compose"

  info "Active Container Images"
  images=`compose_client images`
  msg "    %s\n" "$images"
  echo >&2 ""

  info "Active Services"
  active=`compose_client ps`
  msg "    %s\n" "$active"
  echo >&2 ""

  title "Host Details"
  info "Disk Statistics"
  msg `check_disk_capacity`
  msg `info_backupDiskUsage`
}

function info_TLSCertificateDetails() {
  local certInfo opensslOutput
  local issuer expires subject
  if opensslOutput="`echo | openssl s_client -servername localhost -connect localhost:443 2>/dev/null || true`"; then
    certInfo="`echo "$opensslOutput" | openssl x509 -noout -dates --checkend 6048000 -subject -issuer || true`"
    debug "$certInfo"
    echo "Issuer: \t`awk -F'=' '/issuer/ { $1=""; $2=""; print }' <<<$certInfo | sed 's/ //g'`"
    echo "Expires: \t`awk -F'=' '/notAfter/ { print $2}' <<<$certInfo`"
  else
    error "Certificate Information Unavailable" 2>&1
  fi
}

function releaseDetails() {
  local service image version summary=("Name Image Version")
  for service in `compose_client ps --services | xargs -n1 echo`; do
    image=`_getServiceContainerImageRepo $service || echo "unknown"`
    version=`_getServiceContainerVersion $service || echo "unknown"`
    summary+=("$service $image $version")
  done
  for line in "${summary[@]}"; do echo "$line" | awk '{ printf "%-15s  %25-s %s\n", $1, $2, $3 }'; done
}

function _getImageForService() {
  local imageId service=$1
  imageId=`compose_client images -q $service 2>/dev/null`
  if [ "$imageId" == "" ]; then echo "unknown"; else echo "$imageId"; fi
}

function _getServiceContainerImageRepo() {
  local imageRepo imageId service=$1
  imageId=`_getImageForService $service`
  imageRepo=`docker image inspect $imageId --format='{{ index .RepoTags 0 }}' 2>/dev/null | awk -F':' '{print $1}' 2>/dev/null || echo ''`
  echo $imageRepo
}

function _getServiceContainerVersion() {
  local version imageId service=$1
  imageId=`_getImageForService $service`
  version=`docker image inspect $imageId --format='{{ index .Config.Labels "org.opencontainers.image.version" }}' 2>/dev/null || echo ''`
  if [ "$version" == "" ]; then
    case $service in
      "$coreBackendComposeService")
        version=`compose_client exec $coreBackendComposeService cat package.json | jq -r '.version'`
        ;;
      "$couchbaseComposeService")
        version=`compose_client exec $couchbaseComposeService couchbase-cli --version`
        ;;
      *)
        version="tag:`compose_client images $service | awk 'NR != 1 {print $3}'`"
        ;;
    esac
  fi
  echo "$version"
}
