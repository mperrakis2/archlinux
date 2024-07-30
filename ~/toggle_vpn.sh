#!/usr/bin/bash

# toggle proton vpn user service (stop/start)

is_on="$(sudo wg)"

msg="proton vpn user service was"
declare -i err

echo -n "$msg "
if (( ${#is_on} )); then
    systemctl --user stop protonvpn.service
    ((err=$?))
    if (( err )); then
        echo not stopped
    else
        echo stopped
    fi
else
    systemctl --user start protonvpn.service
    ((err=$?))
    if (( err )); then
        echo not started
    else
        echo started
    fi
fi

exit $err
