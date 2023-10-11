# Credits
# "SchemaVersion": "0.1.0",
# "Vendor": "Karol Musur",
# "Version": "v0.5",
# "ShortDescription": "Rollout new Compose service version"
# "Adapted by": "Michael Burke"

# Defaults
HEALTHCHECK_TIMEOUT=60
NO_HEALTHCHECK_TIMEOUT=10

healthcheck() {
  local container_id="$1"

  if docker inspect --format='{{json .State.Health.Status}}' "$container_id" | grep -v "unhealthy" | grep -q "healthy"; then
    return 0
  fi

  return 1
}

scale() {
  local service="$1"
  local replicas="$2"
  compose_client up --detach --scale $service=$replicas --no-recreate "$service"
}

mod_rollout() {
  # Added removal of the couchbase-migrations container due to this not getting attached to the new network scaled
  if [ `docker compose ps -a --format json | jq -re '.[].Name' | grep couchbase-migrations)` ]
    then
      debug "Removing 'couchbase-migrations' container"
      docker rm -f `docker compose ps -a --format json | jq -re '.[].Name' | grep couchbase-migrations` > /dev/null 2>&1
  fi
  # Get list of services from Docker Compose Config
  service_list=(
    "datalake-maintainer"
    "notification-engine"
    "notification-sender"
    "plextracapi"
  )
  #service_list=$(for i in `docker compose config --format json | jq -re '.services|keys[]'`; do \
  #  docker compose config --format json | jq -re --arg v "$i" '.services | "\($v)=\(.[$v].image)"'; \
  #  done | grep plextracapi | sort -u | cut -d '=' -f1)
  debug "$service_list"
  for s in ${service_list[@]}
  #for s in `echo -ne "$service_list"`
    do
      SERVICE=$s
      SCALE=$(docker compose config --format json | jq -re --arg v "$SERVICE" '.services | .[$v].deploy.replicas | select(. != null)')
      if [ $SCALE == 0 ]
        then
          debug "$SERVICE show $SCALE replicas; skipping"
          continue
      fi
      if [[ "$(compose_client ps --quiet "$SERVICE")" == "" ]]
        then
          debug "Service '$SERVICE' is not running. Starting the service."
          compose_client up --detach --no-recreate "$SERVICE"
          debug "$SERVICE created"
          continue
      fi

      OLD_CONTAINER_IDS_STRING=$(compose_client ps --quiet "$SERVICE")
      readarray -t OLD_CONTAINER_IDS <<<"$OLD_CONTAINER_IDS_STRING"

      if [ $SCALE != "0" ]
        then
          SCALE_TIMES_TWO=$((SCALE * 2))
        else
          SCALE_TIMES_TWO=0
          break
      fi
      debug "Scaling '$SERVICE' to '$SCALE_TIMES_TWO'"
      scale "$SERVICE" $SCALE_TIMES_TWO

      # create a variable that contains the IDs of the new containers, but not the old ones
      NEW_CONTAINER_IDS_STRING=$(compose_client ps --quiet "$SERVICE" | grep --invert-match --file <(echo "$OLD_CONTAINER_IDS_STRING"))
      readarray -t NEW_CONTAINER_IDS <<<"$NEW_CONTAINER_IDS_STRING"

      # check if first container has healthcheck
      if docker inspect --format='{{json .State.Health}}' "${OLD_CONTAINER_IDS[0]}" | grep --quiet "Status"
        then
          debug "Waiting for new containers to be healthy (timeout: $HEALTHCHECK_TIMEOUT seconds)"
          for _ in $(seq 1 "$HEALTHCHECK_TIMEOUT"); do
            SUCCESS=0

            for NEW_CONTAINER_ID in "${NEW_CONTAINER_IDS[@]}"; do
              if healthcheck "$NEW_CONTAINER_ID"; then
                SUCCESS=$((SUCCESS + 1))
              fi
            done

            if [[ "$SUCCESS" == "$SCALE" ]]; then
              break
            fi

            sleep 1
          done

          SUCCESS=0

          for NEW_CONTAINER_ID in "${NEW_CONTAINER_IDS[@]}"; do
            if healthcheck "$NEW_CONTAINER_ID"; then
              SUCCESS=$((SUCCESS + 1))
            fi
          done

          if [[ "$SUCCESS" != "$SCALE" ]]; then
            error "New containers are not healthy. Rolling back."

            for NEW_CONTAINER_ID in "${NEW_CONTAINER_IDS[@]}"; do
              docker stop "$NEW_CONTAINER_ID" > /dev/null 2>&1
              docker rm "$NEW_CONTAINER_ID" > /dev/null 2>&1
            done

            exit 1
          fi
        else
          debug "Waiting for new containers to be ready ($NO_HEALTHCHECK_TIMEOUT seconds)"
          sleep "$NO_HEALTHCHECK_TIMEOUT"
      fi
      for OLD_CONTAINER_ID in "${OLD_CONTAINER_IDS[@]}"; do
        docker stop "$OLD_CONTAINER_ID" > /dev/null 2>&1
        docker rm "$OLD_CONTAINER_ID" > /dev/null 2>&1
      done
    done
    info "Done!"
}
