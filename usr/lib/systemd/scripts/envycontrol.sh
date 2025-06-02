#!/bin/bash

# Enable/disable envycontrol (nvidia hybrid graphics) depending on nvidia
# kernel module being loaded or not.

# make sure only one instance of the script can run at a time taken from the
# man page of flock
if [[ "${FLOCKER}" != "${BASH_SOURCE:-$0}" ]]; then
    exec env FLOCKER="${BASH_SOURCE:-$0}" flock -en "${BASH_SOURCE:-$0}" \
                                                    "${BASH_SOURCE:-$0}" "$@"
else
    true
fi

set -o pipefail

pkg="envycontrol"

# nvidia hybrid package installed
if paru -Qsq "$pkg" &> /dev/null; then
    if ! lsmod | grep -iwq nvidia; then # no nvidia card
        paru -Rns --noconfirm "$pkg" # uninstall nvidia hybrid package
    fi
elif lsmod | grep -iwq nvidia; then # PC with nvidia card
    script="$pkg"

    # get display manager
    dm=$(systemctl --property=Id show display-manager.service)
    dm="${dm//*=}" # remove all up to and including '='
    dm="${dm//.*}" # remove all from '.' and after

    # install nvidia hybrid package and set it up
    paru -S --noconfirm "$pkg" &&
    $script -s hybrid --dm "$dm" --rtd3 0 &&
    $script --cache-create
fi
