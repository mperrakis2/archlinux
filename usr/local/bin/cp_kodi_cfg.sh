#!/usr/bin/bash

# make sure only one instance of the script can run at a time
# taken from the man page of flock
if [[ "${FLOCKER}" != "${BASH_SOURCE:-$0}" ]];then
    exec env FLOCKER="${BASH_SOURCE:-$0}" flock -en "${BASH_SOURCE:-$0}" "${BASH_SOURCE:-$0}" "$@"
else
    true
fi

set -o pipefail

# called before exiting script
finish() {
    local -i stop
    stop=$(date +%s) # the timestamp will be used to calculate the copy run time
    local -i seconds=$(( stop - START ))%60
    local -i hours=$(( stop - START ))/$(( 60 * 60 ))
    local -i minutes=$(( stop - START - $(( hours * 60 * 60 )) ))/60
    printf "Run time: %02d:%02d:%02d (hh:mm:ss).\n" $hours $minutes $seconds
    
    return 0
}

# called when an error occured; it exits the script
# $1    : str, the command that failed
# return: int, the error code of the command that failed
error() {
    local errmsg
    
    errmsg="\nThe command '$cmd' failed. See $LOGFILE (log file) and" \
    errmsg+="$ERRFILE (error file) for more info. Exiting."
    echo -e "$errmsg" 
    finish
    
    exit $err
}

# constants
declare -i START
START=$(date +%s) # the timestamp will be used to calculate the copy run time
readonly START
readonly INTROMSG="This script copies kodi configuration from one user account \
                   to another. It requires two parameters: source & destination \
                   usernames which must be different and an existing kodi \
                   directory on the source account."
readonly WRONGUSER="One or both usernames do not exist or they are the same."

# variables
declare errmsg=""

# src and dst usernames have to be provided
if [[ $# -ne 2 || ! -d /home/"$1"/.kodi || ! -x /home/"$1"/.kodi ]]; then
    errmsg=$(echo "$INTROMSG" | xargs)
else
    # get src and dst usernames
    src=$(compgen -u "$1" | xargs | grep -wo "$1")
    dst=$(compgen -u "$2" | xargs | grep -wo "$2")
    readonly src dst

    # srd & dst usernames must exist
    if [[ "$src" != "$1" || "$dst" != "$2" || "$src" == "$dst" ]]; then
        errmsg=$(echo "$WRONGUSER" | xargs)
    fi
fi

# exit if usernames don't exist
if (( ${#errmsg} )); then
    echo "$errmsg"
    finish
    exit 1
fi

readonly LOGDIR="/var/log/"
LOGFILE="$LOGDIR/$(basename "${BASH_SOURCE:-$0}")_"
ERRFILE="$LOGDIR/$(basename "${BASH_SOURCE:-$0}")_"
CMDFILE="$LOGDIR/$(basename "${BASH_SOURCE:-$0}")_"

# commands to be executed
declare -a CMDS=("[[ -s /home/'$2'/.kodi/userdata/favourites.xml ]] && \
                      cp -pf /home/'$2'/.kodi/userdata/favourites.xml /home/'$2'/__fav__.bak || \
                      true" \
                 "rsync --log-file='$LOGFILE$$.log' --info=misc2,mount,name0,progress2,stats2 \
                        --chown='$2':'$2'  -aAhHxXlzDEU --no-i-r --numeric-ids \
                        --exclude=*.pyc --exclude=*.pyo \
                        /home/'$1'/.kodi/ /home/'$2'/.kodi" \
                 "[[ -s /home/'$2'/__fav__.bak ]] && \
                      rm -fr /home/'$2'/.kodi/userdata/favourites.xml || \
                      true " \
                 "[[ -s /home/'$2'/__fav__.bak ]] && \
                      cp -pf /home/'$2'/__fav__.bak /home/'$2'/.kodi/userdata/favourites.xml || \
                      true" \
                 "rm -fr /home/'$2'/__fav__.bak" \
                )
readonly CMDS

# remove previous logfiles
rm -f "$CMDFILE"[0-9]*.cmd "$LOGFILE"[0-9]*.log "$ERRFILE"[0-9]*.err

LOGFILE+="$$.log" # the output of commands (stdout)
ERRFILE+="$$.err" # errors if any (stderr)
CMDFILE+="$$.cmd" # the commands themselves
readonly LOGFILE ERRFILE CMDFILE

declare -i err=0

# execute commands
echo -e "\nExecuting:" | tee -a "$CMDFILE"
echo -e   "==========" | tee -a "$CMDFILE"
for cmd in "${CMDS[@]}"; do
    # remove unnecessary whitespace
    cmd=$(echo "$cmd" | tr -d -s '\b\f\n\r\t\v' ' ')
    echo "$cmd" | tee -a "$CMDFILE" # echo the command for convenience
	IFS=$'\n' command eval "$cmd" 2>> "$ERRFILE" >> "$LOGFILE"
	err=$?
    (( err )) && error "$cmd"
done
sync; sync -f

echo

# get files on destination that contain the source username
cmd="grep -rlZ /home/'$1' /home/'$2'/.kodi"
echo "$cmd" | tee -a "$CMDFILE" # echo the command for convenience
readarray -td '' FILENAMES < <(IFS=$'\n' command eval "$cmd" 2>> "$ERRFILE")
((err=$?))
(( err )) && finish && exit $err
readonly FILENAMES

# on destination files, substitute the source username with the destination username 
for filename in "${FILENAMES[@]}"; do
    cmd="sed -i \"s|/home/$1|/home/$2|g\" '$filename'"
    echo "$cmd" | tee -a "$CMDFILE" # echo the command for convenience
	IFS=$'\n' command eval "$cmd" 2>> "$ERRFILE" >> "$LOGFILE"
	((err=$?))
    (( err )) && error "$cmd"
done
sync; sync -f

echo -e "\nCopying kodi configuration from user '$1' to user '$2' completed successfully."

finish
exit $err
