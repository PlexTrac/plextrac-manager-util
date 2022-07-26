## Functions for managing the Postgres Database


# From UAT
#
# -- START SQL TEMPLATE --
#  -- Add Service Roles
#  --
#  -- Service Admin
#  CREATE USER $PG_PLACEHOLDER_ADMIN_USER WITH PASSWORD '$PG_PLACEHOLDER_ADMIN_PASSWORD';
#  -- Service Read-Only User
#  CREATE USER $PG_PLACEHOLDER_RO_USER WITH PASSWORD '$PG_PLACEHOLDER_RO_PASSWORD';
#  -- Service Read-Write User
#  CREATE USER $PG_PLACEHOLDER_RW_USER WITH PASSWORD '$PG_PLACEHOLDER_RW_PASSWORD';
#  
#  -- Role memberships
#  -- Each role inherits from the role below
#  GRANT $PG_PLACEHOLDER_RO_USER TO $PG_PLACEHOLDER_RW_USER;
#  GRANT $PG_PLACEHOLDER_RW_USER TO $PG_PLACEHOLDER_ADMIN_USER;
#  
#  -- Create Service Database $PG_PLACEHOLDER_DB
#  CREATE DATABASE $PG_PLACEHOLDER_DB;
#  REVOKE ALL ON DATABASE $PG_PLACEHOLDER_DB FROM public;
#  GRANT CONNECT ON DATABASE $PG_PLACEHOLDER_DB TO $PG_PLACEHOLDER_RO_USER;
#  
#  -- switch to the new database.
#  \connect $PG_PLACEHOLDER_DB;
#  
#  -- Schema level grants within $PG_PLACEHOLDER_DB db
#  --
#  -- Service Read-Only user needs basic access
#  GRANT USAGE ON SCHEMA public TO $PG_PLACEHOLDER_RO_USER;
#  
#  -- Only the admin account should ever create new resources
#  -- This also marks Service Admin account as owner of new resources
#  GRANT CREATE ON SCHEMA public TO $PG_PLACEHOLDER_ADMIN_USER;
#  
#  -- Enable read access to all new tables for Service Read-Only
#  ALTER DEFAULT PRIVILEGES FOR ROLE $PG_PLACEHOLDER_ADMIN_USER
#      GRANT SELECT ON TABLES TO $PG_PLACEHOLDER_RO_USER;
#  
#  -- Enable read-write access to all new tables for Service Read-Write
#  ALTER DEFAULT PRIVILEGES FOR ROLE $PG_PLACEHOLDER_ADMIN_USER
#      GRANT INSERT,DELETE,TRUNCATE,UPDATE ON TABLES TO $PG_PLACEHOLDER_RW_USER;
#  
#  -- Need to enable usage on sequences for Service Read-Write
#  -- to enable auto-incrementing ids
#  ALTER DEFAULT PRIVILEGES FOR ROLE $PG_PLACEHOLDER_ADMIN_USER
#      GRANT USAGE ON SEQUENCES TO $PG_PLACEHOLDER_RW_USER;
# -- END SQL TEMPLATE --
#
# -- START INITDB SCRIPT --
#  #!/bin/bash
#  
#  PGPASSWORD="$POSTGRES_PASSWORD"
#  
#  tmpl=`cat /docker-entrypoint-initdb.d/bootstrap-template.sql.txt`
#  
#  for db in core runbooks; do
#    # Ugh this is ugly. Thanks Bash
#    eval "echo "'"'"`echo "$tmpl" | sed "s/PLACEHOLDER/${db^^}/g" -`"'"'"" |
#      psql -a -v ON_ERROR_STOP=1 --username $POSTGRES_USER -d $POSTGRES_USER
#  done
# -- START INITDB SCRIPT --
# -- START SECRET GENERATION SCRIPT --
#!/bin/bash
#  
#  PG_DATABASES=("CORE" "RUNBOOKS")
#  
#  function generatePostgresDatabaseCredentials() {
#    echo "PG_$1_ADMIN_USER=${1,,}_admin"
#    echo -n "PG_$1_ADMIN_PASSWORD="; generateSecret
#    echo "PG_$1_RW_USER=${1,,}_rw"
#    echo -n "PG_$1_RW_PASSWORD="; generateSecret
#    echo "PG_$1_RO_USER=${1,,}_ro"
#    echo -n "PG_$1_RO_PASSWORD="; generateSecret
#  }
#  
#  function generateSecret() {
#    echo `head -c 64 /dev/urandom | base64 | tr -cd '[:alnum:]._-' | head -c 32`
#  }
#  
#  function main() {
#    echo "PG_HOST=postgres"
#    echo "POSTGRES_USER=ullr"
#    echo -n "POSTGRES_PASSWORD="; generateSecret
#    for db in "${PG_DATABASES[@]}"; do
#      echo "PG_${db}_DB=`echo $db | awk '{ print tolower($0) }'`"
#      generatePostgresDatabaseCredentials $db
#    done
#  }
#  
#  main
# -- END SECRET GENERATION SCRIPT --

