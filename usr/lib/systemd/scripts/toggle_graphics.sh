#!/bin/bash

# enable/disable nvidia services & update intel graphics driver conf file

services="nvidia-hibernate.service nvidia-suspend.service "\
"nvidia-resume.service nvidia-suspend-then-hibernate.service "\
"nvidia-persistenced.service"

# disable nvidia services if no nvidia kernel module loaded
if ! lsmod | grep -wq nvidia; then
    systemctl stop $services
    systemctl disable $services
else
    # enable nvidia services if nvidia kernel module loaded
    for service in $services; do
        if ! systemctl is-enabled "$service"; then
            systemctl enable "$service"
        fi
    done
fi

# below, setup intel graphics driver conf file for xorg

# file that contains graphics card generation number
readonly REV=/sys/class/graphics/fb0/device/revision
if find "$REV"; then
    declare -i gen=0

    (( gen=$(cat "$REV") ))

    drv=/sys/class/graphics/fb0/name # graphics card driver name
    if find "$drv"; then
        drv=$(cat "$drv")

        if [[ "$drv" =~ ^(i915|xe) ]]; then # if intel driver
            readonly INTEL_CONF=/etc/X11/xorg.conf.d/20-intel.conf
            
            if (( gen < 4 )); then # use old driver
                sed -i -e 's|Driver[[:space:]]\+"modesetting"|Driver "intel"|g' \
                           "$INTEL_CONF"
            else # use new driver
                sed -i -e 's|Driver[[:space:]]\+"intel"|Driver "modesetting"|g' \
                           "$INTEL_CONF"
            fi
        fi
    fi
fi 
