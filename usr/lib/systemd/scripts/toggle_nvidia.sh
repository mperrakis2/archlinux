#!/bin/bash

services="nvidia-hibernate.service nvidia-suspend.service "\
"nvidia-resume.service nvidia-suspend-then-hibernate.service "\
"nvidia-persistenced.service"

# disable nvidia systemd services if no nvidia kernel module loaded
if ! lsmod | grep -wq nvidia; then
    systemctl stop $services
    systemctl disable $services
else
    for service in $services; do
        if ! systemctl is-enabled "$service"; then
            systemctl enable "$service"
        fi
    done
fi

# update cfg file for intel gfx driver so Xorg doesn't freeze

readonly INTEL_CONF_FILE=/etc/X11/xorg.conf.d/20-intel.conf

if [[ -f "$INTEL_CONF_FILE" ]]; then
    declare -a GPUs=()

    mapfile -t GPUs < <(lspci | grep -iE 'vga|3d|2d')

    # set intel driver to "intel" if only one GPU
    if [[ ${#GPUs[@]} -eq 1 && "${GPUs[0]}" =~ [Ii][Nn][Tt][Ee][Ll] ]]
    then
        sed -i -e 's|Driver[[:space:]]\+"modesetting"|Driver "intel"|g' "$INTEL_CONF_FILE"
    else
        sed -i -e 's|Driver[[:space:]]\+"intel"|Driver "modesetting"|g' "$INTEL_CONF_FILE"
    fi
fi
