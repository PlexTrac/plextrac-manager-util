# plextrac-manager-util

This is the PlexTrac management CLI that can be used to perform the initial setup of a new PlexTrac installation as well as performing maintenance tasks on running instances.

## Usage

    Usage: plextrac COMMAND [FLAGS]

    [+] Available commands:
        initialize                           initialize local system for PlexTrac installation
        install                              install PlexTrac (assumes previously initialized system)
        start                                run the PlexTrac application
        backup                               perform backup on currently running PlexTrac application
        check                                checks for version & status of PlexTrac application
        configure                            does initial configuration required for PlexTrac application
        info                                 display information about the current PlexTrac Instance

### For a fresh install of a new PlexTrac instance:

    DOCKER_HUB_KEY=${DOCKER_HUB_KEY} plextrac configure
    plextrac update
    plextrac start

## Testing inside a Vagrant box

This repo is bundled with a [Vagrant](https://www.vagrantup.com/) configuration so that the CLI can be tested inside a virtual machine without polluting your host machine.

You'll need to have [Vagrant](https://www.vagrantup.com/) installed before you can use the preconfigured virtual machine.

1.  Start up the Vagrant virtual machine:

        vagrant up

2.  SSH into the Vagrant VM and become the `plextrac` user

        vagrant ssh
        sudo -iu plextrac

3.  Create a default `.env` file by running the `configure` command

        plextrac configure

4.  Set your DOCKER_HUB_KEY environment variable in the `.env` file

        vim /opt/plextrac/.env

    You should update the following vars:

        DOCKER_HUB_KEY    # Your token for pulling images from the plextrac private Docker Hub registry
        UPGRADE_STRATEGY  # A docker image tag to pull (i.e. 'stable', 'edge', 'imminent', or a git commitish)

    You should also set any feature flag or `OVERRIDE` vars in the `.env` file now, _for example_:

        OVERRIDE_TRANSACTION_ID_LOGGING=true

5.  Start the Plextrac application

        plextrac start

6.  You can tail logs:

    ...for a specific service:

        docker-compose logs -f <SERVICE_NAME>

    Example:

        docker-compose logs -f plextracapi

    ...or for the entire stack all at once:

        docker-compose logs -f
