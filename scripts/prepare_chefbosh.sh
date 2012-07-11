#!/usr/bin/env bash

export REGION=${REGION:-'us-east-1'}

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root" 1>&2
  exit 1
fi

if [[ -z $ORIGUSER ]]; then
  echo "SUGGESTION: $ORIGUSER to pass non-root username to copy authorized_keys and .bashrc to vcap user"
fi


groupadd vcap
useradd vcap -m -g vcap
mkdir -p /home/vcap/.ssh
chown -R vcap:vcap /home/vcap/.ssh

mkdir -p ${bosh_app_dir}/deploy ${bosh_app_dir}/store ${bosh_app_dir}/deployments
chown vcap:vcap ${bosh_app_dir}/deploy ${bosh_app_dir}/store ${bosh_app_dir}/deployments

if [[ -f /home/vcap/.ssh/id_rsa ]]
then
  echo "public keys for vcap already exist, skipping..."
else
  su -c "ssh-keygen -f ~/.ssh/id_rsa -N ''" vcap
fi

if [[ -f /root/.ssh/id_rsa ]]
then
  echo "public keys for root already exist, skipping..."
else
  ssh-keygen -f ~/.ssh/id_rsa -N ''
fi

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
cat ~/.ssh/id_rsa.pub >> /home/vcap/.ssh/authorized_keys

echo "deb http://${REGION}.ec2.archive.ubuntu.com/ubuntu/ lucid multiverse" >> /etc/apt/sources.list

apt-get update
apt-get install git-core -y

bosh_app_dir=/var/vcap

mkdir -p ${bosh_app_dir}/bootstrap
cd ${bosh_app_dir}/bootstrap
git clone https://github.com/cloudfoundry/bosh.git
cd bosh/release/template/instance
./prepare_instance.sh

source ~/.profile
