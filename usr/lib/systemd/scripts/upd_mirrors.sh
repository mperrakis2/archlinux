#! /bin/bash

# remove orphan packages and generate new mirrorlist file

# make sure only one instance of the script can run at a time taken from the
# man page of flock
if [[ "${FLOCKER}" != "${BASH_SOURCE:-$0}" ]]; then
    exec env FLOCKER="${BASH_SOURCE:-$0}" flock -en "${BASH_SOURCE:-$0}" \
                                                    "${BASH_SOURCE:-$0}" "$@"
else
    true
fi

declare -i err=0

# answer yes to removal of all orphan packages
yes | LC_ALL=en_US.UTF-8 pamac remove --orphans --unneeded --no-save

# if no orphans found return val is 1 so set it to 0
((err=$?))
(( err == 1 )) && ((err=0))

set -o pipefail # set it here, as 'yes' above has an exit code of 141

# rename existing mirrorlist file
readonly ML_FILE="/etc/pacman.d/mirrorlist"
if [[ ! -s "$ML_FILE" || ! -r "$ML_FILE" || ! -w "$ML_FILE" ]]; then
    errmsg="warning" echo "The '$ML_FILE' file does not exist or is empty or is "
    errmsg+="not readable."
    systemd-cat -t "${0}" -p "$errmsg"
else
    cp -f "$ML_FILE" "$ML_FILE"~
fi

declare -i tmp=0

while true; do
    # generate new mirrorlist file
    rate-mirrors --allow-root --save "$ML_FILE" arch
    ((tmp=$?))
    (( tmp == 0 )) && break
    errmsg="rate-mirrors exited with error code $tmp while generating new "
    errmsg+="mirror list"
    systemd-cat -t "${0}" -p "err" echo "$errmsg"
    sleep 1    
done

sync
exit $err
