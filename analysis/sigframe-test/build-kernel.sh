#!/bin/sh
# build-kernel.sh -- cross-build a MicroBlaze petalogix kernel for qemu-system,
# optionally with patches/linux/ applied, so the signal-frame test can run
# against a real kernel (and against the arg-save-reserve change).
#
#   CROSS_COMPILE=microblazeel-buildroot-linux-gnu- ./build-kernel.sh [stock|patched]
#
# Needs: bc bison flex libssl-dev libelf-dev cpio, and a microblazeel kernel
# cross toolchain (the Bootlin one is fine; the kernel is freestanding).
# Produces ./vmlinux (little-endian ELF) for
#   qemu-system-microblazeel -M petalogix-s3adsp1800 -kernel vmlinux ...
set -eu
KVER=${KVER:-6.12.9}
MODE=${1:-stock}                       # stock | patched
CROSS_COMPILE=${CROSS_COMPILE:-microblazeel-buildroot-linux-gnu-}
here=$(cd "$(dirname "$0")" && pwd)
patches=${PATCHES:-$here/../../patches/linux}

[ -d linux-$KVER ] || { wget -q https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz; tar xf linux-$KVER.tar.xz; }
cd linux-$KVER
export ARCH=microblaze CROSS_COMPILE

if [ "$MODE" = patched ]; then
  for f in "$patches"/000*.patch; do patch -p1 -N -f < "$f" >/dev/null 2>&1 || true; done
  echo "applied patches/linux (signal-frame reserve etc.)"
fi

make mmu_defconfig >/dev/null
# little-endian (microblazeel), UART Lite console, initrd, ELF, futex
./scripts/config --enable CPU_LITTLE_ENDIAN --disable CPU_BIG_ENDIAN \
  --enable SERIAL_UARTLITE --enable SERIAL_UARTLITE_CONSOLE \
  --enable BLK_DEV_INITRD --enable BINFMT_ELF --enable DEVTMPFS --enable DEVTMPFS_MOUNT \
  --enable PROC_FS --enable SYSFS --enable FUTEX
make olddefconfig >/dev/null
make -j"$(nproc)" vmlinux
echo "built $(pwd)/vmlinux ($MODE)"
