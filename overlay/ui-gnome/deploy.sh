#!/bin/bash
set -e
# Desktop backend stuff
xbps-install -y dbus-elogind-libs dbus-elogind-x11 xdg-user-dirs-gtk xdg-utils
# GPU
xbps-install -y mesa-dri
# Base GUI
xbps-install -y xorg-server-xwayland xorg-server xf86-video-fbdev xf86-input-libinput

# A small GNOME desktop with some default applications installed
xbps-install -y gnome-core \
	gnome-tweaks gnome-console gnome-usage gnome-screenshot \
	gnome-disk-utility gnome-clocks gnome-calendar \
	gnome-text-editor gnome-photos

enable_sv gdm
