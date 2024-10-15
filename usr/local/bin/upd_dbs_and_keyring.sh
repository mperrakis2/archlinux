#!/usr/bin/bash
 
# this script is called whenever pacman or paru are run; it's in aliases in
# /etc/skel/.bashrc
 
declare -i err=0

pacman_alias=""
alias pacman &> /dev/null
if (( $? == 0 )); then # save pacman alias if any
    pacman_alias="${BASH_ALIASES[pacman]}"
    unalias pacman # delete pacman alias
fi

if pacman -Qu archlinux-keyring; then       # check update for keyring
    pacman --noconfirm -S archlinux-keyring # update keyring
    let err=$?
    if (( ! err )); then
        pacman -Fy                          # update package lists
        let err=$?
    fi
fi

[[ "$pacman_alias" ]] && # restore pacman alias if any
    alias pacman="$pacman_alias"

exit $err
