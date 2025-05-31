#!/bin/bash

# enable/disable envycontrol (nvidia hybrid graphics) depending on
# nvidia kernel module being loaded or not

# check if user has sudo access
if getent passwd | cut -d ':' -f 1 | xargs -n 1 sudo -l -U &> /dev/null; then
    pm="sudo pamac" # sudo access to package manager (pm)
    pkg="envycontrol"

    # nvidia hybrid package installed
    if [[ $($pm search --installed --quiet "$pkg") ]]; then
        if ! lsmod | grep -iwq nvidia; then # no nvidia card

            # uninstall nvidia package and stop/disable its service
            $pm remove --no-confirm "$pkg"
        fi
    elif lsmod | grep -iwq nvidia; then # PC with nvidia card
        script="sudo $pkg" # sudo access to script

        # get display manager
        dm=$(systemctl --property=Id show display-manager.service)
        dm="${dm//*=}" # remove all up to and including '='
        dm="${dm//.*}" # remove all from '.' and after

        # install nvidia hybrid package and set it up
        $pm install --no-confirm "$pkg" &&
        $script -s hybrid --dm "$dm" --rtd3 0 &&
        $script --cache-create
    fi
fi
