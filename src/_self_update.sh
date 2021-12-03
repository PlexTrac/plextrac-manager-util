# Manage self-updates to the management utility
#
# Usage: plextrac update --self-only

function selfupdate_getLatestRelease() {
  local releaseURL='https://api.github.com/repos/PlexTrac/plextrac-manager-util/releases/latest'
  export releaseInfo=`curl -Ls $releaseURL`
}

function checkForManagerUtilUpdate() {
  
  pass
}
