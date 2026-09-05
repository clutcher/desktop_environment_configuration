#!/bin/bash

# Plasma sources this on session start, so agent is available to every application

export SSH_ASKPASS=/usr/bin/ksshaskpass
export SSH_ASKPASS_REQUIRE=prefer

if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -s)" > /dev/null
fi

for key in "$HOME"/.ssh/id_rsa "$HOME"/.ssh/bitbucket_*; do
    [[ "$key" == *.pub ]] && continue
    [[ -f "$key" ]] && ssh-add "$key" 2>/dev/null
done
