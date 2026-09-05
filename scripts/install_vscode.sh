#!/bin/bash

# Microsoft publishes no sid suite, so the repository follows the current debian stable
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /etc/apt/keyrings/microsoft-prod.gpg
sudo tee /etc/apt/sources.list.d/microsoft-prod.sources > /dev/null <<EOT
Types: deb
URIs: https://packages.microsoft.com/debian/13/prod/
Suites: trixie
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/microsoft-prod.gpg
EOT

sudo apt update
sudo apt install -y code

# @ToDo: add plugins installation
