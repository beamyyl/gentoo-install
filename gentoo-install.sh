#!/bin/bash
# =============================================================================
# Gentoo Auto-Installer
# Target: amd64, UEFI/GPT, desktop/openrc profile
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
    command -v "$cmd" &>/dev/null || die "'$cmd' not found. Are you booted from the official Gentoo live ISO?"
done

# =============================================================================
# STEP 1 — Partition reminder
# =============================================================================
clear
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       GENTOO AUTO-INSTALLER — UEFI/GPT / OpenRC          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
info "This script will install Gentoo to /mnt/gentoo."
info "Your partitions must be formatted and mounted BEFORE continuing."
echo ""
echo "  Recommended GPT/UEFI layout:"
echo ""
echo "    /dev/sda1  →  FAT32   →  EFI System Partition (512M–1G)"
echo "    /dev/sda2  →  swap"
echo "    /dev/sda3  →  xfs     →  root"
echo ""
echo "  Mount commands:"
echo ""
echo "    mount /dev/sda3 /mnt/gentoo"
echo "    mkdir -p /mnt/gentoo/efi"
echo "    mount /dev/sda1 /mnt/gentoo/efi"
echo "    swapon /dev/sda2"
echo ""
warn "If your partitions are NOT yet mounted, press Ctrl+C now,"
warn "mount them, then re-run this script."
echo ""
read -rp "  Press ENTER once your partitions are mounted..."
echo ""

mountpoint -q /mnt/gentoo     || die "/mnt/gentoo is not mounted."
mountpoint -q /mnt/gentoo/efi || die "/mnt/gentoo/efi is not mounted."
info "Mount points verified."
echo ""

# =============================================================================
# STEP 2 — Gather configuration up front
# =============================================================================
info "============================================================"
info " SYSTEM CONFIGURATION"
info "============================================================"
echo ""

# Timezone
ask "Enter your timezone."
ask "Example: America/Los_Angeles"
ask "See /usr/share/zoneinfo/ for a full list."
read -rp "  Timezone: " TIMEZONE
[ -z "$TIMEZONE" ] && die "Timezone cannot be empty."
[ -f "/usr/share/zoneinfo/$TIMEZONE" ] || die "Invalid timezone '$TIMEZONE'. Check /usr/share/zoneinfo/."
echo ""

# Hostname
ask "Enter a hostname for your new system."
ask "This is the name your machine will use on the network (e.g. 'gentoo-desktop')."
read -rp "  Hostname: " HOSTNAME
[ -z "$HOSTNAME" ] && die "Hostname cannot be empty."
echo ""

# Locale
ask "Enter your locale (press ENTER to use the default: en_US.UTF-8)."
read -rp "  Locale: " LOCALE
LOCALE="${LOCALE:-en_US.UTF-8}"
echo ""

# Summary
info "Configuration:"
echo "   Timezone : $TIMEZONE"
echo "   Hostname : $HOSTNAME"
echo "   Locale   : $LOCALE"
echo ""
read -rp "  Press ENTER to continue..."
echo ""

# =============================================================================
# STEP 3 — Stage3 download via Links
# =============================================================================
info "============================================================"
info " STAGE3 DOWNLOAD"
info "============================================================"
echo ""
info "Opening the Gentoo downloads page in the Links browser."
info "Navigate to:  releases → amd64 → autobuilds"
info "Download the stage3-amd64-desktop-openrc tarball."
info "(You can also grab the minimal tarball if you prefer.)"
info "Files will be saved to /mnt/gentoo."
echo ""
warn "When the download is finished, press 'q' to quit Links."
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
tar xpf "$TARBALL" --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo
rm -f "$TARBALL"
info "Stage3 extracted."
echo ""

# =============================================================================
# STEP 4 — make.conf (binpkg + GRUB platform only, nothing else touched)
# =============================================================================
info "============================================================"
info " CONFIGURING make.conf"
info "============================================================"

cat >> /mnt/gentoo/etc/portage/make.conf <<'EOF'

# Binary package host
FEATURES="${FEATURES} getbinpkg"
FEATURES="${FEATURES} binpkg-request-signature"

# GRUB UEFI target
GRUB_PLATFORMS="efi-64"
EOF

info "make.conf updated."
echo ""

# =============================================================================
# STEP 5 — package.use
# =============================================================================
info "============================================================"
info " CONFIGURING package.use"
info "============================================================"

mkdir -p /mnt/gentoo/etc/portage/package.use

cat > /mnt/gentoo/etc/portage/package.use/installkernel <<'EOF'
sys-kernel/installkernel grub dracut
EOF

cat > /mnt/gentoo/etc/portage/package.use/networkmanager <<'EOF'
net-misc/networkmanager wifi
net-wireless/wpa_supplicant dbus
EOF

info "package.use written."
echo ""

# =============================================================================
# STEP 6 — DNS, pseudo-filesystems, genfstab
# =============================================================================
info "============================================================"
info " MOUNTING PSEUDO-FILESYSTEMS & GENERATING FSTAB"
info "============================================================"

cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

mount --types proc  /proc       /mnt/gentoo/proc
mount --rbind       /sys        /mnt/gentoo/sys
mount --make-rslave             /mnt/gentoo/sys
mount --rbind       /dev        /mnt/gentoo/dev
mount --make-rslave             /mnt/gentoo/dev
mount --bind        /run        /mnt/gentoo/run
mount --make-slave              /mnt/gentoo/run

info "Generating /etc/fstab with genfstab -U..."
genfstab -U /mnt/gentoo >> /mnt/gentoo/etc/fstab
info "fstab contents:"
cat /mnt/gentoo/etc/fstab
echo ""

# =============================================================================
# STEP 7 — Build in-chroot script (variables expanded now, heredoc body is not)
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

TIMEZONE="${TIMEZONE}"
HOSTNAME="${HOSTNAME}"
LOCALE="${LOCALE}"

# ---------------------------------------------------------------------------
# Portage snapshot
# ---------------------------------------------------------------------------
info "Fetching portage snapshot (emerge-webrsync)..."
emerge-webrsync

# ---------------------------------------------------------------------------
# Profile — desktop/openrc (no systemd, no gnome, no kde sub-profile)
# ---------------------------------------------------------------------------
info "Selecting desktop/openrc profile..."
PROFILE_NUM=\$(eselect profile list \
    | grep -E '\[.*\].*desktop[[:space:]]' \
    | grep -v systemd | grep -v gnome | grep -v kde \
    | head -n1 | awk -F'[][]' '{print \$2}')
[ -z "\$PROFILE_NUM" ] && die "Could not auto-detect desktop profile. Run 'eselect profile list' manually."
info "Setting profile \${PROFILE_NUM}..."
eselect profile set "\${PROFILE_NUM}"
eselect profile show

# ---------------------------------------------------------------------------
# Binary package keyring
# ---------------------------------------------------------------------------
info "Initialising binary package keyring..."
getuto

# ---------------------------------------------------------------------------
# Timezone
# ---------------------------------------------------------------------------
info "Setting timezone: \${TIMEZONE}"
echo "\${TIMEZONE}" > /etc/timezone
emerge --config sys-libs/timezone-data

# ---------------------------------------------------------------------------
# Locale
# ---------------------------------------------------------------------------
info "Configuring locale: \${LOCALE}"
echo "\${LOCALE} UTF-8" >> /etc/locale.gen
locale-gen
LOCALE_NUM=\$(eselect locale list | grep "\${LOCALE}" | head -n1 | awk -F'[][]' '{print \$2}')
[ -n "\$LOCALE_NUM" ] && eselect locale set "\$LOCALE_NUM"
env-update && source /etc/profile

# ---------------------------------------------------------------------------
# CPU flags
# ---------------------------------------------------------------------------
info "Detecting CPU flags with cpuid2cpuflags..."
emerge --ask=n app-portage/cpuid2cpuflags

mkdir -p /etc/portage/package.use
echo "*/* \$(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags

info "CPU flags written to /etc/portage/package.use/00cpu-flags"

# ---------------------------------------------------------------------------
# Firmware (open source only)
# ---------------------------------------------------------------------------
info "Installing linux-firmware..."
echo 'ACCEPT_LICENSE="*"' >> /mnt/gentoo/etc/portage/make.conf
emerge --ask=n sys-kernel/linux-firmware

info "Installing SOF firmware..."
emerge --ask=n sys-firmware/sof-firmware || warn "sof-firmware not available, skipping."

# ---------------------------------------------------------------------------
# installkernel
# ---------------------------------------------------------------------------
info "Installing installkernel..."
emerge --ask=n sys-kernel/installkernel

# dracut: pass root UUID so the initramfs knows what to mount
info "Configuring dracut..."
mkdir -p /etc/dracut.conf.d
ROOT_UUID=\$(findmnt -n -o UUID /)
cat > /etc/dracut.conf.d/00-installkernel.conf <<EOF
kernel_cmdline=" root=UUID=\${ROOT_UUID} "
EOF

# ---------------------------------------------------------------------------
# Kernel (prebuilt binary distribution kernel)
# ---------------------------------------------------------------------------
info "Installing gentoo-kernel-bin..."
emerge --ask=n sys-kernel/gentoo-kernel-bin

# ---------------------------------------------------------------------------
# Hostname
# ---------------------------------------------------------------------------
info "Setting hostname: \${HOSTNAME}"
echo "\${HOSTNAME}" > /etc/hostname

cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   \${HOSTNAME}.localdomain \${HOSTNAME}
EOF

# ---------------------------------------------------------------------------
# NetworkManager
# ---------------------------------------------------------------------------
info "Installing NetworkManager..."
emerge --ask=n net-misc/networkmanager
rc-update add NetworkManager default

# ---------------------------------------------------------------------------
# Logging + cron
# ---------------------------------------------------------------------------
info "Installing syslog-ng and cronie..."
emerge --ask=n app-admin/syslog-ng sys-process/cronie
rc-update add syslog-ng default
rc-update add cronie default

# ---------------------------------------------------------------------------
# GRUB (UEFI, bootloader-id = Gentoo)
# ---------------------------------------------------------------------------
info "Installing GRUB..."
emerge --ask=n sys-boot/grub

info "Running grub-install (UEFI)..."
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=Gentoo

info "Generating grub.cfg..."
grub-mkconfig -o /boot/grub/grub.cfg

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
# STEP 8 — arch-chroot
# =============================================================================
info "============================================================"
info " ENTERING CHROOT"
info "============================================================"
echo ""

arch-chroot /mnt/gentoo /bin/bash -c \
    "source /etc/profile && export PS1='(chroot) \${PS1}' && /root/chroot-install.sh"

# =============================================================================
# STEP 9 — Cleanup
# =============================================================================
info "============================================================"
info " CLEANUP"
info "============================================================"

rm -f /mnt/gentoo/root/chroot-install.sh

info "Unmounting filesystems..."
umount -R /mnt/gentoo 2>/dev/null || warn "Some mounts may already be gone — that's fine."

echo ""
info "============================================================"
info " All done! Remove your installation media and reboot."
info "============================================================"
