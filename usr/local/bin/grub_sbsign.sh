#!/usr/bin/bash

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

# install grub
bootdir="$(bootctl -p)"
grub-install --modules="$grub_modules" --sbat=/usr/share/grub/sbat.csv \
             --efi-directory="$bootdir" --recheck --target=x86_64-efi

# create new UEFI boot entry for shim
ptn="$(findmnt --noheadings --output SOURCE --target "$bootdir")"
ptn_data=($(lsblk --noheadings --output PKNAME,PARTN "$ptn" | xargs))
distro="$(uname -n)"
efibootmgr --unicode --disk /dev/"${ptn_data[0]}" --part "${ptn_data[1]}" \
           --create --label "Shim" --loader /EFI/"$distro"/shimx64.efi

# copy grub bootloader to dir used by external devices to boot, i.e. EFI/BOOT
# bl -> bootloader
bl_dir="$bootdir/EFI/"
def_bl_dir="$bl_dir/BOOT/"
bl_name="grubx64.efi"
full_bl_path="$bl_dir/$distro/$bl_name"
cp "$full_bl_path" "$def_bl_dir"

# sign grub bootloaders
keyfile="MOK.key"
crtfile="MOK.crt"
cd "$bl_dir"
! sbverify --cert "$crtfile" "$full_bl_path" &>/dev/null &&
    sbsign --key "$keyfile" --cert "$crtfile" --output "$full_bl_path" "$full_bl_path"

full_bl_path="$def_bl_dir/$bl_name"
! sbverify --cert "$crtfile" "$bootloader" &>/dev/null &&
    sbsign --key "$keyfile" --cert "$crtfile" --output "$full_bl_path" "$full_bl_path"

# update grub config file
grub-mkconfig -o "$bootdir"/grub/grub.cfg

# update linux kernel version in grub config file
/usr/local/bin/upd_grub_cfg.sh
