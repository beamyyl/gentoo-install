echo 'You need the USE "+networkmanager" added in portage/make.conf' 
emerge -q eselect-repository
eselect repository enable Miezhiko
emaint sync -r Miezhiko
emerge --unmerge dev-util/gdbus-codegen
echo '*/*::Miezhiko ~amd64' > /etc/portage/package.accept_keywords/Miezhiko
echo '*/gnome-settings-daemon input_devices_wacom' >> /etc/portage/package.use/gnome
echo 'gnome-base/*::Miezhiko systemd -gnome-online-accounts' >> /etc/portage/package.use/gnome
emerge -q gnome-shell gnome-control-center gnome-settings-daemon::Miezhiko
