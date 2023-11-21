# Provides a method using our utility to safely stop the PlexTrac Application
#
# Usage:
#  plextrac stop

function mod_stop() {
  title "Attempting to gracefully stop PlexTrac..."
  debug "Stopping API, NGINX, Notification engine/sender"
  compose_client stop plextracapi plextracnginx notification-engine notification-sender
  sleep 2
  debug "Stopping Couchbase, Postres, and Redis"
  compose_client stop redis plextracdb postgres
  info "PlexTrac stopped. It's now safe to update and restart"
}
