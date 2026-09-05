#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }; warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }; die() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }; ask() { echo -e "${CYAN}[INPUT]${NC} $*"; }

for cmd in arch-chroot genfstab tar; do
    command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' not found."
done

[ "$EUID" -eq 0 ] || die "Run this script as root."

clear
echo
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                GENTOO INSTALLER                         ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo
info "This script will install Gentoo to /mnt/gentoo."
info "Your partitions must be formatted and mounted BEFORE continuing."
echo
echo "Here are some partition examples:"
echo
echo "  Mount commands (UEFI):"
echo
echo "    mount /dev/sda2 /mnt/gentoo"
echo "    mount /dev/sda1 /mnt/gentoo/efi --mkdir"
echo
echo "  For BIOS/GPT, make sure you have a 1MB BIOS boot partition."
echo "  Do NOT format or mount it."
echo
echo "  Mount commands (BIOS):"
echo
echo "    mount /dev/sda1 /mnt/gentoo"
echo
warn "If your partitions are NOT yet mounted, press Ctrl+C now,"
warn "mount them, then re-run this script."
echo

read -rp "Press ENTER once your partitions are mounted..."

mountpoint -q /mnt/gentoo || die "/mnt/gentoo is not mounted."
info "Root mount point verified."
echo

info "============================================================"
info " BOOT MODE & INIT SYSTEM"
info "============================================================"
echo

if [ -d /sys/firmware/efi ]; then
    BOOT_MODE="uefi"
    mountpoint -q /mnt/gentoo/efi || die "/mnt/gentoo/efi is not mounted."
    info "UEFI detected."
else
    BOOT_MODE="bios"
    info "BIOS/legacy boot detected."
    echo
    ask "Enter the disk to install GRUB to (e.g. /dev/sda, /dev/vda, /dev/nvme0n1)."
    ask "This should be the whole disk, NOT a partition."
    read -rp "  Install disk: " GRUB_DISK
    [ -n "$GRUB_DISK" ] || die "GRUB disk cannot be empty."
    [ -b "$GRUB_DISK" ] || die "$GRUB_DISK is not a block device."
    info "GRUB will be installed to: $GRUB_DISK"
fi
echo

ask "Init system — OpenRC or systemd?"
ask "  1) OpenRC  (Gentoo's native init, lightweight)"
ask "  2) systemd (used by most other distros)"
read -rp "  Choice [1/2]: " INIT_CHOICE

case "$INIT_CHOICE" in
    1) INIT_SYSTEM="openrc" ;;
    2) INIT_SYSTEM="systemd" ;;
    *) die "Invalid choice." ;;
esac

echo

ask "Do you want to enable binary support (binpackages)? [y/N]"
read -rp "  Choice [y/N]: " BIN_CHOICE

case "$BIN_CHOICE" in
    [yY][eE][sS]|[yY]) USE_BINPKG="yes" ;;
    *) USE_BINPKG="no" ;;
esac

echo

info "============================================================"
info " SYSTEM CONFIGURATION"
info "============================================================"
echo

ask "Enter a hostname for your new system."
ask "This is the name your machine will go by on the network (e.g. 'gentoo-desktop')."
read -rp "  Hostname: " NEW_HOSTNAME
[ -n "$NEW_HOSTNAME" ] || die "Hostname cannot be empty."

echo

ask "Enter your locale (press ENTER to accept the default: en_US.UTF-8)."
read -rp "  Locale: " LOCALE
LOCALE="${LOCALE:-en_US.UTF-8}"

echo

info "Configuration summary:"
echo "    Boot mode : $BOOT_MODE"
echo "    Init      : $INIT_SYSTEM"
echo "    Binpkg    : $USE_BINPKG"
echo "    Hostname  : $NEW_HOSTNAME"
echo "    Locale    : $LOCALE"
echo

read -rp "  Continue? [y/N] " CONTINUE

case "$CONTINUE" in
    [yY][eE][sS]|[yY]) ;;
    *) die "Cancelled." ;;
esac

echo

info "============================================================"
info " STAGE3 DOWNLOAD"
info "============================================================"
echo

info "Download the appropriate amd64 desktop stage3 from:"
info "https://www.gentoo.org/downloads/"
echo

if [ "$INIT_SYSTEM" = "openrc" ]; then
    info "Use an amd64 desktop OpenRC stage3."
else
    info "Use an amd64 desktop systemd stage3."
fi

echo
read -rp "Path to the downloaded stage3 archive: " STAGE3

[ -f "$STAGE3" ] || die "Stage3 archive not found: $STAGE3"

case "$STAGE3" in
    *.tar.xz|*.tar.zst|*.tar.gz|*.tar.bz2) ;;
    *) die "That doesn't look like a stage3 archive." ;;
esac

info "Extracting $(basename "$STAGE3")..."
tar xpf "$STAGE3" --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo

mkdir -p /mnt/gentoo/etc/portage/package.use
mkdir -p /mnt/gentoo/etc/portage/binrepos.conf

MAKE_CONF=/mnt/gentoo/etc/portage/make.conf

if [ "$BOOT_MODE" = "uefi" ]; then
    cat >> "$MAKE_CONF" <<'EOF'

GRUB_PLATFORMS="efi-64"
EOF
else
    cat >> "$MAKE_CONF" <<'EOF'

GRUB_PLATFORMS="pc"
EOF
fi

if [ "$USE_BINPKG" = "yes" ]; then
    cat >> "$MAKE_CONF" <<'EOF'

FEATURES="${FEATURES} getbinpkg"
FEATURES="${FEATURES} binpkg-request-signature"
EOF

    cat > /mnt/gentoo/etc/portage/binrepos.conf/gentoo.conf <<'EOF'
[gentoo]
priority = 9999
sync-uri = https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64-v3
location = /var/cache/binhost/gentoo
EOF
fi

cat > /mnt/gentoo/etc/portage/package.use/installkernel <<'EOF'
sys-kernel/installkernel grub dracut
EOF

cat > /mnt/gentoo/etc/portage/package.use/networkmanager <<'EOF'
net-misc/networkmanager wifi
net-wireless/wpa_supplicant dbus
EOF

echo "$NEW_HOSTNAME" > /mnt/gentoo/etc/hostname

cat > /mnt/gentoo/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${NEW_HOSTNAME}.localdomain ${NEW_HOSTNAME}
EOF

cp --dereference /etc/resolv.conf /mnt/gentoo/etc/resolv.conf

genfstab -U /mnt/gentoo > /mnt/gentoo/etc/fstab

echo
info "/etc/fstab:"
cat /mnt/gentoo/etc/fstab

cat > /mnt/gentoo/root/chroot-install.sh <<CHROOT
#!/bin/bash
set -e

BOOT_MODE="$BOOT_MODE"
INIT_SYSTEM="$INIT_SYSTEM"
USE_BINPKG="$USE_BINPKG"
NEW_HOSTNAME="$NEW_HOSTNAME"
LOCALE="$LOCALE"
GRUB_DISK="$GRUB_DISK"

info() { echo -e "\033[0;32m[CHROOT]\033[0m \$*"; }; warn() { echo -e "\033[1;33m[WARN]\033[0m \$*"; }; die() { echo -e "\033[0;31m[FAIL]\033[0m \$*"; exit 1; }

info "Updating Portage..."
emerge-webrsync -q

info "Setting locale to \$LOCALE..."
sed -i "s/^\#\${LOCALE} UTF-8/\${LOCALE} UTF-8/" /etc/locale.gen
locale-gen
env-update
source /etc/profile

if [ "\$USE_BINPKG" = "yes" ]; then
    info "Setting up binary package key..."
    getuto
fi

info "Installing firmware..."
emerge sof-firmware linux-firmware

info "Installing gentoo-kernel-bin..."
emerge sys-kernel/installkernel
emerge sys-kernel/gentoo-kernel-bin

info "Installing NetworkManager..."
emerge net-misc/networkmanager

if [ "\$INIT_SYSTEM" = "openrc" ]; then
    rc-update add NetworkManager default
else
    systemctl enable NetworkManager.service
fi

if [ "\$INIT_SYSTEM" = "openrc" ]; then
    info "Installing logging and cron..."
    emerge app-admin/syslog-ng sys-process/cronie
    rc-update add syslog-ng default
    rc-update add cronie default
fi

emerge app-admin/sudo app-editors/vim

info "Installing GRUB..."
emerge sys-boot/grub

if [ "\$BOOT_MODE" = "uefi" ]; then
    grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=Gentoo --recheck
else
    grub-install --target=i386-pc --recheck "\$GRUB_DISK"
fi

grub-mkconfig -o /boot/grub/grub.cfg

if [ "\$INIT_SYSTEM" = "systemd" ]; then
    systemd-firstboot --hostname="\$NEW_HOSTNAME" --locale="\$LOCALE"
fi

echo
info "============================================================"
info " Set the ROOT password:"
info "============================================================"
passwd

echo
echo -e "\033[0;36m[INPUT]\033[0m Would you like to create a new user? (y/n)"
read -rp "  Choice: " CREATE_USER

case "\$CREATE_USER" in
    y|Y|yes|YES|Yes)
        echo -e "\033[0;36m[INPUT]\033[0m Enter the new username:"
        read -rp "  Username: " NEW_USER

        if [ -z "\$NEW_USER" ]; then
            warn "No username entered — skipping user creation."
        else
            useradd -m -G wheel,audio,video -s /bin/bash "\$NEW_USER"
            info "User '\$NEW_USER' created and added to: wheel, audio, video."
            info "Set a password for '\$NEW_USER':"
            passwd "\$NEW_USER"

            mkdir -p /etc/sudoers.d
            echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
            chmod 0440 /etc/sudoers.d/10-wheel

            info "User setup complete."
        fi
        ;;
    *)
        info "Skipping user creation."
        ;;
esac

echo
info "============================================================"
info " Installation complete!"
info "============================================================"
CHROOT

chmod +x /mnt/gentoo/root/chroot-install.sh

info "============================================================"
info " ENTERING CHROOT"
info "============================================================"
echo

arch-chroot /mnt/gentoo /bin/bash /root/chroot-install.sh

rm -f /mnt/gentoo/root/chroot-install.sh

echo
info "Unmounting /mnt/gentoo..."
umount -R /mnt/gentoo 2>/dev/null || true

echo
info "============================================================"
info " All done! Remove your installation media and reboot."
info "============================================================"
