. config.base.sh

arch="x86_64"

musl=false

img_size="24G"

extra_void_repos=(
	nonfree multilib multilib-nonfree
)

base_pkgs+=(
	dejavu-fonts-ttf # for proper font rendering in ff :)
	noto-fonts-emoji # for emoji keyboard on gnome shell mobile
	Vulkan-Tools glxinfo # for vkcube and other GPU tools
	docker docker-cli # docker

	grub grub-x86_64-efi syslinux memtest86+ squashfs-tools xorriso dracut # bootloaders
	binutils xz device-mapper dhclient dracut-network openresolv
	xmirror
	openssh
	
	flatpak
)
extra_build_pkgs+=(
	mutter gnome-shell # gnome shell mobile
	megapixels feedbackd #gnome-calls purism-chatty
)
extra_install_pkgs+=(
	megapixels #gnome-calls purism-chatty

	psensor
	nvtop

	# other stuff
	chromium
	Signal-Desktop

	kicad
	kicad-footprints
	kicad-library
	kicad-packages3D
	kicad-symbols
	kicad-templates

	python3
	python3-pip
	cmake
	gcc
	arduino-cli

	blender
	krita
	gimp

	vlc
	file-roller
	evince
	eog
)
overlays=(
	# drop somainline overlay temporarily to apply it after EVERYTHING else
	${overlays[@]/somainline}

	ui-gnome
	pulseaudio
	qcom_spmi_haptics-feedbackd
	sdm845-mainline-alsa-ucm-conf

	somainline
	somainline-gnome-settings

	orchis-theme
	gnome-extensions-manager-flatpak

	# megaTinyCore-arduino-cli
)
enable_sv=(
	# drop buffyboard sv to avoid potential input issues in GNOME (https://gitlab.com/cherrypicker/buffyboard/-/issues/21)
	"${enable_sv[@]/buffyboard}"

	docker
)
# disable_sv+=(

# )
img_name_format="${img_name_format/-base/-gnome}"
