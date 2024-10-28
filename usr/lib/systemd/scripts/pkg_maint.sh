#! /bin/bash

# remove orphan packages, clear the package cache and generate new mirrorlist file

# make sure only one instance of the script can run at a time
# taken from the man page of flock
if [[ "${FLOCKER}" != "${BASH_SOURCE:-$0}" ]]; then
    exec env FLOCKER="${BASH_SOURCE:-$0}" flock -en "${BASH_SOURCE:-$0}" "${BASH_SOURCE:-$0}" "$@"
else
    true
fi

set -o pipefail

declare -i UID_MIN
UID_MIN=$(awk '/^UID_MIN/ {print $2}' /etc/login.defs)
declare -i UID_MAX
UID_MAX=$(awk '/^UID_MAX/ {print $2}' /etc/login.defs)
readonly UID_MIN UID_MAX

# get normal (non-system) users 
NORMAL_USERS=$(eval getent passwd "{$UID_MIN..$UID_MAX}" | cut -d ':' -f 1)
readonly NORMAL_USERS

# find which normal user has sudo access
declare -a sudo_users=()
for normal_user in $NORMAL_USERS; do
    su - "$normal_user" -c "sudo -ll" | grep ALL > /dev/null &&
        sudo_users+=("$normal_user")
done

readonly sudo_users
declare -i err=0

# all paru commands should not run under root
ORPHANS=$(su - "${sudo_users[0]}" -c "paru -Qttdq") # get orphan packages
((err=$?))
readonly ORPHANS

declare errmsg

if (( ! err )); then
    set +o pipefail # reset it, as 'yes' below has an exit code of 141
    # answer yes to removal of all orphan packages
    for orphan in $ORPHANS; do
        su - "${sudo_users[0]}" -c "yes | LC_ALL=en_US.UTF-8 paru -Rns $orphan"
        ((err+=$?))
    done
    set -o pipefail
elif (( err == 1 )); then # err == 1 => no orphans found which is not an error
    ((err=0))
else
    errmsg="paru get orphans exited with error code $err while searching for "
    errmsg+="orphan packages."
    systemd-cat -t "${0}" -p "err" echo "$errmsg"
fi

declare -i tmp=0

set +o pipefail # reset it, as 'yes' below has an exit code of 141
# answer yes to clearing package cache for all sudo users
for sudo_user in "${sudo_users[@]}"; do
    su - "$sudo_user" -c "yes | LC_ALL=en_US.UTF-8 paru -Scc" 
    tmp=$?
    ((err+=tmp))
    if (( tmp )); then
        errmsg="paru clear cache for user \"$sudo_user\" exited with error code "
        errmsg+="$tmp while clearing the package cache."
        systemd-cat -t "${0}" -p "err" echo "$errmsg"
    fi
done
set -o pipefail

# rename existing mirrorlist file
readonly ML_FILE="/etc/pacman.d/mirrorlist"
if [[ ! -s "$ML_FILE" || ! -r "$ML_FILE" || ! -w "$ML_FILE" ]]; then
    errmsg="warning" echo "The '$ML_FILE' file does not exist or is empty or is "
    errmsg+="not readable."
    systemd-cat -t "${0}" -p "$errmsg"
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
