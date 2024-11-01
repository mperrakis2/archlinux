#! /bin/bash

# update grub.cfg file with latest versions of linux kernel

# make sure only one instance of the script can run at a time
# taken from the man page of flock
if [[ "${FLOCKER}" != "${BASH_SOURCE:-$0}" ]]; then
    exec env FLOCKER="${BASH_SOURCE:-$0}" flock -en "${BASH_SOURCE:-$0}" "${BASH_SOURCE:-$0}" "$@"
else
    true
fi

set -o pipefail

BOOTDIR="$(bootctl -p)"
readonly BOOTDIR

readonly GRUB_CFG_FNAME="$BOOTDIR/grub/grub.cfg"

# [0-9]+ : one or more digits
# [.]    : the '.' char
readonly RE_KV_PREFIX="[0-9]+[.][0-9]+[.][0-9]+"

# check that all input files exist
for file in "$GRUB_CFG_FNAME" "$BOOTDIR"/vmlinuz-linux "$BOOTDIR"/vmlinuz-linux-lts
do
    if [[ ! -f "$file" || ! -r "$file" || ! -w "$file" || ! -s "$file" ]]; then
        declare errmsg="The '$GRUB_CFG_FNAME' file does not exist or is empty "
        
        errmsg+="or is not readable/writable. Can't update $GRUB_CFG_FNAME "
        errmsg+="with latest versions of the linux and linux-lts kernels."
        systemd-cat -t "${BASH_SOURCE:-$0}" -p "err" echo "$errmsg"

        exit 1
    fi
done

# get grub cfg kernel versions
#
# grep options
# ------------
# -o         : return only matched pattern, not entire line
# -P         : use Perl regex
#
# regex
# -----
# \b         : word boundary, only get words that start & end with linux kernel
#              version
# \S*?lts    : any non-whitespace that ends wih 'lts' but stop at the first match
#              (non-greedy)
#              this avoids matching strings like "5.15.79-1-lts-lts" but will match
#              "5.15.79-1-lts"
# (?!\S*?lts): the opposite of the above, do not match lts kernel versions

set +o pipefail # grep below fails if string doesn't exist

# get kernel version in grub cfg file
declare -a GRUB_KV
mapfile -t GRUB_KV < <(grep -oP "\b$RE_KV_PREFIX"'(?!\S*?lts)\b' "$GRUB_CFG_FNAME")
readonly GRUB_KV

# get lts kernel version in grub cfg file
declare -a GRUB_LTS_KV
mapfile -t GRUB_LTS_KV < <(grep -oP "\b$RE_KV_PREFIX\S*?lts\b" "$GRUB_CFG_FNAME")
readonly GRUB_LTS_KV

set -o pipefail 

get_kv() { grep "$(hostname)" | tail -n 1 | xargs | cut -d ' ' -f 1; }

# get installed kernel version
kv="$(strings "$BOOTDIR"/vmlinuz-linux | get_kv)"

# get installed lts kernel version
LTS_KV="$(strings "$BOOTDIR"/vmlinuz-linux-lts | get_kv)"
readonly LTS_KV

sed -i "s| Linux,||g" "$GRUB_CFG_FNAME"
sed -i "s|Linux linux-lts|Linux LTS kernel $LTS_KV|g" "$GRUB_CFG_FNAME"

for kv_entry in "${GRUB_LTS_KV[@]}"; do
    sed -i "s|LTS kernel $kv_entry|LTS kernel $LTS_KV|g" "$GRUB_CFG_FNAME"
done

sed -i "s|Linux linux|Linux kernel $kv|g" "$GRUB_CFG_FNAME"

if (( ${#GRUB_KV[@]} )); then
    # extract only the numbers in the installed kernel version
    kv=$(expr "$kv" : "\(${RE_KV_PREFIX//'+'/'\+'}\)")
    for kv_entry in "${GRUB_KV[@]}"; do
        sed -i "s|Linux kernel $kv_entry|Linux kernel $kv|g" "$GRUB_CFG_FNAME"
    done
fi

exit 0
