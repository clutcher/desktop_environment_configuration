#!/bin/bash

# Package adds its own repository only when no other source has it, so this one stands in for it
curl -fsSL https://downloads.claude.ai/claude-desktop/key.asc | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/claude-desktop.gpg
sudo tee /etc/apt/sources.list.d/claude-desktop.sources > /dev/null <<EOT
Types: deb
URIs: https://downloads.claude.ai/claude-desktop/apt/stable/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/claude-desktop.gpg
EOT

sudo apt update
sudo apt install -y claude-desktop
