Vagrant.configure("2") do |config|
    config.vm.provider "docker" do |d|
        d.build_dir = "."
        d.name = "ubuntu2004"
        d.has_ssh = true
        d.create_args = [ "--privileged" ]
    end
  config.vm.synced_folder ".", "/vagrant"

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
