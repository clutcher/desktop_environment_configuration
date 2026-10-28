#!/bin/bash

wget -q "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xaeeb94e9c5a3b54ecfa4a66aa684470caccaf35c" -O- | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/insynchq.gpg
sudo tee /etc/apt/sources.list.d/insync.sources > /dev/null <<EOT
Types: deb
URIs: http://apt.insync.io/debian/
Suites: sid
Components: non-free contrib
Architectures: amd64
Signed-By: /etc/apt/keyrings/insynchq.gpg
EOT

sudo apt update
sudo apt install -y insync
