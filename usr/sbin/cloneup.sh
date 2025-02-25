#!/bin/bash

# This script clones one drive to another. For detailed info and usage see man
# page: <script_name>(1). For a quick description of the cmd line options run
# '<script_name> -h|--help'.

# legend
# ------
# src: drive to be cloned (source)
# dst: drive to clone to  (destination)
#
# limitations
# -----------
# see LIMITS section in man page: <script_name>(1)
#
# conf files used by script (variables in this section are defined below)
# -----------------------------------------------------------------------
# the following files are under $DEF_CFG_DIR and optionally under 
# $OVR_CFG_DIR and $LCL_CFG_DIR
#
# fstypes.conf: maps filesystem names of 'parted' cmd to 'mkfs' cmd
# exclude.conf: files/dirs to be excluded from and/or included in cloning
#
# log files created by script
# ---------------------------
# log                  : the output of cmds (stdout)
# errors               : errors, if any (stderr)
# commands             : the cmds used during cloning
# <script_name>.pids   : lock file to ensure that the script is executed only
#                        if its src and dst are not destinations for another
#                        script already running (multiple instances are
#                        allowed as long as destinations are different)
# slp_<script_name>.pid: lock file to ensure that only one script instance is
#                        responsible for masking/unmasking system sleep
#                        (suspend/hibernate)
#
# * lock files are created under /var/lock/<script_dir>/ which is deleted after
#   all script instances have terminated
# * all other files are created under /var/log/<script_dir>/X_Y/ (X, Y: drive
#   numbers for src and dst respectively)
#
# other scripts used by this script
# ---------------------------------
# <script_name_no_ext>-lib.sh (under /usr/lib and sourced in)

set -o pipefail
shopt -s extglob

# global constants
SCRIPTDIR="${BASH_SOURCE:-$0}"      # script pathname
SCRIPTNAME=$(basename "$SCRIPTDIR") # script filename
readonly SCRIPTNAME
SCRIPTDIR=$(dirname "$SCRIPTDIR")   # script dir
readonly SCRIPTDIR

readonly DEF_CFG_DIR="/etc/$SCRIPTNAME.d"
readonly OVR_CFG_DIR="$DEF_CFG_DIR/conf.d"

declare -i dry_run=0
FILTERS_FILE=""
FSTYPES_FILE=""

declare -a FSTYPES=()
declare -a FILTERS=()

declare -i MIBIBYTE=1024*1024
readonly MIBIBYTE

UNIT=B # unit supplied to 'parted' cmd is bytes
readonly UNIT

LCKDIR=/var/lock/"$SCRIPTNAME.d"
readonly LCKDIR
LOGDIR=/var/log/"$SCRIPTNAME.d"
DRV_SUFFIX="[0-9]+$"
readonly DRV_SUFFIX
CANCEL_SIGNALS="ABRT HUP INT QUIT TERM"
readonly CANCEL_SIGNALS
LCKFILE="$LCKDIR/${SCRIPTNAME}.pids"
readonly LCKFILE
SLPFILE="$LCKDIR/slp_${SCRIPTNAME}.pid"
readonly SLPFILE

# bold colors foreground
BOLD=$(tput bold)
readonly BOLD
RED="$BOLD$(tput setaf 1)"
readonly RED
GREEN="$BOLD$(tput setaf 2)"  
readonly GREEN
YELLOW="$BOLD$(tput setaf 3)" 
readonly YELLOW
CYAN="$BOLD$(tput setaf 6)"   
readonly CYAN
OFF=$(tput sgr0) # turn off all attributes
readonly OFF

# bold colors background
REDB="$BOLD$(tput setab 1)"
readonly REDB

# these variables are field numbers used by the field() function
# BEGIN
declare -i DNAME=1
declare -i DSIZE=2
declare -i DTYPE=3
declare -i DSECTOR_SIZE=4
declare -i DPTN_TBL_TYPE=6 # updated during execution and then declared readonly
declare -i DMODEL=7

readonly DNAME DSIZE DTYPE DSECTOR_SIZE DMODEL

declare -i PDRV_NUM=1
declare -i PPTN_NUM=1 # updated during execution and then declared readonly
declare -i PSTART=2   # ditto
declare -i PEND=3     # ditto
declare -i PSIZE=4    # ditto
declare -i PFSTYPE=5  # ditto
declare -i PNAME=6    # ditto
declare -i PFLAGS=7   # ditto
declare -i PPTN_CNT=9
declare -i PALIGN_START=10
declare -i PALIGN_SIZE=11
readonly PDRV_NUM PPTN_CNT PALIGN_START PALIGN_SIZE

declare -i MPTN=1
declare -i MDIR=2
declare -i MIS_MNT=3
declare -i MUUID=4
declare -i MDST=4
readonly MPTN MDIR MIS_MNT MUUID MDST

declare -i SOURCE=1
declare -i USED=2
declare -i PCENT=3
readonly SOURCE USED PCENT

declare -i SPTN=1
declare -i SUUID=2
declare -i SDST=2
readonly SPTN SUUID SDST
# END
# the variables above are field numbers used by the field() function

# get partition of boot directory
BOOTPTN=$(findmnt -no SOURCE -T "$(bootctl -x)")
readonly BOOTPTN

# global variable declarations
declare -A drv_data=() # data on drives (-A for associative array)
declare -a partitions=()
declare -a OPTIONS=()  # cloning options entered by the user
declare -i drv_cnt=0   # number of available drives

# total amount of space that can't be resized, i.e. esp, bios, boot and swap 
# partitions
declare -i no_resize=0

declare -A rsync_filters=() # files/dirs excluded from or included in cloning
declare -i clone_size=0
declare -a src_ptn_data=()
srcdrv=""
dstdrv=""
declare -iA esp_ptn_nums=()
declare -iA boot_ptn_nums=()
declare -i bios_ptn=0

declare -i start=0
declare START_DATE=""
declare -i DST_ALIGN=MIBIBYTE
declare -i dst_drv_size=0
declare -i dst_space_avail=0
declare -A alignments=()
declare -i src_lba=0
declare -i create_ptn=0

LOGFILE=""
ERRFILE=""
CMDFILE=""
OPTIONS_S="" # user input saved as string
SP="" # src partiion prefix
DP="" # dst partiion prefix
declare -a rsync_params=()
declare -a g_parted_data=() # drive data retrieved from 'parted' cmd
declare -i LOOP=1
declare -i script=0 # script mode, i.e. no user input other than cmd line args

init() {
    local options
    local script_name
        
    script_name=$(basename "${BASH_SOURCE:-$0}") # get name of script

    # Note the use of "$@" (quoted) to let each cmd line option expand to a
    # separate word. 'options' is needed as 'eval set --' would lose the return
    # value of getopt. A colon (:) after an option specifies a required arg.
    options=$(getopt -q -o 'hre:f:s:d:' \
                     -l 'help,dry-run,exclude:,fstypes:,src:,dst:' \
                     -n "$script_name" -- "$@")
    if (( $? )); then
        print_helpmsg
        exit 1
    fi

    eval set -- "$options" # quotes are required

    while true; do
        case "$1" in
            '-h'|'--help')
                print_helpmsg
                exit 0
                ;;
            '-r'|'--dry-run')
                ((dry_run=1))
                shift
                ;;
            '-e'|'--exclude')
                FILTERS_FILE="$2"
                shift 2
                ;;
            '-f'|'--fstypes')
                FSTYPES_FILE="$2"
                shift 2
                ;;
            '-s'|'--src')
                srcdrv="$2"
                shift 2
                ;;
            '-d'|'--dst')
                dstdrv="$2"
                shift 2
                ;;
            '--')
                shift
                break
                ;;
            *)
                print_helpmsg
                exit 1
                ;;
        esac
    done

    # script mode, i.e. no user input other than cmd line args
    if [[ "$srcdrv" && "$dstdrv" ]]; then
        ((script=1))
    elif [[ ("$srcdrv" && ! "$dstdrv") || (! "$srcdrv" && "$dstdrv") ]]; then
        cecho "${RED}Source or destination drives don't exist."
        return 1
    fi

    # if no cmd line options provided, get default cfg file names
    [[ -z "$FSTYPES_FILE" ]] &&
        FSTYPES_FILE=$(get_cfg_fname fstypes.conf) # get pathname of fstypes file
    [[ -z "$FILTERS_FILE" ]] &&
        FILTERS_FILE=$(get_cfg_fname exclude.conf) # get pathname of exclude file

    local -i err

    files_exist # check that text files needed by script exist
    ((err=$?)); ((err)) && return $err

    local signals
    local D="[0-9]" # digit
    local L=SIG     # literal
    readonly D L

    signals=$(kill -l | xargs) # get all signal names
    signals="${signals//@($D|$D$D)) $L}" # remove leading numbers & letters
    trap "" $signals # ignore all signals
    trap_signals "cleanup 1" "$CANCEL_SIGNALS" # signal handler for cancel
}

# display list of detected drives and cloning usage
# return: 0 on success else 1
usage() {
    (( ! script )) && clear # if src & dst not specified as cmd line args

    local override_file="$OVR_CFG_DIR/exclude.conf"

    # if there is no override for the file set it to empty str
    if [[ ! "$FILTERS_FILE" =~ "$DEF_CFG_DIR" || ! -f "$override_file" || \
          ! -s "$override_file" || ! -r "$override_file" ]]
    then
        override_file=""
    fi

    # read files that contain dirs/files to be excluded from or included in
    # cloning and save these entries into array
    local file
    local -i fd
    local -i i
    local -a filters=()

    for file in "$FILTERS_FILE" $override_file; do
        exec {fd}< "$file" # open filters file
        while read -r -u $fd; do
            # remove leading & trailing spaces and tabs
            REPLY=$(echo "$REPLY" | sed -e 's/^[[:blank:]]*//' \
                                        -e 's/[[:blank:]]*$//')
            [[ -z "$REPLY" ]]  && continue  # skip empty lines

            # get lines that are not comments
            REPLY=$(expr "$REPLY" : "\(^[^#].*$\)")
            (( $? )) && continue # skip comments

            # remove redundant /, * and space
            while [[ "$REPLY" =~ ('//'|'**'|[[:blank:]][[:blank:]][[:blank:]]) ]]
            do 
                REPLY="${REPLY//'//'/'/'}"
                REPLY="${REPLY//'**'/'*'}"

                # replace 3 blanks with 2
                REPLY="${REPLY//[[:blank:]][[:blank:]][[:blank:]]/'  '}"
            done    
            
            if [[ "$file" == "$override_file" ]]; then
                # iterate over existing array and update its elements
                for (( i = 0; i < ${#filters[@]}; ++i )); do
                    [[ "${filters[i]}" == "$REPLY" ]] && break
                done
                (( i == ${#filters[@]} )) && filters+=("$REPLY")
            else
                # save entry excluded from or included in cloning
                filters+=("$REPLY")
            fi
        done
        exec {fd}<&- # close the filters file
    done

    if (( ! script )); then # if src & dst not specified as cmd line args
        cat << usage_msg
DESCRIPTION
===========
This script will clone one drive to another using rsync(1). Source and
destination drives need not be the same size as long as all source data fits on
destination. Also, the files and/or directories contained in the following
file(s)
$YELLOW'$FILTERS_FILE'$OFF
usage_msg

        [[ "$override_file" ]] && cecho "'$override_file'"

        cat << usage_msg
will ${YELLOW}NOT$OFF be cloned. Here they are:

usage_msg

        for fd in "${!filters[@]}"; do
            cecho "$CYAN${filters[fd]}"
        done
        echo

        cat << usage_msg
For more info see $SCRIPTNAME(1) & $SCRIPTNAME-exclude.conf(5).

${YELLOW}LIMITATIONS
===========$OFF
See ${YELLOW}LIMITS$OFF section in $SCRIPTNAME(1).

${YELLOW}WARNING
=======
Before proceeding close all programs on all user accounts and logout from all
user accounts but one that will be used to run this script.$OFF

DRIVES
usage_msg

        filters[0]="==============================================================="
        filters[0]+="==============="

        echo ${filters[0]} # print underlines
    fi

    # get drive and partition data
    g_parted_data=()
    readarray -t g_parted_data < <(parted --machine --script --list 2> /dev/null)

    if (( ! script )); then # if src & dst not specified as cmd line args
        local line

        # iterate over drive and partition data
        ((drv_cnt=0))
        for line in "${g_parted_data[@]}"; do
            # the output of 'parted' cmd is something like:
            #
            # BYT;
            # /dev/nvme0n1:512GB:nvme:512:512:gpt:KBG40ZNS512G NVMe KIOXIA 512GB:;
            # 1:1049kB:11.5MB:10.5MB::BIOS:bios_grub;
            # 2:11.5MB:536MB:524MB:fat32:UEFI:boot, esp;
            # 3:536MB:512GB:512GB:ext4:ROOT:;
            if [[ "$line" =~ ^/dev/ ]]; then
                (( drv_cnt > 0 )) && echo # seperate one drive output from another
                ((++drv_cnt))

                # display drive model and type (see comment above)
                echo "$drv_cnt. Model: $(field "$line" $DMODEL) ($(field "$line" $DTYPE))"

                # display drive size (see comment above)
                echo "   Disk $(field "$line" $DNAME): $(field "$line" $DSIZE)"
            fi
        done

        echo ${filters[0]} # print underlines

        cat << usage_msg

USAGE
=====
Enter the number of the source drive followed by the number of the destination
usage_msg
    fi
}

# Get and validate cloning options.
# return: 0 on success else 1
user_input() {
    if (( ! script )); then # if src & dst not specified as cmd line args
        OPTIONS=()
        echo -n "drive separated by space, e.g. 1 2 or press Ctrl-C anytime to"\
                "cancel: "
        read -r -a OPTIONS # read cloning options into array
    fi

    START_DATE=$(date) # timestamp will be used to calculate the run time

    if (( script )); then # if src & dst specified as cmd line args
        local line

        # iterate over drive and partition data to validate src & dst drives
        for line in "${g_parted_data[@]}"; do
            # the output of 'parted' cmd is something like:
            #
            # BYT;
            # /dev/nvme0n1:512GB:nvme:512:512:gpt:KBG40ZNS512G NVMe KIOXIA 512GB:;
            # 1:1049kB:11.5MB:10.5MB::BIOS:bios_grub;
            # 2:11.5MB:536MB:524MB:fat32:UEFI:boot, esp;
            # 3:536MB:512GB:512GB:ext4:ROOT:;
            if [[ "$line" =~ ^/dev/ ]]; then
                ((++drv_cnt))

                if [[ "$line" =~ "$srcdrv:" ]]; then # ':' is the field delimeter
                    if (( ${#OPTIONS[@]} )); then # dst drive already validated
                        # prepend valid src drive
                        OPTIONS=("$drv_cnt" "${OPTIONS[@]}")
                        break
                    else
                        OPTIONS+=("$drv_cnt") # add valid src drive
                    fi
                fi

                if [[ "$line" =~ "$dstdrv:" ]]; then # ':' is the field delimeter
                    OPTIONS+=("$drv_cnt") # add valid dst drive
                    (( ${#OPTIONS[@]} == 2 )) && break
                fi
            fi
        done

        # exit if none or only one drive is valid
        if (( ${#OPTIONS[@]} == 0 )); then
            prompt LOOP "Source and destination drives don't exist."
        elif (( ${#OPTIONS[@]} == 1 )); then
            prompt LOOP "Source or destination drive doesn't exist."
        fi
    fi

    local -a parted_data

    # get parted data again
    readarray -t parted_data < <(parted --machine --script --list 2> /dev/null)

    # compare current parted data with original
    if [[ "${parted_data[*]}" != "${g_parted_data[*]}" ]]; then
        prompt LOOP "The drive configuration has changed."
        return $?
    fi

    local -i i

    # convert to lowercase and remove whitespace
    for i in "${!OPTIONS[@]}"; do
        OPTIONS[i]="${OPTIONS[i],,}"
        OPTIONS[i]="${OPTIONS[i]//[[:blank:]]/}"
        [[ ! "${OPTIONS[i]}" =~ ^[0-9]+$ ]] && break # break if not a number
    done

    if [[ ! "${OPTIONS[i]}" =~ ^[0-9]+$ ]]; then # if not num display usage again
        prompt LOOP "Source & destination drives have to numbers."
        return $?
    fi
    
    cat << validate_params


Proceeding...

Validating parameters...
validate_params

    # validate cloning options and if error, prompt the user to try again
    if (( ${#OPTIONS[@]} != 2 )); then
        prompt LOOP "Exactly two cloning parameters are needed. See usage above."
    elif (( OPTIONS[0] > drv_cnt || OPTIONS[0] < 1 )); then
        prompt LOOP "Source drive has to be an option within [1, $drv_cnt]."
    elif (( OPTIONS[1] > drv_cnt || OPTIONS[1] < 1 )); then
        prompt LOOP "Destination drive has to be an option within [1, $drv_cnt]."
    elif (( OPTIONS[0] == OPTIONS[1] )); then
        prompt LOOP "Source and destination drives can't be the same."
    else
        ((LOOP=0))
        echo 
    fi
}

# setup variables
# return: 0 on success else the error code of the cmd that failed
setup_env() {
    echo "Initializing..."

    # in case this is not the first attempt, e.g. the user entered wrong data,
    # get existing cloning options
    OPTIONS_S=$(expr "$LOGDIR" : "^.\+\([0-9]\+_[0-9]\+\)$")

    local -i fd

    # create lock dir and set its access rights
    mkdir -p "$LCKDIR" && chmod go+=rx "$LCKDIR"
    ((fd=$?))
    if (( fd )); then
        cechot "${RED}The lock directory, $YELLOW'$LCKDIR'$RED, could not be"\
               "${RED}created or set to read & execute. Exiting."
        return $fd
    fi

    # in case this is not the first attempt, e.g. the user entered wrong data,
    # remove any cloning options from log dir
    LOGDIR="${LOGDIR//$OPTIONS_S/}"
    OPTIONS_S="${OPTIONS[0]}_${OPTIONS[1]}"

    # complete the filename of log dir
    if [[ "${LOGDIR: -1}" == "/" ]]; then
        LOGDIR+="$OPTIONS_S"
    else
        LOGDIR+="/$OPTIONS_S"
    fi

    local line
    local -i drv_num=0 # drive number used as index in associative array

    # iterate over drive data to get drive names
    drv_data=()
    for line in "${g_parted_data[@]}"; do
        if [[ "$line" =~ ^/dev/ ]]; then
            ((++drv_num))

            # if the drive is src or dst save drive name in associative array of drives
            (( drv_num == OPTIONS[0] || drv_num == OPTIONS[1] )) && 
                drv_data[$drv_num]=$(field "$line" $DNAME)
        fi
    done

    srcdrv="${drv_data[${OPTIONS[0]}]}" # extract src drive name
    dstdrv="${drv_data[${OPTIONS[1]}]}" # extract dst drive name

    # device names that end in a number have their partitions prefixed by the
    # following literal 
    local ptn_prefix="p"

    if [[ "$srcdrv" =~ $DRV_SUFFIX ]]; then SP="$ptn_prefix"; else SP=""; fi
    if [[ "$dstdrv" =~ $DRV_SUFFIX ]]; then DP="$ptn_prefix"; else DP=""; fi
    
    # critical section
    (
        if ! flock $fd; then exit $?; fi

        # if no clone process with same dst then delete log dir
        if ! grep -q "$dstdrv" "$LCKFILE" && (( ! dry_run )); then
            echo -e "\tRemoving old $SCRIPTNAME log directory $LOGDIR ..."
            rm -rf "$LOGDIR"
        fi

    ) {fd}>> "$LCKFILE"
    ((fd=$?))
    if (( fd )); then 
        cechot "${RED}The lock file $YELLOW'$LCKFILE'$RED could not be"\
               "${RED}created. Exiting."
        return $fd
    fi

    # set complete filename for log, error and cmd files
    LOGFILE="$LOGDIR/log"
    ERRFILE="$LOGDIR/errors"
    CMDFILE="$LOGDIR/commands"

    # create log dir and set access rights
    mkdir -p "$LOGDIR" &&
    chmod go+=rx "$LOGDIR" && 
    touch "$LOGFILE" "$ERRFILE" "$CMDFILE" &&
    chmod go=+r "$LOGFILE" "$ERRFILE" "$CMDFILE"
    ((fd=$?))
    if (( fd )); then
        cechot "${RED}The log directory, $YELLOW'$LOGDIR'$RED, could not be"\
                "${RED}created or set to read & execute or one of"\
                "$YELLOW'$LOGFILE'$RED, $YELLOW'$ERRFILE'$RED or"\
                "$YELLOW'$CMDFILE'$RED, could not be created or set to read."\
                "${RED}Exiting."
        return $fd
    fi

    local srcptn

    # if script is running on dst drive exit with error
    srcptn=$(findmnt -no SOURCE -T "$SCRIPTDIR")
    if [[ "$srcptn" =~ $dstdrv$DP ]]; then
        prompt LOOP "You can't run the $SCRIPTNAME script on the destination drive."
        return $?
    fi

    local msg
    
    # The dst drive can't be the drive that was used to boot the system, as this
    # would destroy the system. This extreme case is possible if:
    # 1. the clone directory is copied to a drive that was not used to boot the
    #    system
    # 2. the script is executed on that drive and the drive that is selected
    #    as destination is the drive that was used to boot the system 
    if [[ "$BOOTPTN" =~ $dstdrv$DP ]]; then
        msg="The destination drive can't be the drive that was used to boot the"
        msg+=" system."
        prompt LOOP "$msg"
        return $?
    fi
    
    # critical section
    (
        if ! flock $fd >> "$LOGFILE" 2>> "$ERRFILE"; then exit 1; fi

        # exit if src or dst drives are currently used as destinations by
        # other clone processes
        for drv in "$srcdrv" "$dstdrv"; do
            script_process=$(grep -E "^[0-9]+_[0-9]+_[0-9]+_$drv$" "$LCKFILE")
            if (( $? == 0 )); then
                cat << error_msg
${RED}A $SCRIPTNAME process with pid $YELLOW$(expr "$script_process" : "^\([0-9]\+\)")
${RED}is currently running and using ${YELLOW}$drv$RED as a destination.
$OFF
error_msg
                exit 1
            fi
        done
        
        declare -i err
        
        chmod go=+r "$LCKFILE" &&  # set access rights of lock file
        echo "$$_${OPTIONS_S}_$dstdrv" >&$fd # add entry to lock file
        ((err=$?))

        echo
        if ((err)); then
            cechot "${RED}The lock file, $YELLOW'$LCKFILE'$RED, could not be set"\
                "${RED}to read or append to. Exiting." | tee -a "$ERRFILE"
            exit 2
        fi
    ) {fd}>> "$LCKFILE" # open for append

    local -i err=$?

    if (( err == 1 )); then
        prompt LOOP;
        return $?
    elif (( err == 2 )); then
        return 1
    fi

    # if this is a dry run append to all log files a dry run message
    if (( dry_run )); then
        local file

        for file in "$CMDFILE" "$ERRFILE" "$LOGFILE"; do
            echo -e "\n\nTHE FOLLOWING WERE APPENDED AS THE SCRIPT WAS RUN\n"\
                    "WITH THE DRY RUN COMMAND LINE OPTION (-r or --dry-run)\n\n"\
                    >> "$file"
        done
    fi
}

# save src & dst drive data based on user input
# return: 0 on success else 1
populate_arrays() {
    echo "Creating internal data structures..."

    local DST_DRV_NAME
    DST_DRV_NAME=$(expr "$(lsblk -dP -o NAME "$dstdrv")" : "^NAME=\"\(.*\)\"$")

    # the following algorithm was found at
    # http://people.redhat.com/msnitzer/docs/io-limits.txt
    # at the bottom of the web page

    ((DST_ALIGN=MIBIBYTE))

    # get alignment offset
    ((start=$(cat /sys/block/"$DST_DRV_NAME"/alignment_offset)))

    # if no alignment offset then get optimal_io_size
    if (( ! start )); then
        ((start=$(cat /sys/block/"$DST_DRV_NAME"/queue/optimal_io_size)))
        (( start )) && ((DST_ALIGN=start))
    fi

    # if no optimal_io_size then get minimum_io_size
    if (( ! start )); then
        start=$(cat /sys/block/"$DST_DRV_NAME"/queue/minimum_io_size)

        local msg
    
        # if minimum_io_size exists return if not power of 2
        if (( start )); then
            if (( $(bc -l <<< "x=l($start)/l(2); scale=0; 2^((x+0.5)/1)") != start ))
            then
                msg="\nThe minimum_io_size is not a power of two: "
                msg+="$YELLOW$start$RED. Exiting."
                stack "$msg"
                return $?
            else
                # if minimum_io_size is a power of 2 set the alignment to 1MiB
                ((start=MIBIBYTE))
            fi
        else
            msg="\nNo alignment boundary was found for drive $YELLOW$dstdrv$RED. "
            msg+="Exiting."
            stack "$msg"
            return $?
        fi
    fi

    local -i page_size
    local -a page_sizes
    local line

    # get page size
    readarray -t page_sizes < <(getconf -a 2>> "$ERRFILE" | grep -iE "pagesize|page_size")
    
    # save page size
    for line in "${page_sizes[@]}"; do
        ((page_size=${line/+([^0-9])}))
        (( page_size )) && break
    done

    # if page size is 0, exit
    if (( ! page_size )); then
        stack "\nPage size is zero. Exiting."
        return $?
    fi

    echo -e "\tGetting drive and partition data for source and destination drives..."

    partitions=()
    ((no_resize=0))
    esp_ptn_nums=()
    boot_ptn_nums=()
    ((bios_ptn=0))
    local -i drv_num     # drive number used as index in associative array
    local -a parted_data # drive data retrieved from 'parted' cmd
    local -i ptn_num
    local -i ptn_cnt
    local -i startb
    local -i end
    local -i size
    local fstype
    local name  # partition name, if any
    local flags # partition flags
    
    # iterate over all drives to get extra data like drive size and partition data
    # THE ORDER OF DRIVE NUMBERS IS IMPORTANT. SOURCE DRIVE NUMBER MUST BE LAST.
    # THIS HELPS TO FACILITATE PROCESSING LATER ON.
    for drv_num in {${OPTIONS[1]},${OPTIONS[0]}}; do
        # The output of the cmd below is something like
        #
        # BYT;
        # /dev/sda:1000204886016B:scsi:512:4096:gpt:ATA TOSHIBA MQ01ABD1:;
        # 1:1048576B:269484031B:268435456B:fat16:efiboot:boot, esp;
        # 2:269484032B:998024151039B:997754667008B:ext4:root:;
        # 3:998024151040B:1000204140543B:2179989504B:linux-swap(v1):swap:;

        # get drive and partition data for a single drive (unit is bytes)
        readarray -t parted_data \
            < <(parted -ms "${drv_data[$drv_num]}" unit $UNIT print 2>> "$ERRFILE")

        ((ptn_num=0))
        ((ptn_cnt=0))
        
        # iterate over drive data
        for line in "${parted_data[@]}"; do
            if [[ "$line" =~ ^/dev/ ]]; then # if drive get its data
                drv_data[$drv_num]+=":"
                drv_data[$drv_num]+=$(field_re "$line" $DSIZE) # size
                drv_data[$drv_num]+=":"
                
                # partition table type
                drv_data[$drv_num]+=$(field "$line" $DPTN_TBL_TYPE)
                
                # sector size in bytes of src drive
                (( drv_num == OPTIONS[0] )) && 
                    ((src_lba=$(field "$line" $DSECTOR_SIZE)))
                    
            # match the format of the first two fields (see above sample cmd
            # output)
            elif [[ "$line" =~ ^[0-9]+:[0-9]+$UNIT ]]; then
                # get partition data
                ((ptn_num=$(field "$line" $PPTN_NUM)))
                ((startb=$(field_re "$line" $PSTART)))
                ((end=$(field_re "$line" $PEND)))
                ((size=$(field_re "$line" $PSIZE)))
                fstype=$(field "$line" $PFSTYPE)
                name=$(field "$line" $PNAME)
                [[ -z "$name" ]] && name=primary
                flags=$(field_re "$line" $PFLAGS "\([^;]*\)")
                
                # add partition data to partitions array
                partitions+=("$drv_num:$ptn_num:$startb:$end:$size:$fstype:$name:$flags:")

                # if src drive get more data
                if (( drv_num == OPTIONS[0] )); then
                    (( ++ptn_cnt ))
                    partitions[-1]+=$ptn_cnt:

                    # add size of partition 1 start byte
                    (( ptn_cnt == 1 )) && ((no_resize+=startb))

                    # add size of swap partitions
                    [[ "$fstype" =~ swap ]] && ((no_resize+=size))
                    
                    # save partition number of ESP partition and add its size
                    if [[ "$flags" =~ esp ]]; then
                        ((no_resize+=size))
                        ((esp_ptn_nums[$ptn_num]=ptn_cnt))
                    fi

                    # save partition number of bios grub partition and add its size
                    if [[ "$flags" =~ bios ]]; then
                        ((no_resize+=size))
                        ((bios_ptn=ptn_num))
                    fi

                    # save partition number of boot partition
                    [[ "$flags" =~ boot ]] && ((boot_ptn_nums[$ptn_num]=ptn_cnt))
                fi
            fi
        done

        # add size of remaining space in src partition
        if (( drv_num == OPTIONS[0] )); then
            if (( ptn_cnt > 0 )); then
                ((no_resize += $(field "${drv_data[$drv_num]}" $DSIZE) - end))
            else
                # exit if no partitions to clone
                cecho -e "\n${RED}Source drive $YELLOW$srcdrv$RED has no"\
                         "${RED}partitions to clone! Exiting." | tee -a "$ERRFILE"
                return 1
            fi
        fi
    done

    readonly LOOP
    readonly OPTIONS OPTIONS_S
    readonly LOGFILE ERRFILE CMDFILE
    readonly SP DP
    readonly DST_DRV_NAME
    readonly START_DATE

    # at this point there is no more looping so read cfg files into memory
    read_cfg
    readonly FILTERS FSTYPES

    # finalize numbers of fields
    ((DPTN_TBL_TYPE=3))
    ((PPTN_NUM+=1))
    ((PSTART+=1))
    ((PEND+=1))
    ((PSIZE+=1))
    ((PFSTYPE+=1))
    ((PNAME+=1))
    ((PFLAGS+=1))
    readonly DPTN_TBL_TYPE PPTN_NUM PSTART PEND PSIZE PFSTYPE PNAME PFLAGS
    readonly DST_ALIGN

    echo -e "\tCalculating partition offset and size for source and destination drives..."

    # total amount of space that can't be resized, i.e. esp, boot, bios and 
    # swap partitions
    local -i no_resize_dst=0
    local -i i
    local ptn
    local -i alignment
    local -i prev_alignment
    local -i sector_size
    alignments=()
    
    # iterate over partitions to align their start offset and size based on
    # partition and filesystem alignment
    for i in "${!partitions[@]}"; do
        ptn="${partitions[i]}"
        
        # extract drive number to find if partition is src or dst
        ((drv_num=$(field "$ptn" $PDRV_NUM)))

        # if src partition then add aligned fields (start offset & size)
        if (( drv_num == OPTIONS[0] )); then
            ((ptn_cnt=$(field "$ptn" $PPTN_CNT))) # extract partition counter

            # add the aligned start offset of the partition as a last field
            if (( ptn_cnt > 1 )); then
                # if previous partition exists the new start offset is the sum
                # of [start offset + size] of previous partition
                partitions[i]="$ptn"
                partitions[i]+=$(( $(field "${partitions[i-1]}" $PALIGN_START) + 
                                   $(field "${partitions[i-1]}" $PALIGN_SIZE) ))
                partitions[i]+=":"
            else
                # the new start offset is the alignment of first partition
                partitions[i]="$ptn"$start:

                # update the byte counter of non-resizable bytes
                ((no_resize_dst+=start))
            fi

            fstype=$(field "$ptn" $PFSTYPE) # extract filesystem type
            flags=$(field "$ptn" $PFLAGS)   # extract partition flags
            
            # get sector size for partition
            ((sector_size=$(get_sector_size)))
            (( sector_size == 1 )) && return $sector_size
            
            # get partition alignment
            ((alignment=$(align_ptn $DST_ALIGN "$fstype" "$flags")))
            
            ((size=$(field "$ptn" $PSIZE)))         # extract partition size
            ((size=$(align_size $size $alignment))) # align partition size

            # if next partition exists
            if (( i+1 < ${#partitions[@]} )); then
                # extract next partition's filesystem type
                fstype=$(field "${partitions[i+1]}" $PFSTYPE)
                
                # extract next partition's flags
                flags=$(field "${partitions[i+1]}" $PFLAGS)
                
                # get sector size for next partition
                ((sector_size=$(get_sector_size)))
                (( sector_size == 1 )) && return $sector_size
                
                ((prev_alignment=alignment))

                # align next partition size
                ((alignment=$(align_ptn $alignment "$fstype" "$flags")))

                # realign existing partition size to next partition's 
                # filesystem alignment
                ((size=$(realign_size $(field "${partitions[i]}" $PALIGN_START) \
                                      $size $prev_alignment $alignment)))
            fi

            ((ptn_num=$(field "$ptn" $PPTN_NUM))) # extract partition number

            # add partition alignment to array in case partition needs to be
            # resized
            ((alignments[$ptn_num]=alignment))

            # add the newly aligned size as a last field to the existing
            # partition data
            partitions[i]+=$size

            # if swap, esp or bios, update the byte counter of non-resizable bytes
            [[ "$(field "$ptn" $PFSTYPE)" =~ swap || \
               "$(field "$ptn" $PFLAGS)" =~ esp   || \
               "$(field "$ptn" $PFLAGS)" =~ bios ]] && 
                ((no_resize_dst+=size))
        fi
    done

    local -i dst_postamble

    # get number of sectors to exclude from the end of the dst drive
    (( src_lba *= $(gdisk -l "$srcdrv" | grep "First usable sector is" | 
                                         cut -f 1 -d "," | cut -f 5 -d " ") ))

    # get total size of dst drive
    (( dst_drv_size = $(field "${drv_data[${OPTIONS[1]}]}" $DSIZE) ))

    # add dst postamble space to dst non-resizable space
    (( dst_space_avail = dst_drv_size - no_resize_dst ))
    (( dst_postamble = dst_space_avail - (dst_space_avail / DST_ALIGN) * DST_ALIGN ))
    (( dst_postamble < src_lba )) && (( dst_postamble = src_lba ))
    (( no_resize_dst += dst_postamble ))
    (( dst_space_avail -= dst_postamble ))

    # make sure that all partitions on src fit on dst
    if (( dst_drv_size - no_resize_dst <= 0 )); then
        cecho -e "\n${RED}Destination partition size ($YELLOW$dst_drv_size$RED)"\
                 "${RED}< source partition size ($YELLOW$no_resize_dst$RED)."\
                 "${RED}Exiting." | tee -a "$ERRFILE"
        return 1
    fi
    echo
}

# mask system sleep (suspend/hibernate) if it is unmasked
# return: 0 on success, 1 if parameter error else the error code of the cmd that
#         failed
mask_system_sleep() {
    valid_opt_param "$1" # validate parameter
    
    # some other clone process has completed or was interrupted and sent signal
    # USR1 so that this process can handle masking/unmasking system sleep 
    if (( $# == 1 )); then
        # sync and restore stdout and stderr to the terminal
        sync
        exec &> /dev/tty
    fi  

    local -i fd

    exec {fd}>>"$SLPFILE" # append to the system sleep lock file
    
    # critical section follows
    flock $fd >> "$LOGFILE" 2>> "$ERRFILE"

    local -i err=$?

    if (( ! err )); then
        local SEP="//"
        readonly SEP
        
        # mask system sleep if no other clone process already has
        if [[ ! -s "$SLPFILE" ]]; then
            local -a cmds

            # add cmds to mask system sleep
            system_sleep cmds "mask"
            if (( ${#cmds[@]} )); then
                if (( $# == 1 )); then
                    cecho -e "\n\nReceived signal from another $SCRIPTNAME"\
                             "process to disable/enable system sleep"\
                             "(suspend/hibernate)..."
                else
                    echo "Disabling system sleep (suspend/hibernate)..."
                fi
                
                cmds+=("chmod go=+r $SLPFILE")
                exec_cmds "${cmds[@]}"
                ((err=$?))

                # add entry to system sleep lock file
                if (( ! err )); then
                    echo "$$_$OPTIONS_S" >&$fd
                    echo -n "$SLP_CFG_MNT_DIR $SEP " >&$fd
                    echo "${rsync_filters[$SLP_CFG_MNT_DIR]}" >&$fd
                fi
            fi
        else
            # add rsync filters to exclude system sleep target files
            system_sleep "filter"
        fi

        (( ! err )) &&
            trap_signals "mask_system_sleep 1" USR1 # signal handler for USR1

        flock -u $fd # release lock
    fi
    exec {fd}>&- # close sleep lock file
    
    (( $# == 1 )) &&
        if (( err )); then
            cecho -e "${RED}Disabling system sleep (suspend/hibernate) was"\
                     "${RED}unsuccessful.\n"
            cleanup 1
        else
            cecho -e "${GREEN}System sleep (suspend/hibernate) was disabled"\
                     "${GREEN}successfully.\n"
        fi

    return $err
}

# calculate available drive space on dst and subtract any exlcuded dirs/files in
# case dst_size < src_size
# return: 0 on success else 1
calc_drvspace() {
    echo "Calculating available space on destination drive..."
    echo -e "\tTesting that source drive partitions have UUIDs..."

    local ptn
    local -i drv_num
    local fstype
    local -i ptn_num
    local flags    
    local srcmnt
    local -a mount_points=()
    local -i err

    # get mount points for src partitions
    for ptn in "${partitions[@]}"; do
        # extract drive number to find if partition is src or dst
        ((drv_num=$(field "$ptn" "$PDRV_NUM")))
        fstype=$(field "$ptn" "$PFSTYPE")           # extract filesystem type
        
        if (( drv_num == OPTIONS[0] )); then        # if is src partition
            ((ptn_num=$(field "$ptn" "$PPTN_NUM"))) # extract partition number
            flags=$(field "$ptn" "$PFLAGS")         # extract flags
            
            # mount all src partitions other than swap and bios_grub
            if [[ ! "$fstype" =~ swap && ! "$flags" =~ bios ]]; then
                # mount src partition
                mount_ptn "$srcdrv$SP"$ptn_num srcmnt
                ((err=$?))
                if ((err)); then
                    # unmount src partitions that were mounted
                    for ptn in "${mount_points[@]}"; do umount_ptn "$ptn"; done
                    return $err
                fi

                mount_points+=("$srcmnt")
                
                # return if any src partition does not have UUID
                flags=$(lsblk -no UUID "$srcdrv$SP$ptn_num" 2>> "$ERRFILE")
                if [[ -z "$flags" ]]; then
                    cecho -e "\n${RED}The $YELLOW$srcdrv$SP$ptn_num$RED source"\
                             "${RED}partition mounted on"\
                             "$YELLOW$(field "$srcmnt" "$MDIR")${RED} does not"\
                             "${RED}have a UUID. Exiting." | tee -a "$ERRFILE"
                    return 1
                fi
            fi
        fi
    done

    echo -e "\tGetting total data size on source drive..."
    
    # get the total data size on src
    src_ptn_data=()
    readarray -t src_ptn_data < <(df -ak --sync --output=source,used,pcent | \
                                  grep "$srcdrv" | sort -u)

    local -i used
    local -i CONVERSION_UNIT=1024
    readonly CONVERSION_UNIT

    # add src bios partition
    if (( bios_ptn )); then
        (( used = $(lsblk -nb -o SIZE "$srcdrv$SP$bios_ptn") / CONVERSION_UNIT ))
        src_ptn_data+=("$srcdrv$SP$bios_ptn $used 0%")
    fi

    local i
    local -i src_data_size=0
    local source
    local pcent
    local -i total_pcent=0

    # save src partition data and calculate totals
    for i in "${!src_ptn_data[@]}"; do
        # remove whitespace
        src_ptn_data[i]=$(echo "${src_ptn_data[i]}" | xargs)
        source=$(field "${src_ptn_data[i]}" "$SOURCE" ' ')
        (( used = $(field "${src_ptn_data[i]}" "$USED" ' ') * CONVERSION_UNIT ))
        (( ptn_num = 0 ))
        for ptn_num in "${!esp_ptn_nums[@]}"; do
            if [[ "$source" == "$srcdrv$SP$ptn_num" ]]; then
                pcent=0
                break
            fi
        done
        if [[ ! "$source" == "$srcdrv$SP$ptn_num" ]]; then
            pcent=$(field "${src_ptn_data[i]}" "$PCENT" ' ')
            pcent="${pcent/'%'}"
        fi
        src_ptn_data[i]="$source $used $pcent"
        (( total_pcent += pcent ))
        (( src_data_size += used ))
    done

    ((clone_size=src_data_size))

    # normalize percentages
    for i in "${!src_ptn_data[@]}"; do
        pcent=$(field "${src_ptn_data[i]}" "$PCENT" ' ')
        pcent=$(bc <<< "scale=5; $pcent / $total_pcent")
        src_ptn_data[i]="${src_ptn_data[i]%' '[0-9]*} $pcent"
    done

    echo -e "\tUnmounting any source partitions that were mounted..."

    # unmount src partitions that were mounted
    for ptn in "${mount_points[@]}"; do
        umount_ptn "$ptn"
        ((err=$?)); ((err)) && return $err
    done

    echo -e "\n\tChecking files/directories excluded from source drive..."

    local -a paths # the paths of an rsync filter
    local j
    local k
    local -a next_entries # files matching an rsync filter
    local srcptn
    local -A filters=() # key: rsync filter
                        # val: indices of array that stores rsync filter contents
    local -A user_filters=() # key: rsync filter
                             # val: user defined filter in $FILTERS_FILE file
    local -i match
    local -a entries=() # files matching all rsync filters
    local buf
    local -a abuf
    local MSG="Check the '$FILTERS_FILE' file"
    readonly MSG
    
    for buf in "${FILTERS[@]}"; do
        # split line into paths
        ((j=0))
        paths=()
        for (( i = 0; i < ${#buf}; ++i )); do
            if [[ "${buf:i:1}" != [[:blank:]] ]]; then
                # remove redundant '/' and '*'
                if [[ ("${buf:i:1}" != "*" && "${buf:i:1}" != "/") || \
                      "${buf:i:1}" != "${buf:i-1:1}" ]]
                then
                    paths[j]+="${buf:i:1}"
                fi
            else
                if [[ "${paths[j]:${#paths[j]}-1:1}" == '\' ]]; then
                    paths[j]+="${buf:i:1}"
                else
                    ((++j))
                    while [[ "${buf:i:1}" == [[:blank:]] ]]; do ((++i)); done
                    ((--i))
                fi
            fi
        done

        buf="$CYAN'${paths[*]}'$YELLOW has wrong syntax and will be omitted. "
        buf+="$MSG for correct syntax."

        # For valid entries see '$FILTERS_FILE' file.
        case ${#paths[@]} in
            1) [[ ! "${paths[*]}" =~ ^[-+]/.+$ ]] && 
                   { cechot "$buf"; continue; }
            ;;            
            2) [[ ! "${paths[*]}" =~ ^[-+]/.*\ [^/].*$ ]] && 
                   { cechot "$buf"; continue; }
            ;;
            *) cechot "$buf"; continue ;;
        esac

        # Check if pathname is on src drive. 'paths' may include spaces so use
        # 'eval' to treat it as a single argument. Also, use 'dirname' in case
        # 'paths' includes a pattern that will expand to more than one entry.
        srcptn=$(eval findmnt -no SOURCE -T "$(dirname "${paths[0]:1}")")

        if (( $? )); then
            cechot "$CYAN'${paths[*]}'$YELLOW does not exist and will be omitted."\
                   "$MSG."
            continue
        fi

        # skip files/dirs not on source drive. e.g. virtual file systems like
        # /sys, /proc, etc
        if [[ "${srcptn::1}" != "/" ]]; then
            if [[ ${paths[0]::1} == "+" ]]; then
                cechot "$CYAN'${paths[*]}'$YELLOW is not on the source drive"\
                       "and it's an include entry which is not valid. $MSG."
            elif [[ "$BOOTPTN" =~ $srcdrv$SP ]]; then
                add_filter filters user_filters paths
            else                
                cechot "$CYAN'${paths[*]}'$YELLOW exists but not on the source"\
                       "drive and will be omitted. $MSG."
            fi
            continue

        # if paths are not on src drive, skip them
        elif [[ ! "$srcptn" =~ $srcdrv$SP ]]; then
            cechot "$CYAN'${paths[*]}'$YELLOW exists but not on the source drive"\
                   "and will be omitted. $MSG."
            continue

        # any paths that start with the following must be excluded
        elif [[ "${paths[0]:1}" =~ ^(/media|/mnt) ]]; then
            for buf in -/media/* -/mnt/*; do
                paths=("$buf")
                add_filter filters user_filters paths
            done
            continue
        fi

        # get file(s) and/or directories
        if (( ${#paths[@]} == 2 )); then
            # iterate over relative path that will be tokenized based on '/' and
            # passed as a parameter to 'find' cmd
            ((j=0))
            for (( i = 0; i < ${#paths[1]}; ++i )); do
                if [[ "${paths[1]:$i:1}" == "/" ]]; then # get path up to '/'
                    if (( j )); then
                        get_entries next_entries "-type d"
                    else
                        # 'paths' may include spaces so use 'eval' to treat
                        # each path as a single argument
                        readarray -td '' next_entries < <(eval \
                                                          find "${paths[0]:1}" \
                                                               -name "${paths[1]:$j:$i-$j}" \
                                                               -type d \
                                                               -print0 2>> "$ERRFILE")
                    fi
                    (( ! ${#next_entries[@]} )) && break # break if no results
                    ((j=i+1))
                fi
            done
        
            # all tokens of path delimited by '/' were processed except last
            # token which is not delimited
            if (( j && j < i && ${#next_entries[@]} )); then
                get_entries next_entries
            elif (( ! j && i == ${#paths[1]} )); then
                # 'paths' may include spaces so use 'eval' to treat each path
                # as a single argument
                readarray -td '' next_entries < <(eval \
                                                  find "${paths[0]:1}" \
                                                       -name "${paths[1]}" \
                                                       -print0 2>> "$ERRFILE")
            fi
        else
            # 'paths' may include spaces so use 'eval' to treat each path as a
            # single argument
            readarray -td '' next_entries < <(eval \
                                              find "${paths[0]:1}" -maxdepth 0 \
                                                   -print0 2>> "$ERRFILE")
        fi
            
        # read next if file(s) and/or dir(s) don't exist
        if (( ! ${#next_entries[@]} )); then
            cechot "$CYAN'${paths[*]}'$YELLOW does not exist and will be omitted."\
                   "$MSG."
            continue
        fi

        # check if the filter has been processed already
        ((match=0))
        for k in "${!user_filters[@]}"; do
            # if new path is an existing filter, skip it
            if [[ "${paths[*]}" == "${user_filters["$k"]}" ]]; then
                cechot "$CYAN'${paths[*]}'$YELLOW is listed more than once"\
                        "and will be omitted. $MSG."
                ((match=1))
                break
            fi
            
            # compare exclude filters
            if [[ "${paths[0]::1}" == "-" && \
                    "${paths[0]::1}" == "${k::1}" ]]
            then
                # if existing filter "fits" into new filter, skip new
                if [[ "${user_filters["$k"]: -1}" == "/" && \
                        "${paths[*]}" =~ "${user_filters["$k"]}" ]]; then
                    cechot "$CYAN'${paths[*]}'$YELLOW is under"\
                           "$CYAN'${user_filters["$k"]}'$YELLOW and will be"\
                           "omitted. $MSG."
                    ((match=1))
                    break
                fi
                
                # if new filter is dir and "fits" into existing
                # filter, remove existing
                ((i=${#paths[@]}))
                if [[ "${paths[i-1]: -1}" == "/" && \
                        "${user_filters["$k"]}" =~ "${paths[*]}" ]]; then
                    cechot "$CYAN'${user_filters["$k"]}'$YELLOW is under"\
                           "$CYAN'${paths[*]}'$YELLOW and will be omitted. $MSG."
                    for i in ${filters["$k"]}; do # remove filter entries
                        unset entries[i]
                    done
                    
                    # remove rsync & user filters
                    unset filters["$k"] user_filters["$k"]
                fi                    
            fi
        done 
        (( match )) && continue

        for i in "${!next_entries[@]}"; do    
            # add a backslash to each directory
            [[ "${next_entries[i]: -1}" != "/" && -d "${next_entries[i]}" ]] &&
                next_entries[i]+="/"

            next_entries[i]="${paths[0]::1}${next_entries[i]}" # add the sign
        done

        ((j=${#next_entries[@]})) # get new offset for entries
        if (( j )); then
            if (( ${#entries[@]} )); then
                abuf=("${!entries[@]}") # get indices
                ((i=abuf[-1]+1)) # get next index of entries
            else
                ((i=0))
            fi
        
            buf=$(seq $i $((i+j-1)) | xargs)

            # add a space in the end so that all numbers are followed by it
            add_filter filters user_filters paths "$buf "

            entries+=("${next_entries[@]}") # add next entries to existing
        fi
    done

    next_entries=() # release some memory

    local -A matched=() # key: [<filter_idx1>,<filter_idx2>]
                        # val: indices of matched entries
    local -i under

    for i in "${!entries[@]}"; do         # match entries
        [[ ! -v entries[i] ]] && continue # skip if unset
        
        ((match=0))
        for j in "${!entries[@]}"; do
            # check if an entry is under another
            if [[ "${entries[i]:1}" == "${entries[j]:1}" || \
                  ("${entries[j]: -1}" == "/" && \
                   "${entries[i]:1}" =~ "${entries[j]:1}") ]]
            then
                ((under=1))
            else
                ((under=0))
            fi
            
            # match entries that cancel out each other, i.e. include/exclude
            # entries
            if [[ "${entries[i]::1}" == '+' && "${entries[j]::1}" == '-' && \
                  $under -eq 1 ]]
            then
                [[ "${entries[i]:1}" == "${entries[j]:1}" ]] &&
                    add_match "$i" "$j" matched
                ((match=1))

            # match entries that are equal or under others, i.e.
            # include/include or exclude/exclude entries
            elif [[ (("${entries[i]::1}" == '+' && \
                      "${entries[j]::1}" == '+' && $j -ne $i) || \
                     ("${entries[i]::1}" == '-' && \
                      "${entries[j]::1}" == '-' && $j -ne $i)) && \
                    $under -eq 1 ]]
            then
                add_match "$i" "$j" matched
            fi
        done

        # in case include entry not matched by an exclude one, remove it
        if [[ "${entries[i]::1}" == '+' && $match -eq 0 ]]; then
            get_filter_data "$i" k j

            update_matched "$j" matched # update matched entries

            for j in ${filters["$k"]}; do # remove filter entries
                unset entries[j]
            done

            buf="$CYAN'${user_filters["$k"]}'$YELLOW is not under an "
            buf+="exclude entry and will be omitted. $MSG."               

            # remove rsync & user filters
            unset filters["$k"] user_filters["$k"]
            cechot "$buf"                
        fi
    done

    local sign

    # store matched filters, i.e. include and exclude filters that cancel out
    # each other, or filters that are equal or under others
    if (( ${#matched[@]} )); then
        local -A matched_processed=()
        local f
        local rm_entries
        local -A removed_entries
        local -a matched_filters
        local -A filters_rm=() # filters to remove

        # iterate over matched filters and store all that need to be removed
        for i in "${!matched[@]}"; do
            [[ -v matched_processed[$i] ]] && continue # skip already processed
            
            get_filter "${i/,+([0-9])}" k # get filter for 1st idx            
            get_filter "${i/+([0-9]),}" f # get filter for 2nd idx

            rm_entries="entries removed_entries"
            if [[ ${k::1} != "${f::1}" ]]; then # this is a tuple
                # set function to remove matched filter tuple entries
                rm_entries="rm_tuple_entries $rm_entries matched_filters"
            else # both filters are includes or excludes
                # set function to remove matched filter entries
                rm_entries="rm_filter_entries $rm_entries"
                buf=" is under "
            fi

            removed_entries=()
            matched_filters=()
            if $rm_entries; then # remove matched entries
                # set user message if both filters are includes or excludes
                [[ ${k::1} == "${f::1}" ]] &&
                    buf="$buf$CYAN'${user_filters["$f"]}'$YELLOW"
                ((match=1))
            else
                ((match=0))
            fi

            matched_processed[$i]= # add processed matched pair of indices
                        
            # find filters that match the filter with 1st idx
            sign="${f::1}"
            for j in "${!matched[@]}"; do
                # allow self only and different 2nd idx than the one used above
                (( ${j/,+([0-9])} != ${i/,+([0-9])} || \
                   ${j/+([0-9]),} == ${i/+([0-9]),} )) && 
                    continue
                                
                # get filter for 2nd idx
                get_filter "${j/+([0-9]),}" f

                # process filter with the same sign as the previous one
                [[ ${f::1} != "$sign" ]] && continue

                if $rm_entries; then # remove matched entries
                    # set user message if both filters are includes or excludes
                    if [[ ${k::1} == "${f::1}" ]]; then
                        if (( match )); then
                            buf+=" and $CYAN'${user_filters["$f"]}'$YELLOW"
                        else
                            buf="$buf$CYAN'${user_filters["$f"]}'$YELLOW"
                        fi
                    fi
                    ((match=1))
                fi

                matched_processed[$j]= # add processed matched pair of indices
            done

            # print matched filters and store them for removal
            if (( match )); then
                filters_rm[$k]= # store filter for removal
                if [[ ${k::1} != "$sign" ]]; then
                    # set user message
                    buf="$CYAN'${user_filters["$k"]}'$YELLOW"
                    for f in "${matched_filters[@]}"; do
                        buf+=" and $CYAN'${user_filters["$f"]}'$YELLOW"
                        filters_rm[$f]= # store filter for removal
                    done
                    cechot "$buf cancel out each other and will be omitted. $MSG."
                else
                    buf="$CYAN'${user_filters["$k"]}'$YELLOW$buf"
                    cechot "$buf and will be omitted. $MSG."
                fi
            fi                
        done

        # remove matched filters, i.e. include and exclude filters that cancel
        # out each other, or filters that are equal or under others
        for k in "${!filters_rm[@]}"; do 
            unset filters["$k"] user_filters["$k"] # remove rsync & user filters
        done        
    fi

    # reorder user filters storing the includes first
    abuf=()
    for buf in "${user_filters[@]}"; do
        if [[ "${buf::1}" == "+" ]]; then
            abuf=("${OFF}Include$YELLOW in cloning  : $CYAN${buf:1}" "${abuf[@]}")
        else
            abuf+=("Exclude from cloning: $CYAN${buf:1}")
        fi
    done
        
    (( ${#abuf[@]} )) && echo
    for buf in "${abuf[@]}"; do # print reordered user filters
        cechot "$buf"
    done
    
    local -i exc_size
    local -i total_exc_size=0

    # calculate total size of excluded/included files/dirs
    for buf in "${entries[@]}"; do
        sign="${buf::1}"
        sign+="1"
        buf="${buf:1}"

        exc_size=$(du -sB1 "$buf" 2>> "$ERRFILE" | xargs 2>> "$ERRFILE" \
                                                 | cut -f 1 -d ' ')
        ((exc_size*=-1*sign))
        if (( exc_size )); then
            ((total_exc_size+=exc_size))

            srcptn=$(findmnt -no SOURCE -T "$buf")

            # remove the total size calculated above from the size of the
            # partiton the directory is on
            (( ! $? )) &&
                for i in "${!src_ptn_data[@]}"; do
                    source=$(field "${src_ptn_data[i]}" "$SOURCE" ' ')
                    if [[ "$source" == "$srcptn" ]]; then
                        (( used = $(field "${src_ptn_data[i]}" "$USED" ' ') - exc_size ))
                        pcent=$(field "${src_ptn_data[i]}" "$PCENT" ' ')
                        src_ptn_data[i]="$source $used $pcent"
                        break
                    fi
                done
        fi
    done

    ((clone_size-=total_exc_size))

    local -a sizes=("$src_data_size" "$total_exc_size" "$clone_size")
    sizes+=("$dst_drv_size")
    
    # convert sizes to appropriate units, e.g. GB, MB, etc.
    for i in "${!sizes[@]}"; do 
        convert_size sizes[i]
    done

    cecho -e "\n\tData size on source drive: ${OFF}${sizes[0]}$YELLOW."
    if (( total_exc_size )); then
        cechot "Data size of excluded directories and/or files on source drive:"\
               "${CYAN}${sizes[1]}$YELLOW."
        cechot "Total data size to be cloned from source drive:"\
               "$OFF${sizes[0]} - $CYAN${sizes[1]}$OFF = ${sizes[2]}$YELLOW."
    fi
    cechot "Total space on destination drive: $OFF${sizes[3]}$YELLOW."
    if (( clone_size > dst_drv_size )); then
        cechot "${RED}Data on source drive does not fit on destination drive"\
               "${RED}($YELLOW${sizes[2]} > ${sizes[3]}$RED). Exiting."\
               | tee -a "$ERRFILE"
        return 1
    else
        cechot "${GREEN}Data on source drive (${OFF}${sizes[2]}$GREEN) fits"\
               "${GREEN}on destination drive (${OFF}${sizes[3]}$GREEN). Proceeding..."
    fi
    echo

    # iterate over filters (first the include ones) and add them to the 
    # corresponding partition
    local srcmnt_dir

    for k in "${!filters[@]}"; do
        sign="${k::1}"
        k="${k:1}"

        # use 'dirname' in case 'k' includes a pattern that will expand to more
        # than one entry.        
        buf=$(dirname "$k")
        
        # get source partition for the filter
        while true; do
            # use 'eval' to treat filter as a single argument in case it
            # includes spaces
            srcptn=$(eval findmnt -no SOURCE -T "$buf")
            if (( $? )); then
                if [[ "$buf" == "/" ]]; then
                    cecho "No souce partition found for '$k'. Exiting."\
                          | tee -a "$ERRFILE"
                    return 1
                else
                    buf=$(dirname "$buf" | tail -1)
                fi
            else
                break            
            fi
        done
        
        if [[ "${srcptn::1}" != "/" ]]; then
            srcmnt_dir="/"
        else
            srcmnt_dir=$(lsblk -no MOUNTPOINT "$srcptn")
        fi

        k="${k//'"'/'\"'}" # escape double quotes
        
        # rsync uses the first filter it encounters to exclude/include
        # files/dirs therefore, the include filters must be first
        if [[ $sign == "+" ]]; then
            [[ "$k" =~ "/**/" ]] && 
                rsync_filters[$srcmnt_dir]="-f \"$sign ${k/'**/'}\" ${rsync_filters["$srcmnt_dir"]} "
            rsync_filters[$srcmnt_dir]="-f \"$sign $k\" ${rsync_filters["$srcmnt_dir"]} "
        else
            [[ "$k" =~ "/**/" ]] && 
                rsync_filters[$srcmnt_dir]+="-f \"$sign ${k/'**/'}\" "
            rsync_filters[$srcmnt_dir]+="-f \"$sign $k\" "
        fi
    done
}

# if necessary remove & create new partitions on dst
# return: 0 on success else the error code of the cmd that failed
create_partitions() {            
    echo "Checking partitions on destination drive..."
    echo -e "\tGetting source partition table type..."
    
    # extract src partition table type
    local ptn_tbl
    ptn_tbl=$(field "${drv_data[${OPTIONS[0]}]}" "$DPTN_TBL_TYPE")

    # if partition table on dst != src mark dst for wipe
    [[ "$ptn_tbl" != $(field "${drv_data[${OPTIONS[1]}]}" "$DPTN_TBL_TYPE") ]] && 
        ((create_ptn=1))

    local -i i
    local -i SRC_DRV_SIZE
    SRC_DRV_SIZE=$(field "${drv_data[${OPTIONS[0]}]}" "$DSIZE")
    readonly SRC_DRV_SIZE
    local ptn
    local -i ptn_num
    local -i resize_for_data=0
    local -i drv_num
    local flags
    local fstype
    local -i bytes
    local -i src_ptn_data_size=0
    local -i dst_space_left=0
    
    if (( dst_drv_size < SRC_DRV_SIZE )); then
        # update clone size if dst partition size is based on src partition
        # data size
        for i in "${!src_ptn_data[@]}"; do
            ptn=$(field "${src_ptn_data[i]}" "$SOURCE" ' ')
            for ptn_num in "${!esp_ptn_nums[@]}"; do
                if [[ "$ptn" == "$srcdrv$SP$ptn_num" ]]; then
                    (( clone_size -= $(field "${src_ptn_data[i]}" "$USED" ' ') ))
                    break
                fi
            done
            [[ "$ptn" == "$srcdrv$SP$bios_ptn" ]] &&
                (( clone_size -= $(field "${src_ptn_data[i]}" "$USED" ' ') ))
        done

        # normally, the following code should be within the above loop but
        # there's no guarantee that the ESP will be before any other partitions
        # except the bios one
        for i in "${!src_ptn_data[@]}"; do
            if (( resize_for_data )); then
                break
            else
                # check if dst partition size is based on src partition data
                # size
                for ptn in "${partitions[@]}"; do
                    # extract drive number to find if partition is src or dst
                    ((drv_num=$(field "$ptn" "$PDRV_NUM")))

                    # if src partition
                    if (( drv_num == OPTIONS[0] )); then
                        flags=$(field "$ptn" "$PFLAGS")   # extract partition flags
                        fstype=$(field "$ptn" "$PFSTYPE") # extract filesystem type

                        # all partitions except esp, bios & swap can be resized
                        if [[ ! "$flags" =~ esp && ! "$flags" =~ bios && \
                              ! "$fstype" =~ swap ]]
                        then
                            get_ptn_size bytes # get ptn size in bytes variable

                            # get data size of src partition
                            ((src_ptn_data_size=$(field "${src_ptn_data[i]}" "$USED" ' ')))

                            # calculate space left on dst if dst partition size
                            # is based on src partition data size
                            if (( src_ptn_data_size > bytes )); then
                                (( dst_space_left = dst_space_avail - clone_size ))
                                (( resize_for_data = 1 ))
                                break
                            fi
                        fi
                    fi
                done
            fi
        done
    fi

    local name
    local -i ptn_cnt
    local pct
    local cmd
    local -i alloc_bytes=0
    local -i end
    local -i ptn_tbl_flag=0
    local -a cmds=() # contains cmds to create partitions on dst
    local flag
    local dst_ptn
    local -a dst_ptns=()
    local -i j=0

    # iterate over all partitions to create cmds that delete and create
    # partitions on dst if necessary
    for ptn in "${partitions[@]}"; do
        # extract drive number to find if partition src or dst
        ((drv_num=$(field "$ptn" "$PDRV_NUM")))
        ((ptn_num=$(field "$ptn" "$PPTN_NUM"))) # extract partition number
        fstype=$(field "$ptn" "$PFSTYPE")       # extract filesystem type
        
        # if src partition, create cmds that:
        #     create new partition table
        #     create new partitions
        #     format new partitions
        if (( drv_num == OPTIONS[0] )); then
            name=$(field "$ptn" "$PNAME")           # extract partition name
            flags=$(field "$ptn" "$PFLAGS")         # extract partition flags
            ((ptn_cnt=$(field "$ptn" "$PPTN_CNT"))) # extract partition counter

            # all partitions except esp, bios & swap can be resized
            if [[ ! "$flags" =~ esp && ! "$flags" =~ bios && ! "$fstype" =~ swap ]]
            then
                # dst ptn size is calculated based on src ptn data size
                if (( resize_for_data )); then
                    ((src_ptn_data_size=0))
                    for i in "${!src_ptn_data[@]}"; do
                        if [[ "$(field "${src_ptn_data[i]}" "$SOURCE" ' ')" == \
                              "$srcdrv$SP$ptn_num" ]]
                        then
                            # get data size of src partition
                            ((src_ptn_data_size=$(field "${src_ptn_data[i]}" "$USED" ' ')))

                            # get the percentage of scr drive partition data
                            pct=$(field "${src_ptn_data[i]}" "$PCENT" ' ')

                            # calculate the bytes of the percentage above for
                            # space left on dst
                            cmd='{printf "%.0f", ($1 * $2 == int($1 * $2)) '
                            cmd+='? $1 * $2 : int($1 * $2) + 1}'
                            pct=$(awk "$cmd" <<< "$pct $dst_space_left")

                            # dst partition size = src partition data size +
                            #                      percentage of space left on dst
                            ((bytes=src_ptn_data_size+pct))
                            break
                        fi
                    done
                # dst ptn size is calculated based on percentage of src ptn size
                # with respect to src drive size
                else
                    get_ptn_size bytes # get ptn size in bytes variable
                fi

                # align partition size
                ((bytes=$(align_size $bytes "${alignments[$ptn_num]}")))

                # if next partition exists, align existing partition to next
                # partition's filesystem alignment
                if (( ptn_cnt < ${#alignments[@]} )); then
                    ((bytes=$(realign_size "$start" $bytes "${alignments[$ptn_num]}" \
                                           "${alignments[$((ptn_num+1))]}")))
                fi
            else
                # extract src partition size in bytes
                ((bytes=$(field "$ptn" "$PALIGN_SIZE")))
            fi

            # if partition is last one, check that it fits on remaining space
            (( ptn_cnt == ${#alignments[@]} )) &&
                while (( start + bytes - 1 > dst_drv_size - src_lba )); do
                    ((bytes-=alignments[$ptn_num]))
                done

            # update allocated space for dst drive
            (( resize_for_data )) && ((alloc_bytes+=bytes))

            ((end=start+bytes-1)) # set the end byte for the partition

            # create 'mktable' cmd (executed once only)
            if (( ! ptn_tbl_flag )); then
                cmds+=("wipefs --all --force '$dstdrv'")
                cmds+=("parted --script --fix '$dstdrv' mktable '$ptn_tbl'")
                ((ptn_tbl_flag=1))
            fi

            # create 'mkpart' cmd for new partition
            if [[ "$fstype" ]]; then
                cmd="parted --script --fix -a optimal '$dstdrv' unit $UNIT mkpart "
                cmd+="primary '$fstype' $start $end"
                cmds+=("$cmd")
            else
                cmd="parted --script --fix -a optimal '$dstdrv' unit $UNIT mkpart "
                cmd+="primary $start $end"
                cmds+=("$cmd")
            fi
            [[ "$name" && "$ptn_tbl" != "msdos" ]] &&
                cmds+=("parted --script --fix '$dstdrv' name $ptn_cnt \"$name\"")

            # check partition alignment
            cmds+=("parted --script --fix '$dstdrv' align-check opt $ptn_cnt")

            # create set cmds to set partition flags
            ((i=1))
            flag=$(field "$flags" $i ',' | xargs)
            while [[ "$flag" ]]; do
                cmds+=("parted --script --fix '$dstdrv' set $ptn_cnt '$flag' on")
                ((++i))
                flag=$(field "$flags" $i ',' | xargs)
            done

            # create cmds to format the partition
            # get filesystem cmd that applies to partition fstype
            for cmd in "${FSTYPES[@]}"; do
                if [[ "$fstype" && "$cmd" =~ $fstype ]]; then
                    # create cmd to format the newly created partition
                    cmds+=("$(field "$cmd" 2) '$dstdrv$DP$ptn_cnt'")
                    break
                fi
            done

            # compare src and dst partition data and if different set flag
            (( ! create_ptn )) &&
                if (( ${#dst_ptns[@]} > j )); then
                    flags=$(rm_lba_flag "$ptn_tbl" "$flags")
                    dst_ptn="$name$fstype$start$end$flags"
                    dst_ptn=$(echo "$dst_ptn" | xargs) # remove whitespace

                    [[ "$dst_ptn" != "${dst_ptns[j]}" ]] && ((create_ptn=1))
                    ((++j))
                else
                    ((create_ptn=1)) # src has more partitions than dst
                fi

            ((start=end+1)) # update start byte for next partition
        else
            # to remove swap partition it has to be off first
            [[ "$fstype" =~ swap ]] && 
            swapon | grep -q "$dstdrv$DP$ptn_num" 2>> "$ERRFILE" &&
            cmds+=("swapoff '$dstdrv$DP$ptn_num'")            

            # this is a dst partition therefore, create cmds to delete it
            cmds+=("wipefs --all --force '$dstdrv$DP$ptn_num'")
            cmds+=("parted --script --fix '$dstdrv' rm $ptn_num")

            # add dst partition data to array to compare it with src partition
            # data (dst partitions are first in array)
            if (( ! create_ptn )); then
                flags=$(field "$ptn" "$PFLAGS")
                flags=$(rm_lba_flag "$ptn_tbl" "$flags")

                # get dst partition data as "$name$fstype$start$end$flags"
                dst_ptn=$(field "$ptn" "$PNAME")$(field "$ptn" "$PFSTYPE")
                dst_ptn+=$(field "$ptn" "$PSTART")$(field "$ptn" "$PEND")$flags
                dst_ptn=$(echo "$dst_ptn" | xargs) # remove whitespace
                dst_ptns+=("$dst_ptn")
            fi
        fi
    done

    # if src and dst partitions are different create dst partitions
    if (( create_ptn )); then
        echo -e "\n\tCreating partitions on destination drive..."

        # get partitions on dst
        local -a ptns_umount
        mapfile -t ptns_umount < <(findmnt -An -o SOURCE | grep "$dstdrv")
        
        # create cmds to unmount dst partitions
        local -a cmds_umount=()
        for ptn in "${ptns_umount[@]}"; do
            umount_cmd "$ptn" cmds_umount
        done

        # add unmount cmds to cmds and execute all
        (( "${#cmds_umount[@]}" )) && cmds=("${cmds_umount[@]}" "${cmds[@]}")
        exec_cmds "${cmds[@]}"
    else
        echo
    fi
}

# find mount points for src and dst partitions and then clone files for each
# dst partition
# return: 0 on success, 1 if a function failed else the error code of the cmd
#         that failed
clone() {
    echo "Cloning..."
    echo -e "\tMounting partitions for source & destination drives if not mounted already..."

    local ptn
    local -i drv_num
    local fstype
    local flags
    local -i ptn_num
    local -i ptn_cnt
    local srcmnt
    local dstmnt
    local cmd
    local -a cmds=()
    local swap_ptn_UUIDs
    local -a swap_ptns_UUIDs=()
    local -i bios=0
    local -i err

    # get mount points for src and dst partitions
    for ptn in "${partitions[@]}"; do
        # extract drive number to find if partition is src or dst
        ((drv_num=$(field "$ptn" "$PDRV_NUM")))
        if (( drv_num == OPTIONS[0] )); then # if is src partition
            fstype=$(field "$ptn" "$PFSTYPE")       # extract filesystem type
            flags=$(field "$ptn" "$PFLAGS")         # extract flags
            ((ptn_num=$(field "$ptn" "$PPTN_NUM"))) # extract partition number
            ((ptn_cnt=$(field "$ptn" "$PPTN_CNT"))) # extract partition counter

            # swap partitions are not cloned, just created, thus, are not part
            # of any rsync parameters and are not mounted
            if [[ "$fstype" =~ swap ]]; then
                # save src swap UUIDs, as they'll be replaced with dst ones
                # on dst drive after cloning
                swap_ptn_UUIDs="$srcdrv$SP$ptn_num"
                swap_ptn_UUIDs+=":"
                
                # src swap UUID
                cmd="blkid $srcdrv$SP$ptn_num"
                swap_ptn_UUIDs+=$(expr "$($cmd)" : ".* UUID=\"\(.*\)\" TYPE")
                swap_ptn_UUIDs+=":"
                swap_ptn_UUIDs+="$dstdrv$DP$ptn_cnt"
                swap_ptn_UUIDs+=":"
                
                # dst swap UUID
                cmd="blkid $dstdrv$DP$ptn_cnt"
                swap_ptn_UUIDs+=$(expr "$($cmd)" : ".* UUID=\"\(.*\)\" TYPE")
                swap_ptns_UUIDs+=("$swap_ptn_UUIDs")
                cmds+=("mkswap -c -f '$dstdrv$DP$ptn_cnt'")
            elif [[ "$flags" =~ bios ]]; then
                ((bios=1)) # set flag if bios partition
            else
                # mount src partition
                mount_ptn "$srcdrv$SP$ptn_num" srcmnt
                ((err=$?)); ((err)) && return $err

                # mount dst partition
                mount_ptn "$dstdrv$DP$ptn_cnt" dstmnt
                ((err=$?)); ((err)) && return $err

                # pair src and dst mount points so that they can be used as src
                # and dst parameters in rsync
                rsync_params+=("$srcmnt$dstmnt$flags")
            fi
        fi
    done

    echo -e "\tCreating list of files and directories to exclude from cloning..."

    local srcptn

    # log directory created by the script is excluded from cloning 
    srcptn=$(findmnt -no SOURCE -T "$(dirname "$LOGDIR")")
    srcmnt=$(lsblk -no MOUNTPOINT "$srcptn")
    rsync_filters[$srcmnt]+="-f \"- $(dirname "${LOGDIR//\"/\\\"}")/\" "

    local -a entries
    local entry
    local ptn_pair # src partition and its corresponding dst partition
    local file
    local buf
    local -a swap_file_cmds=()
    local -i size
    local -a files=()
    local FSTAB_FILE="/etc/fstab"
    readonly FSTAB_FILE

    if [[ "$BOOTPTN" =~ $srcdrv$SP ]]; then
        # find swap files listed in fstab file
        mapfile -t entries < <(grep swap "$FSTAB_FILE")

        # find swap files that are active as some of these may not be listed in
        # fstab file
        mapfile -t -O ${#entries[@]} entries < <(swapon --noheadings | grep file)

        echo -e "\tCreating list of swap files, if any, to create on destination drive..."

        local -i found
        local -i count
        
        # iterate over swap file names and add cmds to create them on dst
        for entry in "${entries[@]}"; do
            # if swap entry is a file and not a partition
            if [[ "${entry::1}" == "/" ]]; then
                file="${entry%%+( *)}" # get swap filename
                ((found=0))

                # check if swap file has been added to swap file list
                for buf in "${files[@]}"; do
                    [[ "$buf" == "$file" ]] && found=1 && break
                done
                (( found )) && continue    # swap file has been added so skip it
                files+=("$file") # add swap file to swap file list

                srcptn=$(findmnt -no SOURCE -T "$file")

                # add the swap file only if it exists on the src drive
                if [[ "$srcptn" =~ $srcdrv$SP ]]; then
                    srcmnt=$(lsblk -no MOUNTPOINT "$srcptn")
                    
                    # don't clone swap file (add to rsync filters)
                    rsync_filters[$srcmnt]+="-f \"- ${file//\"/\\\"}\" "
                    
                    if [[ -f "$file" && -s "$file" && -r "$file" && -w "$file" ]]
                    then
                        # add cmds to create swap files on dst
                        ((size=$(find "$file" -printf %s)))
                        
                        ((count=size/MIBIBYTE))

                        # get partition swap file resides on
                        ptn=$(findmnt -no SOURCE -T "$file")
                        
                        for ptn_pair in "${rsync_params[@]}"; do
                            if [[ "$ptn" == "$(field "$ptn_pair" "$MPTN")" ]]; then
                                dstmnt=$(field "$ptn_pair" "$((MDIR+MDST))")

                                # the following three numbers at the beginning
                                # of the cmd are parsed as follows:
                                # 1: run in the background
                                # 1: redirect stdout
                                # 0: don't redirect stderr
                                cmd="110 dd if=/dev/zero of='$dstmnt'/'$file' "
                                cmd+="bs=1M count=$count status=progress"
                                swap_file_cmds+=("$cmd")
                                swap_file_cmds+=("chmod 0600 '$dstmnt'/'$file'")
                                swap_file_cmds+=("mkswap -f -U clear '$dstmnt'/'$file'")
                                break
                            fi
                        done
                    fi
                fi
            fi
        done
    fi

    echo -e "\tCreating commands for cloning..."

    local key
    local -i used

    # iterate over partitions and create cmds for cloning
    for ptn_pair in "${rsync_params[@]}"; do
        srcmnt=$(field "$ptn_pair" "$MDIR") # get src dir

        if [[ "$srcmnt" == "/" ]]; then
            key="$srcmnt"
        else
            # remove trailing '/' as it's not part of key of associative array
            key="${srcmnt::-1}"

            # remove src mount directory from filtered directories/files to
            # comply with rsync rules
            rsync_filters[$key]="${rsync_filters["$key"]//$key}"
        fi

        # get size of dst partition
        dstmnt=$(field "$ptn_pair" "$((MDIR+MDST))")

        if (( create_ptn )); then
            (( size = $(df -ak --block-size=KiB --sync --output=avail "$dstmnt" \
                        2>> "$ERRFILE" | tail -1 | tr -d [:alpha:]) ))
            (( size *= 1024 )) # convert to bytes

            # get size of src partition data
            for i in "${!src_ptn_data[@]}"; do
                srcptn=$(field "${src_ptn_data[i]}" "$SOURCE" ' ')
                for ptn_num in "${!esp_ptn_nums[@]}"; do
                    [[ "$srcptn" == "$srcdrv$SP$ptn_num" ]] && break
                done
                [[ "$srcptn" == "$srcdrv$SP$ptn_num" || \
                   "$srcptn" == "$srcdrv$SP$bios_ptn" ]] &&
                    continue

                if [[ "$srcptn" == $(field "$ptn_pair" "$MPTN") ]]; then
                    (( used = $(field "${src_ptn_data[i]}" "$USED" ' ') ))
                    break
                fi
            done

            # check if src partition data fits on dst partition size
            if (( size <= used )); then
                cecho -e "\n${RED}Destination partition"\
                         "$(field "$ptn_pair" "$((MPTN+MDST))")$RED mounted on"\
                         "$dstmnt$RED is too small. It is $YELLOW$size KiB"\
                         "${RED}but should be $YELLOW> $used KiB$RED. Delete"\
                         "${RED}some data in source partition"\
                         "$(field "$ptn_pair" "$((MPTN))")$RED mounted on"\
                         "$srcmnt$RED. Exiting.\n"
                return 1
            fi
        fi

        flags="aAhHxlzEUtX"

        # After tests, rsync does not support extended attributes on HFS
        # filesystems so that option is removed below. After mounting an HFS
        # volume, executing a 'ls' cmd on the mounted volume produces the
        # following message "ls: '<mount_dir>': No data available" yet the
        # contents are displayed correctly.
        [[ "$(findmnt -no FSTYPE "$srcmnt" 2>> "$ERRFILE")" =~ hfs ]] &&
            flags="${flags:0:-1}"

        # create rsync cmd; the following two numbers at the beginning of the 
        # cmd are parsed as follows:
        # 1: run in the background
        # 0: don't redirect stdout
        cmds+=("10 rsync --log-file='$LOGFILE' --info=misc2,mount,name0,progress2,stats2 \
                         -$flags --numeric-ids --inc-recursive --delete-during \
                         --delete-excluded ${rsync_filters["$key"]} \
                         '$srcmnt' '$dstmnt'")
    done

    echo -e "\n\tExecuting cloning commands (this may take a while)..."

    exec_cmds "${cmds[@]}"
    ((err=$?)); ((err)) && return $err

    exec_cmds "${swap_file_cmds[@]}"
    ((err=$?)); ((err)) && return $err

    # get locations of dst fstab file(s); many may exist if src is multiboot
    files=($(dst_pathname "$FSTAB_FILE" "${rsync_params[@]}"))
    cmds=()
    if [[ "${files[*]}" ]]; then
        echo -e "\tCreating commands to make destination drive bootable..."
        echo -e "\tCreating command to update fstab file on destination drive..."

        cmd="sed -i "
        
        # replace src partition data on dst fstab file for all partitions but swap
        for ptn_pair in "${rsync_params[@]}"; do
            # add sed cmd to replace src partition name with dst name
            cmd+="-e \"s|'$(field "$ptn_pair" "$MPTN")'|"
            cmd+="'$(field "$ptn_pair" "$((MPTN+MDST))")'|g\" "

            # add sed cmd to replace src UUID with dst UUID
            cmd+="-e 's|$(field "$ptn_pair" "$MUUID")|"
            cmd+="$(field "$ptn_pair" "$((MUUID+MDST))")|g' "
        done

        for swap_ptn_UUIDs in "${swap_ptns_UUIDs[@]}"; do
            # replace src partition data on dst fstab file for swap partition
            # add sed cmd to replace src partition name with dst name
            cmd+="-e 's|$(field "$swap_ptn_UUIDs" "$SPTN")|"
            cmd+="$(field "$swap_ptn_UUIDs" "$((SPTN+SDST))")|g' "

            # add sed cmd to replace src UUID with dst UUID
            cmd+="-e 's|$(field "$swap_ptn_UUIDs" "$SUUID")|"
            cmd+="$(field "$swap_ptn_UUIDs" "$((SUUID+SDST))")|g' "
        done

        for file in "${files[@]}"; do # create cmd(s) for fstab file(s)
            cmds+=("$cmd'$file'")
        done
    fi
    
    local -a grubcfg_files=()

    # iterate over partitions to find grub cfg file(s)
    for ptn_pair in "${rsync_params[@]}"; do
        dstmnt=$(field "$ptn_pair" "$((MDIR+MDST))")
        mapfile -t -O ${#grubcfg_files[@]} grubcfg_files < <(find "$dstmnt" \
                                                                  -name "grub*.cfg" \
                                                                  2>> "$ERRFILE")
    done

    local UUID
    
    buf=""
    if [[ "${grubcfg_files[*]}" ]]; then
        echo -e "\tCreating commands to update grub cfg and grub default files"\
                "on destination drive..."

        # replace src partition data on dst grub.cfg file
        # iterate over all src partitions and find UUID which exists in grub.cfg
        cmd="sed -i "
        files=()
        for ptn_pair in "${rsync_params[@]}"; do
            UUID=$(field "$ptn_pair" "$MUUID")
            for file in "${grubcfg_files[@]}"; do
                if grep -q "$UUID" "$file" 2>> "$ERRFILE"; then
                    # add sed cmd to replace src UUID with dst UUID
                    [[ ! "$cmd" =~ "$UUID" ]] &&
                        cmd+="-e 's|$UUID|$(field "$ptn_pair" "$((MUUID+MDST))")|g' "
                    [[ ! "${files[*]}" =~ "$file" ]] && files+=("$file")
                fi
            done
        done

        # if swap partitions exist update their UUID in the grub.cfg and grub
        # default files
        if (( ${#swap_ptns_UUIDs[@]} )); then
            for swap_ptn_UUIDs in "${swap_ptns_UUIDs[@]}"; do
                buf+="-e 's|$(field "$swap_ptn_UUIDs" "$SUUID")|"
                buf+="$(field "$swap_ptn_UUIDs" "$((SUUID+SDST))")|g' "
            done

            cmd+="$buf"
        fi

        grubcfg_files=("${files[@]}")
        for file in "${grubcfg_files[@]}"; do
            cmds+=("$cmd '$file'")
        done    
    fi

    local GRUBDEF_FILE="/etc/default/grub"
    readonly GRUBDEF_FILE

    if [[ "$buf" ]]; then
        # get locations of dst default grub file(s); many may exist if src is
        # multiboot
        files=($(dst_pathname "$GRUBDEF_FILE" "${rsync_params[@]}"))
        for file in "${files[@]}"; do
            cmds+=("sed -i $buf '$file'")
        done
    fi

    # iterate over partitions to find grubenv file(s)
    files=()
    for ptn_pair in "${rsync_params[@]}"; do
        dstmnt=$(field "$ptn_pair" "$((MDIR+MDST))")
        mapfile -t -O ${#files[@]} files < <(find "$dstmnt" -name grubenv \
                                                  2>> "$ERRFILE")
    done

    # update grubenv on dst
    buf=""
    for file in "${files[@]}"; do
        val=""
        for ptn_pair in "${rsync_params[@]}"; do
            # get entry if it exists in grubenv file on dst
            if [[ -z "$val" ]]; then
                UUID=$(field "$ptn_pair" "$MUUID")
                entry=$(grep "$UUID" "$file" 2> /dev/null)
                if (( $? == 0 )); then
                    name="${entry%=*}" # name of entry
                    val="${entry#*=}"  # value of entry

                    # replace src with dst UUID
                    val="${val/$UUID/$(field "$ptn_pair" "$((MUUID+MDST))")}"

                    dstmnt=$(field "$ptn_pair" "$((MDIR+MDST))")
                    cmd="$dstmnt"/usr/bin/grub-editenv
                    cmds+=("$cmd '$file' set '$name'='$val'")
                    if [[ -z "$buf" ]]; then
                        echo -e "\tCreating commands to update grubenv file on"\
                                "destination drive..."
                        buf="done"
                    fi
                    break
                else
                    val=""
                fi
            fi
        done
    done

    local all_entries
    local removable=1
    local dstptn
    local EFI="[Ee][Ff][Ii]"
    local BOOT="[Bb][Oo][Oo][Tt]"
    local SHIM="[Ss][Hh][Ii][Mm]"
    readonly EFI BOOT SHIM
    local distro
    local PREFIX_UUID="resume=UUID="
    local RE_UUID="${PREFIX_UUID}[a-fA-F0-9-]\+"
    local PREFIX_OFFSET="resume_offset="
    local RE_OFFSET="${PREFIX_OFFSET}[0-9]\+"
    readonly PREFIX_UUID RE_UUID PREFIX_OFFSET RE_OFFSET
    local dst_bootdir=""

    # if UEFI boot, get UEFI boot entries and check if dst is removable media
    all_entries=$(efibootmgr 2>> "$ERRFILE")
    (( $? == 0 )) &&
        removable=$(lsblk -nr --nodeps --output HOTPLUG "$dstdrv" 2>> "$ERRFILE")

    cmd=""
    for ptn_pair in "${rsync_params[@]}"; do
        dstmnt=$(field "$ptn_pair" "$((MDIR+MDST))")
        if [[ -f "$dstmnt$FSTAB_FILE" ]]; then
            mapfile -t entries < <(grep swap "$dstmnt$FSTAB_FILE" 2>> "$ERRFILE")

            for entry in "${entries[@]}"; do
                # if swap entry is a file and not a partition
                if [[ "${entry::1}" == "/" ]]; then
                    file="${entry%%+( *)}"  # get swap filename
                    file="$dstmnt${file:1}" # add dst dir and remove '/'

                    # get swap file UUID and offset
                    UUID=$(findmnt -no UUID -T "$file" 2>> "$ERRFILE")
                    ((size=$(filefrag -v "$file" | \
                            awk '$1=="0:" {print substr($4, 1, length($4)-2)}')))

                    cmds+=("[[ '$UUID' =~ ^[a-fA-F0-9][a-fA-F0-9-]+$ && \
                               '$size' =~ ^[0-9]+$ && '$size' -gt 0 ]]")
                            
                    UUID="$PREFIX_UUID$UUID"
                    buf="$PREFIX_OFFSET$size"
                    
                    # replace UUID and offset with that of dst in grub cfg 
                    # default file
                    file="$dstmnt$GRUBDEF_FILE"
                    if [[ -f "$file" && -s "$file" && -r "$file" ]]; then
                        cmds+=("sed -i 's|$RE_UUID|$UUID|g' '$file'")
                        cmds+=("sed -i 's|$RE_OFFSET|$buf|g' '$file'")
                    fi

                    # replace UUID and offset with that of dst in grub cfg files
                    for file in "${grubcfg_files[@]}"; do
                        cmds+=("sed -i 's|$RE_UUID|$UUID|g' '$file'")
                        cmds+=("sed -i 's|$RE_OFFSET|$buf|g' '$file'")
                    done    
                fi
            done
        fi

        # if bios flag is set, get dst boot dir
        flags=$(field "$ptn_pair" "$((MUUID+MDST+1))")
        if [[ $bios -ne 0 && -z "$dst_bootdir" && \
              ("$flags" =~ boot || "$flags" =~ esp) ]]
        then
            dst_bootdir="$ptn_pair"
        fi

        # if bios flag is set, install grub bootloader for non-UEFI (bios) system
        if (( bios )); then
            if [[ -z "$cmd" && -x "$dstmnt"/usr/bin/grub-install ]]; then
                cmd="$dstmnt"/usr/bin/grub-install # grub installer pathname
                buf="$dstmnt"
            fi

            if [[ "$dst_bootdir" && "$cmd" ]]; then
                UUID=$(field "$dst_bootdir" "$MUUID")
                if grep -q "$UUID" "$buf/$FSTAB_FILE" 2> /dev/null; then
                    dst_bootdir=$(field "$dst_bootdir" "$((MDIR+MDST))")

                    echo -e "\tCreating command to install grub bootloader on"\
                            "bios and boot partition on destination drive..."

                    # the following three numbers at the beginning of the cmd
                    # are parsed as follows:
                    # 0: don't run in the background
                    # 1: redirect stdout
                    # 0: don't redirect stderr
                    cmds+=("010 $cmd --target=i386-pc \
                                     --boot-directory='$dst_bootdir' \
                                     --recheck '$dstdrv'")
                    ((bios=0)) # install grub bootloader only once
                fi
            fi
        fi

        # if dst is not removable add shim efi boot entries if they don't exist
        if [[ "$removable" == 0 && ("$flags" =~ boot || "$flags" =~ esp)]]; then
            # get dst boot partition UUID
            UUID=$(field "$ptn_pair" "$((MUUID+MDST))")

            # get dst boot partition UUID entry
            UUID=$(lsblk -nro +UUID,PARTUUID | grep "$UUID")
            UUID="${UUID//+(* )}" # extract partition UUID
            
            # get boot loader files (they contain 'EFI' string)
            mapfile -t entries < <(find "$dstmnt"/$EFI -name "*.$EFI")

            dstptn=$(field "$ptn_pair" "$((MPTN+MDST))")
            ptn_num=$(expr "$dstptn" : ".\+[[:alpha:]]\+\([[:digit:]]\+\)")

            # iterate over boot loader files and add shim efi entry if necessary
            for entry in "${entries[@]}"; do
                entry="${entry#"$dstmnt"}" # remove bootdir
                
                # skip entries that contain '/BOOT/' (it's for removable media)
                # or not 'shim'
                [[ "$entry" =~ /$BOOT/ || ! "$entry" =~ $SHIM ]] && continue

                # remove suffix up to and including last '/'
                distro="${entry%+(/*)}"
                
                # remove prefix up to and including last '/'
                distro="${distro##+(*/)}"

                entry="${entry//'/'/'\'}" # efi boot entries use '\'

                # if no shim boot entries for dst, add them
                if [[ ! "$all_entries" =~ .+$ptn_num.+$UUID.+"$entry" ]]; then
                    echo -en "\tCreating command to add UEFI boot entry "

                    # separate line as $entry contains special characters that
                    # echo -e above can't display
                    echo "'$entry' ..."

                    cmds+=("efibootmgr --create --disk '$dstdrv' \
                                       --part $ptn_num \
                                       --loader '$entry' \
                                       --label 'shim-$distro' \
                                       --unicode")
                fi
            done
        fi
    done
    
    (( ${#cmds[@]} )) && echo
    exec_cmds "${cmds[@]}" # execute cmds created above
}

# $1:   : int, optional, valid value: 1, cancellation signal was received
# return: 0 on success, 1 if parameter error else the error code of the cmd that
#         failed
cleanup() {
    valid_opt_param "$1" # validate parameter

    local -i err=0
    local -i tmp
    local -a cmds=()

    # if cancellation signal was received
    if (( $# == 1 )); then
        cecho -e "\n\nReceived signal to terminate cloning. Please wait till"\
                 "cleanup has completed.\nCleanup in progress..."

        # pids of processes running in background
        local -a pids
        mapfile -t pids < <(jobs -p)

        local -i ppid

        for (( tmp = 0; tmp < ${#pids[@]}; ++tmp )); do
            (( ppid=$(ps -ho ppid --pid ${pids[tmp]} | xargs) ))
            (( ppid == $$ )) && cmds+=(${pids[tmp]})
        done

        if (( ${#cmds[@]} )); then # kill processes running in background
            echo -e "\tKilling jobs running in the background..."
            
            # create cmd to terminate any processes running in background
            # the following three numbers at beginning of cmd are parsed as
            # follows:
            # 0: don't run in the background
            # 0: don't redirect stdout
            # 0: don't redirect stderr
            cmds=("000 kill -s TERM ${cmds[*]} >> '$LOGFILE' 2>> '$ERRFILE' || true")
            exec_cmds "${cmds[@]}"
            ((err=$?))
        fi
    else
        echo "Cleaning up..."
    fi
    
    if grep -q ^$$ "$LCKFILE" 2> /dev/null; then
        echo -e "\tIgnoring trapped cancel signals during cleanup..."

        # cleanup should not be interrupted by cancel signals in order to run
        # cleanup!
        cmds=("trap '' $CANCEL_SIGNALS")
        exec_cmds "${cmds[@]}"
        ((err=$?))

        echo -e "\tUnmounting partitions on source and/or destination drives that"\
                "were mounted, if any..."

        local ptn_pair

        # unmount partitions that were mounted
        for ptn_pair in "${rsync_params[@]}"; do
            umount_ptn "$ptn_pair"
            ((tmp=$?))
            (( ! err )) && ((err=tmp))
        done

        echo -e "\tIgnore signal to disable/enable system sleep (suspend/hibernate)..."

        # ignore sig USR1 in order not to mask/unmask system sleep
        cmds=("trap '' USR1")
        exec_cmds "${cmds[@]}"

        unmask_system_sleep
        ((tmp=$?))
        (( ! err )) && ((err=tmp))
        
        echo -e "\tRemove the entry of this $SCRIPTNAME process from the lock file..."

        cmds=("flock '$LCKFILE' sed -Ezi 's|$$_${OPTIONS_S}_$dstdrv[[:space:]]+||g' '$LCKFILE'")
        exec_cmds "${cmds[@]}"
    elif [[ "$OPTIONS_S" ]]; then
        echo -e "\tIgnoring trapped signals during cleanup..."

        cmds=("trap '' USR1 $CANCEL_SIGNALS")
        exec_cmds "${cmds[@]}"
    # if script was cancelled during usage message skip most of cleanup
    else
        trap '' USR1 $CANCEL_SIGNALS &> /dev/null # ignore trapped signals
    fi
    ((tmp=$?))
    (( ! err )) && ((err=tmp))
    
    if (( $# == 1 )); then # if cancellation signal was received
        local buf="$YELLOW${REDB}Cloning was canceled.$OFF "
        
        if (( err )); then
            result "$buf${RED}Cleanup was unsuccessful."
        else
            result "$buf${GREEN}Cleanup completed successfully."
        fi
        ((tmp=$?))
        if (( ! err )); then exit $tmp; else exit $err; fi
    fi

    return $err
}

# called just before the script terminates printing the result and run time
# $1: str, optional, a message to print
result() {
    local -i err=0

    if [[ "$OPTIONS_S" ]] && get_pids; then
        # if this is the only clone process then pid & sleep lock files can be
        # safely removed
        echo -e "\tDeleting lock files directory $LCKDIR ..."

        declare -a cmds=()

        cmds+=("rm -rf '$LCKDIR'"); ((dry_run=0))
        exec_cmds "${cmds[@]}"
        ((err=$?))
    fi

    [[ "$1" ]] && cecho -e "$1"
    
    if [[ "$START_DATE" ]]; then
        # the timestamp will be used to calculate the run time
        local end_date
        end_date=$(date)
        local -i runtime
        ((runtime=$(date -d "$end_date" +%s)-$(date -d "$START_DATE" +%s)))
        local -i seconds=runtime%60
        local -i hours=runtime/$((60*60))
        local -i minutes=$((runtime-(hours*60*60)))/60
        local label="Duration"

        cprintf "%-${#label}s: %s\n%-${#label}s: %s\n%s: %02dh:%02dm:%02ds\n"\
                "Start" "$START_DATE" "End" "$end_date" "$label" $hours $minutes $seconds
    else
        echo
    fi

    return $err
}

declare -i err=0

source /usr/lib/"${SCRIPTNAME/.*}"-lib."${SCRIPTNAME/*.}" && init $@
((err=$?))
readonly FILTERS_FILE FSTYPES_FILE

(( ! err )) &&
    while (( LOOP )); do
        usage             &&
        user_input        &&
        setup_env         &&
        populate_arrays   && # create data structures used for cloning
        mask_system_sleep &&
        calc_drvspace     && # check if src fits on dst
        create_partitions && # create partitions on dst if different than src
        clone
        ((err=$?))
    done
cleanup
((err+=$?))

if (( ! err )); then
    result "${GREEN}Cloning completed successfully."
else
    result "${RED}Cloning was unsuccessful."
fi
((err+=$?))

exit $err
