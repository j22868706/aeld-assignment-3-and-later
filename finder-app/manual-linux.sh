#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

if [ $# -lt 1 ]
then
	echo "Using default directory ${OUTDIR} for output"
else
	OUTDIR=$1
	echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p ${OUTDIR}

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    #Clone only if the repository does not exist.
	echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
	git clone --depth 1 --single-branch --branch "$KERNEL_VERSION" \
		"$KERNEL_REPO" "$OUTDIR/linux-stable"
fi
if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    # TODO: Add your kernel build steps here
    make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" defconfig
    make -j4 ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" Image
fi

echo "Adding the Image in outdir"

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi

# TODO: Create necessary base directories

cp -- "$OUTDIR/linux-stable/arch/$ARCH/boot/Image" "$OUTDIR/Image"

ROOTFS="$OUTDIR/rootfs"
mkdir -p -- "$ROOTFS"/{bin,sbin,etc,dev,proc,sys,tmp,usr/bin,usr/sbin,var/log,home/conf}
chmod 1777 "$ROOTFS/tmp"

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
git clone --depth 1 --single-branch --branch "$BUSYBOX_VERSION" \
	https://github.com/mirror/busybox.git "$OUTDIR/busybox"
    	cd busybox
    	git checkout ${BUSYBOX_VERSION}
    	# TODO:  Configure busybox
	make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" defconfig

else
    cd busybox
fi

# TODO: Make and install busybox

if [ ! -f .config ]; then
    make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" defconfig
fi

make -j4 ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE"
make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
    CONFIG_PREFIX="$ROOTFS" install

cd "$ROOTFS"

echo "Library dependencies"
${CROSS_COMPILE}readelf -a bin/busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library"

# TODO: Add library dependencies to rootfs


sysroot=$("${CROSS_COMPILE}gcc" -print-sysroot)
busybox="$ROOTFS/bin/busybox"

copy_runtime_file() {
    local name="$1" destination="$2" source

    source=$("${CROSS_COMPILE}gcc" -print-file-name="$name")
    if [[ "$source" == "$name" || ! -f "$source" ]]; then
        source=$(find -L "$sysroot" -type f -name "$name" -print -quit)
    fi

    if [[ ! -f "$source" ]]; then
        printf 'Missing ARM64 runtime file: %s\n' "$name" >&2
        return 1
    fi

    mkdir -p -- "$(dirname -- "$destination")"
    cp -L -- "$source" "$destination"
}

interpreter=$("${CROSS_COMPILE}readelf" -l "$busybox" |
    sed -n 's/.*Requesting program interpreter: \(.*\)\].*/\1/p')

test -n "$interpreter"
copy_runtime_file "${interpreter##*/}" "$ROOTFS$interpreter"

libraries=$("${CROSS_COMPILE}readelf" -d "$busybox" |
    sed -n 's/.*(NEEDED).*Shared library: \[\(.*\)\].*/\1/p')

while IFS= read -r library; do
    if [[ -n "$library" ]]; then
        copy_runtime_file "$library" "$ROOTFS/lib64/$library"
    fi
done <<< "$libraries"

# TODO: Make device nodes

sudo mknod -m 666 "$ROOTFS/dev/null" c 1 3
sudo mknod -m 600 "$ROOTFS/dev/console" c 5 1

# TODO: Clean and build the writer utility

make -C "$FINDER_APP_DIR" CROSS_COMPILE="$CROSS_COMPILE" clean

"${CROSS_COMPILE}gcc" -Wall -Wextra -O2 -static \
    "$FINDER_APP_DIR/writer.c" -o "$FINDER_APP_DIR/writer"

# TODO: Copy the finder related scripts and executables to the /home directory
# on the target rootfs

install -m 0755 \
    "$FINDER_APP_DIR/writer" \
    "$FINDER_APP_DIR/finder.sh" \
    "$FINDER_APP_DIR/finder-test.sh" \
    "$FINDER_APP_DIR/autorun-qemu.sh" \
    "$ROOTFS/home/"

install -m 0644 \
    "$FINDER_APP_DIR/../conf/username.txt" \
    "$FINDER_APP_DIR/../conf/assignment.txt" \
    "$ROOTFS/home/conf/"

# TODO: Chown the root directory

sudo chown -R -h 0:0 -- "$ROOTFS"

# TODO: Create initramfs.cpio.gz

(
    set -o pipefail
    cd -- "$ROOTFS"
    find . -print0 | cpio --null -o --format=newc
) > "$OUTDIR/initramfs.cpio"

gzip -c "$OUTDIR/initramfs.cpio" > "$OUTDIR/initramfs.cpio.gz"

