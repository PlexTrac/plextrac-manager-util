## Migrating from Legacy (v1/v2) Scripts

### Prerequisites

- Debian-based operating system, preferably Ubuntu LTS
- CLI access to the host system
- Access to `sudo` for initialization

### Steps

1. Download the PlexTrac utility from Github:
    - `curl -LsO https://github.com/PlexTrac/plextrac-manager-util/releases/latest/download/plextrac`
1. Initialize system for the PlexTrac utility:
    - _Note: if your installation is in a non-standard location, ie not in `/opt/plextrac`, please append the --install-dir=/path/to/plextrac flag_
    - `chmod a+x plextrac && sudo ./plextrac initialize -v`
1. Initialization complete, further steps _must be run_ under the `plextrac` user account:
    - `sudo su - plextrac`
1. Start the migration:
    - `plextrac migrate -v -y`
1. Update `docker-compose.override.yml` to add any custom logos, TLS certs, etc
1. Finalize the installation:
    - `plextrac install -v -y`

### Further Steps

1. Configure backups
    - Example: `0 8 * * * bash -c 'echo "running backups"; date; plextrac backup -v' >> /var/log/plextrac/backup.log 2>&1`
