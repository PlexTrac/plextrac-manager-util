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

1. Download and install [VirtualBox](https://www.oracle.com/virtualization/technologies/vm/downloads/virtualbox-downloads.html) to be used as the provider for Vagrant.

2. Start up the Vagrant virtual machine:

        vagrant up

3. SSH into the Vagrant VM and become the `plextrac` user

        vagrant ssh
        sudo -iu plextrac

4. Create a default `.env` file by running the `configure` command

        DOCKER_HUB_KEY=<YOUR_DOCKER_HUB_KEY> plextrac configure

    This will write a `.env` file to `/opt/plextrac/.env` with default values plus the
    DOCKER_HUB_KEY that you just provided.

5. Set any non-default environment variables in the `.env` file

        vim /opt/plextrac/.env

    You should check the following vars:

        DOCKER_HUB_KEY    # Your token for pulling images from the plextrac Docker Hub registry
        UPGRADE_STRATEGY  # A docker image tag to pull (i.e. 'stable', 'edge')

    You should also set any feature flag or `OVERRIDE` vars in the `.env` file now, _for example_:

        OVERRIDE_TRANSACTION_ID_LOGGING=true

6. Install the Plextrac application

        plextrac install

7. You can tail logs:

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

## Testing UMF / DVU locally

**UMF** (*Unified Migration Framework*) is the app’s unified migration runner. **DVU** (*Direct Version Upgrades*) is upgrading across version gaps in one go; UMF is what enables that once you’re on images that ship it.

You can test the `unified-migrations` Compose service without a full v3 API image in some cases. Use the **live source**: `/vagrant/src/plextrac <command>` (Vagrant) or `./src/plextrac <command>` from the repo root (local).

### How the script chooses unified vs legacy

- **Rule:** resolved version **≥ v3.0** and **`FORCE_LEGACY_MIGRATIONS` is not `true`**
  -> **`unified-migrations`** (UMF / `npm run db:migrate` chain — the path used for DVU on v3+).  
  **Otherwise** -> **`couchbase-migrations`** (full legacy chain).  
  There is no env flag to run UMF on **2.x**; those images are not expected to ship UMF.  
  Pinned **`UPGRADE_STRATEGY`** and image labels use plain semver (**`2.26.5`**, **`3.0`**) — no **`v`** prefix.

- **`USE_UMF`** is an internal boolean used by the script only (not an operator setting).

- If **`UPGRADE_STRATEGY`** is `stable` (or another non-numeric tag), the version **must** be read
  from **`org.opencontainers.image.version`** on the pulled `plextracapi` image. Missing or invalid
  label -> **abort** (no silent fallback).

### 0. Inspect the decision without running migrations

From `/opt/plextrac` (or your `PLEXTRAC_HOME`) as the `plextrac` user, with `.env` loaded:

      plextrac migration-plan

This prints resolved version, whether it came from `.env` vs image label, and which compose service
would run (`unified-migrations` vs `couchbase-migrations`).

### 1. Legacy path (2.x)

Resolved **2.x** -> **`couchbase-migrations`** always.

- From Vagrant (as `plextrac` user, with `.env` in place):

      cd /opt/plextrac
      /vagrant/src/plextrac update -y

- You should see the **`couchbase-migrations`** container run.

### 2. Unified path (3.0+)

Resolved **3.0+** and **`FORCE_LEGACY_MIGRATIONS` unset/false** -> **`unified-migrations`**
(`maintenance:enable` -> `db:migrate` -> `maintenance:disable` -> `seed:prebuilt-content --if-present`).

- You should see "Using Unified Migration Framework (resolved …)" and
  `compose --profile database-migrations up unified-migrations`.

- The API image must define **`npm run db:migrate`**. If it is missing, the container exits with an error.

### 3. Break-glass: legacy on 3.x

      FORCE_LEGACY_MIGRATIONS=true /vagrant/src/plextrac update -y

Forces **`couchbase-migrations`** even when the resolved version is **3.x**.

### 4. Run only the migration service (no full update)

To test just the compose definition and the migration command (no install/update flow):

- From the directory that has your compose file and `.env` (e.g. `/opt/plextrac` or
  wherever `PLEXTRAC_HOME` points):

      docker compose --profile database-migrations run --rm unified-migrations

- This runs the `unified-migrations` service once. It will fail if the image does not have
  `npm run db:migrate` (and the other scripts in the chain).

- To run the legacy migration container for comparison:

      docker compose --profile database-migrations up couchbase-migrations

### 5. Trace which path runs (debug)

      bash -x /vagrant/src/plextrac update -y 2>&1 | tee update.log

- Search for `unified-migrations`, `couchbase-migrations`, `FORCE_LEGACY`, `_migration_resolve`.

