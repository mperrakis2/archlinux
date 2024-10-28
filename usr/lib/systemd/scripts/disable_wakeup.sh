#! /bin/bash

# disable all devices that are under acpi else the system wakes up right after suspend

# make sure only one instance of the script can run at a time
# taken from the man page of flock
if [[ "${FLOCKER}" != "${BASH_SOURCE:-$0}" ]]; then
    exec env FLOCKER="${BASH_SOURCE:-$0}" flock -en "${BASH_SOURCE:-$0}" "${BASH_SOURCE:-$0}" "$@"
else
    true
fi

set -o pipefail

# file that contains devices that are under acpi
readonly WAKEUP_FILE="/proc/acpi/wakeup"

# check that wakeup file is ok
if [[ ! -f "$WAKEUP_FILE" || ! -r "$WAKEUP_FILE"  || ! -w "$WAKEUP_FILE" ]]; then
    errmsg="The '$WAKEUP_FILE' file does not exist or is not readable or "
    errmsg+="writable. Can't disable devices under acpi so that suspend will "
    errmsg+="work. Exiting."
    systemd-cat -t "${0}" -p "err" echo "$errmsg"

    exit 1
fi

# See https://docs.kernel.org/firmware-guide/acpi/namespace.html
# section named "Example ACPI Namespace"
# the device code is 4 bytes with the first byte in [A-Z] and the others in 
# [A-Z], [0-9] or _
# the wakeup file line starts with that 4 byte code
# and we capture it as it is the device that will be disabled
readonly RE_DEVICE_CODE="\(^[A-Z]\{1,1\}[A-Z0-9_]\{3,3\}\)"

# the wakeup file line ends with the sysfs node
# only enabled devices have this entry
# when disabling devices only enabled ones should be disabled
readonly RE_SYSFS_NODE="[0-9]\{2,2\}:[0-9]\{2,2\}.[0-9]\{1,1\}$"

# the wakeup file line starts with <device_code> and ends with <sysfs_node>
# anything else is inbetween, i.e. <.*>
# below is the final regex
readonly RE_WAKEUP_LINE="$RE_DEVICE_CODE.*$RE_SYSFS_NODE"

declare -i fd
exec {fd}< "$WAKEUP_FILE" # open wakeup file

# loop through the wakeup file and disable everything that is enabled
while read -ru $fd; do
    device_code=$(expr "$REPLY" : "$RE_WAKEUP_LINE")
    (( ${#device_code} )) && echo "$device_code" > "$WAKEUP_FILE"
done
exec {fd}<&- # close the wakeup file

exit 0
