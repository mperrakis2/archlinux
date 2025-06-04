#!/usr/bin/bash

# delete the user passed in as a parameter

# make sure only one instance of the script can run at a time
# taken from the man page of flock
if [[ ${FLOCKER} != ${BASH_SOURCE:-$0} ]]; then
    exec env FLOCKER="${BASH_SOURCE:-$0}" flock -en "${BASH_SOURCE:-$0}" "${BASH_SOURCE:-$0}" "$@"
else
    true
fi

set -o pipefail

trap "echo; exit" ABRT HUP INT QUIT TERM &> /dev/null

read -rep $'warning: this script will delete a user and all user data\nCtrl+C to exit or enter user to delete: '

if [[ $REPLY == $(logname) ]]; then
    echo -e "\nYou can't delete user '$REPLY' as its the user you used to log in."
    exit 1
else
    userdel -r "$REPLY"
fi

declare -i err=$?

(( ! err )) && echo -e "\nuser account '$REPLY' has been deleted successfully"
sync

for param; do
    if [[ $param == -w || $param == --wait ]]; then
        echo -e '\nPress any key to exit.'
        read -rsn 1
        break
    fi
done

exit $err
