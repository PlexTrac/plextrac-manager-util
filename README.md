# plextrac-manager-util

This is the PlexTrac management CLI that can be used to perform the initial setup of a new PlexTrac
installation as well as performing maintenance tasks on running instances.

## Usage

Please refer to `docs/getting-started.md` for usage instructions.

## Contributing

Please refer to `docs/development.md` for development setup and contribution instructions.

## Support

Now officially supported on:

- Ubuntu 20.04 and 22.04
- CentOS 7, Stream 8, and Stream 9*
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
