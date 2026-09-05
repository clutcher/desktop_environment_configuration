#!/bin/bash

# Switch on debian sid repository
sudo tee /etc/apt/sources.list.d/debian.sources > /dev/null <<EOT
Types: deb
URIs: http://deb.debian.org/debian/
Suites: sid
Components: main non-free non-free-firmware contrib
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOT

# Deb822 format is used instead of legacy one, so old file should be dropped to avoid duplicated sources
sudo rm -f /etc/apt/sources.list

# Update system
sudo apt update
sudo apt upgrade -y
sudo apt dist-upgrade -y
sudo apt autoremove -y

# Prepare for gpg dearmor for custom repositories
sudo apt install -y apt-transport-https ca-certificates curl gnupg2

sudo mkdir -p /etc/apt/keyrings/
