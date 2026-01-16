# ----------------------------------------------------------
# made by beamyyl
# This is the BIOS systemd installer.
# ----------------------------------------------------------
#!/bin/bash
set -e

echo ">>> Ensure MBR/dos label and Bootable flag are set on /dev/sda."
sleep 3

# ----------------------------------------------------------
# Download stage3 (SYSTEMD version)
# ----------------------------------------------------------
echo ">>> Select a mirror and download the latest SYSTEMD stage3"
links https://www.gentoo.org/downloads/

# ----------------------------------------------------------
# Extract stage3
# ----------------------------------------------------------
tar xpvf stage3-*-systemd-*.tar.xz \
  --xattrs-include='*.*' \
  --numeric-owner \
  -C /mnt/gentoo

cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

# ----------------------------------------------------------
# Configuration
# ----------------------------------------------------------
echo 'EMERGE_DEFAULT_OPTS="${EMERGE_DEFAULT_OPTS} --getbinpkg"' >> /mnt/gentoo/etc/portage/make.conf
echo 'FEATURES="getbinpkg"' >> /mnt/gentoo/etc/portage/make.conf
echo 'ACCEPT_LICENSE="*"' >> /mnt/gentoo/etc/portage/make.conf

# Generating FSTAB
genfstab -U /mnt/gentoo > /mnt/gentoo/etc/fstab

# ----------------------------------------------------------
# Enter chroot
# ----------------------------------------------------------
arch-chroot /mnt/gentoo /bin/bash <<'EOF'
source /etc/profile
export PS1="(systemd-bios) ${PS1}"

# Sync
getuto
emaint binhost --sync
emerge-webrsync
emerge --sync --quiet

# CPU flags
emerge -gqv --oneshot app-portage/cpuid2cpuflags
mkdir -p /etc/portage/package.use
echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags

# World update
emerge -qvquDU --getbinpkg @world

# Firmware & kernel
mkdir -p /etc/portage/package.use
echo 'sys-kernel/installkernel dracut' >> /etc/portage/package.use/00installkernel
emerge -qv sys-kernel/linux-firmware sys-firmware/sof-firmware sys-kernel/gentoo-kernel-bin

# Hostname & Machine ID
echo "gentoo" > /etc/hostname
systemd-machine-id-setup

# Networking
emerge -qv net-misc/networkmanager
systemctl enable NetworkManager

# Utilities
emerge -qv vim nano sys-process/cronie
systemctl enable cronie

# ----------------------------------------------------------
# Bootloader (BIOS)
# ----------------------------------------------------------
echo 'GRUB_PLATFORMS="pc"' >> /etc/portage/make.conf

emerge -qv sys-boot/grub

# Target the DRIVE (/dev/sda)
grub-install --target=i386-pc /dev/sda

grub-mkconfig -o /boot/grub/grub.cfg

env-update
EOF

# ----------------------------------------------------------
# Root password
# ----------------------------------------------------------
echo ">>> Set root password"
arch-chroot /mnt/gentoo /bin/bash -c 'passwd'

echo "=================================================="
echo " Gentoo systemd BIOS installation complete!"
echo "=================================================="
