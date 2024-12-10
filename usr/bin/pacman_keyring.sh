#!/usr/bin/bash
 
# this script is called whenever pacman or paru are run; it's in aliases in
# /etc/skel/.bashrc

pacman=$(which pacman)
declare -i err=0

if "$pacman" -Qu archlinux-keyring; then       # check update for keyring
    "$pacman" --noconfirm -S archlinux-keyring # update keyring
    let err=$?
    if (( ! err )); then
        "$pacman" -Fy                          # update package lists
        let err=$?
    fi
fi

exit $err
