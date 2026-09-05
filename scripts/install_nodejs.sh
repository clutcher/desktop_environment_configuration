#!/bin/bash

# Install latest nvm
VER=$(curl --silent -qI https://github.com/nvm-sh/nvm/releases/latest | awk -F '/' '/^location/ {print  substr($NF, 1, length($NF)-1)}'); \
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/$VER/install.sh | bash

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install node
