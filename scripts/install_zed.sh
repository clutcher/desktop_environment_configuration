#!/bin/bash

# Zed publishes no apt repository, the official installer unpacks the latest release into ~/.local/zed.app
# and writes a desktop entry with absolute paths, so no symlink or icon fixup is needed
curl -fsSL https://zed.dev/install.sh | sh
