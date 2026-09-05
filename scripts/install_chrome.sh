#!/bin/bash

wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg
sudo tee /etc/apt/sources.list.d/google-chrome.sources > /dev/null <<EOT
Types: deb
URIs: https://dl.google.com/linux/chrome/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/google-chrome.gpg
EOT

sudo apt update
sudo apt install -y google-chrome-stable
