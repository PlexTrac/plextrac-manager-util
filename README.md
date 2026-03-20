# plextrac-manager-util

This is the PlexTrac management CLI that can be used to perform the initial setup of a new PlexTrac
installation as well as performing maintenance tasks on running instances.

## Usage

Please refer to `docs/getting-started.md` for usage instructions.

## Contributing

Please refer to `docs/development.md` for development setup and contribution instructions.

## Database migrations, UMF, and DVU (app v3.0+)

- **UMF** (*Unified Migration Framework*) is the migration system in the application (e.g. `npm run db:migrate`) that can apply all pending migrations in order.
- **DVU** (*Direct Version Upgrades*) is the *outcome*: upgrading across multiple minor versions in one step (one pull / one update) instead of stepping every release. **UMF is what makes DVU safe** once the app ships it—manager-util switches to the UMF path when you’re on a **v3.0+** image.

**This CLI** (see `docs/development.md` and `plextrac migration-plan`): resolved app version **≥ 3.0** runs the **`unified-migrations`** Compose service (UMF chain); otherwise **`couchbase-migrations`** (legacy stepped-era chain). Optional break-glass: **`FORCE_LEGACY_MIGRATIONS=true`** forces legacy even on v3.x.

## Support

Now officially supported on:

- Ubuntu 22.04 and 24.04
- CentOS Stream 8, and Stream 9*
- RedHat Linux 8 and 9*
- Rocky Linux 8 and 9*
- Debian 11 and 12

*Note: if running CentOS Stream 9, RHEL 9, or Rocky LInux 9, you'll need to use the PlexTrac version of Coucbase 7.2.0

### Package Requirements

The following system packages are used by and install by this application:
| Package | Version|
| -- | -- |
| jq | v1-6 |
| bc | all |
| bash | v5+ |
| apt-transport-https | all |
| ca-certificates | all |
| wget | all |
| gnupg-agent | all |
| software-properties-common | all (Debian) |
| unzip | all |
| docker-ce | >=v26.0.0 |
| docker-ce-cli | >=v26.0.0 |
| containerd.io | >=1.6.28 |
| docker-compose-plugin | ~v2.24 |
