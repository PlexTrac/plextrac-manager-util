# Build functionality for certificate renewal / injection into NGINX

function mod_cert-renew() {
  title "PlexTrac SSL Certificate Renewal"
  # Check if using LETS_ENCRYPT
  LETS_ENCRYPT_EMAIL=${LETS_ENCRYPT_EMAIL:-}
  USE_CUSTOM_CERT=${USE_CUSTOM_CERT:-false}
  if [ "$LETS_ENCRYPT_EMAIL" != '' ] && [ "$USE_CUSTOM_CERT" == 'false' ]; then
    # IF LETS_ENCRYPT = TRUE
    # ASK TO REMOVE pem/key
    info "Let's Encrypt certificate detected!"
    info "Would you like to force renew your SSL certificate?"
    if get_user_approval; then
      #if yes, continue to delete pem/key and recreate NGINX
      info "Deleting current certificates and loading new certificates"
      compose_client rm -f plextracnginx
      docker volume rm plextrac_letsencrypt
      sleep 2
      compose_client up -d --force-recreate plextracnginx
    else 
      die "No changes made!"
    fi
  else
    # IF LETS_ENCRYPT = FALSE
    # Assume custom_certificate key/pem has been replaced and simply re-inject via NGINX recreate
    info "Custom or Self-signed certificate in use"
    info "Would you like to reload your custom or self-signed certificates?"
    if get_user_approval; then
      info "Reloading certificate..."
      compose_client up -d --force-recreate plextracnginx
    else
      die "No changes made!"
    fi
  fi
}
