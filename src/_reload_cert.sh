# Build functionality for certificate renewal / injection into NGINX

function mod_reload-cert() {
  var=$(declare -p "$1")
  eval "declare -A serviceValues="${var#*=}
  if [ "$LETS_ENCRYPT_EMAIL" != '' ] && [ "$USE_CUSTOM_CERT" == 'false' ]; then
    serviceValues[plextracnginx-ports]="-p 0.0.0.0:443:443 -p 0.0.0.0:80:80"
  else
    serviceValues[plextracnginx-ports]="-p 0.0.0.0:443:443"
  fi

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
        podman run ${serviceValues[env-file]} --restart=always \
        ${serviceValues[plextracnginx-volumes]} --name=plextracnginx --network=plextrac ${serviceValues[plextracnginx-ports]} -d ${serviceValues[plextracnginx-image]} 1>/dev/null
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
        podman run ${serviceValues[env-file]} --restart=always \
        ${serviceValues[plextracnginx-volumes]} --name=plextracnginx --network=plextrac ${serviceValues[plextracnginx-ports]} -d ${serviceValues[plextracnginx-image]} 1>/dev/null
      else
        compose_client up -d --force-recreate plextracnginx
      fi
    else
      die "No changes made!"
    fi
  fi
}
