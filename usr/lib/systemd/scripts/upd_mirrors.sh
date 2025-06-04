#! /bin/bash

# remove orphan packages and generate new mirrorlist file

# make sure only one instance of the script can run at a time taken from the
# man page of flock
if [[ ${FLOCKER} != ${BASH_SOURCE:-$0} ]]; then
    exec env FLOCKER="${BASH_SOURCE:-$0}" flock -en "${BASH_SOURCE:-$0}" \
                                                    "${BASH_SOURCE:-$0}" "$@"
else
    true
fi

set -o pipefail

declare -i err=0

# all paru commands should not run under root
ORPHANS=$(paru -Qttdq | xargs) # get orphan packages
((err=$?))
readonly ORPHANS

declare errmsg

if (( ! err )); then
    set +o pipefail # reset it, as 'yes' below has an exit code of 141
    # answer yes to removal of all orphan packages
    yes | LC_ALL=en_US.UTF-8 paru -Rns $ORPHANS
    ((err=$?))
    set -o pipefail
elif (( err == 1 )); then # err == 1 => no orphans found which is not an error
    ((err=0))
else
    errmsg="paru get orphans exited with error code $err while searching for "
    errmsg+="orphan packages."
    systemd-cat -t "${0}" -p "err" echo "$errmsg"
fi

# rename existing mirrorlist file
readonly ML_FILE="/etc/pacman.d/mirrorlist"
if [[ ! -s $ML_FILE || ! -r $ML_FILE || ! -w $ML_FILE ]]; then
    errmsg="The '$ML_FILE' file does not exist or is empty or is "
    errmsg+="not readable."
    systemd-cat -t "${0}" -p "warning" echo "$errmsg"
else
    cp -f "$ML_FILE" "$ML_FILE"~
fi

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
