# made by beamyyl
# MAKE SURE TO MOUNT EVERYTHING TO /mnt/gentoo AND ALREADY CONFIGURE THE DISKS!
# This is the EFI installer.
# Also, make sure to download the latest !! OPENRC !! stage3 file.
#!/bin/bash
# Gentoo EFI Auto-Installer (OpenRC)
# Modified for LiveGUI environment

GENTOO="/mnt/gentoo"

echo "Checking environment..."
if [[ ! -d "$GENTOO/etc" ]]; then
    echo "Error: /mnt/gentoo is not populated. Please mount your partitions first!"
    exit 1
fi

# 1. Download Stage 3 (Automated for OpenRC)
echo "Downloading latest Stage 3 tarball..."
cd $GENTOO
STAGE3_URL=$(curl -s https://www.gentoo.org/downloads/mirrors/ | grep -oP 'https?://[^\"]+stage3-amd64-openrc-[0-9TZ]+.tar.xz' | head -n 1)
# Fallback if the regex fails due to site changes
if [ -z "$STAGE3_URL" ]; then
    echo "Manual download required. Opening mirrors..."
    links https://www.gentoo.org/downloads/mirrors/
else
    wget "$STAGE3_URL"
fi

# 2. Extract Tarball
echo "Extracting stage3..."
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C $GENTOO

# 3. Configure Portage & Binary Packages
echo "Configuring Portage..."
cat <<EOF >> $GENTOO/etc/portage/make.conf
EMERGE_DEFAULT_OPTS="\${EMERGE_DEFAULT_OPTS} --getbinpkg --ask=n"
FEATURES="getbinpkg"
ACCEPT_LICENSE="*"
VIDEO_CARDS="amdgpu radeon nouveau intel"
EOF

# 4. Prepare Chroot Environment
cp --dereference /etc/resolv.conf $GENTOO/etc/
mount --types proc /proc $GENTOO/proc
mount --rbind /sys $GENTOO/sys
mount --make-rslave $GENTOO/sys
mount --rbind /dev $GENTOO/dev
mount --make-rslave $GENTOO/dev
mount --bind /run $GENTOO/run
mount --make-slave $GENTOO/run

# 5. Execution within Chroot
echo "Entering Chroot for system configuration..."
chroot $GENTOO /bin/bash <<'EOF'
source /etc/profile
export PS1="(chroot) $PS1"

# Sync and Portage tools
emerge-webrsync
emerge --oneshot app-portage/mirrorselect app-portage/cpuid2cpuflags sys-kernel/genfstab

# Optimization
echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags

# System Update (Using Binaries)
emerge --update --deep --newuse @world

# Kernel and Firmware
emerge sys-kernel/linux-firmware sys-firmware/sof-firmware sys-kernel/gentoo-kernel-bin

# Fstab and Networking
genfstab -U / >> /etc/fstab
echo "gentoo" > /etc/hostname
emerge networkmanager sys-process/cronie vim nano
rc-update add NetworkManager default
rc-update add cronie default

# Bootloader (EFI)
echo 'GRUB_PLATFORMS="efi-64"' >> /etc/portage/make.conf
emerge --newuse sys-boot/grub:2 sys-boot/efibootmgr

# Standard EFI Install
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Gentoo
grub-mkconfig -o /boot/grub/grub.cfg

env-update
EOF

# 6. Finalization
echo "------------------------------------------------"
echo "Set the ROOT password:"
chroot $GENTOO /bin/bash -c "passwd"

echo "Installation complete. Unmount and reboot!"
