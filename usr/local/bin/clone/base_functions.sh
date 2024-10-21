#! /bin/bash

# base functions for clone.sh

# echo pathname of config file
# $1    : str, filename
# stdout: pathname of config file
get_cfg_fname() {
    (( $# != 1 )) &&
        exit_with_stack "\nOne param required: filename. Exiting."

    local cwd
    local gbl_cfgdir="/etc/clone" # global cfg dir
    local lcl_cfgdir

    cwd=$(pwd)
    lcl_cfgdir=$(eval echo ~$(logname))"/.config/clone" # local cfg dir

    if [[ "$cwd" != "$SCRIPTDIR" && -f "$lcl_cfgdir/$1" && \
          -r "$lcl_cfgdir/$1" && -s "$lcl_cfgdir/$1" ]]
    then
        echo "$lcl_cfgdir/$1"
    else
        echo "$gbl_cfgdir/$1"
    fi
}

# $1    : str, function name and its params
# $2    : str, list of signals
# return: 0 on success else the error code of the command that failed
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

    if [[ ! -f "$1" || ! -r "$1" || ! -s "$1" ]]; then
        cecho -e "\n${RED}The $YELLOW$1$RED file does not exist or has zero size or"\
                 "${RED}is not readable.\n$RED$2"

        return 1
    fi
}

# prompt the user to reselect cloning options
# $1    : optional, str, prompt
# $2    : int, 0 or 1, loop or not
# return: 1
prompt() {
    local -n ref_loop="$1"

    if [[ $# -lt 1 || $# -gt 2 || ! $ref_loop =~ ^[0-1]$ ]]; then
        local msg="\nOne or two params required: bool, 0 or 1 (loop or not) and "
        
        msg+="an optional prompt string. Exiting."
        exit_with_stack "$msg"
    fi
    
    # check if this process has an entry in the lock file
    if grep ^$$ "$LCKFILE" &> /dev/null; then
        local -a cmds=()
        local -i err

        echo -e "\tRemoving the entry of this clone process from the lock file..."

        cmds+=("flock '$LCKFILE' sed -Ezi 's|$$_${OPTIONS_S}[[:space:]]+||g' '$LCKFILE'")        
        exec_cmds "${cmds[@]}"
        ((err=$?))
        
        if (( err )); then return $err; fi
    fi

    local MSG="Would you like to re-enter cloning options? (y/yes/n/no) "
    readonly MSG

    while read -rn 3 -p "$(cecho -e "$RED$2$MSG")"; do
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
    
    # to avoid noise we start with 1 to skip the stack function
    for (( i = 1; i < stack_size; i++ )); do
	    local func="${FUNCNAME[$i]:-(top level)}"
	    local -i line="${BASH_LINENO[i-1]}"
	    local src="${BASH_SOURCE[$i]:-(no file)}"

	    stack+=("\t($i) $func $src:$line")
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
# $@    : text to echo preceded by optional 'echo' command line options
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
# $3    : optional, str, a regex, default is shown below.
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
# $3    : optional, str, a delimeter, default is shown below.
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
        # The first part of the 'find' command  needs to be in single quotes as
        # it may contain spaces that are not escaped. Also, 'PATHS' may include 
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
            return 0
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

# return: 0 on success else the error code of the command that failed
read_cfg_into_mem() {
    local -i err

    files_exist
    ((err=$?)); ((err)) && return $err

    local -i fd

    exec {fd}< "$FSTYPES_FILE" # open file
    while read -r -u $fd; do
        # remove leading and trailing whitespace
        REPLY=$(echo "$REPLY" | xargs 2>> "$ERRFILE")

        # ignore empty lines & comments
        (( ! ${#REPLY} )) || [[ "$REPLY" =~ ^#.*$ ]] && continue

        FSTYPES+=("$REPLY")
    done
    exec {fd}<&- # close file

    exec {fd}< "$FILTERS_FILE" # open file
    while read -r -u $fd; do
        # remove leading & trailing spaces and tabs
        REPLY=$(echo "$REPLY" | sed -e 's/^[[:blank:]]*//' -e 's/[[:blank:]]*$//')

        # ignore empty lines & comments
        (( ! ${#REPLY} )) || [[ "$REPLY" =~ ^#.*$ ]] && continue
        
        FILTERS+=("$REPLY")
    done
    exec {fd}<&- # close file

    readonly FILTERS FSTYPES

    return $err
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

readonly SLP_CFG_DIR="/etc/systemd/system"
SLP_CFG_PTN=$(df -ak --sync --output=source "$SLP_CFG_DIR" | tail -1)
readonly SLP_CFG_PTN
SLP_CFG_MNT_DIR=$(lsblk -no MOUNTPOINT "$SLP_CFG_PTN")
readonly SLP_CFG_MNT_DIR
declare -a sleep_cmds=()

# create mask/unmask sleep commands
# $1: ref to str array, store the commands
# $2: optional, str, valid value: mask
system_sleep() {
    local -i err=0
    
    (( $# == 2 )) && [[ "$2" != "mask" ]] && ((err=1))
    if (( err || $# < 1 || $# > 2 )); then
        local msg="\nOne or two params required: reference to cmds array "
        
        msg+="and optional param == 'mask'. Exiting."
        exit_with_stack "$msg"
    fi

    if (( $# == 2 )); then # mask sleep
        local target
        local -a TARGETS=("sleep.target" "suspend.target" "hibernate.target")
        local sleep_cmd=""
        local rsync_exclude

        TARGETS+=("hybrid-sleep.target" "suspend-then-hibernate.target")
        readonly TARGETS
        sleep_cmds=()

        # iterate over targets and create commands to mask unmasked ones
        for target in "${TARGETS[@]}"; do
            # check if target is masked
            systemctl status "$target" | grep masked &> /dev/null
            
            if (( ${PIPESTATUS[-1]} )); then # get output of last pipe, i.e. grep
                # create cmd to mask target
                if (( ${#sleep_cmd} )); then
                    sleep_cmd+="$target "
                else
                    sleep_cmd+="systemctl $2 $target "
                fi
                
                rsync_exclude="-f \"- $SLP_CFG_DIR/$target\" "
                [[ ! "${rsync_filters[$SLP_CFG_MNT_DIR]}" =~ $rsync_exclude ]] &&
                    rsync_filters["$SLP_CFG_MNT_DIR"]+="$rsync_exclude"
            fi
        done
        
        (( ${#sleep_cmd} )) && sleep_cmds+=("$sleep_cmd")
    fi

    # add command to mask/unmask sleep
    if (( ${#sleep_cmds[@]} )); then
        local -n ref="$1"
    
        ref+=("${sleep_cmds[@]}")
        if (( $# == 2 )); then 
            # unmask sleep
            sleep_cmds=("${sleep_cmds[@]//$2/unmask}")
            sleep_cmds+=("flock '$SLPFILE' truncate -s 0 '$SLPFILE'")
        else
            sleep_cmds=()
        fi
    fi
}

# mount a src or dst partition
# $1    : str, the device on which the partition exists
# $2    : int, the partition number
# $3    : ref to str, mount data
# return: 0 on success else the error code of cmd that failed
mount_ptn() {
    if [[ $# -ne 3 || ! "$2" =~ ^[0-9]+$ || $2 -lt 1 ]]; then
        local msg="\nThree params required: device, partition number and "
        
        msg+="ref to mount data. Exiting."
        exit_with_stack "$msg"
    fi
    
    local p
    local UUID
    local mnt_dir
    local fstype
    local -i is_mnt=0
    
    if [[ "$1" == "$srcdrv" ]]; then p="$SP"; else p="$DP"; fi

    # get partition UUID
    UUID=$(expr "$(blkid "$1$p$2")" : ".* UUID=\"\([^\"]*\)\"")

    mnt_dir=$(lsblk -no MOUNTPOINT "$1$p$2") # get partition mount directory
    fstype=$(lsblk -no FSTYPE "$1$p$2")    # get partition filesystem

    # For reasons unknown if a ntfs filesystem is mounted already by the system
    # errors are produced during cloning. Therefore, it has to be unmounted and
    # then re-mounted.
    if [[ "$mnt_dir" && "$fstype" =~ ntfs ]]; then
        umount "$mnt_dir"
        mnt_dir=""
    fi

    # if partition not mounted, mount it based on its partition UUID under
    # /media/<UUID>
    if [[ -z "$mnt_dir" ]]; then
        local -a cmds=()
        
        # create command to create directory for mounting if one does not exist
        [[ ! -d /media/$UUID ]] && cmds+=("mkdir -p /media/$UUID")

        # if partition has one of the following filesystems or a 'dos' partition
        # table type, create cmd to mount with 'uid' and 'gid'
        if [[ "ntfs udf hfsplus" =~ "$fstype" || \
              "$(lsblk -no PTTYPE "$1$p$2")" =~ dos ]]
        then
            local uid
            local gid

            get_id U uid
            get_id G gid
            cmds+=("mount -o uid=$uid,gid=$gid '$1$p$2' /media/$UUID")        
        else
            cmds+=("mount '$1$p$2' /media/$UUID")
        fi
        
        local -i err

        # execute commands created above
        exec_cmds "${cmds[@]}"
        err=$?
        if (( err )); then return $err; fi

        mnt_dir=/media/"$UUID" # get new mount point
        ((is_mnt=1))
    elif [[ "$mnt_dir" == "/" ]]; then
        mnt_dir=""
    fi

    local -n ref="$3"

    ref="$1$p$2:$mnt_dir/:$is_mnt:$UUID:"
}

# unmount a partition
# $1: str, partition data in the format:
#
#     "src_ptn:mnt_dir:bool:UUID:dst_ptn:mnt_dir:bool:UUID:"
#     where bool: mounted or not
#
#     Example: /dev/sda1:/boot/efi:0:<UUID>:/dev/sdc1:/media/<UUID>:1:<UUID>:
umount_ptn() {
    (( $# != 1 )) &&
        exit_with_stack "\nOne param required: partition data. Exiting."

    local -i is_mnt
    local -i field_num
    local -a cmds=()

    # iterate over the booleans described in the comment above
    for field_num in $MIS_MNT $((MIS_MNT+MDST)); do
        (( is_mnt=$(( $(field "$1" $field_num) )) ))
        
        # if partition was mounted, unmount it
        if (( is_mnt )); then
            dirname=$(field "$1" "$((field_num-1))") # extract directory name

            # create command to unmount partition
            cmds+=("umount --recursive '$dirname'")

            # create cmd to remove the directory the partition was mounted on
            cmds+=("rm -rf '$dirname'")
        fi
    done

    # execute commands created above
    exec_cmds "${cmds[@]}"
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
    pct=$(bc <<< "scale=3; $ref / $SRC_DRV_RESIZE")

    # calculate dst partition size based on percentage above
    cmd='{printf "%.0f", ($1 * $2 == int($1 * $2)) '
    cmd+='? $1 * $2 : int($1 * $2) + 1}'
    ((ref=$(awk "$cmd" <<< "$pct $dst_space_avail")))
}

# executes an array of commands
# $@    : array of str, commands
# stdout: commands that are executed
# return: 0 on success, else the error code of the command that failed
exec_cmds() {
    local -a cmds=("$@")
    local -i i

    for i in "${!cmds[@]}"; do # remove empty commands
        [[ -z "${cmds[i]//[[:space:]]}" ]] && unset cmds[i]
    done
    if (( ! ${#cmds[@]} )); then return 0; fi # return if no commands

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
        # remove extra whitespace from command
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
        
        # echo the command for convenience
        printf "\t%s\n" "${cmds[i]}" | tee -a "$CMDFILE"
        
        # commands that run in the background take a long time to complete and
        # usually have a progress indicator, e.g. percentage
        (( ${#fd[0]} )) && cecho -e "\tProgress..."
        
        # run cmd and use 'eval' to take into account spaces between arguments
        # but not within each argument
        eval "${cmds[i]}" "${fd[1]}" "${fd[2]}" "${fd[0]}"
        err=$?
        if (( err )); then
            print_err_msg "${cmds[i]}"
            break
        fi
        
        # if the command currently running takes a long time to complete and the
        # script receives a signal, the handler wouldn't get called unless the
        # command completed. To avoid this, long running commands are executed
        # in the background and 'wait' is used to wait on them. If the script
        # receives a signal, 'wait' exits with an error > 128 and the following
        # code keeps looping until the command exits on its own. Of course, if
        # a cancel signal is received, e.g. INT, TERM, HUP, etc., its handler
        # would exit the script.
        if (( ${#fd[0]} )); then
            ((pid=$!))
            while true; do
                printf "\t%s\n" "wait $pid" >> "$CMDFILE" # update cmds file

                # run cmd and use 'eval' to take into account spaces between
                # arguments but not within each argument
                eval wait $pid "${fd[1]}" "${fd[2]}"
                ((err=$?))
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
        local msg="\nAt least two params required: filename and rsync "
        
        msg+="params. Exiting."
        exit_with_stack "$msg"
    fi
    
    local ptn_pair
    local -a rsync_params=("${@:2}") # get all params except first one
    local -a pathnames=()

    # iterate over partition data to find the file on dst
    for ptn_pair in "${rsync_params[@]}"; do
        # check if dst file exists
        if [[ -f "$(field "$ptn_pair" "$((MDIR+MDST))")/$1" && \
              -s "$(field "$ptn_pair" "$((MDIR+MDST))")/$1" ]]; then
            # get location of dst file
            pathnames+=("$(field "$ptn_pair" "$((MDIR+MDST))")/$1")
        fi
    done

    echo "${pathnames[@]}"
}

# $1: optional, int, valid value: 1, signal was received
valid_opt_param() {
    local -i err=0

    # validate param
    (( $# == 1 )) && (( ${#1} )) && [[ ! "$1" =~ ^[0-9]+$ || $1 -ne 1 ]] && ((err=1))
    if (( err || $# > 1 )); then
        local msg="\nOnly one optional param allowed: a value of 1 to indicate "
        
        msg+="a signal was received. Exiting."
        exit_with_stack "$msg"
    fi
}

# return: 0 on success else the error code of the command that failed
unmask_sleep() {
    local -a cmds=()
    system_sleep cmds # add cmds to unmask sleep
    
    (( ${#cmds[@]} )) && echo -e "\tEnabling sleep (suspend/hibernate)..."
    exec_cmds "${cmds[@]}"
    local -i err=$?

    if (( ! err  && ${#cmds[@]} )); then
        # if other clone processes exist, one of them must mask/unmask sleep so
        # send signal USR1 to all of them
        get_pids 1
        ((err=$?))
        
        # In case the desktop environment attempted sleep (suspend/hibernate) 
        # and it failed, a notification was sent and a popup appears on the
        # desktop. The popup has no timeout so the following code clears all
        # popups.
        if [[ "$DISPLAY" ]]; then            
            local -i nid
            local user
            local -i uid

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
    fi
    
    return $err
}        

# get shell executable and script filenames
SHELL_FNAME=$(expr "$(head -1 "$0")" : "^\s*#\!\s*\(.\+\)$")
readonly SHELL_FNAME
SCRIPT_FNAME=$(basename "$0")
readonly SCRIPT_FNAME

# get the number of pids of clone processes running or send signal USR1
# $1    : optional, int, valid value: 1, boolean to send signal USR1
# return: 0 if signal USR1 was sent else the number of clone pids in the lock
#         file
get_pids() {
    # validate param
    if (( $# > 1 )) || (( $# == 1 )) && [[ $1 -ne 1 ]]; then
        local msg="\nOnly one optional param allowed: boolean to send signal "
        
        msg+="USR1. Exiting."
        exit_with_stack "$msg"
    fi
    
    local -i fd
    
    # critical section
    (
        if ! flock $fd; then exit 1; fi

        # get pids of all clone processes
        declare -a pids
        mapfile -t pids < <(cat "$LCKFILE" 2>> "$ERRFILE")
        
        declare pid
        declare cmd_line
        declare -a cmds
        declare -i i=0

        # extract pids
        for pid in "${pids[@]}"; do
            pid=$(expr "$pid" : "^\([0-9]\+\)")
            (( pid == $$ )) && continue # skip own pid

            if [[ -e /proc/$pid/cmdline ]]; then
                # get cmd line corresponding to pid
                cmd_line=$(tr -d '\0' < /proc/"$pid"/cmdline 2>> "$ERRFILE")
                
                if [[ "$cmd_line" =~ $SHELL_FNAME && \
                      "$cmd_line" =~ $SCRIPT_FNAME ]]
                then
                    if (( $# == 1 )); then
                        cmds=("kill -s USR1 $pid")
                        if exec_cmds "${cmds[@]}"; then
                            cecho -e "\tSent signal to 'clone.sh' process with"\
                                     "ID $pid to disable/enable sleep"\
                                     "(suspend/hibernate)...\n"
                        fi
                    else
                        ((++i))
                    fi
                fi
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
# $1: str, valid values: 'U' or 'G'
# $2: ref to int, user or group id
get_id() {
    if [[ $# -ne 2 || ! "$1" =~ ^[UG]$ ]]; then
        local msg="\nTwo params required: a string literal ('U' or 'G') "
        
        msg+="and a reference to user or group id. Exiting."
        exit_with_stack "$msg"
    fi
    
    local -n ref="$2"

    ref=$(env | grep SUDO_"$1"ID)
    ref=$(expr "$ref" : "^SUDO_${1}ID=\([0-9]\+\)")
}

# $1: str, an error message
print_err_msg() {
    local msg
    
    if [[ $# -ne 1 || ${#1} -eq 0 ]]; then
        msg="\nOne non-empty param required. An error message. Exiting."
        exit_with_stack "$msg"
    else
        msg="\nThe command $YELLOW'$1'$RED failed with error code "
        msg+="$YELLOW$err$RED. See $YELLOW$LOGFILE$RED (log file) and "
        msg+="$YELLOW$ERRFILE$RED (error file) for more info. Exiting."
        stack "$msg"
    fi
}
