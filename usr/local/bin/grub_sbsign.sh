#!/usr/bin/bash

# install and sign grub bootloader, create UEFI boot entry and update grub cfg file

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

# redirect stderr to stdout
exec 2>&1

# get boot dir
bootdir=$(bootctl -p)
exit_on_error $? "$bootdir"

# get boot partition
ptn=$(findmnt --noheadings --output SOURCE --target "$bootdir")
exit_on_error $? "$ptn"

# get device name & boot partition number
ptn_data=($(lsblk --noheadings --output PKNAME,PARTN "$ptn" | xargs))
exit_on_error $? "${ptn_data[*]}"

# check if ESP exists
parted /dev/"${ptn_data[0]}" print | grep -q esp
declare -i is_esp=$(( ! $? ))

if (( is_esp )); then
    # modules to embed in grub bootloader 
    grub_modules="all_video boot btrfs cat chain configfile echo efifwsetup efinet "\
"ext2 fat font gettext gfxmenu gfxterm gfxterm_background gzio "\
"halt help hfsplus iso9660 jpeg keystatus loadenv loopback linux "\
"ls lsefi lsefimmap lsefisystab lssal memdisk minicmd normal ntfs "\
"part_apple part_msdos part_gpt password_pbkdf2 png probe reboot "\
"regexp search search_fs_uuid search_fs_file search_label sleep "\
"smbios squash4 test true video xfs zfs zfscrypt zfsinfo cpuid "\
"play tpm cryptodisk gcry_arcfour gcry_blowfish gcry_camellia "\
"gcry_cast5 gcry_crc gcry_des gcry_dsa gcry_idea gcry_md4 gcry_md5 "\
"gcry_rfc2268 gcry_rijndael gcry_rmd160 gcry_rsa gcry_seed "\
"gcry_serpent gcry_sha1 gcry_sha256 gcry_sha512 gcry_tiger "\
"gcry_twofish gcry_whirlpool luks lvm mdraid09 mdraid1x raid5rec "\
"raid6rec http tftp"

    # install grub to ESP/<distro>
    res=$(grub-install --modules="$grub_modules" --sbat=/usr/share/grub/sbat.csv \
                       --efi-directory="$bootdir" --recheck --target=x86_64-efi)
    exit_on_error $? "$res"
fi

# check if bios partition exists
if parted /dev/"${ptn_data[0]}" print | grep -q bios_grub; then
    # install grub to bios partition
    res=$(grub-install --boot-directory='$dstdir' --recheck --target=i386-pc \
                       /dev/"${ptn_data[0]}")
    exit_on_error $? "$res"
fi

# get distro string
distro=$(uname -n)
exit_on_error $? "$res"

# install efi boot entry even if not secure boot
if efibootmgr > /dev/null; then
    # create new UEFI boot entry for shim
    res=$(efibootmgr --unicode --disk /dev/"${ptn_data[0]}" --part "${ptn_data[1]}" \
                     --create --label "Shim" --loader /EFI/"$distro"/shimx64.efi)
    exit_on_error $? "$res"
fi

# if ESP exists, sign grub bootloaders
if (( is_esp )); then
    bl_dir="$bootdir/EFI/" # bl -> bootloader
    bl_name="grubx64.efi"
    keyfile="MOK.key"
    crtfile="MOK.crt"

    cd "$bl_dir"

    def_bl_dir="$bl_dir/BOOT/"
    if [[ -s "$def_bl_dir" ]]; then
        # copy grub bootloader to EFI/BOOT
        full_bl_path="$bl_dir/$distro/$bl_name"
        res=$(cp "$full_bl_path" "$def_bl_dir")
        exit_on_error $? "$res"

        # sign grub bootloader in EFI/BOOT used by external device to boot
        full_bl_path="$def_bl_dir/$bl_name"
        if ! sbverify --cert "$crtfile" "$full_bl_path" &>/dev/null; then
            res=$(sbsign --key "$keyfile" --cert "$crtfile" --output "$full_bl_path" \
                                                                     "$full_bl_path")
            exit_on_error $? "$res"
        fi
    fi

    # sign grub bootloader in EFI/<distro> used by internal device to boot
    full_bl_path="$bl_dir/$distro/$bl_name"
    if ! sbverify --cert "$crtfile" "$full_bl_path" &>/dev/null; then
        res=$(sbsign --key "$keyfile" --cert "$crtfile" --output "$full_bl_path" \
                                                                 "$full_bl_path")
        exit_on_error $? "$res"
    fi
fi

# update grub config file
res=$(grub-mkconfig -o "$bootdir"/grub/grub.cfg)
exit_on_error $? "$res"

exec 2> /dev/tty # restore stderr

# update linux kernel version in grub config file
/usr/local/bin/upd_grub_cfg.sh
