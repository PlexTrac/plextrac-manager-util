# -*- mode: ruby -*-
# vi: set ft=ruby :

supportedBoxes = [
  {
    :name     => "amzn",
    :box      => "bento/amazonlinux-2",
    :default  => false,
  },
  {
    :name     => "centos7",
    :box      => "bento/centos-7",
    :default  => false,
  },
  {
    :name     => "centos8",
    :box      => "bento/centos-8",
    :default  => false,
  },
  {
    :name     => "rockylinux",
    :box      => "bento/rockylinux-8",
    :default  => false,
  },
  {
    :name     => "ubuntu",
    :box      => "bento/ubuntu-20.04",
    :default  => true,
  },
]

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure("2") do |config|
  if Vagrant.has_plugin?("vagrant-hostmanager")
    # Manage hosts file entries
    # Do `vagrant plugin install vagrant-hostmanager` if you want this
    config.hostmanager.enabled = true
    config.hostmanager.manage_host = true
    config.hostmanager.ignore_private_ip = false
    config.hostmanager.ip_resolver = proc do |vm, resolving_vm|
      if hostname = (vm.ssh_info && vm.ssh_info[:host])
        `vagrant ssh -c "hostname -I"`.split()[1]
      end
    end
  end
  # The most common configuration options are documented and commented below.
  # For a complete reference, please see the online documentation at
  # https://docs.vagrantup.com.

  # Every Vagrant development environment requires a box. You can search for
  # boxes at https://vagrantcloud.com/search.
  supportedBoxes.each do |boxConfig|
    hostname = "test-instance-#{boxConfig[:name]}.plextrac.local"
    isDefault = boxConfig[:default] ? true : false 
    config.vm.define hostname, primary: isDefault, autostart: isDefault do |host|
      host.vm.box = boxConfig[:box]
      host.vm.box_check_update = true # disable this to skip box updates, but remember to run `vagrant box outdated`
    end
  end

  # Create a forwarded port mapping which allows access to a specific port
  # within the machine from a port on the host machine. In the example below,
  # accessing "localhost:8080" will access port 80 on the guest machine.
  # NOTE: This will enable public access to the opened port
  # config.vm.network "forwarded_port", guest: 80, host: 8080

  # Create a forwarded port mapping which allows access to a specific port
  # within the machine from a port on the host machine and only allow access
  # via 127.0.0.1 to disable public access
  # config.vm.network "forwarded_port", guest: 80, host: 8080, host_ip: "127.0.0.1"

  # Create a private network, which allows host-only access to the machine
  # using a specific IP.
  config.vm.network "private_network", type: "dhcp"

  # Create a public network, which generally matched to bridged network.
  # Bridged networks make the machine appear as another physical device on
  # your network.
  # config.vm.network "public_network"

  # Share an additional folder to the guest VM. The first argument is
  # the path on the host to the actual folder. The second argument is
  # the path on the guest to mount the folder. And the optional third
  # argument is a set of non-required options.
  config.vm.synced_folder ".", "/vagrant"

  # Provider-specific configuration so you can fine-tune various
  # backing providers for Vagrant. These expose provider-specific options.
  # Example for VirtualBox:
  #
  config.vm.provider "virtualbox" do |vb|
    # Customize the amount of memory on the VM:
    vb.memory = "8192"
    vb.cpus = 4
    vb.customize ["modifyvm", :id, "--cpuexecutioncap", "50"]
  end
  #
  # View the documentation for the provider you are using for more
  # information on available options.

  # Enable provisioning with a shell script. Additional provisioners such as
  # Ansible, Chef, Docker, Puppet and Salt are also available. Please see the
  # documentation for more information about their specific syntax and use.
  # U291bmR0cmFjayBmb3IgdGVzdGluZzogaHR0cHM6Ly93d3cueW91dHViZS5jb20vd2F0Y2g/dj1FbDkwT0JJTEZCdwo=

  config.vm.provision "shell", inline: <<-SHELL
  echo "Generating plextrac CLI dist"
  /vagrant/src/plextrac dist > plextrac && chmod +x plextrac

  echo ""
  echo "# Example customized deployment directory and domain name:"
  echo "#   PLEXTRAC_HOME=/var/apps/plextrac-demo CLIENT_DOMAIN_NAME=192.168.56.37 ./plextrac initialize"
  echo ""

  echo "Initializing PlexTrac at default location..."
  echo ""
  ./plextrac initialize -v 2>&1

  echo "You need to provide a valid DOCKER_HUB_KEY to configure PlexTrac"
  echo "On Linux, this can be retrieved using the following command:"
  echo ""
  echo -n 'RE9DS0VSX0hVQl9LRVk9JChqcSAnLmF1dGhzLiJodHRwczovL2luZGV4LmRvY2tlci5pby92MS8iLmF1dGgnIH4vLmRvY2tlci9jb25maWcuanNvbiAtciB8IGJhc2U2NCAtZCB8IGN1dCAtZCc6JyAtZjIpOwo=' | base64 -d
  echo ""
  echo "On MacOS, this can be retrieved using the following command (enter login passphrase in the prompt(s):"
  echo ""
  echo -n 'RE9DS0VSX0hVQl9LRVk9JChzZWN1cml0eSBmaW5kLWludGVybmV0LXBhc3N3b3JkIC1hIHBsZXh0cmFjdXNlcnMgLXMgaW5kZXguZG9ja2VyLmlvIC13KTsK' | base64 -d
  echo ""
  echo "If on Windows, please figure out where that is stored and issue a PR to add support here :)"
  echo ""
  echo "One-liner configuration for Linux users:"
  echo ""
  echo -n 'RE9DS0VSX0hVQl9LRVk9JChqcSAnLmF1dGhzLiJodHRwczovL2luZGV4LmRvY2tlci5pby92MS8iLmF1dGgnIH4vLmRvY2tlci9jb25maWcuanNvbiAtciB8IGJhc2U2NCAtZCB8IGN1dCAtZCc6JyAtZjIpOyB2YWdyYW50IHNzaCAtYyAic3VkbyAtaSAtdSBwbGV4dHJhYyBET0NLRVJfSFVCX0tFWT0ke0RPQ0tFUl9IVUJfS0VZfSBwbGV4dHJhYyBjb25maWd1cmU7IHN1ZG8gLWkgLXUgcGxleHRyYWMgcGxleHRyYWMgdXBkYXRlOyBzdWRvIC1pIC11IHBsZXh0cmFjIHBsZXh0cmFjIHN0YXJ0OyBzdWRvIC1pIC11IHBsZXh0cmFjIGRvY2tlciBsb2dzIC1mIHBsZXh0cmFjYXBpIgo=' | base64 -d
  SHELL
end
