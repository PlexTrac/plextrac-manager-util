## Additional Package Requirements

podman | >=v4.6 (RHEL 8/9 only)

## Podman support

We've expanded the capabilities to support podman in specific circumstances.

*OS:* RHEL 8/9+
*Podman Compose:* No (currently)

> Note: the module for podman was written with RHEL 9 specifically in mind. It is not officially supported at this time to use the container runtime set to Podman on Debian, Ubuntu, or CentOS.

> Note: All testing has been done on BASE images without hardening with a security profile or SELinux or anything -- its just a stock operating system

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

- You'll need to run `systemctl daemon-reload` after every reboot [source](https://bugzilla.redhat.com/show_bug.cgi?id=1897579)
- For setting up container persistence: https://www.redhat.com/sysadmin/container-systemd-persist-reboot
- The recommended method to start the PlexTrac containers is `plextrac start` after a reboot of the host OS

#### RHEL 8 Support

The following will need to be done before running any PlexTrac specific commands:

- Edit `/etc/default/grub` and enable `cgroup v2`

    ```bash
    vim /etc/default/grub

    # Add the following line to the `GRUB_CMDLINE_LINUX` key and then save
    systemd.unified_cgroup_hierarchy=1

    # From CLI, run:
    grub2-mkconfig -o /boot/grub2/grub.cfg
    yum install netavark
    # If not already enabled, run
    yum module enable container-tools

    # Install Podman
    yum install -y podman podman-plugins

    # Add value to /etc/sysctl.conf and reload daemon
    net.ipv4.ip_unprivileged_port_start=443
    sysctl --system
    
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

    reboot
    sudo systemctl daemon-reload
    ```

### Sources

---
`cgroup2` configuration: <https://rootlesscontaine.rs/getting-started/common/cgroup2/>

---
`netavark` configuration: <https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/building_running_and_managing_containers/assembly_setting-container-network-modes_building-running-and-managing-containers#proc_switching-the-network-stack-from-cni-to-netavark_assembly_setting-container-network-modes>

---
Service Persistance: <https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/building_running_and_managing_containers/assembly_porting-containers-to-systemd-using-podman_building-running-and-managing-containers>
