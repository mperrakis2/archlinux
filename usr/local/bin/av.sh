#!/bin/bash

# this script has to be run as root or sudo by adding the following to /etc/sudoers
#
# let all users run a virus scan
# ALL   ALL=NOPASSWD: /usr/local/share/av.sh

# make sure only one instance of the script can run at a time
# taken from the man page of flock
if [[ "${FLOCKER}" != "${BASH_SOURCE:-$0}" ]]; then
    exec env FLOCKER="${BASH_SOURCE:-$0}" flock -en "${BASH_SOURCE:-$0}" "${BASH_SOURCE:-$0}" "$@"
else
    true
fi

set -o pipefail

# variables for dirs and files
readonly LOGDIR="/var/log/clamav"
readonly VIRDIR="/var/tmp/virus"
readonly TMPDIR="/var/tmp/clamscan"
readonly LOGFILE="clamscan.log" # the output of commands (stdout)
readonly ERRFILE="clamscan.err" # errors if any (stderr)
readonly CMDFILE="clamscan.cmd" # the commands themselves

# commands to be executed
declare -a cmds=(\
                 # run check rootkit
                 "chkrootkit -x" \

                 # remove virus & tmp dir and log & error files from last scan      
                 "rm -rf $LOGDIR/$LOGFILE $LOGDIR/$ERRFILE $VIRDIR $TMPDIR" \

                 # create new virus & tmp dir and log & error files
                 "mkdir $TMPDIR $VIRDIR" \
                 "touch $LOGDIR/$LOGFILE $LOGDIR/$ERRFILE" \

                 # change permissions of new log & error files to that of other
                 # files under log dir
                 "chown clamav:adm $LOGDIR/$LOGFILE $LOGDIR/$ERRFILE" \

                 # run virus scan
                 # --exclude-dir are directories that are virtual and clamscan 
                 #               can't scan them
                 # --exclude are files that are false positives
                 "clamscan -ri --tempdir=$TMPDIR --log=$LOGDIR/$LOGFILE \
                           --remove=yes \
                           --exclude=$LOGDIR/$LOGFILE --exclude-dir=$VIRDIR \
                           --exclude-dir=/var/lib/clamav-unofficial-sigs \
                           --exclude-dir=/var/lib/clamav --exclude-dir=^/sys \
                           --exclude-dir=^/dev --exclude-dir=^/proc \
                           --exclude-dir=^/usr/share/clamav-testfiles -aio \
                           --heuristic-scan-precedence=yes \
                           --follow-dir-symlinks=2 \
                           --follow-file-symlinks=2 / "
)

declare -i err=0

# execute commands
echo -e "\nExecuting:"
echo -e   "=========="
for cmd in "${cmds[@]}"; do
    cmd=$(echo "$cmd" | tr -d -s '\b\f\n\r\t\v' ' ') # remove unnecessary whitespace
    echo "$cmd" | tee -a "$LOGDIR/$CMDFILE" # echo the command for convenience
    echo
    IFS=$'\n' command eval "$cmd" 2>> "$LOGDIR/$ERRFILE"
    err=$?
    (( err )) &&
        echo -e "\nThe command \"$cmd\" exited with error code $err. See" \
                "$ERRFILE (error file) for more info." &&
        break
done

exit $err
