#! /bin/bash

# base functions for clone script

readonly LCL_CFG_DIR=".config/$SCRIPTNAME.d"

print_helpmsg() {
        cat << helpmsg
usage: $SCRIPTNAME [OPTION]...
clone one drive to another using rsync(1)

-d, --dst <dst_drive>        destination drive, e.g. /dev/sdb
                             must be combined with '-s, --src' option
-e, --exclude <exclude_file> pathname of custom conf file that contains
                             files/dirs to be excluded from cloning
-f, --fstypes <fstypes_file> pathname of custom conf file that contains the
                             commands to format various filesystems (don't use
                             this unless you really know what are doing)
-h, --help                   display this help and exit
-r, --dry-run                display commands but don't execute them
-s, --src <src_drive>        source drive, e.g. /dev/sda
                             must be combined with '-d, --dst' option

if '-s' and '-d' are omitted a list of drives is displayed and user input is
based on source and destination drive number as per the list

if '-e' or '-f' is omitted the conf file is read from:
    * ~/$LCL_CFG_DIR/ if it exists and the script is not run under its
      own directory ($SCRIPTDIR/)
    * $DEF_CFG_DIR/ and $OVR_CFG_DIR/ (if it exists) in all
      other cases

for more info see $SCRIPTNAME(1) & $SCRIPTNAME-exclude.conf(5)
helpmsg
}

# echo pathname of config file
# $1    : str, filename
# stdout: pathname of config file
get_cfg_fname() {
    (( $# != 1 )) &&
        exit_with_stack "\nOne param required: filename. Exiting."

    local cwd
    local gbl_cfg_file="$DEF_CFG_DIR/$1" # global cfg file
    local lcl_cfg_file

    cwd=$(pwd)
    lcl_cfg_file=$(eval echo ~$(logname))/"$LCL_CFG_DIR/$1" # local cfg file

    if [[ "$cwd" != "$SCRIPTDIR" && -f "$lcl_cfg_file" && \
          -r "$lcl_cfg_file" && -s "$lcl_cfg_file" ]]
    then
        echo "$lcl_cfg_file"
    else
        echo "$gbl_cfg_file"
    fi
}

# $1    : str, function name and its params
# $2    : str, list of signals
# return: 0 on success else the error code of the cmd that failed
trap_signals() {
    if (( $# != 2 )); then
        local msg="\nTwo params required: function and its params (first param) "
        
        msg+="and list of signals (second param). Exiting."
        exit_with_stack "$msg"
    fi

    local -i err
    
    trap "$1" $2 &> /dev/null # register signal handler
    ((err=$?))
    
    (( err )) && 
    cecho -e "\n${RED}Error while trapping signals, error code: $err. Exiting."

    return $err
}

declare -A CFG_FNAMES=()

# check that all files exist, are readable and have size != 0
# return: 0 on success, 1 if a file does not exist, not readable or zero size
files_exist() {
    local key
    local -i err=0
    
    if (( ! ${#CFG_FNAMES[@]} )); then
        CFG_FNAMES[$FILTERS_FILE]="It is needed to exclude/include files/dirs when cloning. Exiting."
        CFG_FNAMES[$FSTYPES_FILE]="It is needed when formatting partitions. Exiting."
        readonly CFG_FNAMES
    fi

    for key in "${!CFG_FNAMES[@]}"; do
        file_exists "$key" "${CFG_FNAMES["$key"]}"
        ((err+=$?))
    done
    
    return $err
}

# check that a file exists, is readable and has size != 0
# $1    : str, the filename
# $2    : str, the msg to display
# return: 0 on success, 1 if file not exist, not readable or zero size
file_exists() {
    if (( $# != 2 )); then
        local msg="\nTwo params required: filename and message. Exiting."

        exit_with_stack "$msg"
    fi

    if [[ ! -f "$1" || ! -s "$1" || ! -r "$1" ]]; then
        cecho -e "\n${RED}The $YELLOW$1$RED file does not exist or has zero size or"\
                 "${RED}is not readable.\n$RED$2"

        return 1
    fi
}

# prompt the user to reselect cloning options
# $1    : ref to int, 0 or 1, loop or not
# $2    : optional, str, prompt
# return: 1
prompt() {
    local -n ref_loop="$1"

    if [[ $# -lt 1 || $# -gt 2 || ! $ref_loop =~ ^[0-1]$ ]]; then
        local msg="\nOne or two params required: bool, 0 or 1 (loop or not) and "
        
        msg+="an optional prompt string. Exiting."
        exit_with_stack "$msg"
    fi
    
    if (( script )); then # if src & dst specified as cmd line args
        [[ "$2" ]] && cecho -e "$RED$2"
        ((ref_loop=0))
    else
        local MSG="Would you like to re-enter cloning options? (y/yes/n/no) "
        readonly MSG

        while read -rn 3 -p "$(cecho -e "$RED\n$2\n$MSG")"; do
            case "${REPLY,,}" in
                y | yes)
                    ((ref_loop=1))
                    break
                    ;;
                n | no)
                    ((ref_loop=0))
                    break
                    ;;
            esac 
        done
    fi

    (( ! ref_loop )) && kill -s TERM $$ # exit if user selected no
        
    return 1
}

# exit and print the stack
# 1: str, an error message
exit_with_stack() {
    stack "$@"
    exit $?
}

# borrowed from the web
# https://gist.github.com/akostadinov/33bb2606afe1b334169dfbf202991d36
stack() {
    local -a stack=("\n\nStack trace:")
    local stack_size=${#FUNCNAME[@]}
    local -i i
    local func
    local -i line
    local src
    
    # to avoid noise we start with 1 to skip the stack function
    for (( i = 1; i < stack_size; i++ )); do
	    func="${FUNCNAME[$i]:-(top level)}"
	    line="${BASH_LINENO[i-1]}"
	    src="${BASH_SOURCE[$i]:-(no file)}"

	    stack+=("\t($i) file: $src, function: $func, line: $line")
    done
    (IFS=$'\n'; cecho -e "$RED$*${stack[*]}\n")
    
    return 1
}

# echo colored text with a leading tab and print rest of characters verbatim
# $@    : text to echo
# stdout: colored text
cechot() {
    echo -en "\t"
    cecho "$@"
}

# echo text with color
# $@    : text to echo preceded by optional 'echo' cmd line options
# stdout: colored text
cecho() {
    local param
    local -i i
    local -i j
    local options="enE" # echo cmd line options
    local -i len=1
    local -i idx=1
    
    # get index of first echo param that is not a cmd line option
    for param in "$@"; do
        [[ "${param::1}" != '-' ]] && break # quit if param not cmd line option
        for (( i = 1; i < ${#param}; ++i )); do # iterate over param chars
            for (( j = 0; j < ${#options}; ++j )); do # iterate over options chars
                # if chars are the same, increment counter
                if [[ "${param:$i:1}" == "${options:$j:1}" ]]; then
                    ((++len))
                    # don't use 'break' here as same cmd line option might be 
                    # repeated
                fi
            done
        done

        # param is a cmd line option if all its chars are cmd line options
        if (( len == ${#param} )); then
            ((++idx))
            ((len=1))
        else
            break # only first params of echo can be cmd line options
        fi
    done

    local -a params=()
    
    # get params that are not cmd line options and add appropriate str color
    # header and trailer
    for param in "${@:$idx:$#}"; do
        if [[ "$param" =~ ^"$BOLD" ]]; then # param already prefixed by str color
            params+=("$param$OFF")          # header so just turn off at the end
        else
            # param not prefixed by str color header so add default (yellow) and
            # then turn off at the end
            params+=("$YELLOW$param$OFF")
        fi
    done
        
    echo "${@:1:$(( idx - 1 ))}" "${params[*]}"
}

# print message with color
# $@    : text to print followed by optional 'printf' arguments
# stdout: text with color code
cprintf() {
    if (( $# < 1 )); then
        local msg="$YELLOW${FUNCNAME[0]}$RED: At least one param required: "
        
        msg+="string to print and optional 'printf' arguments. Exiting."
        exit_with_stack "$msg"
    fi
    
    # "${@:2}": all params except the first
    [[ "$1" =~ ^"$BOLD" ]] && printf "$1$OFF" "${@:2}" || 
                              printf "$YELLOW$1$OFF" "${@:2}"
}

# get a field (substring) from a string based on a regex
# $1    : str, the string to get the field from
# $2    : int, the number of the field to extract
# $3    : optional, str, a regex (default below).
# stdout: the field (substring)
field_re() {
    if [[ $# -lt 2 || $# -gt 3 || ! "$2" =~ ^[0-9]+$ || $2 -lt 1 ]]; then
        local msg="\nTwo or three params required: a string, the number of "
        
        msg+="a field within it to extract and optional regex. Exiting."
        exit_with_stack "$msg"
    fi
    
    expr "$(field "$1" "$2")" : ${3:-"\([0-9]*\)"}
}

# get a field (substring) from a string based on a delimeter
# $1    : str, the string to get the field from
# $2    : int, the number of the field to extract
# $3    : optional, str, a delimeter (default below).
# stdout: the field (substring)
field() {
    if [[ $# -lt 2 || $# -gt 3 || ! "$2" =~ ^[0-9]+$ || $2 -lt 1 ]]; then
        local msg="\nTwo or three params required: a string, the number of "
        
        msg+="a field within it to extract and optional delimeter. Exiting."
        exit_with_stack "$msg"
    fi
    
    local od=""
    local d=":"
    
    (( $2 > 1 )) && od=--only-delimited
    [[ "$3" ]] && d="$3"
    
    echo "$1" | cut $od -f "$2" -d "$d"
}

# add new filter
# $1: ref to str associative array, rsync filters
# $2: ref to str associative array, user filters
# $3: ref to str array, the new filter to add
# $4: optional, str, buf of indices of filter entries
add_filter() {
    if (( $# < 3 || $# > 4 )); then
        local msg="\nThree or four params required: ref to assoc array of rsync "
        
        msg+="filters, ref to assoc array of user filters, ref to filter and an "
        msg+="optional buf of indices of filter entries. Exiting."
        exit_with_stack "$msg"
    fi
    
    local -n ref_filters="$1"
    local -n ref_user_filters="$2"
    local -n ref_paths="$3"

    if (( ${#ref_paths[@]} == 1 )); then
        ref_filters[${ref_paths[0]}]="$4" # add new filter
     
        # add new user filter
        ref_user_filters[${ref_paths[0]}]="${ref_paths[*]}"
    else
        # add new user filter
        if [[ "${ref_paths[0]: -1}" != '/' ]]; then
            ref_user_filters[${ref_paths[0]}"/**/"${ref_paths[1]}]="${ref_paths[*]}"
            ref_paths[0]+="/"
        else
            ref_user_filters[${ref_paths[0]}"**/"${ref_paths[1]}]="${ref_paths[*]}"                    
        fi

        # add new filter 2 or more levels under top level dir
        ref_filters[${ref_paths[0]}"**/"${ref_paths[1]}]="$4"
    fi
}

# get entries (files and/or dirs) for a user filter
# $1: ref to str array, store file(s) and/or dir(s) to be filtered
# $2: optional, str, valid value="-type d"
get_entries() {
    local -i err=0
    
    (( $# == 2 )) && [[ "$2" != "-type d" ]] && ((err=1))
    if (( err || $# < 1 || $# > 2 )); then
        local msg="\nOne or two params required: reference to array of "
        
        msg+='paths and optional param = "-type d". Exiting.'
        exit_with_stack "$msg"
    fi

    local -i k
    local -a new_names

    local -a names=()
    local -n ref="$1"

    # iterate over previous result set and pass next token of relative path to
    # 'find' cmd
    for k in "${!ref[@]}"; do
        # The first part of the 'find' cmd  needs to be in single quotes as it
        # may contain spaces that are not escaped. Also, 'PATHS' may include 
        # spaces that are escaped so 'eval' is used to treat 'PATHS' as a single
        # argument.
        readarray -td '' new_names < <(eval \
                                       'find "${ref[k]}"'/"${PATHS[1]:$j:$i-$j}" \
                                             -maxdepth 0 \
                                             "$2" \
                                             -print0 2>> "$ERRFILE")
        (( ${#new_names[@]} )) && names+=("${new_names[@]}")
    done

    if (( ${#names[@]} )); then
        ref=("${names[@]}") 
    else
        ref=()
    fi
}

# update matched entries
# $1: int, a filter index
# $2: ref to associative str array, matched entries
update_matched() {
    if [[ $# -ne 2 || ! "$1" =~ ^[0-9]+$ ]]; then
        local msg="\nTwo params required: filter idx >= 0 and a ref to an "
        
        msg+="assoc array of matched entries. Exiting."
        exit_with_stack "$msg"
    fi
    
    local idx_pair
    local -n ref_matched="$2"
    local -i idx1
    local -i idx2
    local -a matched_sorted

    # sort matched entries so that they can be updated easily and correctly    
    IFS=$'\n' matched_sorted=($(sort -V <<< "${!matched[@]}")); unset IFS

    # update matched entries
    for idx_pair in "${matched_sorted[@]}"; do
        ((idx1=${idx_pair/,+([0-9])})) # get 1st filter idx
        ((idx2=${idx_pair/+([0-9]),})) # get 2nd filter idx

        if (( idx1 == $1 || idx2 == $1 )); then # remove equal
            unset ref_matched[$idx_pair]

        # create new match with updated indices and delete existing
        elif (( idx1 > $1 )); then
            if (( idx2 < $1 )); then
                ref_matched[$((idx1-1)),$idx2]="${ref_matched[$idx_pair]}"
            else
                ref_matched[$((idx1-1)),$((idx2-1))]="${ref_matched[$idx_pair]}"            
            fi
            unset ref_matched[$idx_pair]
        elif (( idx2 > $1 )); then
            ref_matched[$idx1,$((idx2-1))]="${ref_matched[$idx_pair]}"            
            unset ref_matched[$idx_pair]
        fi    
    done
}

# add indices of two matched entries
# $1: int, index of entry within a filter
# $2: int, index of entry within a filter
# $3: ref to associative str array, indices of matched entries
add_match() {
    if [[ $# -ne 3 || ! "$1" =~ ^[0-9]+$ || ! "$2" =~ ^[0-9]+$ ]]; then
        local msg="\nThree params required: idx1 >= 0, idx2 >= 0 and a ref to "
        
        msg+="assoc array of matched entries. Exiting."
        exit_with_stack "$msg"
    fi
    
    local f
    local -i i
    local -i j
    local -n ref="$3"
    
    # get indices of filters
    get_filter_data "$1" f i
    get_filter_data "$2" f j

    # match include to include or exclude filter and increment their counter
    ref[$i,$j]+="$1 $2 "
}

# get rsync filter data given the index of an entry
# $1: int, an index of a filter entry >= 0
# $2: ref to str, store the filter
# $3: optional, ref to int, the index of the filter in the filter array
get_filter_data() {
    if [[ $# -lt 2 || $# -gt 3 || ! "$1" =~ ^[0-9]+$ ]]; then
        local msg="\nTwo or three params required: a filter entry idx >=0, a "
        
        msg+="ref to store the filter and an optional ref to store the filter "
        msg+="idx. Exiting."
        exit_with_stack "$msg"
    fi

    local f
    local -n fref="$2"
    local -i idx=0

    # iterate over rsync filters to find the filter for the index of an entry
    for f in "${!filters[@]}"; do        
        if [[ "${filters["$f"]}" =~ ^"$1 " || "${filters["$f"]}" =~ " $1 " ]]
        then
            fref="$f" # store rsync filter
            break
        fi
        (( ++idx ))
    done
    
    if (( $# == 3 )); then
        local -n iref="$3"
        
        ((iref=idx)) # store rsync filter index
    fi
}

# get rsync filter given its index
# $1: int, an index of a filter >= 0
# $2: ref to str, store the filter
get_filter() {
    if [[ $# -ne 2 || ! "$1" =~ ^[0-9]+$ ]]; then
        local msg="\nTwo three params required: a filter idx >=0 and a ref to "
        
        msg+="store the filter. Exiting."
        exit_with_stack "$msg"
    fi

    local flt
    local -n fref="$2"
    local -i idx=0

    # iterate over rsync filters to find the filter given its index
    for flt in "${!filters[@]}"; do
        if (( idx == $1 )); then
            fref="$flt" # store rsync filter
            break
        fi
        (( ++idx ))
    done
}

# remove filter tuple entries that cancel out each other
# $1    : ref to str array, filter entries
# $2    : ref to associative str array, removed entries
# $3    : ref to str array of matched filters
# return: 0 if a filter tuple is to be removed else 1
rm_tuple_entries() {
    if (( $# != 3 )); then
        local msg="\nThree params required: ref to array of filter entries, "
        
        msg+="ref to assoc array of removed entries and ref to assoc array of "
        msg+="matched filters. Exiting."
        exit_with_stack "$msg"
    fi

    local matched_idx
    
    if [[ -v matched_processed[$i] ]]; then
        matched_idx=$j
    else
        matched_idx=$i
    fi
    
    local -n ref_removed_entries="$2"
    local -n ref_entries="$1"
    local -i j=0
    local -a abuf=(${matched[$matched_idx]}) # store indices of matched entries

    # remove all include/exclude entries
    for matched_idx in ${matched[$matched_idx]}; do
        # store indices of include entries only
        (( j % 2 == 0 )) && ref_removed_entries[$matched_idx]=
        unset ref_entries[matched_idx]
        ((++j))
    done

    ((matched_idx=${#abuf[@]}/2))
    abuf=(${filters["$f"]})
    if (( ${#abuf[@]} == matched_idx )); then # all exclude entries are matched
        local -n ref_matched_filters="$3"
        
        ref_matched_filters+=("$f") # add matched filter for removal
        abuf=(${filters["$k"]})               

        # all include entries are matched
        if (( ${#abuf[@]} == ${#ref_removed_entries[@]} )); then
            ref_removed_entries=()
            return
        fi
    fi

    return 1
}

# remove filter entries that are under others
# $1    : ref to str array, filter entries
# $2    : ref to associative str array, removed entries
# return: 0 if a filter is to be removed else 1
rm_filter_entries() {
    if (( $# != 2 )); then
        local msg="\nTwo params required: ref to array of filter entries and "
        
        msg+="ref to assoc array of removed entries. Exiting."
        exit_with_stack "$msg"
    fi

    local idx

    if [[ -v matched_processed[$i] ]]; then
        idx=$j
    else
        idx=$i
    fi

    local -i idx1=${idx/,+([0-9])} # get 1st filter idx
    local -i idx2=${idx/+([0-9]),} # get 2nd filter idx
    local -i prev_idx=-1
    local -n ref_entries="$1"
    local -i removed=0
    local -n ref_removed_entries="$2"

    # remove the entries that are under others
    for idx in ${matched[$idx]}; do
        # remove only the first entry of every index pair
        if (( prev_idx >= 0 )); then
            # In case the pair exists as a reverse match then its two entries
            # are equal and only one of them has to be removed in each pair.
            # Thus, the second entry of this pair is removed which is the first
            # entry of the reverse pair.
            if [[ "${matched[$idx2,$idx1]}" =~ "$idx $prev_idx " ]]; then
                if [[ -v ref_entries[prev_idx] ]]; then
                    unset ref_entries[idx]
                else
                    ((removed+=1))
                fi
            else
                unset ref_entries[prev_idx]                
            fi
            
            ref_removed_entries[$prev_idx]= # store entry index
            ((prev_idx=-1))
        else
            ((prev_idx=idx))
        fi
    done

    local -a abuf=(${filters["$k"]})

    # skip if filter entries not matched or equal in number to already removed
    if (( ${#abuf[@]} != ${#ref_removed_entries[@]} )); then
        return 1
    elif (( ${#abuf[@]} == removed )); then
        abuf=(${filters["$f"]})
        if (( ${#abuf[@]} == removed )); then
            ref_removed_entries=()
            return 1
        fi
    fi

    ref_removed_entries=()
}

# convert size in bytes to GB or MB or KB
# $1    : ref to int >=0
convert_size() {
    local -n ref="$1"

    [[ $# -ne 1 || ! "$ref" =~ ^[0-9]+$ || $ref -lt 0 ]] &&
        exit_with_stack "\nOne param required: size >=0. Exiting."

    local -i unit=1
    local unit_str="B"

    if (( $1 >= 1000000000 )); then
        ((unit=1000000000))
        unit_str="GB"
    elif (( $1 >= 1000000 )); then
        ((unit=1000000))
        unit_str="MB"
    elif (( $1 >= 1000 )); then
        ((unit=1000))
        unit_str="KB"
    fi
    
    if (( unit > 1 )); then
        local decimal
        local integral

        decimal=$(echo "$ref/$unit" | bc -l)
        decimal=$(echo "$decimal+0.5" | bc -l)
        integral=$(echo "$ref/$unit" | bc)
        if (( $(echo "$decimal >= ($integral + 1)" | bc -l) )); then
            ((ref=integral+1))
        else
            ((ref=integral))
        fi
    fi
    ref+=" $unit_str"
}

# return: 0 on success else the error code of the cmd that failed
read_cfg() {
    ! files_exist && return 1

    local override_file="$OVR_CFG_DIR/fstypes.conf"

    # if there is no override for the file set it to empty str
    if [[ ! "$FSTYPES_FILE" =~ "$DEF_CFG_DIR" || ! -f "$override_file" || \
          ! -s "$override_file" || ! -r "$override_file" ]]
    then
        override_file=""
    fi

    local file
    local -i fd
    local -i i

    for file in "$FSTYPES_FILE" $override_file; do
        exec {fd}< "$file" # open file
        while read -r -u $fd; do
            # remove leading and trailing whitespace
            REPLY=$(echo "$REPLY" | xargs 2>> "$ERRFILE")

            # ignore empty lines & comments
            [[ -z "$REPLY" || "$REPLY" =~ ^#.*$ ]] && continue

            # read and update contents of array
            if [[ "$file" == "$override_file" ]]; then # override file exists
                # iterate over existing array and update its elements
                for (( i = 0; i < ${#FSTYPES[@]}; ++i )); do
                    if [[ "${FSTYPES[i]}" =~ ^"$(field "$REPLY" 1)" ]]; then
                        FSTYPES[i]="$REPLY"
                        break
                    fi
                done
                (( i == ${#FSTYPES[@]} )) && FSTYPES+=("$REPLY")
            else
                FSTYPES+=("$REPLY")
            fi
        done
        exec {fd}<&- # close file
    done

    override_file="$OVR_CFG_DIR/exclude.conf"

    # if there is no override for the file set it to empty str
    if [[ ! "$FILTERS_FILE" =~ "$DEF_CFG_DIR" || ! -f "$override_file" || \
          ! -s "$override_file" || ! -r "$override_file" ]]
    then
        override_file=""
    fi

    for file in "$FILTERS_FILE" $override_file; do
        exec {fd}< "$file" # open file
        while read -r -u $fd; do
            # remove leading and trailing whitespace
            REPLY=$(echo "$REPLY" | sed -e 's/^[[:blank:]]*//' \
                                        -e 's/[[:blank:]]*$//')

            # ignore empty lines & comments
            [[ -z "$REPLY" || "$REPLY" =~ ^#.*$ ]] && continue

            # read and update contents of array
            if [[ "$file" == "$override_file" ]]; then # override file exists
                # iterate over existing array and update its elements
                for (( i = 0; i < ${#FILTERS[@]}; ++i )); do
                    [[ "${FILTERS[i]}" == "$REPLY" ]] && break
                done
                (( i == ${#FILTERS[@]} )) && FILTERS+=("$REPLY")
            else
                FILTERS+=("$REPLY")
            fi
        done
        exec {fd}<&- # close file
    done
}

# get sector size based on partition type and size
# stdout: the aligned sector size
get_sector_size() {
    local -i size=0

    if [[ "$fstype" && ! "$fstype" =~ swap ]]; then
        local -i min_size=0
        local -i max_size=0

        ((size=$?))
        if (( ! size )); then
            # get min & max sector size for fstype
            local rec

            for rec in "${FSTYPES[@]}"; do
                if [[ "$rec" =~ $fstype ]]; then
                    ((min_size=$(field "$rec" 3)))
                    ((max_size=$(field "$rec" 4)))
                    if (( min_size == 0 || max_size == 0 )); then # btrfs
                        ((min_size=page_size))
                        ((max_size=page_size))
                    fi
                    break
                fi
            done

            ((size=$(field "${partitions[i]}" "$PALIGN_START")))
            ((size=$(align_sector_size $min_size $max_size $size)))
        fi
    fi

    echo $size
}

# get new partition alignment using LCM
# $1    : int, existing partition alignment
# $2    : str, filesystem type
# $3    : str, flags (used to find bios_grub partition, if any)
# stdout: new alignment
align_ptn() {
    if [[ $# -ne 3 || ! "$1" =~ ^[0-9]+$ || $1 -lt 1 ]]; then
        local msg="\nThree params required: alignment > 0, filesystem type "
        
        msg+="and flags. Exiting."
        exit_with_stack "$msg"
    fi
    
    if [[ "$2" =~ swap ]]; then
        lcm "$1" "$page_size"
    elif [[ "$3" =~ bios ]]; then # keep existing alignment as bios_grub
        echo "$1"                 # partition has no fstype and is unformatted
    else
        lcm "$1" "$sector_size"
    fi
}

# realign partition size based on next partition's filesystem alignment
# $1    : int, partition offset
# $2    : int, partition size
# $3    : int, partition filesystem alignment
# $4    : int, next partition filesystem alignment
# stdout: the aligned size
realign_size() {
    if [[ $# -ne 4 || ! "$1" =~ ^[0-9]+$ || ! "$2" =~ ^[0-9]+$ || \
          ! "$3" =~ ^[0-9]+$ || ! "$4" =~ ^[0-9]+$ || $1 -lt 1 || $3 -lt 1 || \
          $4 -lt 1 || $2 -lt 1 ]]
    then
        local msg="\nFour params required all > 0: partition offset, size, "
        
        msg+="current & next alignment. Exiting."
        exit_with_stack "$msg"
    fi
    
    # align size only if [offset + size] not an integral multiple of next
    # partition's filesystem alignment
    if (( ($1 + $2) % $4 )); then
        local -i offset
        local -i next_offset
        local -i new_next_offset

        # align partition's offset based on next partition's filesystem alignment
        ((offset=$(align_size "$1" "$3")))

        ((next_offset=offset+$2)) # next partition's offset = new offset + size

        # align [new offset + size] based on next partition's filesystem alignment
        ((new_next_offset=$(align_size "$next_offset" "$4")))

        # the new size is the existing + any delta to compensate for alignment
        # differences with next partition (size + delta is an integral
        # multiple of current partition & filesystem alignment)
        echo $(( $2 + (new_next_offset - next_offset) ))
    else
        echo "$2"
    fi
}

# get the aligned size of a partition
# $1    : int, the size
# $2    : int, the alignment
# stdout: the aligned size
align_size() {
    if [[ $# -ne 2 || ! "$1" =~ ^[0-9]+$ || ! "$2" =~ ^[0-9]+$ || $1 -lt 1 || \
          $2 -lt 1 ]]
    then
        local msg="\nTwo params required all > 0: size and alignment. Exiting."
        
        exit_with_stack "$msg"
    fi
    
    if (( $1 < $2 )); then
        echo "$2"
    elif (( $1 % $2 == 0 )); then
        echo "$1"

    # get the aligned size that is closer to original size
    elif (( $1 - (($1 / $2) * $2) < ((($1 / $2) * $2 ) + $2) - $1 )); then
        echo $(( ($1 / $2) * $2 ))
    else
        echo $(( (($1 / $2) * $2) + $2 ))
    fi
}

# mount a src or dst partition
# $1    : str, the partition
# $2    : ref to str, mount data
#
#         src_ptn:mnt_dir:bool:UUID:dst_ptn:mnt_dir:bool:UUID:
#
#         where bool: mounted or not
#
#         Example: /dev/sda1:/boot/efi:0:<UUID>:/dev/sdc1:/media/<UUID>:1:<UUID>:
#
# return: 0 on success else the error code of cmd that failed
mount_ptn() {
    if (( $# != 2)) || ! find "$1" >> "$LOGFILE" 2>> "$ERRFILE"; then
        local msg="\nTwo params required: str, valid partition and ref to str, "

        msg+="mount data. Exiting."
        exit_with_stack "$msg"
    fi
    
    local UUID
    local mnt_dir
    local options
    local -a cmds=()
    local -i is_mnt=0
    
    if [[ "$1" =~ "$dstdrv" ]]; then options="--options rw"; else options=""; fi

    # get read/write dir for mounted partition
    mnt_dir=$(findmnt $options -no TARGET "$1")

    UUID=$(expr "$(blkid "$1")" : ".* UUID=\"\([^\"]*\)\"") # get partition UUID

    # mount the partition if not mounted
    if [[ -z "$mnt_dir" ]]; then
        fstype=$(lsblk -no FSTYPE "$1") # get partition filesystem

        # if drive has ('dos' partition table and FAT) or UDF, create cmd to
        # mount with 'uid' and 'gid' options
        if [[ ("$(lsblk -no PTTYPE "$1")" =~ dos && "$fstype" =~ fat) || \
              "$fstype" =~ udf ]]
        then
            local uid
            local gid

            get_id u uid
            get_id g gid

            mnt_dir=/run/media/$(logname)/$UUID
            cmds+=("mkdir -p '$mnt_dir'")
            cmds+=("mount $options -o uid=$uid,gid=$gid '$1' '$mnt_dir'")
        else
            cmds+=("udisksctl mount $options -b '$1' --no-user-interaction")        
        fi

        local -i err

        exec_cmds "${cmds[@]}" # execute cmd created above
        ((err=$?)); ((err)) && return $err

        # get dir for mounted partition
        if [[ -z "$mnt_dir" ]]; then
            mnt_dir=$(findmnt $options -no TARGET "$1" 2>> "$ERRFILE")
            ((err=$?)); ((err)) && return $err
        fi

       ((is_mnt=1))
    fi

    [[ $mnt_dir != "/" ]] && mnt_dir+="/"

    local -n ref="$2"

    ref="$1:$mnt_dir:$is_mnt:$UUID:"
}

# unmount partitions
# $1: str, partition data (see format in mount_ptn() function)
umount_ptn() {
    (( $# != 1 )) &&
        exit_with_stack "\nOne param required: partition data. Exiting."

    local -i field_num
    local -i is_mnt
    local ptn
    local -a cmds=()

    for field_num in $MIS_MNT $((MIS_MNT+MDST)); do
        # if partition mounted by script, create unmount cmd
        is_mnt=$(field "$1" "$field_num")
        
        # if partition was mounted, unmount it
        if [[ "$is_mnt" == 1 ]]; then
            ptn=$(field "$1" "$((field_num-2))") # extract partition name
            umount_cmd "$ptn" cmds # create cmd to unmount partition
        fi
    done

    exec_cmds "${cmds[@]}" # execute cmds created above
}

# add cmd to unmount a partition
# $1: str, partition, e.g. /dev/sda1
# $2: ref to str array, the cmds array
umount_cmd() {
    if (( $# != 2 )) || ! find "$1" >> "$LOGFILE" 2>> "$ERRFILE"; then
        local msg="\nTwo params required: valid partition and ref to cmds "

        msg+="array. Exiting."
        exit_with_stack "$msg"
    fi

    local -n ref="$2"

    ref+=("udisksctl unmount -b '$1' --force --no-user-interaction")
}

# get partition size
# $1: ref to int, size of dst partition
get_ptn_size() {
    if (( $# != 1 )); then
        local msg="\nOne param required: int ref to dst partition size. Exiting."
        
        exit_with_stack "$msg"
    fi
    
    local -n ref="$1"
    local pct
    local cmd

    # get size of src partition in bytes
    (( ref = $(field "$ptn" "$PSIZE") ))

    # calculate percentage of src partition based on src drive size
    pct=$(bc <<< "scale=3; $ref / $((SRC_DRV_SIZE-no_resize))")

    # calculate dst partition size based on percentage above
    cmd='{printf "%.0f", ($1 * $2 == int($1 * $2)) '
    cmd+='? $1 * $2 : int($1 * $2) + 1}'
    ((ref=$(awk "$cmd" <<< "$pct $dst_space_avail")))
}

# executes an array of cmd
# $@    : array of str, cmd
# stdout: cmd that are executed
# return: 0 on success, else the error code of the cmd that failed
exec_cmds() {
    local -a cmds=("$@")
    local -i i

    for i in "${!cmds[@]}"; do # remove empty cmd
        [[ -z "${cmds[i]//[[:space:]]}" ]] && unset cmds[i]
    done
    (( ! ${#cmds[@]} )) && return 0 # return if no cmds

    # file discriptor array that enables/disables stdout, stderr and execution
    # in the background
    local -a fd 
    local -i j
    local -i err=0
    local -i pid
    local -i SIGMASK=128
    readonly SIGMASK

    echo -e "\tExecuting\n\t=========" | tee -a "$CMDFILE"
    for i in "${!cmds[@]}"; do
        # remove extra whitespace from cmd
        cmds[i]=$(echo "${cmds[i]}" | tr -d -s '\b\f\n\r\t\v' ' ')

        # sensible defaults, i.e. redirect stdout & stderr and don't run in the
        # background
        fd=("" " >> '$LOGFILE'" " 2>> '$ERRFILE'")

        # check if there are overrides for the defaults above
        for j in "${!fd[@]}"; do
            if [[ "${cmds[i]::1}" =~ ^[01]$ ]]; then
                if (( ${cmds[i]::1} == 0 )); then
                    fd[j]="" # don't redirect stdout or stderr
                elif [[ -z "${fd[j]}" ]]; then
                    fd[j]="&" # run in the background
                fi
                cmds[i]="${cmds[i]:1}"
            else
                break
            fi        
        done
        
        # echo the cmd for convenience
        printf "\t%s\n" "${cmds[i]}" | tee -a "$CMDFILE"
        
        # cmd that run in the background take a long time to complete and
        # usually have a progress indicator, e.g. percentage
        [[ "${fd[0]}" ]] && cecho -e "\tProgress..."
        
        # run cmd and use 'eval' to take into account spaces between arguments
        # but not within each argument
        if (( ! dry_run )); then
            eval "${cmds[i]}" "${fd[1]}" "${fd[2]}" "${fd[0]}"
            err=$?
            if (( err )); then
                print_err_msg "${cmds[i]}"
                break
            fi
        fi

        # if the cmd currently running takes a long time to complete and the
        # script receives a signal, the handler wouldn't get called unless the
        # cmd completed. To avoid this, long running cmds are executed in the
        # background and 'wait' is used to wait on them. If the script receives
        # a signal, 'wait' exits with an error > 128 and the following code
        # keeps looping until the cmd exits on its own. Of course, if a cancel
        # signal is received, e.g. INT, TERM, HUP, etc., its handler would exit
        # the script.
        if [[ "${fd[0]}" ]]; then
            ((pid=$!))
            while true; do
                printf "\t%s\n" "wait $pid" >> "$CMDFILE" # update cmds file

                # run cmd and use 'eval' to take into account spaces between
                # arguments but not within each argument
                if (( ! dry_run )); then
                    eval wait $pid "${fd[1]}" "${fd[2]}"
                    ((err=$?))
                fi

                if (( err )); then
                    if (( err < SIGMASK )); then
                        # ignore if 'rsync' failed and err=24, i.e. partial
                        # transfer due to vanished source files
                        if [[ "${cmds[i]}" =~ ^[[:blank:]]*rsync && $err -eq 24 ]]
                        then
                            ((err=0))
                        else
                            print_err_msg "wait $pid"
                        fi
                        break
                    fi
                else
                    break
                fi
            done
            (( err )) && break
        fi           
        sync
    done
    echo | tee -a "$CMDFILE"

    return $err
}

# remove the lba flag from the partition flags
# $1    : str, partition table type
# $2    : str, partition flags
# stdout: the flags without the lba flag
rm_lba_flag() {
    if (( $# != 2 )); then
        local msg="\nTwo params required: partition table type and "
        
        msg+="partition flags. Exiting."
        exit_with_stack "$msg"        
    fi
    
    local flags_no_lba="$2"

    if [[ "$1" == msdos && "$2" =~ lba ]]; then
        # remove the lba flag as it may not exist on src
        flags_no_lba="${flags_no_lba//lba,/}"

        # just in case it is the last flag and there's no comma as above
        flags_no_lba="${flags_no_lba//lba/}"
    fi
    
    echo "$flags_no_lba"
}

# get the destination pathnames of a file based on mount point
# $1    : str, filename
# $@    : array of str, rsync params
# stdout: array of pathnames 
dst_pathname() {   
    if (( $# < 2 )); then
        local msg="\nAt least two params required: filename and rsync params. "
        
        msg+="Exiting."
        exit_with_stack "$msg"
    fi
    
    local ptn_pair
    local -a rsync_params=("${@:2}") # get all params except first one
    local file
    local -a pathnames=()

    # iterate over partition data to add the file on dst
    for ptn_pair in "${rsync_params[@]}"; do
        # add dst file if it exists
        file=$(field "$ptn_pair" "$((MDIR+MDST))")/"$1"
        [[ -f "$file" && -s "$file" ]] && pathnames+=("$file")
    done

    echo "${pathnames[@]}"
}

# build sed expressions
# $1    : str, file (must exist)
# $2    : ref to associative str array of sed expressions
# stdout: sed expressions
# return: 0 on success else 1
build_sed_exps() {
    if [[ $# -ne 2 || ! -f "$1" ]]; then
        local msg="\nTwo params required: str, file that exists and associative "
        
        msg+="str array. Exiting."
        exit_with_stack "$msg"
    fi
    
    local cmd
    local UUID
    local -n ref_sed_exps="$2"
    local -i success=1

    cmd="sed -i "
    for UUID in "${!ref_sed_exps[@]}"; do
        if grep -q "$UUID" "$1" 2>> "$ERRFILE"; then
            cmd+="${ref_sed_exps[$UUID]}"
            ((success=0))
        fi
    done

    echo "$cmd"

    return $success
}

# $1: str, valid value: "" or "1" (signal was received)
valid_opt_param() {
    # validate param
    if [[ $# -ne 1 || ("$1" && "$1" -ne 1) ]]; then
        local msg="\nOnly one param allowed: '' or '1' to indicate a signal was "
        
        msg+="received. Exiting."
        exit_with_stack "$msg"
    fi
}

# In case the desktop environment attempted system sleep (suspend/hibernate) and
# it failed, a notification was sent and a popup appears on the desktop. The
# popup has no timeout so the following code closes all popup notifications.
close_notifications() {
    if [[ "$DISPLAY" ]]; then            
        local user
        local -i uid
        local -i nid

        user=$(logname)
        uid=$(id -u "$user")
        
        # send dummy notification to get the latest notification id
        ((nid=$(sudo -u "$user" DISPLAY=:0 \
                                DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus \
                                notify-send -p 'get the latest notification id' )))
        
        # iterate over all notification ids and clear all popups
        (( $? == 0 )) &&
            for i in $(seq $nid); do 
                sudo -u "$user" DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus \
                                dbus-send --type=method_call \
                                          --dest=org.freedesktop.Notifications \
                                          /org/freedesktop/Notifications \
                                          org.freedesktop.Notifications.CloseNotification \
                                          uint32:"$i"
            done
    fi
}        

# get shell executable and script filenames
SHELLNAME=$(expr "$(head -1 "$0")" : "^\s*#\!\s*\(.\+\)$")
readonly SHELLNAME

# get the number of pids of clone processes running
# return: the number of pids in the lock file
get_pids() {
    local -i fd
    
    # critical section
    (
        if ! flock $fd; then exit 1; fi

        # get pids of all clone processes
        declare -a pids
        mapfile -t pids < <(cat "$LCKFILE" 2>> "$ERRFILE")
        
        declare pid
        declare cmd_line
        declare -i i=0

        # extract pids
        for pid in "${pids[@]}"; do
            pid=$(expr "$pid" : "^\([0-9]\+\)")
            (( pid == $$ )) && continue # skip own pid

            if [[ -e /proc/$pid/cmdline ]]; then
                # get cmd line corresponding to pid
                cmd_line=$(tr -d '\0' < /proc/"$pid"/cmdline 2>> "$ERRFILE")
                
                [[ "$cmd_line" =~ $SHELLNAME && "$cmd_line" =~ $SCRIPTNAME ]] &&
                    ((++i))
            fi
        done
        
        exit $i
            
    ) {fd}>> "$LCKFILE"
}

# get aligned sector size for partition
# $1    : int, min sector size
# $2    : int, max sector size
# $3    : int, partition size
# stdout: the aligned sector size or 1 if none found
align_sector_size() {
    if [[ $# -ne 3 || ! "$1" =~ ^[0-9]+$ || ! "$2" =~ ^[0-9]+$ || \
          ! "$3" =~ ^[0-9]+$ || $1 -eq 0 || $2 -eq 0 || $3 -eq 0 ]]
    then
        local msg="\nThree params required all > 0: base & max alignment "
        
        msg+="and partition size. Exiting."
        exit_with_stack "$msg"
    fi
    
    local -i size=$2

    while (( size >= $1 && $3 - (($3 / size) * size) > 0 )); do
        ((size/=2))
    done

    if (( $3 - (($3 / size) * size) == 0 )); then
        echo $size
    else
        stack "\nNo aligned sector size found for partition. Exiting."
        echo $?
    fi
}

# calculate the Least Common Multiple (LCM) of two numbers
# $1    : int, first num
# $2    : int, second num
# stdout: the lcm
lcm() {
    [[ $# -ne 2 || ! "$1" =~ ^[0-9]+$ || ! "$2" =~ ^[0-9]+$ || $1 -lt 2 || \
       $2 -lt 2 ]] &&
        exit_with_stack "\nTwo params required both > 1: two numbers. Exiting."

    # the LCM of two numbers x,y is GCD * factorsX * factorsY
    # where x = GCD * factorsX, y = GCD * factorsY
    # thus, LCM = GCD * (x / GCD) * (y / GCD) = x * y / GCD
    echo $(( $1 * $2 / $(gcd "$1" "$2") ))
}

# calculate the Greatest Common Divisor (GCD) of two numbers
# $1    : int, first num
# $2    : int, second num
# stdout: the GCD
gcd() {
    [[ $# -ne 2 || ! "$1" =~ ^[0-9]+$ || ! "$2" =~ ^[0-9]+$ || $1 -lt 1 || \
       $2 -lt 1 ]] &&
        exit_with_stack "\nTwo params required both > 0: two numbers. Exiting."

    local -i divident
    local -i divisor
    local -i remainder

    if (( $1 >= $2 )); then
        ((divident=$1))
        ((divisor=$2))
    else
        ((divident=$2))
        ((divisor=$1))
    fi

    ((remainder=divident%divisor))
    while (( remainder && remainder != 1 )); do
        ((divident=divisor))
        ((divisor=remainder))
        ((remainder=divident%divisor))
    done

    (( ! remainder )) && echo $divisor || echo 1 # no GCD
}

# get user or group id
# $1: str, valid values: 'u' or 'g'
# $2: ref to int, user or group id
get_id() {
    if [[ $# -ne 2 || ! "${1,,}" =~ ^[ug]$ ]]; then
        local msg="\nTwo params required: a string literal ('U' or 'G') "
        
        msg+="and a reference to user or group id. Exiting."
        exit_with_stack "$msg"
    fi
    
    local -n ref="$2"

    ref=$(id -"${1,,}" $(logname))
}

# $1: str, an error message
print_err_msg() {
    local msg
    
    if [[ $# -ne 1 || -z "$1" ]]; then
        msg="\nOne non-empty param required. An error message. Exiting."
        exit_with_stack "$msg"
    else
        msg="\nThe command $YELLOW'$1'$RED failed with error code "
        msg+="$YELLOW$err$RED. See $YELLOW$LOGFILE$RED (log file) and "
        msg+="$YELLOW$ERRFILE$RED (error file) for more info. Exiting."
        stack "$msg"
    fi
}
