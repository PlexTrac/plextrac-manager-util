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

## For a fresh install of a new PlexTrac instance:

    DOCKER_HUB_KEY=${DOCKER_HUB_KEY} plextrac install -y

### A quick note about the `DOCKER_HUB_KEY`

It should look several groups of alphanumeric characters separated by hyphens. It should _not_ be base64-encoded.
Example: `abcd123-11a1-22bb-c3c3-defg567890`

## Testing inside a Vagrant box

This repo is bundled with a [Vagrant](https://www.vagrantup.com/) configuration so that the CLI can be tested inside a virtual machine without polluting your host machine.

You'll need to have [Vagrant](https://www.vagrantup.com/) installed before you can use the preconfigured virtual machine.

1.  Start up the Vagrant virtual machine:

        vagrant up

2.  SSH into the Vagrant VM and become the `plextrac` user

        vagrant ssh
        sudo -iu plextrac

3.  Create a default `.env` file by running the `configure` command

        DOCKER_HUB_KEY=<YOUR_DOCKER_HUB_KEY> plextrac configure

    This will write a `.env` file to `/opt/plextrac/.env` with default values plus the DOCKER_HUB_KEY that you just provided.

4.  Set any non-default environment variables in the `.env` file

        vim /opt/plextrac/.env

    You should check the following vars:

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

## Development

To test changes to the bash scripts, you can SSH into the running Vagrant box and re-compile the plextrac cli by running

    /vagrant/src/plextrac dist > /opt/plextrac/.local/bin/plextrac

Then run whatever cli command you were editing. I.e. `plextrac info`