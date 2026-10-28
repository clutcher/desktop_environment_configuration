#!/bin/bash

sudo apt remove -y docker docker-engine docker.io containerd runc

# Docker publishes no sid suite, so the repository follows the current debian stable
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOT
Types: deb
URIs: https://download.docker.com/linux/debian/
Suites: trixie
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.gpg
EOT

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Add permission for current user
sudo usermod -aG docker $USER
sudo chmod 666 /var/run/docker.sock

# Disable docker service on startup. Would be enabled manually only when needed.
sudo systemctl disable docker.service
sudo systemctl disable containerd.service
