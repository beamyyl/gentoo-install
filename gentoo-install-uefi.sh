# made by beamyyl
# MAKE SURE TO MOUNT EVERYTHING TO /mnt/gentoo AND ALREADY CONFIGURE THE DISKS!
# This is the EFI installer.
# Also, make sure to download the latest !! OPENRC !! stage3 file.
#!/bin/bash

printf "Did you mount the root and efi partitions? (y/n): "
read confirm
if [[ "$confirm" != "y" ]]; then
    exit 1
fi

links https://www.gentoo.org/downloads/mirrors
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

chroot /mnt/gentoo /bin/bash <<'EOF'
source /etc/profile
echo 'EMERGE_DEFAULT_OPTS="${EMERGE_DEFAULT_OPTS} --getbinpkg"' >> /etc/portage/make.conf
echo 'FEATURES="getbinpkg"' >> /etc/portage/make.conf
emerge-webrsync
emerge -gv --oneshot app-portage/mirrorselect
mirrorselect -i -o >> /etc/portage/make.conf
emerge --sync --quiet
emerge -gv --oneshot app-portage/cpuid2cpuflags
echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags
emerge --verbose --quiet --update --deep --newuse --getbinpkg @world
emerge -gvq sys-kernel/linux-firmware sys-firmware/sof-firmware
emerge -gvuq sys-kernel/gentoo-kernel-bin
emerge -gvuq genfstab
genfstab -U / >> /etc/fstab
echo gentoo > /etc/hostname
emerge -qvg networkmanager
rc-update add NetworkManager default
emerge -qvg vim nano sys-process/cronie
rc-update add cronie default
echo 'GRUB_PLATFORMS="efi-64"' >> /etc/portage/make.conf
emerge -qv sys-boot/grub sys-boot/shim sys-boot/mokutil sys-boot/efibootmgr
mkdir -p /efi/EFI/Gentoo
grub-install --target=x86_64-efi --efi-directory=/efi --removable
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=Gentoo
cp /usr/share/shim/BOOTX64.EFI /efi/EFI/Gentoo/shimx64.efi
cp /usr/share/shim/mmx64.efi /efi/EFI/Gentoo/mmx64.efi
cp /usr/lib/grub/grub-x86_64.efi.signed /efi/EFI/Gentoo/grubx64.efi
grub-mkconfig -o /boot/grub/grub.cfg
env-update
passwd
EOF

echo 'The installation is finished. You can chroot into the OS to do changes, or you can just reboot.'
