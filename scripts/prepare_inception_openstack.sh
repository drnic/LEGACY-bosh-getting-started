#!/usr/bin/env bash

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root" 1>&2
  exit 1
fi

if [[ -z $ORIGUSER ]]; then
  echo "SUGGESTION: set ORIGUSER to pass non-root username to copy authorized_keys and .bashrc to vcap user"
fi

groupadd vcap
useradd vcap -m -g vcap
mkdir -p /home/vcap/.ssh
chown -R vcap:vcap /home/vcap/.ssh

if [[ -f /home/vcap/.ssh/id_rsa ]]
then
  echo "public keys for vcap already exist, skipping..."
else
  su -c "ssh-keygen -f ~/.ssh/id_rsa -N ''" vcap
fi

bosh_app_dir=/var/vcap
mkdir -p ${bosh_app_dir}
mkdir -p ${bosh_app_dir}/bosh
export PATH=${bosh_app_dir}/bosh/bin:$PATH
mkdir -p ${bosh_app_dir}/deployments ${bosh_app_dir}/releases ${bosh_app_dir}/manifests
chown vcap:vcap ${bosh_app_dir}/deployments ${bosh_app_dir}/releases ${bosh_app_dir}/manifests
echo "export PATH=${bosh_app_dir}/bosh/bin:\$PATH" >> /root/.bashrc
echo "export PATH=${bosh_app_dir}/bosh/bin:\$PATH" >> /home/vcap/.bashrc

if [[ -n $ORIGUSER ]]
then
  cp /home/${ORIGUSER}/.ssh/authorized_keys ${bosh_app_dir}/
  cp /home/${ORIGUSER}/.ssh/authorized_keys /home/vcap/.ssh/authorized_keys
  cp /home/${ORIGUSER}/.bashrc /home/vcap/
  echo "export PATH=${bosh_app_dir}/bosh/bin:\$PATH" >> /home/${ORIGUSER}/.bashrc
else
  echo "Skipping copying authorized_keys to vcap user"
  echo "Skipping copying .bashrc to vcap user"
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install build-essential libsqlite3-dev curl rsync git-core \
libmysqlclient-dev libxml2-dev libxslt-dev libpq-dev genisoimage mkpasswd \
debootstrap python-vm-builder -y

echo "install: --no-ri --no-rdoc" > /etc/gemrc
echo "update: --no-ri --no-rdoc" >> /etc/gemrc
if [[ -x rvm ]]
then
  rvm get stable
else
  curl -L get.rvm.io | bash -s stable
  source /etc/profile.d/rvm.sh
fi
command rvm install 1.9.3 # oh god this takes a long time
rvm 1.9.3
rvm alias create default 1.9.3
gem install bundler --no-ri --no-rdoc
gem pristine rake
gem install bundler fog --no-ri --no-rdoc

mkdir -p ${bosh_app_dir}/bootstrap
cd ${bosh_app_dir}/bootstrap
git clone git://github.com/frodenas/bosh.git
cd ${bosh_app_dir}/bootstrap/bosh/cli/
bundle install --without=development test
bundle exec rake install

cd ${bosh_app_dir}/bootstrap/bosh/deployer/
bundle install --without=development test
bundle exec rake install

cd ${bosh_app_dir}/bootstrap/bosh/agent/
bundle install --without=development test

cd ${bosh_app_dir}/bootstrap/bosh/openstack_registry/
bundle install --without=development test
bundle exec rake install

cd ${bosh_app_dir}/releases
git clone git://github.com/frodenas/bosh-release.git
cd ${bosh_app_dir}/releases/bosh-release
git submodule update --init

echo "Sanity check..."
echo "$ bosh help micro"
bosh help micro
