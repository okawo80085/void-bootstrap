#!/bin/bash

xbps-install -y sassc gtk-engine-murrine gnome-themes-extra

installusrs=($USERNAMES)

runas ${installusrs[0]} <<EOF
git clone https://github.com/vinceliuice/Orchis-theme.git
./Orchis-theme/install.sh -l -t pink -c dark --tweaks black -name orchis-inssoma
EOF

sudo flatpak override --filesystem=xdg-config/gtk-3.0 && sudo flatpak override --filesystem=xdg-config/gtk-4.0

rm -rf ./Orchis-theme

log "Orchis-theme installed"
