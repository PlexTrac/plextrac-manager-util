# Build functionality for certificate renewal / injection into NGINX

function mod_reload-cert() {
  declare -A nginxValues
  nginxValues[env-file]="--env-file /opt/plextrac/.env"
  nginxValues[plextracnginx-volumes]="-v letsencrypt:/etc/letsencrypt:rw"
  nginxValues[plextracnginx-ports]="-p 0.0.0.0:443:443"
  nginxValues[plextracnginx-image]="docker.io/plextrac/plextracnginx:${UPGRADE_STRATEGY:-stable}"

  title "PlexTrac SSL Certificate Renewal"
  # Check if using LETS_ENCRYPT
  LETS_ENCRYPT_EMAIL=${LETS_ENCRYPT_EMAIL:-}
  USE_CUSTOM_CERT=${USE_CUSTOM_CERT:-false}
  if [ "$LETS_ENCRYPT_EMAIL" != '' ] && [ "$USE_CUSTOM_CERT" == 'false' ]; then
    # IF LETS_ENCRYPT = TRUE
    # ASK TO REMOVE pem/key
    info "Let's Encrypt certificate detected!"
    info "Would you like to reload the SSL Certificates? This will recreate the NGINX container"
    if get_user_approval; then
      info "Recreating plextrac-plextracnginx-1"
      if [ "$CONTAINER_RUNTIME" == "podman" ]; then
        podman rm -f plextracnginx; podman volume rm letsencrypt
        podman run ${nginxValues[env-file]} --restart=always \
        ${nginxValues[plextracnginx-volumes]} --name=plextracnginx --network=plextrac ${nginxValues[plextracnginx-ports]} -d ${nginxValues[plextracnginx-image]} 1>/dev/null
      else
        compose_client up -d --force-recreate plextracnginx
      fi
    else 
      die "No changes made!"
    fi
  else
    # IF LETS_ENCRYPT = FALSE
    # Assume custom_certificate key/pem has been replaced and simply re-inject via NGINX recreate
    info "Custom or Self-signed certificate detected!"
    info "Would you like to reload your custom or self-signed SSL certificates? This will recreate the NGINX container"
    if get_user_approval; then
      info "Reloading certificates..."
      if [ "$CONTAINER_RUNTIME" == "podman" ]; then
        podman rm -f plextracnginx; podman volume rm letsencrypt
        podman run ${nginxValues[env-file]} --restart=always \
        ${nginxValues[plextracnginx-volumes]} --name=plextracnginx --network=plextrac ${nginxValues[plextracnginx-ports]} -d ${nginxValues[plextracnginx-image]} 1>/dev/null
      else
        compose_client up -d --force-recreate plextracnginx
      fi
    else
      die "No changes made!"
    fi
  fi
}
