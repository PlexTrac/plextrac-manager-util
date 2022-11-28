FROM gitpod/workspace-full

RUN curl -O https://releases.hashicorp.com/vagrant/2.3.3/vagrant_2.3.3-1_amd64.deb \
    && sudo apt install ./*.deb \
    && vagrant plugin install docker
