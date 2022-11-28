FROM gitpod/workspace-full

RUN curl -O https://releases.hashicorp.com/vagrant/2.2.6/vagrant_2.2.6_x86_64.deb \
    && sudo apt install ./*.deb \
    && vagrant plugin install docker
