#! /bin/bash
#

[ "$(grep -c "^systemd.*" /etc/wsl.conf)" -eq 0 ] && echo -e "\n[boot]\nsystemd=true\n" | sudo tee -a /etc/wsl.conf
[ "$(grep -c "^systemd.*=.*true$" /etc/wsl.conf)" -eq 0 ] && sudo sed -i "s/^systemd.*=.*false$/systemd=true/" /etc/wsl.conf

[ "$(grep -c "^hostname.*" /etc/wsl.conf)" -eq 0 ] && sudo sed -i '/\[network\]/s/.*/&\nhostname=fedoraremix/' /etc/wsl.conf

update.sh

#sudo dnf -y group install 'GNOME'

sudo localectl set-locale LANG="en_US.UTF-8"

sudo dnf -y install xrdp
sudo systemctl enable xrdp
sudo sed -i "s/port=3389/port=3396/" /etc/xrdp/xrdp.ini
sudo sed -i "s/ListenPort=3350/ListenPort=3346/" /etc/xrdp/sesman.ini

wsl.exe --terminate ${WSL_DISTRO_NAME}