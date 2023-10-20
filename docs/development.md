---
# vim: set expandtab ft=markdown ts=4 sw=4 sts=4 tw=100:
---

# Development


## Testing inside a Vagrant box

This repo is bundled with a [Vagrant](https://www.vagrantup.com/) configuration so that the CLI can
be tested inside a virtual machine without polluting your host machine.

You'll need to have [Vagrant](https://www.vagrantup.com/) installed before you can use the
preconfigured virtual machine. Optionally, install the `vagrant-hostmanager` plugin to allow Vagrant
to manage host entries for you.

1.  Start up the Vagrant virtual machine:

        vagrant up

2.  SSH into the Vagrant VM and become the `plextrac` user

        vagrant ssh
        sudo -iu plextrac

3.  Create a default `.env` file by running the `configure` command

        DOCKER_HUB_KEY=<YOUR_DOCKER_HUB_KEY> plextrac configure

    This will write a `.env` file to `/opt/plextrac/.env` with default values plus the
    DOCKER_HUB_KEY that you just provided.

4.  Set any non-default environment variables in the `.env` file

        vim /opt/plextrac/.env

    You should check the following vars:

        DOCKER_HUB_KEY    # Your token for pulling images from the plextrac Docker Hub registry
        UPGRADE_STRATEGY  # A docker image tag to pull (i.e. 'stable', 'edge')

    You should also set any feature flag or `OVERRIDE` vars in the `.env` file now, _for example_:

        OVERRIDE_TRANSACTION_ID_LOGGING=true

5.  Install the Plextrac application

        plextrac install

6.  You can tail logs:

    ...for a specific service:

        docker compose logs -f <SERVICE_NAME>

    Example:

        docker compose logs -f plextracapi

    ...or for the entire stack all at once:

        docker compose logs -f

## Development

To test changes to the bash scripts, you can SSH into the running Vagrant box and re-compile the
plextrac cli:

    /vagrant/src/plextrac dist > /opt/plextrac/.local/bin/plextrac

Then run whatever cli command you were editing. i.e. `plextrac info`

!!! warn
    The auto-update capability of the client will helpfully replace the local cli with the latest
    release any time you run `plextrac update`. I find it most helpful when debugging to simply run
    `/vagrant/src/plextrac <command>` which will always use the live source code.

    As a bonus, stack traces will be more useful as the line numbers and file references will point
    to the actual source files.

