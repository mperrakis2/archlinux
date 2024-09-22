#! /bin/bash

# copy shim binaries to ESP

bl_dir="$(bootctl -p)/EFI/"
def_bl_dir="$bl_dir/BOOT/"
distro_bl_dir="$bl_dir/$(uname -n)/"

cp /usr/share/shim-signed/shimx64.efi "$def_bl_dir"/BOOTX64.EFI
cp /usr/share/shim-signed/mmx64.efi "$def_bl_dir"
cp /usr/share/shim-signed/shimx64.efi "$distro_bl_dir"
cp /usr/share/shim-signed/mmx64.efi "$distro_bl_dir"
