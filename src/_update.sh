# Instance & Utility Update Management
#
# Usage: plextrac update

# subcommand function, this is the entrypoint eg `plextrac update`
function mod_update() {
  title "Updating PlexTrac Instance"
  info "Checking for updates to the PlexTrac Management Utility"
  if selfupdate_checkForNewRelease; then
    event__log_activity "update:upgrade-utility" "${releaseInfo}"
    selfupdate_doUpgrade
    die "Failed to upgrade PlexTrac Management Util! Please reach out to support if problem persists"
    exit 1 # just in case, previous line should already exit
  fi
  info "Updating PlexTrac instance to latest release..."
  mod_configure
  pull_docker_images
  mod_start
  mod_check
}

function _selfupdate_refreshReleaseInfo() {
  if test -z ${releaseInfo+x}; then
    local releaseURL='https://api.github.com/repos/PlexTrac/plextrac-manager-util/releases/latest'
    export releaseInfo=`curl -Ls $releaseURL`
    debug "`jq . <<< "$releaseInfo"`"
  fi
}

function selfupdate_checkForNewRelease() {
  #if test -z ${DIST+x}; then
  #  log "Running in local mode, skipping release check"
  #  return 1
  #fi
  _selfupdate_refreshReleaseInfo
  local releaseTag=$(jq '.tag_name' -r <<<$releaseInfo)
  local releaseVersion=$(_parseVersion "$releaseTag")
  local localVersion=$(_parseVersion "$VERSION")
  debug "Current Version: $localVersion"
  debug "Latest Version: $releaseVersion"
  if [ $localVersion == $releaseVersion ]; then
    info "$localVersion is already up to date"
    return 1
  fi
  info "Updating from $localVersion to $releaseVersion"

  return 0
}

function _parseVersion() {
  local rawVersion=$1
  sed -E 's/^v?(.*)$/\1/' <<< $rawVersion
}

function info_getReleaseDetails() {
  local changeLog=$(jq '.body' <<<$releaseInfo)
  debug "$changeLog"
}

function selfupdate_doUpgrade() {
  info "Performing Self Update"
  local releaseVersion=$(jq '.tag_name' -r <<<$releaseInfo)
  local scriptAsset=$(jq '.assets[] | select(.name=="plextrac") | .' <<<$releaseInfo)
  debug "$scriptAsset"
  local temp=`mktemp -t plextrac-$releaseVersion-XXX`
  local target="${PLEXTRAC_HOME}/.local/bin/plextrac"

  debug "`curl --no-progress-meter --verbose -L -o $temp $(jq .browser_download_url -r <<<$scriptAsset) 2>&1`"
  # todo: add md5sum matching here
  test -f $temp || die "Failed to download release $releaseVersion"
  chmod a+x $temp
  $temp -h >/dev/null 2>&1 && (
    debug "Moving $temp to "
    mv -b --suffix=.bak $temp "${target}"
    debug `chmod a-x "${target}.bak" || true`
    chmod a+x "${target}"
    log "Successfully downloaded & tested update"
    )

  debug "Initially called w/ args '$_INITIAL_CMD_ARGS'" 
  eval $target $_INITIAL_CMD_ARGS
  exit
}
