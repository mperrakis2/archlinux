#!/bin/bash

# update cfg file for intel gfx driver so Xorg doesn't freeze and then launch lightdm

readonly INTEL_CONF_FILE=/etc/X11/xorg.conf.d/20-intel.conf

declare -i numGPU=0

numGPU=$(lspci | grep -iE 'vga|3d|2d' | wc -l)

# set intel driver to "intel" if only one GPU
if [[ -f "$INTEL_CONF_FILE" && "$numGPU" && "$numGPU" -eq 1 ]]; then
    sed -i -e 's|Driver "modesetting"|Driver "intel"|g' "$INTEL_CONF_FILE"
fi

$(which lightdm) # run lightdm
