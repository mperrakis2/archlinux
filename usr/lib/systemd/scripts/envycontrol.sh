#!/bin/bash

# enable/disable envycontrol (nvidia hybrid graphics) depending on
# nvidia kernel module being loaded or not

if paru -Qsq envycontrol &> /dev/null; then # nvidia hybrid package installed
    if ! lsmod | grep -iwq nvidia; then     # PC with no nvidia card

        # uninstall nvidia package and stop/disable its service
        pamac remove --no-confirm envycontrol
    fi
elif lsmod | grep -iwq nvidia; then # PC with nvidia card
    # get display manager
    dm=$(systemctl --property=Id show display-manager.service)
    dm="${dm//*=}" # remove all up to and including '='
    dm="${dm//.*}" # remove all from '.' and after

    # install nvidia hybrid package and set it up
    pamac install --no-confirm envycontrol &&
    envycontrol -s hybrid --dm "$dm" --rtd3 0 &&
    envycontrol --cache-create
fi
