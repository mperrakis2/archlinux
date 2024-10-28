#!/usr/bin/bash

# create a new user based on user input and directory structure under the
# script's directory

# make sure only one instance of the script can run at a time
# taken from the man page of flock
if [[ "${FLOCKER}" != "${BASH_SOURCE:-$0}" ]]; then
    exec env FLOCKER="${BASH_SOURCE:-$0}" flock -en "${BASH_SOURCE:-$0}" "${BASH_SOURCE:-$0}" "$@"
else
    true
fi

set -o pipefail
shopt -s extglob

# called before exiting script
finish() {
    if (( START )); then
        local -i stop
        stop=$(date +%s) # the timestamp will be used to calculate the copy run time
        local -i seconds=$(( stop - START ))%60
        local -i hours=$(( stop - START ))/$(( 60 * 60 ))
        local -i minutes=$(( stop - START - $(( hours * 60 * 60)) ))/60
        
        printf "run time: %02d:%02d:%02d (hh:mm:ss)\n" $hours $minutes $seconds
    fi
}

# called when an error occured; it exits the script
# $1  : str, the command that failed
# exit: int, the error code of the command that failed
error() {
    local errmsg
    
    errmsg="\nThe command '$1' failed. See $ERRFILE (error file) for more "
    errmsg+="info. Exiting."
    echo -e "$errmsg" 
    finish
    
    exit $err
}

declare -i START=0
declare -i err=0

trap "echo; exit" ABRT HUP INT QUIT TERM &> /dev/null

# get new username
prompt="This script creates a new user. Enter username or Ctrl-C at any time to exit: "
while read -er -p "$prompt" NEWUSER; do
    prompt="Enter username: "
    if [[ "$NEWUSER" ]]; then
        # check if user exists already
        user=$(compgen -u "$NEWUSER" | xargs | grep -wo "$NEWUSER")
        if [[ "$user" == "$NEWUSER" ]]; then
            prompt='The new user you entered already exists. Are you sure you '
            prompt+='want to delete it? (y/yes/n/no) '
            while read -rn 3 -p "$prompt"; do
                case "${REPLY,,}" in
                    y | yes)
                        break
                        ;;

                    n | no)
                        finish && exit $err
                        ;;
                esac 
            done    

            echo
            userdel -r "$user"
            ((err=$?))
            (( err )) && finish && exit $err
            sync
        fi

        break
    fi
done

# ask for sudo group
prompt="Add new user to sudo group? (y/n): "
while read -er -n 1 -p "$prompt" IS_SUDO; do
    [[ "${IS_SUDO,,}" =~ y|n ]] && break
done

START=$(date +%s) # the timestamp will be used to calculate the copy run time
readonly NEWUSER IS_SUDO START

declare -a cmds=() # commands to be executed

cmds+=("useradd $NEWUSER") # add new user
cmds+=("echo $NEWUSER:$NEWUSER | chpasswd") # change password to username

# add groups to new user
cmds+=("usermod -aG sys,ftp,log,http,games,rfkill,systemd-journal,uucp,wheel,adm \
                '$NEWUSER'")
                    
# add sudo group to new user                    
[[ "${IS_SUDO,,}" == y ]] && cmds+=("usermod -aG sudo '$NEWUSER'")

readonly LOGDIR="/var/log/"
LOGFILE="$LOGDIR/$(basename "${BASH_SOURCE:-$0}")_"
ERRFILE="$LOGDIR/$(basename "${BASH_SOURCE:-$0}")_"
CMDFILE="$LOGDIR/$(basename "${BASH_SOURCE:-$0}")_"

# remove previous logfiles
rm -f "$CMDFILE"[0-9]*.cmd "$LOGFILE"[0-9]*.log "$ERRFILE"[0-9]*.err

readonly LOGFILE+="$$.log" # the output of commands (stdout)
readonly ERRFILE+="$$.err" # errors if any (stderr)
readonly CMDFILE+="$$.cmd" # the commands themselves

cmds+=("rsync --log-file='$LOGFILE' --info=misc2,mount,name0,progress2,stats2 \
              --chown='$NEWUSER':'$NEWUSER' -aAhHxlzEUtX --no-i-r --numeric-ids \
              /usr/sbin/useradd.d/new_user/ /home/'$NEWUSER'/" \
       "rsync --log-file='$LOGFILE' --info=misc2,mount,name0,progress2,stats2 \
              --chown='$NEWUSER':'$NEWUSER' -aAhHxlzEUtX --no-i-r --numeric-ids \
              /etc/skel/.bash* /home/'$NEWUSER'/" \
       "if groups '$NEWUSER' | grep --quiet sudo; then \
            rm /home/$NEWUSER/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xmlE; \
        else \
            desktop=\$(su - '$NEWUSER' -c 'xdg-user-dir DESKTOP | xargs -0 basename'); \
            eval cd /home/'$NEWUSER/\$desktop'; \
            rm add-user.desktop clone.desktop del-user.desktop; \
            unset desktop; \
            cd -; \
            mv /home/$NEWUSER/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xmlE \
               /home/$NEWUSER/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml; \
        fi")

# execute commands
echo
for cmd in "${cmds[@]}"; do
    # remove unnecessary whitespace
    cmd=$(echo "$cmd" | tr -d -s '\b\f\n\r\t\v' ' ')
    echo "$cmd" | tee -a "$CMDFILE" # echo the command for convenience
    IFS=$'\n' command eval "$cmd" 2>> "$ERRFILE" >> "$LOGFILE"
    ((err=$?))
    (( err )) && error "$cmd"
done
sync
echo

readonly TEMPLATE_USER=admin

if [[ "$NEWUSER" != "$TEMPLATE_USER" ]]; then
    # get files on destination that contain 'admin'
    cmd="grep -rlZ /home/admin /home/'$NEWUSER'"
    echo "$cmd" | tee -a "$CMDFILE" # echo the command for convenience
    readarray -td '' FILENAMES < <(IFS=$'\n' command eval "$cmd" 2>> "$ERRFILE")
    ((err=$?))
    (( err )) && finish && exit $err
    readonly FILENAMES

    # on destination files, substitute 'admin' with the destination username 
    for filename in "${FILENAMES[@]}"; do
        cmd="sed -i 's|/home/admin|/home/$NEWUSER|g' '$filename'"
        echo "$cmd" | tee -a "$CMDFILE" # echo the command for convenience
	    IFS=$'\n' command eval "$cmd" 2>> "$ERRFILE" >> "$LOGFILE"
	    ((err=$?))
        (( err )) && error "$cmd"
    done
    sync
    echo
fi

# get pictures directory of new user
PICTURES=$(su - "$NEWUSER" -c "xdg-user-dir PICTURES | xargs -0 basename")
readonly PICTURES

# the following command gets the filenames of the image file that will be used
# as a desktop background image for new user
cmd="ls -1 /home/'$NEWUSER'/'$PICTURES'"
echo "$cmd" | tee -a "$CMDFILE" # echo the command for convenience
declare -a BGDIMG_FILES=($(IFS=$'\n' command eval "$cmd" 2>> "$ERRFILE"))
readonly BGDIMG_FILES
(( ! ${#BGDIMG_FILES[@]} )) && error "$cmd"

# set the filename of the desktop background image
if groups "$NEWUSER" | grep --quiet sudo; then
    BGDIMG_FILE=${BGDIMG_FILES[1]}
else
    BGDIMG_FILE=${BGDIMG_FILES[0]}
fi

# the following config files contain the desktop background image for new user
declare -a BGDIMG_CFGFILES=(/home/"$NEWUSER"/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml \
                            /home/"$NEWUSER"/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml)
readonly BGDIMG_CFGFILES

# set the image as the new desktop background image in new user config files    
for bgdimg_cfgfile in "${BGDIMG_CFGFILES[@]}"; do
    cmd="sed -iE 's|/home/$NEWUSER/$PICTURES/.*\"/>$|/home/$NEWUSER/$PICTURES/$BGDIMG_FILE\"/>|g' "
    cmd+="'$bgdimg_cfgfile'"
    echo "$cmd" | tee -a "$CMDFILE" # echo the command for convenience
    IFS=$'\n' command eval "$cmd" 2>> "$ERRFILE" >> "$LOGFILE"
    ((err=$?))
    (( err )) && error "$cmd"
done
sync
echo

if [[ "$NEWUSER" != "$TEMPLATE_USER" ]]; then
    # if keyring dir exists then generate new login keyring for new user
    readonly KEYRING_DIR="/home/$NEWUSER/.local/share/keyrings/"

    if [[ -d "$KEYRING_DIR" ]]; then
        # log into new user and generate new login keyring
        cmd="su - '$NEWUSER' -c \"echo -n '$NEWUSER' | gnome-keyring-daemon --unlock\""
        echo "$cmd" | tee -a "$CMDFILE" # echo the command for convenience
	    IFS=$'\n' command eval "$cmd" 2>> "$ERRFILE" >> "$LOGFILE"
        ((err=$?))

        cmd="pgrep -f -u '$NEWUSER' gnome-keyring-daemon"
        echo "$cmd" | tee -a "$CMDFILE" # echo the command for convenience
        
        declare -i PID=0
        declare -i TMP=0
        
        PID=$(IFS=$'\n' command eval "$cmd" 2>> "$ERRFILE")
        ((TMP=$?))
        readonly PID TMP

        if (( ! TMP )); then # if keyring daemon exists terminate it
            cmd="kill -TERM $PID"
            echo "$cmd" | tee -a "$CMDFILE" # echo the command for convenience
	        IFS=$'\n' command eval "$cmd" 2>> "$ERRFILE" >> "$LOGFILE"
            ((err+=$?))
        else
            ((err+=TMP))
        fi
    fi
    echo
fi

if (( ! err )); then
    declare -i USRID=$(sudo -u "$NEWUSER" id -u)
    readonly USRID

    # set BackgroundFile property in section [DisplayManager.AccountsService] in 
    # /var/lib/AccountsService/users/$NEWUSER
    cmd="busctl set-property org.freedesktop.Accounts \
                /org/freedesktop/Accounts/User$USRID \
                org.freedesktop.DisplayManager.AccountsService \
                BackgroundFile s '/home/$NEWUSER/$PICTURES/$BGDIMG_FILE'"
    cmd=$(echo "$cmd" | tr -d -s '\b\f\n\r\t\v' ' ')
    echo "$cmd" | tee -a "$CMDFILE" # echo the command for convenience
    IFS=$'\n' command eval "$cmd" 2>> "$ERRFILE" >> "$LOGFILE"
    ((err=$?))
    (( err )) && finish && exit $err

    # set property in section [User] in /var/lib/AccountsService/users/$NEWUSER
    cmd="busctl call org.freedesktop.Accounts \
                /org/freedesktop/Accounts/User$USRID \
                org.freedesktop.Accounts.User SetSession s '${XDG_CURRENT_DESKTOP,,}'"
    cmd=$(echo "$cmd" | tr -d -s '\b\f\n\r\t\v' ' ')
    echo "$cmd" | tee -a "$CMDFILE" # echo the command for convenience
    IFS=$'\n' command eval "$cmd" 2>> "$ERRFILE" >> "$LOGFILE"
    ((err=$?))
    (( err )) && finish && exit $err
    echo
fi

if (( ! err )); then
    echo -n "user '$NEWUSER' was created successfully and its password is its "
    echo "username"
else
    echo "errors occured; please check the logs" \
         "('$ERRFILE', '$LOGFILE', '$CMDFILE')," \
         "delete the newly created user '$NEWUSER' and try again"
fi

finish
exit $err
