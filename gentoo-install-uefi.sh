# ----------------------------------------------------------
# made by beamyyl
# This is the EFI installer.
# ----------------------------------------------------------
#!/bin/bash
set -e

echo ">>> Make sure disks are partitioned and mounted to /mnt/gentoo and /mnt/gentoo/boot/efi."
sleep 3

# ----------------------------------------------------------
# Download stage3
# ----------------------------------------------------------
echo ">>> Select a mirror and download the latest OpenRC stage3"
links https://www.gentoo.org/downloads/

# ----------------------------------------------------------
# Extract stage3
# ----------------------------------------------------------
tar xpvf stage3-*.tar.xz \
  --xattrs-include='*.*' \
  --numeric-owner \
  -C /mnt/gentoo

cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

# ----------------------------------------------------------
# Binary packages
# ----------------------------------------------------------

echo 'EMERGE_DEFAULT_OPTS="${EMERGE_DEFAULT_OPTS} --getbinpkg"' >> /mnt/gentoo/etc/portage/make.conf
echo 'FEATURES="getbinpkg"' >> /mnt/gentoo/etc/portage/make.conf

# ----------------------------------------------------------
# Accept all licenses
# ----------------------------------------------------------

echo 'ACCEPT_LICENSE="*"' >> /mnt/gentoo/etc/portage/make.conf

# ----------------------------------------------------------
# Generating FSTAB
# ----------------------------------------------------------

echo ">>> Generating fstab..."
genfstab -U /mnt/gentoo > /mnt/gentoo/etc/fstab

# ----------------------------------------------------------
# Enter chroot
# ----------------------------------------------------------
arch-chroot /mnt/gentoo /bin/bash <<'EOF'
source /etc/profile
export PS1="(gentoo) ${PS1}"

# Sync portage
emerge-webrsync
emaint binhost --sync
emerge-webrsync
getuto
emerge --sync --quiet

# Mirrors
emerge -qgv --oneshot app-portage/mirrorselect
mirrorselect -i -o >> /etc/portage/make.conf

# CPU flags
emerge -gqv --oneshot app-portage/cpuid2cpuflags
mkdir -p /etc/portage/package.use
echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags

# World update (binary)
emerge -qvquDU --getbinpkg @world

# Firmware & kernel
mkdir -p /etc/portage/package.use
echo 'sys-kernel/installkernel dracut' >> /etc/portage/package.use/00installkernel
emerge -qv sys-kernel/linux-firmware sys-firmware/sof-firmware sys-kernel/gentoo-kernel-bin

# Hostname
echo "gentoo" > /etc/hostname

# Networking
rc-update add dbus default
emerge -qv net-misc/networkmanager
rc-update add NetworkManager default

# Utilities
emerge -qv vim nano
emerge -qv sys-process/cronie
rc-update add cronie default

# ----------------------------------------------------------
# Bootloader (EFI)
# ----------------------------------------------------------
echo 'GRUB_PLATFORMS="efi-64"' >> /etc/portage/make.conf

emerge -qv \
  sys-boot/grub \
  sys-boot/shim \
  sys-boot/mokutil \
  sys-boot/efibootmgr

grub-install \
  --target=x86_64-efi \
  --efi-directory=/boot/efi \
  --bootloader-id=Gentoo

grub-mkconfig -o /boot/grub/grub.cfg

# Environment
env-update
EOF

# ----------------------------------------------------------
# Root password
# ----------------------------------------------------------
echo ">>> Set root password"
arch-chroot /mnt/gentoo /bin/bash -c 'passwd'

echo "=================================================="
echo " Gentoo installation complete!"
echo " You may reboot or chroot back in to continue."
echo "=================================================="



