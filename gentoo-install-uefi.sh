# made by beamyyl
# MAKE SURE TO MOUNT EVERYTHING TO /mnt/gentoo AND ALREADY CONFIGURE THE DISKS!
# This is the EFI installer.
# Also, make sure to download the latest !! OPENRC !! stage3 file.
links https://www.gentoo.org/downloads/mirrors
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo
cd /mnt/gentoo
echo 'EMERGE_DEFAULT_OPTS="${EMERGE_DEFAULT_OPTS} --getbinpkg"' >> /mnt/gentoo/etc/portage/make.conf
echo 'FEATURES="getbinpkg"' >> /mnt/gentoo/etc/portage/make.conf
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run
chroot /mnt/gentoo /bin/bash -c 'emerge-webrsync'
chroot /mnt/gentoo /bin/bash -c 'emerge -gv --oneshot app-portage/mirrorselect'
chroot /mnt/gentoo /bin/bash -c 'mirrorselect -i -o >> /etc/portage/make.conf'
chroot /mnt/gentoo /bin/bash -c 'emerge --sync --quiet'
chroot /mnt/gentoo /bin/bash -c 'emerge -gv --oneshot app-portage/cpuid2cpuflags'
chroot /mnt/gentoo /bin/bash -c 'echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags'
chroot /mnt/gentoo /bin/bash -c 'emerge --verbose --quiet --update --deep --newuse --getbinpkg @world'
chroot /mnt/gentoo /bin/bash -c 'emerge -gvq sys-kernel/linux-firmware sys-firmware/sof-firmware'
chroot /mnt/gentoo /bin/bash -c 'emerge -gvuq sys-kernel/gentoo-kernel-bin'
chroot /mnt/gentoo /bin/bash -c 'emerge -gvuq genfstab'
chroot /mnt/gentoo /bin/bash -c 'genfstab -U >> /etc/fstab'
chroot /mnt/gentoo /bin/bash -c 'echo gentoo > /etc/hostname'
chroot /mnt/gentoo /bin/bash -c 'emerge -qvg networkmanager'
chroot /mnt/gentoo /bin/bash -c 'rc-update add NetworkManager default'
chroot /mnt/gentoo /bin/bash -c 'emerge -qvg vim nano'
chroot /mnt/gentoo /bin/bash -c 'emerge -qvg sys-process/cronie'
chroot /mnt/gentoo /bin/bash -c 'rc-update add cronie default'
chroot /mnt/gentoo /bin/bash -c 'echo 'GRUB_PLATFORMS="efi-64"' >> /etc/portage/make.conf'
chroot /mnt/gentoo /bin/bash -c 'emerge -qv sys-boot/grub sys-boot/shim sys-boot/mokutil sys-boot/efibootmgr'
chroot /mnt/gentoo /bin/bash -c 'emerge -qv --newuse sys-boot/grub'
chroot /mnt/gentoo /bin/bash -c 'grub-install --target=x86_64-efi --efi-directory=/efi --removable'
chroot /mnt/gentoo /bin/bash -c 'grub-install --efi-directory=/efi'
chroot /mnt/gentoo /bin/bash -c 'cp /usr/share/shim/BOOTX64.EFI /efi/EFI/Gentoo/shimx64.efi'
chroot /mnt/gentoo /bin/bash -c 'cp /usr/share/shim/mmx64.efi /efi/EFI/Gentoo/mmx64.efi'
chroot /mnt/gentoo /bin/bash -c 'cp /usr/lib/grub/grub-x86_64.efi.signed /efi/EFI/Gentoo/grubx64.efi'
chroot /mnt/gentoo /bin/bash -c 'grub-mkconfig -o /efi/EFI/Gentoo/grub.cfg'
chroot /mnt/gentoo /bin/bash -c 'grub-mkconfig -o /boot/grub/grub.cfg'
chroot /mnt/gentoo /bin/bash -c 'env-update'
chroot /mnt/gentoo /bin/bash -c 'exit'
echo 'Choose a password for the ROOT account:'
chroot /mnt/gentoo /bin/bash -c 'passwd'
echo 'The installation is finished. You can chroot into the OS to do changes, or you can just reboot.'
