#!/usr/bin/env bash

set -e # exit immediately if a simple command exits with a non-zero status
set -u # report the usage of uninitialized variables

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root" 1>&2
  exit 1
fi

login=vcap
password=vcap

if [[ ! -d /home/${login} ]]
then
  /usr/sbin/addgroup --system admin
  /usr/sbin/adduser --disabled-password --gecos Ubuntu ${login}
  echo "${login}:${password}" | /usr/sbin/chpasswd
  echo "${login}    ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

  for grp in admin adm audio cdrom dialout floppy video plugdev dip
  do
    /usr/sbin/adduser ${login} ${grp}
  done
fi
