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

### Package Requirements:

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
| podman | >=v4.6 (RHEL 9 only) |

## Podman support

We've expanded the capabilities to support podman in specific circumstances.

*OS:* RHEL 9+
*Podman Compose:* No (currently)

> Note: the module for podman was written with RHEL 9 specifically in mind. It is not officially supported at this time to use the container runtime set to Podman on Debian, Ubuntu, or CentOS.

---

### Podman Troubleshooting

Depending on your configuration, you may need to solve the following issues:

#### *I'm unable to bind to port 443 with unprivileged user*

- Add value to /etc/sysctl.conf and reload daemon
    > `net.ipv4.ip_unprivileged_port_start=443`
    > `sysctl --system`

#### *I'm unable to use Let's Encrypt for SSL Certificate*

- Adjust the `/etc/sysctl.conf` value to start at `80` instead of `443`
    > `net.ipv4.ip_unprivileged_port_start=80`
    > `sysctl --system`

#### *I'm using a SSH solution that doesn't directly create a user.slice with a login*

- Enable service persistance after logout
    > `loginctl enable-linger plextrac`

#### *I can't execute out of `/tmp` folder*

- Download PlexTrac Manager Utility with wget using this command:
    > `wget -O ~/plextrac -q https://github.com/PlexTrac/plextrac-manager-util/releases/latest/download/plextrac && sudo chmod a+x ~/plextrac && sudo bash ~/plextrac initialize -v -c podman`

#### My containers don't start after rebooting the host VM

- For setting up container persistence: https://www.redhat.com/sysadmin/container-systemd-persist-reboot
- The recommended method to start the PlexTrac containers is `plextrac start` after a reboot of the host OS


#### RHEL 8 Support

The following will need to be done before running any PlexTrac specific commands:

- Edit `/etc/default/grub` and enable `cgroup v2`

    ```bash
    vim /etc/default/grub

    # Add the following line and then save
    systemd.unified_cgroup_hierarchy=1

    # From CLI, run:
    grub-mkconfig -o /boot/grub/grub.cfg
    yum install netavark
    # If not already enabled, run
    yum module enable container-tools

    # Enabling netavark over CNI
    # As Root:
    cp /usr/share/containers/containers.conf /etc/containers/
    vim /etc/containers/containers.conf
    ...
    [network]
    network_backend="netavark"
    ...
    podman system reset -f

    # Finish setting up cgroups v2
    sudo mkdir -p /etc/systemd/system/user@.service.d
    cat <<EOF | sudo tee /etc/systemd/system/user@.service.d/delegate.conf
    [Service]
    Delegate=cpu cpuset io memory pids
    EOF
    sudo systemctl daemon-reload

    reboot
    ```

### Sources

---
`cgroup2` configuration: <https://rootlesscontaine.rs/getting-started/common/cgroup2/>

---
`netavark` configuration: <https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/building_running_and_managing_containers/assembly_setting-container-network-modes_building-running-and-managing-containers#proc_switching-the-network-stack-from-cni-to-netavark_assembly_setting-container-network-modes>

---
Service Persistance: <https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/building_running_and_managing_containers/assembly_porting-containers-to-systemd-using-podman_building-running-and-managing-containers>
