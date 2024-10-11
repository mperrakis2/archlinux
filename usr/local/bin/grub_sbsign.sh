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

arch=$(uname -m)                # get architecture
arch="${arch//+([[:digit:]])_}" # remove chars not part of bl filename
distro="$(uname -n)"

if (( is_esp )); then
    # modules to embed in grub bootloader 
    grub_modules="all_video backtrace bitmap bitmap_scale bli blocklist boot "\
"boottime btrfs bufio cacheinfo cat chain cmdline_cat_test cmp cmp_test "\
"configfile cpio cpuid crc64 cryptodisk date datehook datetime disk diskfilter "\
"echo efifwsetup efinet efitextmode efi_gop efi_uga elf eval exfat ext2 fat "\
"file fixvideo font fshelp functional_test gcry_arcfour gcry_blowfish "\
"gcry_camellia gcry_cast5 gcry_crc gcry_des gcry_dsa gcry_idea gcry_md4 "\
"gcry_md5 gcry_rfc2268 gcry_rijndael gcry_rmd160 gcry_rsa gcry_seed "\
"gcry_serpent gcry_sha1 gcry_sha256 gcry_sha512 gcry_tiger gcry_twofish "\
"gcry_whirlpool gettext gfxmenu gfxterm gfxterm_background gfxterm_menu "\
"gptsync gptsync gzio halt hashsum hdparm hello hello help hexdump hfsplus "\
"http iorw iso9660 jpeg keystatus linux loadbios loadenv loopback ls lsacpi "\
"lsefi lsefimmap lsefisystab lsmmap lspci lssal luks luks2 lvm mdraid1x "\
"mdraid09 memdisk memrw minicmd mmap msdospart multiboot multiboot2 normal "\
"ntfs ntfscomp parttool part_apple part_gpt part_msdos password "\
"password_pbkdf2 play png probe progress raid5rec raid6rec read reboot regexp "\
"search search_fs_file search_fs_uuid search_label signature_test sleep "\
"sleep_test smbios squash4 tar terminal terminfo test testload testspeed tftp "\
"time tpm tr true usb usbtest video videoinfo videotest videotest_checksum "\
"video_bochs video_cirrus video_colors video_fb xfs xzio zfs zfscrypt zfsinfo"

    # install grub to ESP/BOOT
    res=$(grub-install --modules="$grub_modules" --sbat=/usr/share/grub/sbat.csv \
                       --efi-directory="$bootdir" --removable --recheck \
                       --target=x86_64-efi)
    exit_on_error $? "$res"

    # install grub to ESP/<distro>
    res=$(grub-install --modules="$grub_modules" --sbat=/usr/share/grub/sbat.csv \
                       --efi-directory="$bootdir" --recheck --target=x86_64-efi)
    exit_on_error $? "$res"

    bl_dir="$bootdir/EFI/"     # bl -> bootloader
    def_bl_dir="$bl_dir"/BOOT/ # bootloader dir for external drives
    bl_path="$def_bl_dir"/BOOT"${arch^^}".EFI
    bl_name="grub$arch.efi"

    mv "$bl_path" "$def_bl_dir/$bl_name" # rename bootloader

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

# install efi boot entry even if not secure boot
if efibootmgr &> /dev/null; then
    # create new UEFI boot entry for shim
    res=$(efibootmgr --unicode --disk /dev/"${ptn_data[0]}" --part "${ptn_data[1]}" \
                     --create --label "Shim" --loader /EFI/"$distro"/shim"$arch".efi)
    exit_on_error $? "$res"
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
