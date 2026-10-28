#!/bin/bash

sudo apt update

# Minimal install and hardware configuration
source scripts/setup_debian_repository.sh
source scripts/setup_hardware_and_cli.sh

# Below installs the most recent kernel and firmware
# This is a must have for recently release hardware (for example, laptop released less than year ago)
#source scripts/install_linux_firmware_from_source.sh
#source scripts/install_liquorix_kernel.sh

source scripts/configure_backlight.sh

source scripts/configure_global_settings.sh

# Desktop environment setup and configuration
source scripts/setup_plasma_de.sh
source scripts/setup_kwin_tiling.sh
source scripts/configure_plasma_shortcuts.sh
source scripts/configure_plasma_session.sh

source scripts/install_chrome.sh
source scripts/install_claude_desktop.sh

source scripts/setup_dotfiles.sh

# Dev tools
source scripts/install_java.sh
source scripts/install_nodejs.sh

source scripts/install_intellij.sh
source scripts/setup_microsoft_repository.sh
source scripts/install_vscode.sh
source scripts/install_dotnet.sh
source scripts/install_zed.sh

source scripts/install_docker.sh

source scripts/install_acli.sh

# Knowledge base
source scripts/install_obsidian.sh
source scripts/install_insync.sh
