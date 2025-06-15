. config.gnome.sh


extra_install_pkgs+=(
	# needed missing packages for nvidia proprietary drivers to work with steam
	libgcc-32bit libstdc++-32bit libdrm-32bit libglvnd-32bit mesa-dri-32bit
	libglvnd libglvnd-devel mesa-dri
        libdrm libdrm-devel

	zfs lzfse zfs-pam
)


overlays+=(
)
