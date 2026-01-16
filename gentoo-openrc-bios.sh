#!/bin/bash
set -e

# ----------------------------------------------------------
# made by beamyyl
# This is the BIOS/MBR installer.
# ----------------------------------------------------------

echo ">>> Ensure your root partition is marked as 'Bootable' in fdisk/cfdisk and that its MBR."
sleep 3

# ----------------------------------------------------------
# Download & Extract Stage3
# ----------------------------------------------------------
echo ">>> Select a mirror and download the latest OpenRC stage3"
links https://www.gentoo.org/downloads/

tar xpvf stage3-*.tar.xz \
  --xattrs-include='*.*' \
  --numeric-owner \
  -C /mnt/gentoo

cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

# ----------------------------------------------------------
# Portage Configuration
# ----------------------------------------------------------
echo 'EMERGE_DEFAULT_OPTS="${EMERGE_DEFAULT_OPTS} --getbinpkg"' >> /mnt/gentoo/etc/portage/make.conf
echo 'FEATURES="getbinpkg"' >> /mnt/gentoo/etc/portage/make.conf
echo 'ACCEPT_LICENSE="*"' >> /mnt/gentoo/etc/portage/make.conf

# ----------------------------------------------------------
# FSTAB Generation
# ----------------------------------------------------------
echo ">>> Generating fstab..."
genfstab -U /mnt/gentoo > /mnt/gentoo/etc/fstab

# ----------------------------------------------------------
# Enter Chroot
# ----------------------------------------------------------
arch-chroot /mnt/gentoo /bin/bash <<'EOF'
source /etc/profile
export PS1="(gentoo) ${PS1}"

# Syncing
getuto
emaint binhost --sync
emerge-webrsync
emerge --sync --quiet

# Optimizations
emerge -qgv --oneshot app-portage/mirrorselect app-portage/cpuid2cpuflags
mirrorselect -i -o >> /etc/portage/make.conf
mkdir -p /etc/portage/package.use
echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags

# World Update
emerge -qvquDU --getbinpkg @world

# Kernel & Firmware
# Using the same fix from before to ensure /boot is populated
mkdir -p /etc/portage/package.use
echo 'sys-kernel/installkernel dracut' >> /etc/portage/package.use/00installkernel
emerge -qv sys-kernel/linux-firmware sys-firmware/sof-firmware sys-kernel/gentoo-kernel-bin

# System Essentials
echo "gentoo" > /etc/hostname
rc-update add dbus default
emerge -qv net-misc/networkmanager sys-process/cronie vim nano
rc-update add NetworkManager default
rc-update add cronie default

# ----------------------------------------------------------
# GRUB for BIOS/MBR
# ----------------------------------------------------------
# Tell Portage we are using the PC (BIOS) platform
echo 'GRUB_PLATFORMS="pc"' >> /etc/portage/make.conf

emerge -qv sys-boot/grub

# Install to the Master Boot Record of the drive
# Ensure /dev/sda is your correct VM disk
grub-install --target=i386-pc /dev/sda

# Generate the config
grub-mkconfig -o /boot/grub/grub.cfg

env-update
EOF

# ----------------------------------------------------------
# Set Root Password
# ----------------------------------------------------------
echo ">>> Set root password"
arch-chroot /mnt/gentoo /bin/bash -c 'passwd'

echo "=================================================="
echo " Gentoo installation complete!"
echo "=================================================="
