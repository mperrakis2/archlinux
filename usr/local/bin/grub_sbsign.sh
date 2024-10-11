#!/usr/bin/bash

# install and sign grub bootloader and update grub cfg file

shopt -s extglob

# if first param is non-zero, display error message and exit with first param
# $1    : int, the result returned from a command
# $2    : str, the error message from a command, if any
# return: 0 if (( $1 == 0 )) else $1
exit_on_error() {
    if (( $# != 2 )) || [[ ! "$1" =~ ^-?[0-9]+$ ]]; then
        local msg="Two params are required and the first must be an integer. "

        msg+="Exiting."

        echo "$msg"
        systemd-cat -t "$0" -p "err" echo "$msg"
        exit 1
    fi

    if (( $1 )); then
        systemd-cat -t "$0" -p "err" echo "$2"
        exit $1
    fi
}

exec 2>&1 # redirect stderr to stdout

# get boot dir
bootdir=$(bootctl -p)
exit_on_error $? "$bootdir"

# get boot partition
ptn=$(findmnt --noheadings --output SOURCE --target "$bootdir")
exit_on_error $? "$ptn"

# get drive name & boot partition number
ptn_data=($(lsblk --noheadings --output PKNAME,PARTN "$ptn" | xargs))
exit_on_error $? "${ptn_data[*]}"

# check if bios partition exists
if parted /dev/"${ptn_data[0]}" print | grep -q bios_grub; then
    # install grub to bios partition
    res=$(grub-install --boot-directory='$dstdir' --recheck --target=i386-pc \
                       /dev/"${ptn_data[0]}")
    exit_on_error $? "$res"
fi

# check if ESP exists
parted /dev/"${ptn_data[0]}" print | grep -q esp
declare -i is_esp=$(( ! $? ))

if (( is_esp )); then
    # modules to embed in grub bootloader 
    source /etc/clone/grub_modules

    # install grub to ESP/BOOT
    res=$(grub-install --modules="$GRUB_MODULES" --sbat=/usr/share/grub/sbat.csv \
                       --efi-directory="$bootdir" --removable --recheck \
                       --target=x86_64-efi)
    exit_on_error $? "$res"

    bl_dir="$bootdir/EFI/"     # bl -> bootloader
    def_bl_dir="$bl_dir"/BOOT/ # bootloader dir for external drives
    arch=$(uname -m)                # get architecture
    arch="${arch//+([[:digit:]])_}" # remove chars not part of bl filename
    bl_path="$def_bl_dir"/BOOT"${arch^^}".EFI
    bl_name="grub$arch.efi"
    distro="$(uname -n)"

    mv "$bl_path" "$def_bl_dir/$bl_name"         # rename bootloader
    cp "$def_bl_dir/$bl_name" "$bl_dir/$distro"/ # copy bootloader

    # copy shim to default bootloader dir so that external drives can boot
    cp /usr/share/shim-signed/shim"$arch".efi "$bl_path"

    cd "$bl_dir"

    keyfile="MOK.key"
    crtfile="MOK.crt"

    # sign grub bootloader in EFI/BOOT used by external drive to boot
    bl_path="$def_bl_dir/$bl_name"
    if ! sbverify --cert "$crtfile" "$bl_path" &>/dev/null; then
        res=$(sbsign --key "$keyfile" --cert "$crtfile" --output "$bl_path" \
                                                                 "$bl_path")
        exit_on_error $? "$res"
    fi

    # sign grub bootloader in EFI/<distro> used by internal drive to boot
    bl_path="$bl_dir/$distro/$bl_name"
    if ! sbverify --cert "$crtfile" "$bl_path" &>/dev/null; then
        res=$(sbsign --key "$keyfile" --cert "$crtfile" --output "$bl_path" \
                                                                 "$bl_path")
        exit_on_error $? "$res"
    fi

fi

# update grub config file
grub_cfg_path="$bootdir"/grub/grub.cfg
res=$(grub-mkconfig -o "$grub_cfg_path")
exit_on_error $? "$res"

res=$(mokutil --sb-state) # get secure boot state

# if secure boot is enabled, disable 'insmod' cmds in grub cfg file as the grub
# bootloader sometimes displays errors like 'error: command failed.' or
# 'error: prohibited by secure boot policy'
[[ "${res,,}" =~ enabled ]] &&
    sed -i -E 's|^(\s*insmod.*)$|true #\1|g' "$grub_cfg_path"

# if grub cfg file contains password hash restrict permissions
grep -q password_pbkdf2 "$grub_cfg_path" && chmod o-r "$grub_cfg_path"

exec 2> /dev/tty # restore stderr

# update linux kernel version in grub config file
/usr/local/bin/upd_grub_cfg.sh
