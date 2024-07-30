#! /bin/bash

# copy shim binaries to ESP

cp /usr/share/shim-signed/shimx64.efi /boot/EFI/BOOT/BOOTX64.EFI
cp /usr/share/shim-signed/mmx64.efi /boot/EFI/BOOT/
cp /usr/share/shim-signed/shimx64.efi /boot/EFI/"$(uname -n)"/
cp /usr/share/shim-signed/mmx64.efi /boot/EFI/"$(uname -n)"/
