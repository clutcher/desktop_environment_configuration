#!/bin/bash

# Chrome's package registers its own apt repository and rewrites it on every update, so it is not written here
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/google-chrome.deb
sudo apt install -y /tmp/google-chrome.deb
