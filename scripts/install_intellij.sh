#!/bin/bash

sudo cp configs/sysctl/60-jetbrains.conf /etc/sysctl.d/60-jetbrains.conf
sudo sysctl --system

# Direct download gives the latest release, while toolbox cli requires an exact build number
# Previous release is removed first, as its leftover jars and plugins break the new one
sudo rm -rf /opt/idea
sudo mkdir -p /opt/idea
sudo curl -L "https://download.jetbrains.com/product?code=IIU&latest&distribution=linux" | sudo tar xz -C /opt/idea --strip 1
sudo chown -R "$(id -u):$(id -g)" /opt/idea
sudo ln -sf /opt/idea/bin/idea.sh /usr/local/bin/idea

# Toolbox manages the rest of jetbrains ides and picks up directly installed ones from desktop entries
toolbox_url=$(curl --silent 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release' | jq --raw-output '.TBA[0].downloads.linux.link')
mkdir -p ~/.local/share/JetBrains/Toolbox
curl -L --progress-bar "$toolbox_url" | tar xz -C ~/.local/share/JetBrains/Toolbox --strip 1
