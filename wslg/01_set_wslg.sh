#!/bin/bash
# Install Ansible on Oracle Linux/WSL
set -e

echo "### 01_set_wslg.sh -  Installing WSLg..."

# Check root
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Must run as root"
    exit 1
fi

sudo dnf install -y oracle-epel-release-el8
sudo dnf update -y
#sudo dnf groupinstall -y "Xfce"
# startxfce4 &
sudo dnf group list --available
# sudo dnf groupinstall -y "Server with GUI"

# Enable required repos for OL8.10 (for xorg/font utils)
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --set-enabled ol8_codeready_builder


# Install WSLg dependencies
echo "- Installing WSLg dependencies..."
dnf install -y mesa-libGL mesa-libEGL mesa-dri-drivers
dnf install -y gtk3
dnf install -y libX11 libXext libXi libXrender libXrandr
#dnf install -y xorg-x11-server-Xorg xorg-x11-xauth xterm dbus-x11

# Fonts
dnf install -y dejavu-sans-fonts dejavu-serif-fonts dejavu-sans-mono-fonts liberation-fonts
dnf install -y cabextract xorg-x11-font-utils fontconfig
# Update fonts
fc-cache -fv

#dnf install -y gedit

# Install dependencies
echo "- Installing gvim ..."
dnf update -y
dnf install -y gvim


echo "[OK] WSLg installed: $(ansible --version | head -1)"
echo "- Test in WSL: gvim &"
