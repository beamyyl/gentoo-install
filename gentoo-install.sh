#!/bin/bash
# =============================================================================
# Gentoo Auto-Installer
# Supports: UEFI or BIOS  |  OpenRC or systemd
# =============================================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }
ask()   { echo -e "${CYAN}[INPUT]${NC} $*"; }

# =============================================================================
# STEP 0 — Sanity checks
# =============================================================================
for cmd in arch-chroot genfstab links; do
    command -v "$cmd" &>/dev/null \
        || die "'$cmd' not found. Are you booted from the official Gentoo live ISO?"
done

# =============================================================================
# STEP 1 — Banner + partition reminder
# =============================================================================
clear
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║            GENTOO AUTO-INSTALLER — amd64                 ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
info "This script will install Gentoo to /mnt/gentoo."
info "Your partitions must be formatted and mounted BEFORE continuing."
echo ""
echo "  Recommended GPT/UEFI layout:"
echo ""
echo "    /dev/sda1  →  FAT32  →  EFI System Partition (512M–1G)"
echo "    /dev/sda2  →  swap"
echo "    /dev/sda3  →  ext4    →  root"
echo ""
echo "  Mount commands (UEFI):"
echo ""
echo "    mount /dev/sda3 /mnt/gentoo"
echo "    mkdir -p /mnt/gentoo/efi"
echo "    mount /dev/sda1 /mnt/gentoo/efi"
echo "    swapon /dev/sda2"
echo ""
echo "  For BIOS/MBR, /dev/sda1 is your /boot (ext4), no EFI partition needed:"
echo ""
echo "    mount /dev/sda2 /mnt/gentoo"
echo "    mkdir -p /mnt/gentoo/boot"
echo "    mount /dev/sda1 /mnt/gentoo/boot"
echo "    swapon /dev/sda3"
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
# STEP 2 — Boot mode & init system selection
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
    mountpoint -q /mnt/gentoo/boot \
        || die "/mnt/gentoo/boot is not mounted. Mount your boot partition and re-run."
    info "BIOS mode selected. /boot mount verified."
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
# STEP 3 — System configuration
# =============================================================================
info "============================================================"
info " SYSTEM CONFIGURATION"
info "============================================================"
echo ""

ask "Enter your timezone."
ask "Example: America/Los_Angeles"
ask "Full list: ls /usr/share/zoneinfo/"
read -rp "  Timezone: " TIMEZONE
[ -z "$TIMEZONE" ] && die "Timezone cannot be empty."
[ -f "/usr/share/zoneinfo/$TIMEZONE" ] \
    || die "Invalid timezone '$TIMEZONE'. Check /usr/share/zoneinfo/."
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
echo "   Timezone  : $TIMEZONE"
echo "   Hostname  : $NEW_HOSTNAME"
echo "   Locale    : $LOCALE"
echo ""
read -rp "  Press ENTER to continue..."
echo ""

# =============================================================================
# STEP 4 — Stage3 download via Links
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

info "The file will be saved to your current directory (/mnt/gentoo)."
echo ""
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
# STEP 5 — make.conf
# =============================================================================
info "============================================================"
info " CONFIGURING make.conf"
info "============================================================"

cat >> /mnt/gentoo/etc/portage/make.conf <<EOF

# Binary package host
FEATURES="\${FEATURES} getbinpkg"
FEATURES="\${FEATURES} binpkg-request-signature"

# GRUB platform
GRUB_PLATFORMS="efi-64"
EOF

info "make.conf updated."
echo ""

# =============================================================================
# STEP 6 — package.use
# =============================================================================
info "============================================================"
info " CONFIGURING package.use"
info "============================================================"

mkdir -p /mnt/gentoo/etc/portage/package.use

if [ "$BOOT_MODE" = "uefi" ]; then
    echo "sys-kernel/installkernel grub dracut" \
        > /mnt/gentoo/etc/portage/package.use/installkernel
else
    # BIOS: grub still used but no EFI stub needed; dracut still good
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
# STEP 7 — Write hostname early (fixes livecd hostname leaking into chroot)
# =============================================================================
echo "$NEW_HOSTNAME" > /mnt/gentoo/etc/hostname

cat > /mnt/gentoo/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${NEW_HOSTNAME}.localdomain ${NEW_HOSTNAME}
EOF

info "Hostname written to /mnt/gentoo/etc/hostname: $NEW_HOSTNAME"
echo ""

# =============================================================================
# STEP 8 — DNS, pseudo-filesystems, genfstab
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

info "Generating /etc/fstab with genfstab -U..."
genfstab -U /mnt/gentoo >> /mnt/gentoo/etc/fstab
info "fstab contents:"
cat /mnt/gentoo/etc/fstab
echo ""

# =============================================================================
# STEP 9 — Build in-chroot script
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
TIMEZONE="${TIMEZONE}"
NEW_HOSTNAME="${NEW_HOSTNAME}"
LOCALE="${LOCALE}"

# ---------------------------------------------------------------------------
# Portage snapshot
# ---------------------------------------------------------------------------
info "Fetching portage snapshot..."
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
# Timezone
# ---------------------------------------------------------------------------
info "Setting timezone: \${TIMEZONE}"
echo "\${TIMEZONE}" > /etc/timezone
emerge -q --config sys-libs/timezone-data

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
info "Detecting CPU flags with cpuid2cpuflags..."
emerge -q --ask=n app-portage/cpuid2cpuflags
mkdir -p /etc/portage/package.use
echo "*/* \$(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags
info "CPU flags written to /etc/portage/package.use/00cpu-flags:"
cat /etc/portage/package.use/00cpu-flags

# ---------------------------------------------------------------------------
# Firmware (open source only)
# ---------------------------------------------------------------------------
info "Installing linux-firmware..."
echo 'ACCEPT_LICENSE="*"' >> /etc/portage/make.conf
emerge -q --ask=n sys-kernel/linux-firmware

info "Installing SOF firmware..."
emerge -q --ask=n sys-firmware/sof-firmware \
    || warn "sof-firmware not available, skipping."

# ---------------------------------------------------------------------------
# installkernel + dracut config
# ---------------------------------------------------------------------------
info "Installing installkernel..."
emerge -q --ask=n sys-kernel/installkernel

info "Configuring dracut..."
mkdir -p /etc/dracut.conf.d
ROOT_UUID=\$(findmnt -n -o UUID /)
cat > /etc/dracut.conf.d/00-installkernel.conf <<EOF
kernel_cmdline=" root=UUID=\${ROOT_UUID} "
EOF

# ---------------------------------------------------------------------------
# Kernel (prebuilt binary)
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
# Logging + cron  (OpenRC only; systemd has journald + systemd-cron options)
# ---------------------------------------------------------------------------
if [ "\${INIT_SYSTEM}" = "openrc" ]; then
    info "Installing syslog-ng and cronie..."
    emerge -q --ask=n app-admin/syslog-ng sys-process/cronie
    rc-update add syslog-ng default
    rc-update add cronie default
fi

# ---------------------------------------------------------------------------
# sudo + vim
# ---------------------------------------------------------------------------
info "Installing sudo and vim..."
emerge -q --ask=n app-admin/sudo app-editors/vim

# Allow wheel group to use sudo
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel
info "Wheel group granted sudo access."

# ---------------------------------------------------------------------------
# GRUB
# ---------------------------------------------------------------------------
info "Installing GRUB..."
emerge -q --ask=n sys-boot/grub

if [ "\${BOOT_MODE}" = "uefi" ]; then
    info "Running grub-install (UEFI, label: Gentoo)..."
    grub-install --quiet --target=x86_64-efi --efi-directory=/efi --bootloader-id=Gentoo
else
    info "Running grub-install (BIOS)..."
    # Install to the disk, not a partition — adjust /dev/sda if needed
    GRUB_DISK=\$(lsblk -no pkname \$(findmnt -n -o SOURCE /) | head -n1)
    [ -z "\$GRUB_DISK" ] && GRUB_DISK="sda"
    grub-install --quiet /dev/\${GRUB_DISK}
fi

info "Generating grub.cfg..."
grub-mkconfig -q -o /boot/grub/grub.cfg \
    || grub-mkconfig -o /boot/grub/grub.cfg

# ---------------------------------------------------------------------------
# systemd first-boot setup
# ---------------------------------------------------------------------------
if [ "\${INIT_SYSTEM}" = "systemd" ]; then
    info "Running systemd-firstboot..."
    systemd-firstboot --timezone="\${TIMEZONE}" --hostname="\${NEW_HOSTNAME}" --locale="\${LOCALE}"
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
# STEP 10 — arch-chroot
# =============================================================================
info "============================================================"
info " ENTERING CHROOT"
info "============================================================"
echo ""

arch-chroot /mnt/gentoo /bin/bash /root/chroot-install.sh

# =============================================================================
# STEP 11 — Cleanup
# =============================================================================
info "============================================================"
info " CLEANUP"
info "============================================================"

rm -f /mnt/gentoo/root/chroot-install.sh

info "Unmounting filesystems..."
umount -R /mnt/gentoo 2>/dev/null \
    || warn "Some mounts may already be gone — that's fine."

echo ""
info "============================================================"
info " All done! Remove your installation media and reboot."
info "============================================================"
