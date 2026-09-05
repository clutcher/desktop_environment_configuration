#!/bin/bash

# Install packages for backlight control
sudo apt install -y acpid acpi-support brightnessctl

systemctl enable acpid