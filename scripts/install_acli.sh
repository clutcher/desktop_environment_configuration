#!/bin/bash

# Atlassian CLI, used to work with Jira and Bitbucket
curl -fsSL https://acli.atlassian.com/gpg/public-key.asc | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/acli-archive-keyring.gpg
sudo tee /etc/apt/sources.list.d/acli.sources > /dev/null <<EOT
Types: deb
URIs: https://acli.atlassian.com/linux/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/acli-archive-keyring.gpg
EOT

sudo apt update
sudo apt install -y acli
