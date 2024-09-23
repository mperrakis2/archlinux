#! /bin/bash

# copy shim binaries to ESP

bl_dir="$(bootctl -p)/EFI/"
def_bl_dir="$bl_dir/BOOT/"
distro_bl_dir="$bl_dir/$(uname -n)/"
shim_dir=/usr/share/shim-signed/
shim_fname=shimx64.efi
mm_fname=mmx64.efi

cp "$shim_dir/$shim_fname" "$def_bl_dir"/BOOTX64.EFI
cp "$shim_dir/$mm_fname" "$def_bl_dir"
cp "$shim_dir/$shim_fname" "$shim_dir/$mm_fname" "$distro_bl_dir"
