#!/bin/bash

# System folders settings
mkdir -p ~/Downloads ~/projects ~/screenshots

xdg-user-dirs-update --set DOWNLOAD "$HOME/Downloads"
xdg-user-dirs-update --set DOCUMENTS "$HOME/projects"
xdg-user-dirs-update --set PICTURES "$HOME/screenshots"

# Desktop folder is not used, so it points at home and is never created
xdg-user-dirs-update --set DESKTOP "$HOME"

# Stop recreation of unused folders, like Desktop, Music or Videos, on every login
cat <<EOT > ~/.config/user-dirs.conf
enabled=False
EOT

# Generate new ssh keys
ssh-keygen -t rsa -C "iclutcher@gmail.com" -f ~/.ssh/id_rsa -q -N ""

# Git settings
git config --global user.name "Igor Zarvanskyi"
git config --global user.email "iclutcher@gmail.com"
git config --global init.defaultbranch main
git config --global core.autocrlf input
git config --global credential.credentialstore secretservice
git config --global gui.encoding utf-8
git config --global i18n.commit.encoding utf-8
git config --global i18n.logoutputencoding utf-8
