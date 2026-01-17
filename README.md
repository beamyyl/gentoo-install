Hey! I made some auto-install gentoo scripts for both systemd and openrc with bios and uefi support :)
You need to load into an actuall gentoo iso (this also works with an arch linux iso) and git clone this repository, then make the file you want to use executable by typing 'chmod +x filename.sh', and then just run it as ROOT with sudo ./filename.sh
Make sure to first make the partitions, format them and ALSO mount them to /mnt/gentoo (and /mnt/gentoo/boot/efi if on UEFI)
