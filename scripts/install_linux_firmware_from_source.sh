#!/bin/bash

FIRMWARE_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/
latest_version=$(git ls-remote --tags $FIRMWARE_REPO | sort -t '/' -k 3 -V | awk -F/ '{ print $3 }' | awk '!/\^\{\}/' | tail -n 1)

echo "Latest version of firmware: ${latest_version}"

rm -rf /tmp/firmware/
mkdir -p /tmp/firmware
git clone --branch $latest_version --depth 1 $FIRMWARE_REPO /tmp/firmware

sudo cp -rf /tmp/firmware/* /lib/firmware


sudo update-initramfs -c -k all