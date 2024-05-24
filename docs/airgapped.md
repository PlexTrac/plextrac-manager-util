# Air-Gapped in RHEL8

## VM Prep

1. Install Needful Packages
	- bc, jq, unzip, yum-utils, docker-ce, docker-ce-cli, containerd.io, docker-compose-plugin
	- Enable Docker: `systemctl enable docker`
	- Restart Docker: `/bin/systemctl restart docker.service`
2. Download Manager Util
	- `wget -O ~/plextrac -q https://github.com/PlexTrac/plextrac-manager-util/releases/latest/download/plextrac`
	- Set execution and permissions: `chmod a+x plextrac`

## Docker Image Prep

1. Download Docker Images

```shell
docker pull plextrac/plextracapi:<NEXT_VERSION>
docker pull plextrac/plextracnginx:<NEXT_VERSION>
# The plextracdb shouldn't ever get updated so this will be a one time pull and can be omited from process / automation
docker pull plextrac/plextracdb:7.2.0
docker pull redis:6.2-alpine
docker pull postgres:14-alpine
# Save the images into a TAR(s)
docker save -o plextrac_images.tar plextrac/plextracapi:<NEXT_VERSION> plextrac/plextracnginx:<NEXT_VERSION> plextrac/plextracdb:7.2.0 redis:6.2-alpine postgres:14-alpine
```

> Note you'll want to specify the image's platform if there are differences between where you're pulling the image (e.g., linux/arm64) and the VM (linux/x86_64)

2. Next ensure the created image bundle(s) are transferred to the AIR GAPPED environment and loaded:

```shell
docker load < plextrac_images.tar
```

## PlexTrac Initialization and Install

1. Run initialize command: `plextrac initialize -v --air-gapped`

    - This creates a user and group named `plextrac` with the homedir of `/opt/plextrac` and adds them to the `docker` user group
    - It copies the `plextrac` utility to `/opt/plextrac/.local/bin/plextrac` and adds it to the `plextrac` user path

2. Switch to `plextrac` user: `su - plextrac`
3. Run: `plextrac configure -v --air-gapped`
4. Edit the `.env` file and add `AIRGAPPED=true` to the end

    - Also edit the `UPGRADE_STRATEGY=` and make it equal to the latest version of the PlexTrac application (e.g., `UPGRADE_STRATEGY=2.5`)

5. Rerun `plextrac configure -v --air-gapped`
6. Install PlexTrac: `plextrac install -v -y`

## PlexTrac Updates

You'll need to pull the new docker images and load them into the environment. Then you'll need to set the `UPGRADE_STRATEGY` value in the `.env` file to the new version. Then just run `plextrac update -v -y`

> NOTE: PlexTrac REQUIRES contiguous updates, so don't skip a version for any reason unless you're installing the FIRST time.
