#! /bin/bash

# copy shim binaries to ESP

bootdir="$(bootctl -p)"
cp /usr/share/shim-signed/shimx64.efi "$bootdir"/EFI/BOOT/BOOTX64.EFI
cp /usr/share/shim-signed/mmx64.efi "$bootdir"/EFI/BOOT/
cp /usr/share/shim-signed/shimx64.efi "$bootdir"/EFI/"$(uname -n)"/
cp /usr/share/shim-signed/mmx64.efi "$bootdir"/"$(uname -n)"/
