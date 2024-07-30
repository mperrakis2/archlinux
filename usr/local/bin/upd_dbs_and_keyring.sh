#!/usr/bin/bash

# this script is called whenever pacman or yay are run; it's part of aliases in
# /usr/local/bin/.bashrc

if pacman -Fy; then # update package DBs
    if pacman -Qu archlinux-keyring; then # check update for keyring
        pacman --noconfirm -S archlinux-keyring # update keyring
    else
        exit 0
    fi
else
    exit $?
fi
