# Access logs of a running instance
# Usage:
#   plextrac logs

function mod_logs() {
  tail_logs
}

function tail_logs() {
    compose_client logs -f --tail=50
}
