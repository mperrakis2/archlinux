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
