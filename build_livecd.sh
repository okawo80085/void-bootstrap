#!/bin/bash


SPECIAL_MOUNTS=(sys dev proc)

get_rootfs_mounts() { grep "$ROOTFS" /proc/mounts | awk '{print $2}' || :; }

chroot_setup() {
    for mount in ${SPECIAL_MOUNTS[@]}; do
        sudo mount --rbind /$mount "$ROOTFS"/$mount
        sudo mount --make-rslave "$ROOTFS"/$mount
    done
}

setup_rootfs() {
    sudo mount -o loop $ROOTFSIMAGE $ROOTFS
    chroot_setup
}

umount_rootfs_special() {
    local rootfs_mounts="$(get_rootfs_mounts)"
    for mount in ${SPECIAL_MOUNTS[@]}; do
        echo "$rootfs_mounts" | grep -q "/$mount" && sudo umount -Rl "$ROOTFS"/$mount
    done
}

cleanup_rootfs() {
    umount_rootfs_special
    rootfs_mounts="$(get_rootfs_mounts)"
    for mount in $rootfs_mounts; do
        sudo umount "$mount"
    done
    # rm -rf "$ROOTFS" "$BOOT_DIR"
}

die() {
    cleanup_rootfs
    echo "ERROR: $@"
    exit $LINENO
}


copy_autoinstaller_files() {
    mkdir -p "$1"/usr/lib/dracut/modules.d/01autoinstaller
    cp dracut/autoinstaller/* "$1"/usr/lib/dracut/modules.d/01autoinstaller/
}

copy_dracut_files() {
    mkdir -p "$1"/usr/lib/dracut/modules.d/01vmklive
    cp dracut/vmklive/* "$1"/usr/lib/dracut/modules.d/01vmklive/
}

make_boot_things() {
    local _args

    copy_dracut_files "$ROOTFS"
    copy_autoinstaller_files "$ROOTFS"
    chroot "$ROOTFS" env -i /usr/bin/dracut -N --"${INITRAMFS_COMPRESSION}" \
        --add-drivers "ahci" --force-add "vmklive autoinstaller" --omit systemd "/boot/initrd" $KERNELVERSION
    [ $? -ne 0 ] && die "Failed to generate the initramfs"

    mv "$ROOTFS"/boot/initrd "$BOOT_DIR"
    cp "$ROOTFS"/boot/vmlinuz-$KERNELVERSION "$BOOT_DIR"/vmlinuz
}

generate_isolinux_boot() {
    cp -f "$SYSLINUX_DATADIR"/isolinux.bin "$ISOLINUX_DIR"
    cp -f "$SYSLINUX_DATADIR"/ldlinux.c32 "$ISOLINUX_DIR"
    cp -f "$SYSLINUX_DATADIR"/libcom32.c32 "$ISOLINUX_DIR"
    cp -f "$SYSLINUX_DATADIR"/vesamenu.c32 "$ISOLINUX_DIR"
    cp -f "$SYSLINUX_DATADIR"/libutil.c32 "$ISOLINUX_DIR"
    cp -f "$SYSLINUX_DATADIR"/chain.c32 "$ISOLINUX_DIR"
    cp -f "$SYSLINUX_DATADIR"/reboot.c32 "$ISOLINUX_DIR"
    cp -f "$SYSLINUX_DATADIR"/poweroff.c32 "$ISOLINUX_DIR"
    cp -f isolinux/isolinux.cfg.in "$ISOLINUX_DIR"/isolinux.cfg
    cp -f ${SPLASH_IMAGE} "$ISOLINUX_DIR"

    sed -i  -e "s|@@SPLASHIMAGE@@|$(basename "${SPLASH_IMAGE}")|" \
        -e "s|@@KERNVER@@|${KERNELVERSION}|" \
        -e "s|@@KEYMAP@@|${KEYMAP}|" \
        -e "s|@@ARCH@@|$BASE_ARCH|" \
        -e "s|@@LOCALE@@|${LOCALE}|" \
        -e "s|@@BOOT_TITLE@@|${BOOT_TITLE}|" \
        -e "s|@@BOOT_CMDLINE@@|${BOOT_CMDLINE}|" \
        "$ISOLINUX_DIR"/isolinux.cfg

    # include memtest86+
    cp -f "$ROOTFS"/boot/memtest.bin "$BOOT_DIR"
}

generate_grub_efi_boot() {
    cp -f grub/grub.cfg "$GRUB_DIR"
    cp -f grub/grub_void.cfg.in "$GRUB_DIR"/grub_void.cfg
    sed -i  -e "s|@@SPLASHIMAGE@@|$(basename "${SPLASH_IMAGE}")|" \
        -e "s|@@KERNVER@@|${KERNELVERSION}|" \
        -e "s|@@KEYMAP@@|${KEYMAP}|" \
        -e "s|@@ARCH@@|$BASE_ARCH|" \
        -e "s|@@BOOT_TITLE@@|${BOOT_TITLE}|" \
        -e "s|@@BOOT_CMDLINE@@|${BOOT_CMDLINE}|" \
        -e "s|@@LOCALE@@|${LOCALE}|" "$GRUB_DIR"/grub_void.cfg
    mkdir -p "$GRUB_DIR"/fonts
    cp -f "$GRUB_DATADIR"/unicode.pf2 "$GRUB_DIR"/fonts

    modprobe -q loop || :

    # Create EFI vfat image.
    truncate -s 32M "$GRUB_DIR"/efiboot.img >/dev/null 2>&1
    mkfs.vfat -F12 -S 512 -n "grub_uefi" "$GRUB_DIR/efiboot.img" >/dev/null 2>&1

    GRUB_EFI_TMPDIR="$(mktemp --tmpdir="$HOME" -d)"
    LOOP_DEVICE="$(losetup --show --find "${GRUB_DIR}"/efiboot.img)"
    mount -o rw,flush -t vfat "${LOOP_DEVICE}" "${GRUB_EFI_TMPDIR}" >/dev/null 2>&1

    cp -a "$IMAGEDIR"/boot "$ROOTFS"
    xbps-uchroot "$ROOTFS" grub-mkstandalone -- \
		 --directory="/usr/lib/grub/i386-pc" \
		 --format="i386-pc" \
		 --output="/tmp/bootia32.efi" \
         --install-modules="linux normal iso9660 biosdisk memdisk search tar ls png gfxmenu" \
        --modules="linux normal iso9660 biosdisk search png gfxmenu" \
         --locales="" \
        --fonts="" \
        --themes="" \
		 "boot/grub/grub.cfg"
    if [ $? -ne 0 ]; then
        umount "$GRUB_EFI_TMPDIR"
        losetup --detach "${LOOP_DEVICE}"
        die "Failed to generate EFI loader"
    fi
    mkdir -p "${GRUB_EFI_TMPDIR}"/EFI/BOOT
    cp -f "$ROOTFS"/tmp/bootia32.efi "${GRUB_EFI_TMPDIR}"/EFI/BOOT/BOOTIA32.EFI
    xbps-uchroot "$ROOTFS" grub-mkstandalone -- \
		 --directory="/usr/lib/grub/x86_64-efi" \
		 --format="x86_64-efi" \
		 --output="/tmp/bootx64.efi" \
		 "boot/grub/grub.cfg"
    if [ $? -ne 0 ]; then
        umount "$GRUB_EFI_TMPDIR"
        losetup --detach "${LOOP_DEVICE}"
        die "Failed to generate EFI loader"
    fi
    cp -f "$ROOTFS"/tmp/bootx64.efi "${GRUB_EFI_TMPDIR}"/EFI/BOOT/BOOTX64.EFI
    umount "$GRUB_EFI_TMPDIR"
    losetup --detach "${LOOP_DEVICE}"
    rm -rf "$GRUB_EFI_TMPDIR"

    # include memtest86+
    cp -f "$ROOTFS"/boot/memtest.efi "$BOOT_DIR"
}

generate_squashfs() {
    umount_rootfs_special

    # Find out required size for the rootfs and create an ext3fs image off it.
    ROOTFS_SIZE=$(du --apparent-size -sm "$ROOTFS"|awk '{print $1}')
    mkdir -p "$BUILDDIR/tmp/LiveOS"
    truncate -s "$((ROOTFS_SIZE+ROOTFS_SIZE))M" \
        "$BUILDDIR"/tmp/LiveOS/ext3fs.img >/dev/null 2>&1
    mkdir -p "$BUILDDIR/tmp-rootfs"
    mkfs.ext3 -F -m1 "$BUILDDIR/tmp/LiveOS/ext3fs.img" >/dev/null 2>&1
    mount -o loop "$BUILDDIR/tmp/LiveOS/ext3fs.img" "$BUILDDIR/tmp-rootfs"
    cp -a "$ROOTFS"/* "$BUILDDIR"/tmp-rootfs/
    umount -f "$BUILDDIR/tmp-rootfs"
    mkdir -p "$IMAGEDIR/LiveOS"

    "$ROOTFS"/usr/bin/mksquashfs "$BUILDDIR/tmp" "$IMAGEDIR/LiveOS/squashfs.img" \
        -comp "${SQUASHFS_COMPRESSION}" || die "Failed to generate squashfs image"
    chmod 444 "$IMAGEDIR/LiveOS/squashfs.img"

    # Remove rootfs and temporary dirs, we don't need them anymore.
    cp "$SYSLINUX_DATADIR"/isohdpfx.bin $BUILDDIR
    cleanup_rootfs
    rm -rf $ROOTFS "$BUILDDIR/tmp-rootfs" "$BUILDDIR/tmp"
}

generate_iso_image() {
    xorriso -as mkisofs \
        -iso-level 3 -rock -joliet \
        -max-iso9660-filenames -omit-period \
        -omit-version-number -relaxed-filenames -allow-lowercase \
        -volid "VOID_LIVE" \
        -eltorito-boot boot/isolinux/isolinux.bin \
        -eltorito-catalog boot/isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot -e boot/grub/efiboot.img -isohybrid-gpt-basdat -no-emul-boot \
        -isohybrid-mbr "$BUILDDIR"/isohdpfx.bin \
        -output "$OUTPUT_FILE" "$IMAGEDIR" || die "Failed to generate ISO image"
}


# Check for root permissions.
if [ "$(id -u)" -ne 0 ]; then
    echo "Must be run as root, exiting..."
    exit 1
fi

# Configure dracut to use overlayfs for the writable overlay.
BOOT_CMDLINE="$BOOT_CMDLINE rd.live.overlay.overlayfs=1 "

ARCH=$(xbps-uhelper arch)

# Set defaults
: ${BASE_ARCH:=$(xbps-uhelper arch 2>/dev/null || uname -m)}
: ${XBPS_CACHEDIR:="$(pwd -P)"/xbps-cachedir-${BASE_ARCH}}
: ${XBPS_HOST_CACHEDIR:="$(pwd -P)"/xbps-cachedir-${ARCH}}
: ${KEYMAP:=us}
: ${LOCALE:=en_US.UTF-8}
: ${INITRAMFS_COMPRESSION:=xz}
: ${SQUASHFS_COMPRESSION:=xz}
: ${BASE_SYSTEM_PKG:=base-system}
: ${BOOT_TITLE:="Void Linux"}

unset -v IMAGE_NAME
for file in "$(pwd -P)/images"/*; do
  [[ $file -nt $IMAGE_NAME ]] && IMAGE_NAME=$file
done

if [ -z IMAGE_NAME ]; then
    echo no images found, please build an image
    exit -1
fi

echo using image for livecd build: $IMAGE_NAME

# if [ -n "$ROOTDIR" ]; then
#     BUILDDIR=$(mktemp --tmpdir="$ROOTDIR" -d)
# else
BUILDDIR=$(mktemp --tmpdir="$(pwd -P)" -d)
# fi
BUILDDIR=$(readlink -f "$BUILDDIR")
IMAGEDIR="$BUILDDIR/images"
ROOTFSIMAGE=$IMAGE_NAME
ROOTFS="$IMAGEDIR/rootfs"
BOOT_DIR="$IMAGEDIR/boot"
ISOLINUX_DIR="$BOOT_DIR/isolinux"
GRUB_DIR="$BOOT_DIR/grub"
CURRENT_STEP=0

: ${BASE_ARCH:=$(xbps-uhelper arch 2>/dev/null || uname -m)}

: ${SYSLINUX_DATADIR:="$ROOTFS"/usr/lib/syslinux}
: ${GRUB_DATADIR:="$ROOTFS"/usr/share/grub}
: ${SPLASH_IMAGE:=data/splash.png}
: ${XBPS_INSTALL_CMD:=xbps-install}
: ${XBPS_REMOVE_CMD:=xbps-remove}
: ${XBPS_QUERY_CMD:=xbps-query}
: ${XBPS_RINDEX_CMD:=xbps-rindex}
: ${XBPS_UHELPER_CMD:=xbps-uhelper}
: ${XBPS_RECONFIGURE_CMD:=xbps-reconfigure}

mkdir -p "$ROOTFS" "$ISOLINUX_DIR" "$GRUB_DIR"

echo "Setting up rootfs..."
setup_rootfs


_linux_series=$(XBPS_ARCH=$BASE_ARCH $XBPS_QUERY_CMD -r "$ROOTFS" ${XBPS_REPOSITORY:=-R} -x linux | grep 'linux[0-9._]\+')

_kver=$(XBPS_ARCH=$BASE_ARCH $XBPS_QUERY_CMD -r "$ROOTFS" ${XBPS_REPOSITORY:=-R} -p pkgver ${_linux_series})
KERNELVERSION=$($XBPS_UHELPER_CMD getpkgversion ${_kver})

: ${OUTPUT_FILE="void-live-${BASE_ARCH}-${KERNELVERSION}-$(date -u +%Y%m%d).iso"}

echo $KERNELVERSION
echo $OUTPUT_FILE

echo "Making boot stuff..."
make_boot_things

echo "Generating isolinux support for PC-BIOS systems..."
generate_isolinux_boot

echo "Generating GRUB support for EFI systems..."
generate_grub_efi_boot

echo "Generating squashfs image ($SQUASHFS_COMPRESSION) from rootfs..."
generate_squashfs

echo "Generating ISO image..."
generate_iso_image

echo "Cleaning up rootfs..."
cleanup_rootfs

hsize=$(du -sh "$OUTPUT_FILE"|awk '{print $1}')
echo "Created $(readlink -f "$OUTPUT_FILE") ($hsize) successfully."

rm -rf $BUILDDIR