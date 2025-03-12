#! /bin/bash

# wrapper for clone script

readonly SCRIPTPATH=/usr/lib/cloneup.sh.d/cloneup.sh

if [[ ! -x "$SCRIPTPATH" || ! -s "$SCRIPTPATH" ]]; then
    echo "$SCRIPTPATH is not executable or is empty"
    exit 1
fi

declare -i wait=0

params=()
for param; do
    if [[ "$param" == -w || "$param" == --wait ]]; then
        ((wait=1))
    else
        params+=("$param")
    fi
done

if [[ "$(ps -p 1 -o comm=)" == systemd ]]; then
    operations="shutdown:sleep:idle:handle-power-key:handle-suspend-key"
    operations+=":handle-hibernate-key:handle-lid-switch"
    systemd-inhibit --what="$operations" \
                    --who="$SCRIPTPATH" \
                    --why="cloning in progress" \
                    "$SCRIPTPATH" "${params[@]}"
else
    "$SCRIPTPATH" "${params[@]}"
fi

if ((wait)); then
    echo -e '\nPress any key to exit.'
    read -rsn 1
fi
