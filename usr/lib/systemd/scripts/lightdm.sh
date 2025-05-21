#!/bin/bash

# lightdm wrapper: update cfg file for intel gfx driver so Xorg doesn't freeze
# and then launch lightdm

readonly INTEL_CONF_FILE=/etc/X11/xorg.conf.d/20-intel.conf

# set intel driver to "intel" if only one GPU
if [[ -f "$INTEL_CONF_FILE" ]]; then
    declare -a GPUs=()

    mapfile -t GPUs < <(lspci | grep -iE 'vga|3d|2d')

    if [[ ${#GPUs[@]} -eq 1 && "${GPUs[0]}" =~ [Ii][Nn][Tt][Ee][Ll] ]]
    then
        sed -i -e 's|Driver[[:space:]]\+"modesetting"|Driver "intel"|g' "$INTEL_CONF_FILE"
    else
        sed -i -e 's|Driver[[:space:]]\+"intel"|Driver "modesetting"|g' "$INTEL_CONF_FILE"
    fi
fi

$(which lightdm) # run lightdm
