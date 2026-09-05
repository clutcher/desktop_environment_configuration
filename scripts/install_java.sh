#!/bin/bash

curl -s "https://get.sdkman.io" | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"

# SapMachine is required for SAP Commerce (Hybris) projects
sdk install java 17.0.20-sapmchn
# JetBrains Runtime is used by Intellij IDEA based IDEs
sdk install java 25.0.3-jbr

sdk install java 26.0.2-amzn
sdk default java 26.0.2-amzn
