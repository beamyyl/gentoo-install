#!/bin/bash
# =============================================================================
# The "best" Gentoo Install Script
# Supports: UEFI or BIOS + OpenRC or systemd
# =============================================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }
ask()   { echo -e "${CYAN}[INPUT]${NC} $*"; }

# =============================================================================
# Sanity checks
# =============================================================================
for cmd in arch-chroot genfstab links; do
    command -v "$cmd" &>/dev/null \
        || die "'$cmd' not found. Are you booted from the official Gentoo live ISO?"
done

# =============================================================================
# Reminders
# =============================================================================
clear
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║            GENTOO INSTALLER                                        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
info "This script will install Gentoo to /mnt/gentoo."
info "Your partitions must be formatted and mounted BEFORE continuing."
echo ""
echo "Here are some partition examples:"
echo "  Mount commands (UEFI):"
echo ""
echo "    mount /dev/sda3 /mnt/gentoo"
echo "    mkdir -p /mnt/gentoo/efi"
echo "    mount /dev/sda1 /mnt/gentoo/efi"
echo "    swapon /dev/sda2"
echo ""
echo "  For BIOS/GPT, you MUST have a 1MB BIOS BOOT partition."
echo "  Do NOT format or mount it."
echo ""
echo ""
echo "  Mount commands (BIOS):"
echo ""
echo "    mount /dev/sda3 /mnt/gentoo"
echo "    swapon /dev/sda2"
echo ""
warn "If your partitions are NOT yet mounted, press Ctrl+C now,"
warn "mount them, then re-run this script."
echo ""
read -rp "  Press ENTER once your partitions are mounted..."
echo ""

mountpoint -q /mnt/gentoo || die "/mnt/gentoo is not mounted."
info "Root mount point verified."
echo ""

# =============================================================================
# Boot mode & init system selection
# =============================================================================
info "============================================================"
info " BOOT MODE & INIT SYSTEM"
info "============================================================"
echo ""

ask "Boot mode — are you using UEFI or BIOS?"
ask "  1) UEFI  (modern systems, GPT disk)"
ask "  2) BIOS  (legacy / older systems, MBR or GPT disk)"
read -rp "  Choice [1/2]: " BOOT_CHOICE
case "$BOOT_CHOICE" in
    1) BOOT_MODE="uefi" ;;
    2) BOOT_MODE="bios" ;;
    *) die "Invalid choice. Enter 1 or 2." ;;
esac
echo ""

if [ "$BOOT_MODE" = "uefi" ]; then
    mountpoint -q /mnt/gentoo/efi \
        || die "/mnt/gentoo/efi is not mounted. Mount your EFI partition and re-run."
    info "UEFI mode selected. EFI mount verified."
else
    info "BIOS mode selected."
    echo ""
    ask "Enter the disk to install GRUB to (e.g. /dev/sda, /dev/vda, /dev/nvme0n1)."
    ask "This should be the whole disk, NOT a partition."
    read -rp "  Install disk: " GRUB_DISK
    [ -z "$GRUB_DISK" ] && die "Disk cannot be empty."
    [ -b "$GRUB_DISK" ] || die "'$GRUB_DISK' is not a valid block device."
    info "GRUB will be installed to: $GRUB_DISK"
fi
echo ""

ask "Init system — OpenRC or systemd?"
ask "  1) OpenRC  (Gentoo's native init, lightweight)"
ask "  2) systemd (used by most other distros)"
read -rp "  Choice [1/2]: " INIT_CHOICE
case "$INIT_CHOICE" in
    1) INIT_SYSTEM="openrc" ;;
    2) INIT_SYSTEM="systemd" ;;
    *) die "Invalid choice. Enter 1 or 2." ;;
esac
echo ""
info "Selected: boot=$BOOT_MODE  init=$INIT_SYSTEM"
echo ""

# =============================================================================
# System configuration
# =============================================================================
info "============================================================"
info " SYSTEM CONFIGURATION"
info "============================================================"
echo ""

ask "Enter a hostname for your new system."
ask "This is the name your machine will go by on the network (e.g. 'gentoo-desktop')."
read -rp "  Hostname: " NEW_HOSTNAME
[ -z "$NEW_HOSTNAME" ] && die "Hostname cannot be empty."
echo ""

ask "Enter your locale (press ENTER to accept the default: en_US.UTF-8)."
read -rp "  Locale: " LOCALE
LOCALE="${LOCALE:-en_US.UTF-8}"
echo ""

info "Configuration summary:"
echo "   Boot mode : $BOOT_MODE"
echo "   Init      : $INIT_SYSTEM"
echo "   Hostname  : $NEW_HOSTNAME"
echo "   Locale    : $LOCALE"
echo ""
read -rp "  Press ENTER to continue..."
echo ""

# =============================================================================
# Stage3
# =============================================================================
info "============================================================"
info " STAGE3 DOWNLOAD"
info "============================================================"
echo ""
info "Opening the Gentoo downloads page in the Links browser."
info "Navigate to: releases → amd64 → autobuilds"

if [ "$INIT_SYSTEM" = "openrc" ]; then
    info "Download: stage3-amd64-desktop-openrc-*.tar.xz"
else
    info "Download: stage3-amd64-desktop-systemd-*.tar.xz"
fi

warn "When the download finishes, press 'q' to quit Links."
echo ""
read -rp "  Press ENTER to open Links..."
echo ""

cd /mnt/gentoo
links https://www.gentoo.org/downloads/

echo ""
TARBALL=$(ls /mnt/gentoo/stage3-amd64-*.tar.xz 2>/dev/null | head -n1)
[ -z "$TARBALL" ] && die "No stage3 tarball found in /mnt/gentoo. Did the download finish?"

info "Found: $(basename "$TARBALL")"
info "Extracting..."
tar xpf "$TARBALL" --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo -q 2>/dev/null \
    || tar xpf "$TARBALL" --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo
# Note: tar doesn't have a -q flag; silence via output redirect for cleanliness
rm -f "$TARBALL"
info "Stage3 extracted."
echo ""

# =============================================================================
# make.conf
# =============================================================================
info "============================================================"
info " CONFIGURING make.conf"
info "============================================================"
if [ "$BOOT_MODE" = "uefi" ]; then
    TARGET_GRUB="efi-64"
else
    TARGET_GRUB="pc"
fi

cat >> /mnt/gentoo/etc/portage/make.conf <<EOF

# Binary package host
FEATURES="\${FEATURES} getbinpkg"
FEATURES="\${FEATURES} binpkg-request-signature"

# GRUB platform
GRUB_PLATFORMS="$TARGET_GRUB"
EOF
# cat 'EMERGE_DEFAULT_OPTS="--jobs=6 --load-average=8"' >> /mnt/gentoo/etc/portage/make.conf 

info "make.conf updated."
echo ""
sleep 0.5

# =============================================================================
# Binrepo setup
# =============================================================================
info "============================================================"
info " CONFIGURING BINREPOS"
info "============================================================"
mkdir -p /mnt/gentoo/etc/portage/binrepos.conf

cat >> /mnt/gentoo/etc/portage/binrepos.conf/gentoo.conf <<EOF

[gentoo-x86-64-v3]
priority = 9999
sync-uri = https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64-v3
location = /var/cache/binhost/gentoo-x86-64-v3
EOF

info "binrepos.conf updated with x86-64v3 repository."
echo ""

# =============================================================================
# package.use
# =============================================================================
info "============================================================"
info " CONFIGURING package.use"
info "============================================================"

mkdir -p /mnt/gentoo/etc/portage/package.use

if [ "$BOOT_MODE" = "uefi" ]; then
    echo "sys-kernel/installkernel grub dracut" \
        > /mnt/gentoo/etc/portage/package.use/installkernel
else
    echo "sys-kernel/installkernel grub dracut" \
        > /mnt/gentoo/etc/portage/package.use/installkernel
fi

cat > /mnt/gentoo/etc/portage/package.use/networkmanager <<'EOF'
net-misc/networkmanager wifi
net-wireless/wpa_supplicant dbus
EOF

info "package.use written."
echo ""

# =============================================================================
# Hostname
# =============================================================================
echo "$NEW_HOSTNAME" > /mnt/gentoo/etc/hostname
echo 'hostname="$NEW_HOSTNAME"' > /mnt/gentoo/etc/conf.d/hostname
cat > /mnt/gentoo/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${NEW_HOSTNAME}.localdomain ${NEW_HOSTNAME}
EOF

info "Hostname written to /mnt/gentoo/etc/hostname: $NEW_HOSTNAME"
echo ""

# =============================================================================
# Mounting pseudo-filesystems
# =============================================================================
info "============================================================"
info " PSEUDO-FILESYSTEMS & FSTAB"
info "============================================================"

cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

mount --types proc  /proc    /mnt/gentoo/proc
mount --rbind       /sys     /mnt/gentoo/sys
mount --make-rslave          /mnt/gentoo/sys
mount --rbind       /dev     /mnt/gentoo/dev
mount --make-rslave          /mnt/gentoo/dev
mount --bind        /run     /mnt/gentoo/run
mount --make-slave           /mnt/gentoo/run

info "Generating /etc/fstab..."
genfstab -U /mnt/gentoo >> /mnt/gentoo/etc/fstab
info "fstab contents:"
cat /mnt/gentoo/etc/fstab
echo ""

# =============================================================================
# setting up chroot
# =============================================================================
info "============================================================"
info " WRITING IN-CHROOT SCRIPT"
info "============================================================"

cat > /mnt/gentoo/root/chroot-install.sh <<CHROOT_EOF
#!/bin/bash
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "\${GREEN}[CHROOT]\${NC}  \$*"; }
warn()  { echo -e "\${YELLOW}[CHROOT]\${NC}  \$*"; }

BOOT_MODE="${BOOT_MODE}"
INIT_SYSTEM="${INIT_SYSTEM}"
NEW_HOSTNAME="${NEW_HOSTNAME}"
LOCALE="${LOCALE}"
GRUB_DISK="${GRUB_DISK}"

# ---------------------------------------------------------------------------
# Portage snapshot
# ---------------------------------------------------------------------------
emerge-webrsync -q

# ---------------------------------------------------------------------------
# Profile selection
# ---------------------------------------------------------------------------
info "Selecting desktop/${INIT_SYSTEM} profile..."

if [ "\${INIT_SYSTEM}" = "openrc" ]; then
    PROFILE_NUM=\$(eselect profile list \
        | grep -E 'desktop[[:space:]]' \
        | grep -v systemd | grep -v gnome | grep -v kde \
        | head -n1 | awk -F'[][]' '{print \$2}')
else
    PROFILE_NUM=\$(eselect profile list \
        | grep -E 'desktop.*systemd' \
        | grep -v gnome | grep -v kde \
        | head -n1 | awk -F'[][]' '{print \$2}')
fi

[ -z "\$PROFILE_NUM" ] && {
    warn "Could not auto-detect profile. Available profiles:"
    eselect profile list
    die "Set the profile manually with: eselect profile set <number>"
}

info "Setting profile \${PROFILE_NUM}..."
eselect profile set "\${PROFILE_NUM}"
eselect profile show

# ---------------------------------------------------------------------------
# Binary package keyring
# ---------------------------------------------------------------------------
info "Initialising binary package keyring..."
getuto -q 2>/dev/null || getuto

# ---------------------------------------------------------------------------
# Locale
# ---------------------------------------------------------------------------
info "Configuring locale: \${LOCALE}"
echo "\${LOCALE} UTF-8" >> /etc/locale.gen
locale-gen 2>/dev/null
LOCALE_NUM=\$(eselect locale list | grep "\${LOCALE}" | head -n1 | awk -F'[][]' '{print \$2}')
[ -n "\$LOCALE_NUM" ] && eselect locale set "\$LOCALE_NUM"
env-update && source /etc/profile

# ---------------------------------------------------------------------------
# CPU flags
# ---------------------------------------------------------------------------
emerge -q --ask=n app-portage/cpuid2cpuflags
mkdir -p /etc/portage/package.use
echo "*/* \$(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags
info "CPU flags written to /etc/portage/package.use/00cpu-flags:"
cat /etc/portage/package.use/00cpu-flags

# ---------------------------------------------------------------------------
# Firmware
# ---------------------------------------------------------------------------
echo 'ACCEPT_LICENSE="*"' >> /etc/portage/make.conf
emerge -q --ask=n sys-kernel/linux-firmware
emerge -q --ask=n sys-firmware/sof-firmware \
    || warn "sof-firmware not available, skipping."

# ---------------------------------------------------------------------------
# installkernel + dracut config
# ---------------------------------------------------------------------------
emerge -q --ask=n sys-kernel/installkernel

info "Configuring dracut..."
mkdir -p /etc/dracut.conf.d
ROOT_UUID=\$(findmnt -n -o UUID /)
cat > /etc/dracut.conf.d/00-installkernel.conf <<EOF
kernel_cmdline=" root=UUID=\${ROOT_UUID} "
EOF

# ---------------------------------------------------------------------------
# Kernel
# ---------------------------------------------------------------------------
info "Installing gentoo-kernel-bin..."
emerge -q --ask=n sys-kernel/gentoo-kernel-bin

# ---------------------------------------------------------------------------
# NetworkManager
# ---------------------------------------------------------------------------
info "Installing NetworkManager..."
emerge -q --ask=n net-misc/networkmanager

if [ "\${INIT_SYSTEM}" = "openrc" ]; then
    rc-update add NetworkManager default
else
    systemctl enable NetworkManager
fi

# ---------------------------------------------------------------------------
# Logging + cron
# ---------------------------------------------------------------------------
if [ "\${INIT_SYSTEM}" = "openrc" ]; then
    info "Installing syslog-ng and cronie..."
    emerge -q --ask=n app-admin/syslog-ng sys-process/cronie
    rc-update add syslog-ng default
    rc-update add cronie default
fi

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------
emerge -q --ask=n app-admin/sudo app-editors/vim
# ---------------------------------------------------------------------------
# GRUB
# ---------------------------------------------------------------------------
info "Installing GRUB..."
emerge -q --ask=n sys-boot/grub --noreplace 

if [ "\${BOOT_MODE}" = "uefi" ]; then
    info "Running grub-install (UEFI)..."
    grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=Gentoo
else
    info "Running grub-install (BIOS) to \${GRUB_DISK}..."
    grub-install "\${GRUB_DISK}"
fi

info "Generating grub.cfg..."
grub-mkconfig -o /boot/grub/grub.cfg \
    || grub-mkconfig -o /boot/grub/grub.cfg

# ---------------------------------------------------------------------------
# systemd first-boot setup
# ---------------------------------------------------------------------------
if [ "\${INIT_SYSTEM}" = "systemd" ]; then
    info "Running systemd-firstboot..."
    systemd-firstboot --hostname="\${NEW_HOSTNAME}" --locale="\${LOCALE}"
fi

# ---------------------------------------------------------------------------
# Root password
# ---------------------------------------------------------------------------
echo ""
info "============================================================"
info " Set the ROOT password:"
info "============================================================"
passwd

# ---------------------------------------------------------------------------
# Optional new user
# ---------------------------------------------------------------------------
echo ""
echo -e "\${CYAN}[INPUT]\${NC} Would you like to create a new user? (y/n)"
read -rp "  Choice: " CREATE_USER

if [ "\${CREATE_USER}" = "y" ]; then
    echo -e "\${CYAN}[INPUT]\${NC} Enter the new username:"
    read -rp "  Username: " NEW_USER
    if [ -z "\${NEW_USER}" ]; then
        warn "No username entered — skipping user creation."
    else
        useradd -m -G wheel,audio,video -s /bin/bash "\${NEW_USER}"
        info "User '\${NEW_USER}' created and added to: wheel, audio, video."
        info "Set a password for '\${NEW_USER}':"
        passwd "\${NEW_USER}"
        info "User setup complete."
    fi
else
    info "Skipping user creation."
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
info "============================================================"
info " Installation complete!"
info "============================================================"
info " Exit the chroot and reboot:"
info ""
info "   exit"
info "   umount -R /mnt/gentoo"
info "   reboot"
info "============================================================"
CHROOT_EOF

chmod +x /mnt/gentoo/root/chroot-install.sh
info "In-chroot script written."
echo ""

# =============================================================================
# Actual chroot
# =============================================================================
info "============================================================"
info " ENTERING CHROOT"
info "============================================================"
echo ""

arch-chroot /mnt/gentoo /bin/bash /root/chroot-install.sh

# =============================================================================
# Cleanup
# =============================================================================
info "============================================================"
info " CLEANUP"
info "============================================================"

rm -f /mnt/gentoo/root/chroot-install.sh

info "Unmounting filesystems..."
umount -R /mnt/gentoo 2>/dev/null

echo ""
info "============================================================"
info " All done! Remove your installation media and reboot."
info "============================================================"
