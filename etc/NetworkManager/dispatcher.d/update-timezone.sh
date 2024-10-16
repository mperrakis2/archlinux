#! /bin/bash
# Automatically set time zone when connected to the network
iface=$1
action=$2

if [[ $iface != lo && $action == up ]]; then
    tz=$(tzupdate -p 2>/dev/null)
    if [[ -n $tz && -r /usr/share/zoneinfo/$tz && ! pgrep protonvpn-app > /dev/null ]]
    then
        timedatectl set-timezone $tz
    fi
fi
