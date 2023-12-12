## Functions for managing the Postgres Database

postgresDatabases=('CORE' 'RUNBOOKS')
postgresUsers=('ADMIN' 'RW' 'RO')

function generate_default_postgres_env() {
  cat <<- ENDPOSTGRES
`
  echo PG_HOST=postgres
  echo POSTGRES_USER=internalonly
  echo "POSTGRES_PASSWORD=<secret>"
  for db in ${postgresDatabases[@]}; do
    echo "PG_${db}_DB=${db,,}"
    for user in ${postgresUsers[@]}; do
      echo "PG_${db}_${user}_USER=${db,,}_${user,,}"
      echo "PG_${db}_${user}_PASSWORD=<secret>"
    done
  done
`
ENDPOSTGRES
}

function postgres_metrics_validation() {
  if [ "${PG_METRICS_USER:-}" != "" ]; then
    info "Checking user $PG_METRICS_USER can access postgres metrics"
    debug "`compose_client exec -T -u 1337 -e PGPASSWORD=$POSTGRES_PASSWORD $postgresComposeService \
        psql -a -v -U internalonly -d core 2>&1 <<- EOF 
CREATE OR REPLACE FUNCTION __tmp_create_user() returns void as \\$\\$
BEGIN
  IF NOT EXISTS (
          SELECT                       -- SELECT list can stay empty for this
          FROM   pg_catalog.pg_user
          WHERE  usename = '$PG_METRICS_USER') THEN
    CREATE USER $PG_METRICS_USER;
  END IF;
END;
\\$\\$ language plpgsql;

SELECT __tmp_create_user();
DROP FUNCTION __tmp_create_user();

ALTER USER $PG_METRICS_USER WITH PASSWORD '$PG_METRICS_PASSWORD';
ALTER USER $PG_METRICS_USER SET SEARCH_PATH TO $PG_METRICS_USER,pg_catalog;

GRANT pg_monitor to $PG_METRICS_USER;
EOF
`"
fi

  # Stand up PlexTrac in Vagrant --
  # Query inside container with compose_client passing in user / pass and then query
  # Review _backup.sh for a postgres query / access example

  # This function should be run when? Run on update or arbitrarily -- _check.sh line 21
  # /vagrant/src/plextrac autofix

}
