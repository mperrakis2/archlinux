#!/usr/bin/bash
 
# this script is called whenever pacman, paru or pacaur are run; it's in aliases
# in /etc/bash.bashrc

declare -i err=0

if (( $(id -u) == 0 )); then
    pacman=$(which pacman)
    if "$pacman" -Qu archlinux-keyring; then       # check update for keyring
        "$pacman" --noconfirm -S archlinux-keyring # update keyring
        ((err=$?))
        if (( ! err )); then
            "$pacman" -Fy                          # update package lists
            ((err=$?))
        fi
    fi

    [[ $err -eq 0 && "$1" == pacman ]] && echo sudo
fi

exit $err
