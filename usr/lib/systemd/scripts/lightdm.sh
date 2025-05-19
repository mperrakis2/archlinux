#!/bin/bash

# update cfg file for intel gfx driver so Xorg doesn't freeze and then launch lightdm

readonly INTEL_CONF_FILE=/etc/X11/xorg.conf.d/20-intel.conf

declare -i numGPU=0

numGPU=$(lspci | grep -iE 'vga|3d|2d' | wc -l)

# if AMD and no intel graphics card, set intel driver to "modesetting"
if lsmod | grep -E amdgpu && ! lsmod | grep -E i915; then
    [[ -f "$INTEL_CONF_FILE" ]] &&
        sed -i -e 's|Driver "intel"|Driver "modesetting"|g' "$INTEL_CONF_FILE"

# set intel driver to "intel"
elif [[ -f "$INTEL_CONF_FILE" && "$numGPU" && "$numGPU" -eq 1 ]]; then
    sed -i -e 's|Driver "modesetting"|Driver "intel"|g' "$INTEL_CONF_FILE"
fi

$(which lightdm) # run lightdm
