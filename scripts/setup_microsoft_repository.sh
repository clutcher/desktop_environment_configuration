#!/bin/bash

# Debian 13 suite is signed by the 2025 key, the older microsoft.asc fails verification
curl -fsSL https://packages.microsoft.com/keys/microsoft-2025.asc | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/microsoft-prod.gpg
# Microsoft publishes no sid suite, so the repository follows the current debian stable
sudo tee /etc/apt/sources.list.d/microsoft-prod.sources > /dev/null <<EOT
Types: deb
URIs: https://packages.microsoft.com/debian/13/prod/
Suites: trixie
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/microsoft-prod.gpg
EOT

sudo apt update
