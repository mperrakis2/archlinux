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

pm="pamac" # package manager (pm)
pkg="envycontrol"

# nvidia hybrid package installed
if [[ $($pm search --installed --quiet "$pkg") ]]; then
    if ! lsmod | grep -iwq nvidia; then # no nvidia card

        # uninstall nvidia package and stop/disable its service
        $pm remove --no-confirm "$pkg"
    fi
elif lsmod | grep -iwq nvidia; then # PC with nvidia card
    script="$pkg"

    # get display manager
    dm=$(systemctl --property=Id show display-manager.service)
    dm="${dm//*=}" # remove all up to and including '='
    dm="${dm//.*}" # remove all from '.' and after

    # install nvidia hybrid package and set it up
    $pm install --no-confirm "$pkg" &&
    $script -s hybrid --dm "$dm" --rtd3 0 &&
    $script --cache-create
fi
